// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchEgg} from "../src/HatchEgg.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {PoolKey, Currency} from "../src/IUniswapV4.sol";
import {MockERC20, MockPonsEscrow, MockPonsFactory, RevertingEscrow} from "./Mocks.sol";

/// @dev Burnable mock standing in for PonsV2LauncherToken (which is ERC20Burnable).
contract MockHatch is MockERC20 {
    uint256 public totalSupply;
    function mintSupply(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function burn(uint256 a) external {
        require(balanceOf[msg.sender] >= a, "BAL");
        balanceOf[msg.sender] -= a;
        totalSupply -= a;
    }
}

contract MockCurve {
    MockERC20 public quote;
    MockHatch public hatch;
    bool public graduated;
    uint256 public rate = 1_000_000; // hatch per quote

    constructor(MockERC20 q, MockHatch h) { quote = q; hatch = h; }
    function setGraduated(bool g) external { graduated = g; }
    function buy(uint256 quoteIn, uint256 minOut, address recipient) external returns (uint256 out) {
        require(!graduated, "GRADUATED");
        quote.transferFrom(msg.sender, address(this), quoteIn);
        out = quoteIn * rate;
        require(out >= minOut, "SLIPPAGE");
        hatch.mintSupply(recipient, out);
    }
}

contract HatchTest is Test {
    MockERC20 nvda;
    MockHatch hatch;
    MockPonsEscrow escrow;
    MockPonsFactory factory;
    HatchEgg egg;
    HatchFeeRouter router;
    MockCurve curve;

    address hooked = address(0xBEEF);
    address team = address(0xCAFE);
    address cracker = address(0xC4AC);

    uint256 constant CRACK = 5 ether;      // round 1
    uint256 constant GROWTH = 20_000;      // 2x per round
    uint256 constant MAXCRACK = 100 ether;

    function setUp() public {
        nvda = new MockERC20();
        hatch = new MockHatch();
        escrow = new MockPonsEscrow(nvda);
        factory = new MockPonsFactory();
        egg = new HatchEgg(address(nvda), address(0x4444), address(this), CRACK, GROWTH, MAXCRACK);
        router = new HatchFeeRouter(
            address(nvda), address(escrow), address(factory), address(egg), hooked, team, address(0xdEaD)
        );
        curve = new MockCurve(nvda, hatch);
        egg.initialise(address(hatch), address(curve));
    }

    function _fill(uint256 amount) internal {
        nvda.mint(address(this), amount);
        nvda.approve(address(egg), amount);
        egg.feed(amount);
    }

    // --- split -------------------------------------------------------------

    function test_Split_70_20_10_IntoTheEgg() public {
        nvda.mint(address(this), 100 ether);
        nvda.approve(address(escrow), 100 ether);
        escrow.credit(address(router), 100 ether);
        router.claimAndSplit();
        assertEq(nvda.balanceOf(address(egg)), 70 ether, "egg 70%");
        assertEq(nvda.balanceOf(hooked), 20 ether, "hooked 20%");
        assertEq(nvda.balanceOf(team), 10 ether, "team 10%");
        assertEq(nvda.balanceOf(address(router)), 0, "router dust");
    }

    // --- cracking ----------------------------------------------------------

    function test_CannotCrackBelowThreshold() public {
        _fill(CRACK - 1);
        assertFalse(egg.crackable(), "should not be crackable");
        vm.expectRevert(HatchEgg.NotReadyToCrack.selector);
        egg.crackEgg(1);
    }

    function test_CrackBuysAndBurns_AndPaysTheCracker() public {
        _fill(CRACK);
        assertTrue(egg.crackable(), "should be crackable");
        assertEq(egg.currentBounty(), (CRACK * 500) / 10_000, "bounty preview");

        uint256 supplyBefore = hatch.totalSupply();

        vm.prank(cracker); // anyone
        (uint256 bounty, uint256 spent, uint256 burned) = egg.crackEgg(1);

        assertEq(bounty, 0.25 ether, "5% bounty");
        assertEq(spent, 4.75 ether, "95% spent");
        assertEq(nvda.balanceOf(cracker), 0.25 ether, "cracker not paid");
        assertGt(burned, 0, "nothing burned");

        // The bought HATCH must be destroyed, not held.
        assertEq(hatch.balanceOf(address(egg)), 0, "egg still holds HATCH");
        assertEq(hatch.totalSupply(), supplyBefore, "supply did not net to zero change");

        // Egg is emptied and starts refilling.
        assertEq(egg.eggBalance(), 0, "egg not emptied");
        assertEq(egg.stage(), 0, "stage did not reset");
        assertEq(egg.crackCount(), 1, "crack not counted");
        assertEq(egg.totalBurned(), burned, "burn stat");
        assertEq(egg.totalBounties(), bounty, "bounty stat");
    }

    /// @dev The whole flywheel depends on this repeating, not firing once.
    function test_EggRefillsAndCracksAgain() public {
        for (uint256 i = 1; i <= 3; ++i) {
            _fill(egg.crackThreshold());
            vm.prank(cracker);
            egg.crackEgg(1);
            assertEq(egg.crackCount(), i, "cycle count");
            assertEq(egg.eggBalance(), 0, "not emptied");
        }
        assertGt(egg.totalBurned(), 0, "nothing burned across cycles");
    }

    function testFuzz_CrackConservesValue(uint256 extra) public {
        extra = bound(extra, 0, 100 ether);
        _fill(CRACK + extra);
        uint256 size = egg.eggBalance();

        vm.prank(cracker);
        (uint256 bounty, uint256 spent,) = egg.crackEgg(1);

        assertEq(bounty + spent, size, "bounty + spent must equal the egg");
        assertEq(egg.eggBalance(), 0, "egg must be empty");
        assertEq(bounty, (size * 500) / 10_000, "bounty is exactly 5%");
    }

    function test_RejectsZeroMinOut() public {
        _fill(CRACK);
        vm.expectRevert(HatchEgg.SlippageTooLoose.selector);
        egg.crackEgg(0);
    }

    function test_CannotCrackBeforeInitialisation() public {
        HatchEgg fresh = new HatchEgg(address(nvda), address(0x4444), address(this), CRACK, GROWTH, MAXCRACK);
        nvda.mint(address(this), CRACK);
        nvda.approve(address(fresh), CRACK);
        fresh.feed(CRACK);
        vm.expectRevert(HatchEgg.NotInitialised.selector);
        fresh.crackEgg(1);
    }

    /// @dev Graduated with no pool wired: cracking must fail loudly, not burn nothing.
    function test_GraduatedWithoutPool_Reverts() public {
        _fill(CRACK);
        curve.setGraduated(true);
        vm.expectRevert(HatchEgg.NoVenue.selector);
        egg.crackEgg(1);
    }

    // --- no exit path ------------------------------------------------------

    /// @dev NVDA may only leave via crackEgg. Nothing else can move it.
    function test_EggHasNoWithdrawalPath() public {
        _fill(10 ether);
        string[5] memory sigs = [
            "withdraw(uint256)", "transfer(address,uint256)", "sweep(address)",
            "rescue(address,uint256)", "emergencyWithdraw()"
        ];
        for (uint256 i = 0; i < sigs.length; ++i) {
            (bool ok,) = address(egg).call(abi.encodeWithSignature(sigs[i], uint256(1)));
            assertFalse(ok, "an exit path exists");
        }
        assertEq(egg.eggBalance(), 10 ether, "balance moved");
    }

    // --- initialisation ----------------------------------------------------

    function test_Initialise_IsOneShotAndBurnsTheRole() public {
        assertEq(egg.initialiser(), address(0), "initialiser must be burned in setUp");
        vm.expectRevert(HatchEgg.NotInitialiser.selector);
        egg.initialise(address(0x1234), address(curve));
    }

    function test_ConfigurePool_RejectsWrongPair() public {
        PoolKey memory bad = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 0, tickSpacing: 200, hooks: address(0)
        });
        vm.expectRevert(HatchEgg.ZeroAddress.selector);
        egg.configurePool(bad);
    }

    function test_UnlockCallback_OnlyPoolManager() public {
        vm.expectRevert(HatchEgg.NotPoolManager.selector);
        egg.unlockCallback("");
    }

    // --- stages ------------------------------------------------------------

    function test_StagesTrackProgressToTheCrack() public {
        assertEq(egg.stage(), 0, "s0");
        _fill(0.1 ether);  assertEq(egg.stage(), 1, "2% -> s1");
        _fill(0.4 ether);  assertEq(egg.stage(), 2, "10% -> s2");
        _fill(1.5 ether);  assertEq(egg.stage(), 4, "40% -> s4");
        _fill(3 ether);    assertEq(egg.stage(), 7, "100% -> s7");
        assertTrue(egg.crackable(), "crackable at stage 7");
        assertEq(egg.progressBps(), 10_000, "full");
    }

    /// @dev Stages are fractions of THIS round's threshold, so the art ramps the
    ///      same way whether the round needs 5 NVDA or 100.
    function testFuzz_StageMatchesProgress(uint256 amount) public {
        amount = bound(amount, 1, CRACK);
        _fill(amount);
        uint256 p = (amount * 10_000) / CRACK;
        uint16[7] memory gates = [200, 1_000, 2_000, 4_000, 6_000, 8_000, 10_000];
        uint8 expected;
        for (uint256 i = 0; i < 7; ++i) { if (p < gates[i]) break; expected++; }
        assertEq(egg.stage(), expected, "stage vs progress");
    }

    // --- rounds ------------------------------------------------------------

    function test_RoundsEscalate() public {
        assertEq(egg.round(), 1, "starts at round 1");
        assertEq(egg.crackThreshold(), 5 ether, "round 1 threshold");
        assertEq(egg.nextRoundThreshold(), 10 ether, "round 2 preview");

        uint256[4] memory expected = [uint256(10 ether), 20 ether, 40 ether, 80 ether];
        for (uint256 i = 0; i < expected.length; ++i) {
            _fill(egg.crackThreshold());
            vm.prank(cracker);
            egg.crackEgg(1);
            assertEq(egg.round(), i + 2, "round advanced");
            assertEq(egg.crackThreshold(), expected[i], "threshold escalated");
        }
    }

    /// @dev The egg must never escalate itself out of reach.
    function test_ThresholdIsCapped() public {
        for (uint256 i = 0; i < 8; ++i) {
            _fill(egg.crackThreshold());
            vm.prank(cracker);
            egg.crackEgg(1);
        }
        assertEq(egg.crackThreshold(), MAXCRACK, "must cap at maxThreshold");
        assertEq(egg.nextRoundThreshold(), MAXCRACK, "cap is sticky");
    }

    function test_ConstructorRejectsShrinkingRounds() public {
        vm.expectRevert(bytes("GROWTH_BELOW_ONE"));
        new HatchEgg(address(nvda), address(0x4444), address(this), 5 ether, 9_999, MAXCRACK);
    }

    function test_ConstructorRejectsCapBelowBase() public {
        vm.expectRevert(bytes("MAX_BELOW_BASE"));
        new HatchEgg(address(nvda), address(0x4444), address(this), 10 ether, 20_000, 5 ether);
    }

    function test_NextThresholdIsRemainingNotAbsolute() public {
        _fill(2 ether);
        assertEq(egg.nextThreshold(), 3 ether, "should report NVDA still needed");
        _fill(3 ether);
        assertEq(egg.nextThreshold(), 0, "nothing needed once crackable");
    }

    function test_FeedRevertsOnZero() public {
        vm.expectRevert(HatchEgg.ZeroAmount.selector);
        egg.feed(0);
    }

    function test_RevertingEscrowDoesNotBlockSplit() public {
        RevertingEscrow bad = new RevertingEscrow();
        HatchFeeRouter r = new HatchFeeRouter(
            address(nvda), address(bad), address(factory), address(egg), hooked, team, address(0xdEaD)
        );
        nvda.mint(address(r), 100 ether);
        assertEq(r.pendingPonsFees(), 0, "view must not revert");
        (uint256 total,,,) = r.claimAndSplit();
        assertEq(total, 100 ether, "split blocked by bad escrow");
    }
}
