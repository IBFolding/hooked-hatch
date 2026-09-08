// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouterV2} from "../src/HatchFeeRouterV2.sol";
import {HatchBuybackLocker, IPonsV2BondingCurve} from "../src/HatchBuybackLocker.sol";
import {PoolKey, Currency} from "../src/IUniswapV4.sol";

interface IFactory {
    struct Socials { string twitter; string telegram; string discord; string website; string farcaster; }
    struct TokenParams {
        string name; string symbol; string logo; string description; Socials socials;
        address creatorFeeRecipient; uint16 creatorTaxBps; bool buybackEnabled;
        bytes32 expectedEconomics; bytes32 salt;
    }
    function launchToken(TokenParams calldata p, uint256 configId, address pairToken)
        external payable returns (address token, address curve);
    function previewLaunchEconomics(uint256, address) external view returns (bytes32);
    function launchFee() external view returns (uint256);
    function graduate(address token) external;
    function sweepGraduation(address token) external;
    function createGraduatedPool(address token) external returns (uint256);
    function getLaunchedToken(address token) external view returns (bytes memory);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Exercises the buyback locker against the REAL PONS protocol, including
///         graduating the curve and swapping through the live Uniswap v4 pool.
contract BuybackForkTest is Test {
    IFactory constant FACTORY = IFactory(0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e);
    address constant ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant MEME_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address constant WHALE = 0xFe7E25dE55e5cBbEcCcb661F3679F873f72B9b0D;

    HatchNestVault nest;
    HatchBuybackLocker locker;
    HatchFeeRouterV2 router;
    address token;
    address curve;
    bool forked;

    function setUp() public {
        string memory url = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        try vm.createSelectFork(url) { forked = true; } catch { return; }

        uint256[7] memory T = [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];
        nest = new HatchNestVault(NVDA, T);
        locker = new HatchBuybackLocker(NVDA, address(nest), POOL_MANAGER, address(this));
        router = new HatchFeeRouterV2(
            NVDA, ESCROW, address(FACTORY), address(nest), address(locker),
            address(0xA11CE), address(0xB0B), address(0xdEaD)
        );

        IFactory.TokenParams memory p = IFactory.TokenParams({
            name: "HATCH",
            symbol: "HATCH",
            logo: "",
            description: "fork test",
            socials: IFactory.Socials("", "", "", "", ""),
            creatorFeeRecipient: address(router),
            creatorTaxBps: 0,
            buybackEnabled: false,
            expectedEconomics: FACTORY.previewLaunchEconomics(0, NVDA),
            salt: keccak256(abi.encodePacked("hatch-buyback-fork", address(this)))
        });

        vm.deal(address(this), 1 ether);
        (token, curve) = FACTORY.launchToken{value: FACTORY.launchFee()}(p, 0, NVDA);
        locker.initialise(token, curve);
    }

    modifier onlyForked() {
        if (!forked) { emit log("SKIP: set ROBINHOOD_RPC_URL"); return; }
        _;
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(WHALE);
        IERC20(NVDA).transfer(to, amount);
    }

    function test_LaunchWiredToRouter() public onlyForked {
        assertTrue(token != address(0), "no token");
        assertTrue(curve != address(0), "no curve");
        assertEq(locker.hatchToken(), token, "locker not bound");
        assertEq(locker.initialiser(), address(0), "initialiser not burned");
    }

    /// @dev Buyback on the live bonding curve, before graduation.
    function test_BuybackOnLiveCurve() public onlyForked {
        _fund(address(locker), 2 ether);

        (uint256 qr, uint256 tr) = IPonsV2BondingCurve(curve).getReserves();
        emit log_named_decimal_uint("live quoteReserve", qr, 18);
        emit log_named_decimal_uint("live tokenReserve", tr, 18);
        uint256 fee = IPonsV2BondingCurve(curve).feeBps();
        uint256 net = 2 ether - (2 ether * fee) / 10_000;
        uint256 cp = (net * tr) / (qr + net);
        uint256 sellable = IPonsV2BondingCurve(curve).sellableTokens();
        emit log_named_decimal_uint("naive cp estimate ", cp, 18);
        emit log_named_decimal_uint("sellableTokens    ", sellable, 18);
        vm.prank(address(0xDEAD1));
        (uint256 spent, uint256 locked) = locker.buybackAndLock(1);

        assertEq(spent, 2 ether, "spent");
        assertGt(locked, 0, "bought nothing");
        assertEq(IERC20(token).balanceOf(address(locker)), locked, "hatch not locked here");
        emit log_named_decimal_uint("HATCH locked from 2 NVDA", locked, 18);
    }

    /// @dev The real test: graduate the curve, then buy through the live v4 pool.
    function test_BuybackAfterGraduation_ViaUniswapV4() public onlyForked {
        // Push the curve past its graduation threshold with real NVDA.
        _fund(address(this), 60 ether);
        IERC20(NVDA).approve(curve, 60 ether);
        IPonsV2BondingCurve(curve).buy(60 ether, 0, address(this));

        // Graduate. Phase machine may need more than one call.
        // buy() may already have tripped graduation, so both steps are best-effort.
        try FACTORY.graduate(token) { emit log("graduate() called"); }
        catch { emit log("already graduated by the buy"); }
        try FACTORY.createGraduatedPool(token) returns (uint256 id) {
            emit log_named_uint("graduated pool position id", id);
        } catch { emit log("createGraduatedPool failed"); }
        assertTrue(IPonsV2BondingCurve(curve).graduated(), "curve did not graduate");
        emit log("curve graduated");

        // Build the pool key exactly as the factory does: sorted currencies,
        // config poolFee/tickSpacing, PONS meme hook.
        (address c0, address c1) = token < NVDA ? (token, NVDA) : (NVDA, token);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 0,
            tickSpacing: 200,
            hooks: MEME_HOOK
        });
        locker.configurePool(key);

        _fund(address(locker), 1 ether);
        uint256 before = IERC20(token).balanceOf(address(locker));

        vm.prank(address(0xDEAD2)); // permissionless
        (uint256 spent, uint256 locked) = locker.buybackAndLock(1);

        assertEq(spent, 1 ether, "spent");
        assertGt(locked, 0, "v4 swap returned nothing");
        assertEq(IERC20(token).balanceOf(address(locker)) - before, locked, "hatch not received");
        assertEq(locker.pendingQuote(), 0, "quote stranded");
        emit log_named_decimal_uint("HATCH locked from 1 NVDA via v4", locked, 18);
    }
}
