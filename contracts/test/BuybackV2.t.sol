// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouterV2} from "../src/HatchFeeRouterV2.sol";
import {HatchBuybackLocker} from "../src/HatchBuybackLocker.sol";
import {PoolKey, Currency} from "../src/IUniswapV4.sol";
import {MockERC20, MockPonsEscrow, MockPonsFactory} from "./Mocks.sol";

/// @dev Stands in for the PONS bonding curve, including its graduation switch.
contract MockCurve {
    MockERC20 public quote;
    MockERC20 public hatch;
    bool public graduated;
    uint256 public feeBps = 100;
    uint256 public creatorTaxBps = 0;
    uint256 public qr = 16.64 ether;
    uint256 public tr = 1_000_000_000 ether;

    constructor(MockERC20 q, MockERC20 h) { quote = q; hatch = h; }
    function setGraduated(bool g) external { graduated = g; }
    function getReserves() external view returns (uint256, uint256) { return (qr, tr); }
    function sellableTokens() external view returns (uint256) { return tr; }

    function buy(uint256 quoteIn, uint256 minOut, address recipient) external returns (uint256 out) {
        require(!graduated, "GRADUATED");
        quote.transferFrom(msg.sender, address(this), quoteIn);
        uint256 net = quoteIn - (quoteIn * feeBps) / 10_000;
        out = (net * tr) / (qr + net);
        require(out >= minOut, "SLIPPAGE");
        qr += net; tr -= out;
        hatch.mint(recipient, out);
    }
}

contract BuybackV2Test is Test {
    MockERC20 nvda;
    MockERC20 hatch;
    MockPonsEscrow escrow;
    MockPonsFactory factory;
    HatchNestVault nest;
    HatchBuybackLocker locker;
    HatchFeeRouterV2 router;
    MockCurve curve;

    address hooked = address(0xBEEF);
    address team = address(0xCAFE);
    address poolManager = address(0x4444);

    uint256[7] T = [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];

    function setUp() public {
        nvda = new MockERC20();
        hatch = new MockERC20();
        escrow = new MockPonsEscrow(nvda);
        factory = new MockPonsFactory();
        nest = new HatchNestVault(address(nvda), T);
        locker = new HatchBuybackLocker(address(nvda), address(nest), poolManager, address(this));
        router = new HatchFeeRouterV2(
            address(nvda), address(escrow), address(factory), address(nest),
            address(locker), hooked, team, address(0xdEaD)
        );
        curve = new MockCurve(nvda, hatch);
    }

    function _credit(uint256 amount) internal {
        nvda.mint(address(this), amount);
        nvda.approve(address(escrow), amount);
        escrow.credit(address(router), amount);
    }

    // --- split ------------------------------------------------------------

    function test_Split_50_20_20_10() public {
        _credit(100 ether);
        router.claimAndSplit();
        assertEq(nvda.balanceOf(address(nest)), 50 ether, "nest 50%");
        assertEq(nvda.balanceOf(address(locker)), 20 ether, "buyback 20%");
        assertEq(nvda.balanceOf(hooked), 20 ether, "hooked 20%");
        assertEq(nvda.balanceOf(team), 10 ether, "team 10%");
        assertEq(nvda.balanceOf(address(router)), 0, "no dust");
    }

    function testFuzz_SplitConservesValue(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _credit(amount);
        (uint256 total, uint256 n, uint256 b, uint256 h, uint256 t) = router.claimAndSplit();
        assertEq(total, amount, "total");
        assertEq(n + b + h + t, total, "four-way split must conserve value");
        assertEq(nvda.balanceOf(address(router)), 0, "dust stranded");
    }

    function test_BpsSumToWhole() public view {
        assertEq(
            router.NEST_BPS() + router.BUYBACK_BPS() + router.HOOKED_BPS() + router.TEAM_BPS(),
            router.BPS(),
            "bps must sum to 10000"
        );
    }

    // --- locker: initialisation -------------------------------------------

    function test_Initialise_IsOneShotAndBurnsTheInitialiser() public {
        locker.initialise(address(hatch), address(curve));
        assertEq(locker.hatchToken(), address(hatch), "token set");
        assertEq(locker.initialiser(), address(0), "initialiser must be burned");

        vm.expectRevert(HatchBuybackLocker.NotInitialiser.selector);
        locker.initialise(address(0x1234), address(curve));
    }

    function test_Initialise_OnlyInitialiser() public {
        vm.prank(address(0xA11CE));
        vm.expectRevert(HatchBuybackLocker.NotInitialiser.selector);
        locker.initialise(address(hatch), address(curve));
    }

    function test_BuybackRevertsBeforeInitialisation() public {
        vm.expectRevert(HatchBuybackLocker.NotInitialised.selector);
        locker.buybackAndLock(0);
    }

    // --- locker: curve phase ----------------------------------------------

    function test_BuybackOnCurve_LocksHatchPermanently() public {
        locker.initialise(address(hatch), address(curve));
        _credit(100 ether);
        router.claimAndSplit(); // 20 NVDA lands in the locker

        assertEq(locker.pendingQuote(), 20 ether, "pending");

        vm.prank(address(0xA11CE)); // permissionless
        (uint256 spent, uint256 locked) = locker.buybackAndLock(1);

        assertEq(spent, 20 ether, "spent everything");
        assertGt(locked, 0, "bought nothing");
        assertEq(locker.hatchLocked(), locked, "hatch not held by the locker");
        assertEq(locker.pendingQuote(), 0, "quote left behind");
    }

    /// @dev The whole point: nothing can ever leave.
    function test_LockerHasNoWithdrawalPath() public {
        locker.initialise(address(hatch), address(curve));
        hatch.mint(address(locker), 1_000 ether);
        nvda.mint(address(locker), 5 ether);

        string[4] memory sigs =
            ["withdraw(uint256)", "transfer(address,uint256)", "sweep(address)", "rescue(address,uint256)"];
        for (uint256 i = 0; i < sigs.length; ++i) {
            (bool ok,) = address(locker).call(abi.encodeWithSignature(sigs[i], uint256(1)));
            assertFalse(ok, "an exit path exists");
        }
        assertEq(locker.hatchLocked(), 1_000 ether, "hatch moved");
    }

    /// @dev A caller must not be able to hand the trade to a sandwicher.
    /// @dev A zero floor would hand the trade to a sandwicher; reject it outright.
    function test_RejectsZeroMinOut() public {
        locker.initialise(address(hatch), address(curve));
        _credit(100 ether);
        router.claimAndSplit();

        vm.expectRevert(HatchBuybackLocker.SlippageTooLoose.selector);
        locker.buybackAndLock(0);
    }

    function test_RevertsWhenNothingToBuy() public {
        locker.initialise(address(hatch), address(curve));
        vm.expectRevert(HatchBuybackLocker.NothingToBuy.selector);
        locker.buybackAndLock(1);
    }

    // --- locker: graduated, no pool configured ----------------------------

    /// @dev Fees must never be stranded. With the curve dead and no pool wired,
    ///      the quote asset goes to the Nest, which locks it just as permanently.
    function test_GraduatedWithoutPool_ForwardsToNest() public {
        locker.initialise(address(hatch), address(curve));
        _credit(100 ether);
        router.claimAndSplit();
        curve.setGraduated(true);

        uint256 nestBefore = nvda.balanceOf(address(nest));
        (uint256 spent, uint256 locked) = locker.buybackAndLock(0);

        assertEq(spent, 20 ether, "spent");
        assertEq(locked, 0, "should not have bought");
        assertEq(nvda.balanceOf(address(nest)) - nestBefore, 20 ether, "not forwarded to nest");
        assertEq(locker.pendingQuote(), 0, "stranded in locker");
    }

    // --- locker: pool configuration --------------------------------------

    function test_ConfigurePool_RejectsWrongPair() public {
        locker.initialise(address(hatch), address(curve));
        PoolKey memory bad = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(HatchBuybackLocker.ZeroAddress.selector);
        locker.configurePool(bad);
    }

    function test_ConfigurePool_AcceptsCorrectPairOnce() public {
        locker.initialise(address(hatch), address(curve));
        PoolKey memory good = PoolKey({
            currency0: Currency.wrap(address(nvda)),
            currency1: Currency.wrap(address(hatch)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0x9999)
        });
        locker.configurePool(good);
        assertTrue(locker.poolConfigured(), "not configured");

        vm.expectRevert(HatchBuybackLocker.AlreadyInitialised.selector);
        locker.configurePool(good);
    }

    function test_UnlockCallback_OnlyPoolManager() public {
        vm.expectRevert(HatchBuybackLocker.NotPoolManager.selector);
        locker.unlockCallback("");
    }
}
