// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "./Interfaces.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {
    IPoolManager, IUnlockCallback, PoolKey, SwapParams, Currency, BalanceDelta, DeltaLib
} from "./IUniswapV4.sol";

interface IPonsV2BondingCurve {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256 tokensOut);
    function graduated() external view returns (bool);
}

interface IBurnableERC20 {
    function balanceOf(address) external view returns (uint256);
    function burn(uint256 amount) external;
    function totalSupply() external view returns (uint256);
}

/// @title HatchEgg
/// @notice The HATCH egg. Creator-fee NVDA accumulates here in public. Once it
///         reaches the crack threshold, ANYONE may crack it: the egg spends its
///         NVDA buying HATCH on the open market and burns every token it buys,
///         and the caller keeps a bounty for doing it. Then the egg refills.
///
/// @dev The egg holds no permanent balance and pays no holder. It converts fees
///      into a public, repeating, permanent supply burn. There is no withdrawal
///      function and no admin: the only way NVDA leaves is through `crackEgg`,
///      which can only buy-and-burn and pay the caller's bounty.
contract HatchEgg is IUnlockCallback {
    using SafeTransferLib for address;
    using DeltaLib for BalanceDelta;

    uint160 private constant MIN_SQRT_PRICE = 4295128739;
    uint160 private constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    /// @notice Share of the egg paid to whoever cracks it. Immutable.
    uint256 public constant CRACKER_BPS = 500; // 5%
    uint256 public constant BPS = 10_000;

    error ZeroAddress();
    error ZeroAmount();
    error AlreadyInitialised();
    error NotInitialised();
    error NotInitialiser();
    error NotPoolManager();
    error ReentrantCall();
    error NotReadyToCrack();
    error NoVenue();
    error SlippageTooLoose();
    error AmountOverflow();
    error UnexpectedDelta();

    address public immutable asset; // NVDA
    IPoolManager public immutable poolManager;
    uint256 public immutable crackThreshold;

    address public hatchToken;
    address public curve;
    PoolKey public poolKey;
    bool public poolConfigured;
    address public initialiser;

    /// @dev Stage display only. thresholds[6] is the crack threshold.
    uint256[7] public thresholds;

    uint256 public totalFed;
    uint256 public totalBurned;
    uint256 public totalBounties;
    uint256 public crackCount;
    uint256 public lastCrackAt;

    uint256 private _entered = 1;

    event Initialised(address indexed hatchToken, address indexed curve);
    event PoolConfigured(address indexed hatchToken);
    event Fed(address indexed feeder, uint256 amount, uint256 newBalance, uint8 stage);
    event Cracked(
        address indexed cracker, uint256 eggSize, uint256 bounty, uint256 spent, uint256 burned, uint256 crackNumber
    );

    modifier nonReentrant() {
        if (_entered != 1) revert ReentrantCall();
        _entered = 2;
        _;
        _entered = 1;
    }

    constructor(address asset_, address poolManager_, address initialiser_, uint256[7] memory thresholds_) {
        if (asset_ == address(0) || poolManager_ == address(0) || initialiser_ == address(0)) revert ZeroAddress();
        for (uint256 i = 1; i < thresholds_.length; ++i) {
            require(thresholds_[i] > thresholds_[i - 1], "THRESHOLDS_NOT_ASCENDING");
        }
        asset = asset_;
        poolManager = IPoolManager(poolManager_);
        initialiser = initialiser_;
        thresholds = thresholds_;
        crackThreshold = thresholds_[6];
    }

    // --- one-shot wiring ---------------------------------------------------

    /// @dev HATCH cannot exist before the PONS launch, and the launch needs this
    ///      address first. Calling this burns the initialiser role permanently.
    function initialise(address hatchToken_, address curve_) external {
        if (msg.sender != initialiser) revert NotInitialiser();
        if (hatchToken != address(0)) revert AlreadyInitialised();
        if (hatchToken_ == address(0) || curve_ == address(0)) revert ZeroAddress();
        hatchToken = hatchToken_;
        curve = curve_;
        initialiser = address(0);
        emit Initialised(hatchToken_, curve_);
    }

    /// @notice Wire the graduated v4 pool. Permissionless, once, and only with a
    ///         key that genuinely pairs HATCH against the quote asset.
    function configurePool(PoolKey calldata key) external {
        if (hatchToken == address(0)) revert NotInitialised();
        if (poolConfigured) revert AlreadyInitialised();
        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        if (!((c0 == hatchToken && c1 == asset) || (c0 == asset && c1 == hatchToken))) revert ZeroAddress();
        poolKey = key;
        poolConfigured = true;
        emit PoolConfigured(hatchToken);
    }

    // --- feeding -----------------------------------------------------------

    /// @notice Anyone may feed the egg directly after approving it.
    function feed(uint256 amount) external returns (uint256 newBalance) {
        if (amount == 0) revert ZeroAmount();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalFed += amount;
        newBalance = eggBalance();
        emit Fed(msg.sender, amount, newBalance, stage());
    }

    // --- cracking ----------------------------------------------------------

    function crackable() public view returns (bool) {
        return eggBalance() >= crackThreshold && hatchToken != address(0);
    }

    /// @notice Crack the egg: buy HATCH with everything inside and burn it.
    ///         Permissionless. The caller keeps CRACKER_BPS of the egg.
    /// @param minHatchOut slippage floor for the market buy, enforced by the venue.
    function crackEgg(uint256 minHatchOut)
        external
        nonReentrant
        returns (uint256 bounty, uint256 spent, uint256 burned)
    {
        if (hatchToken == address(0)) revert NotInitialised();

        uint256 size = eggBalance();
        if (size < crackThreshold) revert NotReadyToCrack();
        if (minHatchOut == 0) revert SlippageTooLoose();

        bool graduated = IPonsV2BondingCurve(curve).graduated();
        if (graduated && !poolConfigured) revert NoVenue();

        bounty = (size * CRACKER_BPS) / BPS;
        spent = size - bounty;

        // Pay the cracker first; the rest is spent on the market buy.
        asset.safeTransfer(msg.sender, bounty);

        if (!graduated) {
            asset.safeApprove(curve, spent);
            burned = IPonsV2BondingCurve(curve).buy(spent, minHatchOut, address(this));
        } else {
            burned = abi.decode(poolManager.unlock(abi.encode(spent, minHatchOut)), (uint256));
        }

        // Burn every token bought. Real supply reduction, visible in totalSupply().
        IBurnableERC20(hatchToken).burn(burned);

        unchecked {
            totalBurned += burned;
            totalBounties += bounty;
            ++crackCount;
        }
        lastCrackAt = block.timestamp;

        emit Cracked(msg.sender, size, bounty, spent, burned, crackCount);
    }

    /// @dev v4 settlement: pay the quote asset in, take HATCH out.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint256 amountIn, uint256 minOut) = abi.decode(data, (uint256, uint256));
        if (amountIn > uint256(type(int256).max)) revert AmountOverflow();

        PoolKey memory key = poolKey;
        bool zeroForOne = Currency.unwrap(key.currency0) == asset;

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                // forge-lint: disable-next-line(unsafe-typecast) - bounded above
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 quoteDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 hatchDelta = zeroForOne ? delta.amount1() : delta.amount0();
        // We must owe quote and receive HATCH. Any other shape and a blind cast
        // would turn a negative into an enormous uint.
        if (quoteDelta >= 0 || hatchDelta <= 0) revert UnexpectedDelta();

        // forge-lint: disable-next-line(unsafe-typecast) - sign checked above
        uint256 owed = uint256(uint128(-quoteDelta));
        poolManager.sync(zeroForOne ? key.currency0 : key.currency1);
        asset.safeTransfer(address(poolManager), owed);
        poolManager.settle();

        // forge-lint: disable-next-line(unsafe-typecast) - sign checked above
        uint256 out = uint256(uint128(hatchDelta));
        if (out < minOut) revert SlippageTooLoose();
        poolManager.take(zeroForOne ? key.currency1 : key.currency0, address(this), out);

        return abi.encode(out);
    }

    // --- views -------------------------------------------------------------

    function eggBalance() public view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @return Current stage 0-7. Stage 7 means the egg is ready to crack.
    function stage() public view returns (uint8) {
        uint256 balance = eggBalance();
        uint8 s;
        for (uint8 i = 0; i < 7; ++i) {
            if (balance < thresholds[i]) break;
            unchecked { ++s; }
        }
        return s;
    }

    function nextThreshold() external view returns (uint256) {
        uint8 s = stage();
        return s >= 7 ? 0 : thresholds[s];
    }

    function progressBps() external view returns (uint256) {
        uint256 balance = eggBalance();
        if (balance >= crackThreshold) return BPS;
        return (balance * BPS) / crackThreshold;
    }

    /// @notice What the next cracker would earn right now.
    function currentBounty() external view returns (uint256) {
        return (eggBalance() * CRACKER_BPS) / BPS;
    }

    /// @notice HATCH destroyed so far, and the token's remaining supply.
    function burnStats() external view returns (uint256 burned, uint256 remainingSupply) {
        burned = totalBurned;
        remainingSupply = hatchToken == address(0) ? 0 : IBurnableERC20(hatchToken).totalSupply();
    }
}
