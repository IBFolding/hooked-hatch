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
    function getReserves() external view returns (uint256 quoteReserve, uint256 tokenReserve);
    function sellableTokens() external view returns (uint256);
    function feeBps() external view returns (uint256);
    function creatorTaxBps() external view returns (uint256);
    function graduated() external view returns (bool);
}

/// @title HatchBuybackLocker
/// @notice Receives a slice of HATCH's creator fees in the quote asset, buys HATCH
///         with it, and locks the HATCH here permanently.
///
/// @dev There is deliberately NO withdrawal function for either asset. Bought HATCH
///      is removed from circulation for good, which is why this is a lock rather
///      than a treasury.
///
///      Two market venues, because PONS launches move:
///        - before graduation, HATCH trades on the PONS bonding curve
///        - after graduation, it trades in a Uniswap v4 pool behind the PONS hook
///      `buybackAndLock` routes to whichever is live. If the v4 pool has not been
///      configured by the time the curve graduates, the quote asset is forwarded to
///      the Nest instead, so fees are never stranded here.
contract HatchBuybackLocker is IUnlockCallback {
    using SafeTransferLib for address;
    using DeltaLib for BalanceDelta;

    /// @dev v4-core PoolManager keeps pool state in a mapping at storage slot 6.
    uint256 private constant POOLS_SLOT = 6;
    uint160 private constant MIN_SQRT_PRICE = 4295128739;
    uint160 private constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    error ZeroAddress();
    error AlreadyInitialised();
    error NotInitialised();
    error NotInitialiser();
    error NotPoolManager();
    error ReentrantCall();
    error SlippageTooLoose();
    error NothingToBuy();
    error NoVenue();
    error AmountOverflow();
    error UnexpectedDelta();

    address public immutable quoteToken;
    address public immutable nest;
    IPoolManager public immutable poolManager;

    /// @dev Set once, after the PONS launch exists. Then permanently frozen.
    address public hatchToken;
    address public curve;
    PoolKey public poolKey;
    bool public poolConfigured;

    /// @dev Zeroed by `initialise`, so the privileged window closes for good.
    address public initialiser;

    uint256 private _entered = 1;

    event Initialised(address indexed hatchToken, address indexed curve);
    event PoolConfigured(address indexed hatchToken);
    event BoughtAndLocked(address indexed caller, uint256 quoteSpent, uint256 hatchLocked, bool viaCurve);
    event ForwardedToNest(uint256 amount);

    modifier nonReentrant() {
        if (_entered != 1) revert ReentrantCall();
        _entered = 2;
        _;
        _entered = 1;
    }

    constructor(address quoteToken_, address nest_, address poolManager_, address initialiser_) {
        if (
            quoteToken_ == address(0) || nest_ == address(0) || poolManager_ == address(0)
                || initialiser_ == address(0)
        ) revert ZeroAddress();
        quoteToken = quoteToken_;
        nest = nest_;
        poolManager = IPoolManager(poolManager_);
        initialiser = initialiser_;
    }

    /// @notice One-shot wiring of the launched token and its curve.
    /// @dev The HATCH address cannot exist before the PONS launch, and the launch
    ///      needs this contract's address first, so this cannot be a constructor
    ///      argument. Calling it burns the initialiser permanently.
    function initialise(address hatchToken_, address curve_) external {
        if (msg.sender != initialiser) revert NotInitialiser();
        if (hatchToken != address(0)) revert AlreadyInitialised();
        if (hatchToken_ == address(0) || curve_ == address(0)) revert ZeroAddress();
        hatchToken = hatchToken_;
        curve = curve_;
        initialiser = address(0); // no privileged actor survives this call
        emit Initialised(hatchToken_, curve_);
    }

    /// @notice One-shot wiring of the graduated v4 pool.
    /// @dev Separate from `initialise` because the pool does not exist until the
    ///      curve graduates. Anyone may call it, but only with a key that actually
    ///      contains HATCH and the quote asset, and only once.
    function configurePool(PoolKey calldata key) external {
        if (hatchToken == address(0)) revert NotInitialised();
        if (poolConfigured) revert AlreadyInitialised();

        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        bool pairMatches = (c0 == hatchToken && c1 == quoteToken) || (c0 == quoteToken && c1 == hatchToken);
        if (!pairMatches) revert ZeroAddress();

        poolKey = key;
        poolConfigured = true;
        emit PoolConfigured(hatchToken);
    }

    /// @notice Buy HATCH with everything held here and lock it forever. Permissionless.
    /// @param minHatchOut the caller's slippage floor, enforced by the venue itself
    ///        (the curve reverts SlippageExceeded, the v4 leg is checked here).
    ///
    /// @dev minHatchOut must be non-zero. We deliberately do NOT recompute the
    ///      venue's own price on-chain to derive a floor: doing so means baking
    ///      another protocol's internal pricing into an immutable contract, and if
    ///      PONS ever changes it every future buyback reverts permanently. A stale
    ///      floor is a worse failure than a loose one, because it cannot be fixed.
    ///      Callers should quote off-chain; the launch tooling does exactly that.
    function buybackAndLock(uint256 minHatchOut)
        external
        nonReentrant
        returns (uint256 spent, uint256 locked)
    {
        if (hatchToken == address(0)) revert NotInitialised();

        spent = IERC20Minimal(quoteToken).balanceOf(address(this));
        if (spent == 0) revert NothingToBuy();

        bool graduated = IPonsV2BondingCurve(curve).graduated();

        if (!graduated) {
            if (minHatchOut == 0) revert SlippageTooLoose();
            quoteToken.safeApprove(curve, spent);
            locked = IPonsV2BondingCurve(curve).buy(spent, minHatchOut, address(this));
            emit BoughtAndLocked(msg.sender, spent, locked, true);
            return (spent, locked);
        }

        // Graduated. If no pool has been configured yet the fees must not sit here
        // idle, so send them to the Nest, which locks them just as permanently.
        if (!poolConfigured) {
            quoteToken.safeTransfer(nest, spent);
            emit ForwardedToNest(spent);
            return (spent, 0);
        }

        if (minHatchOut == 0) revert SlippageTooLoose();
        locked = abi.decode(
            poolManager.unlock(abi.encode(spent, minHatchOut)),
            (uint256)
        );
        emit BoughtAndLocked(msg.sender, spent, locked, false);
    }

    /// @dev v4 settlement callback. Pays the quote asset in and takes HATCH out.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (uint256 amountIn, uint256 minOut) = abi.decode(data, (uint256, uint256));

        // A v4 exact-input swap encodes the input as a negative int256.
        if (amountIn > uint256(type(int256).max)) revert AmountOverflow();

        PoolKey memory key = poolKey;
        bool zeroForOne = Currency.unwrap(key.currency0) == quoteToken;

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                // forge-lint: disable-next-line(unsafe-typecast) - bounded above
                amountSpecified: -int256(amountIn), // exact input
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 quoteDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 hatchDelta = zeroForOne ? delta.amount1() : delta.amount0();

        // We spend the quote asset and receive HATCH, so the signs are fixed:
        // a negative quote delta is what we owe, a positive HATCH delta is ours.
        // Anything else means the pool did something we did not ask for, and
        // casting it blindly would turn a negative into an enormous uint.
        if (quoteDelta >= 0 || hatchDelta <= 0) revert UnexpectedDelta();

        // Pay what we owe the pool. Negating a non-min int128 is always safe,
        // and quoteDelta cannot be type(int128).min for any real balance.
        // forge-lint: disable-next-line(unsafe-typecast) - sign checked above
        uint256 owed = uint256(uint128(-quoteDelta));
        poolManager.sync(zeroForOne ? key.currency0 : key.currency1);
        quoteToken.safeTransfer(address(poolManager), owed);
        poolManager.settle();

        // Collect the HATCH and keep it here permanently.
        // forge-lint: disable-next-line(unsafe-typecast) - sign checked above
        uint256 out = uint256(uint128(hatchDelta));
        if (out < minOut) revert SlippageTooLoose();
        poolManager.take(zeroForOne ? key.currency1 : key.currency0, address(this), out);

        return abi.encode(out);
    }

    /// @notice HATCH permanently locked in this contract.
    function hatchLocked() external view returns (uint256) {
        if (hatchToken == address(0)) return 0;
        return IERC20Minimal(hatchToken).balanceOf(address(this));
    }

    /// @notice Quote asset waiting to be spent on the next buyback.
    function pendingQuote() external view returns (uint256) {
        return IERC20Minimal(quoteToken).balanceOf(address(this));
    }
}
