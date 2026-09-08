// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {SafeTransferLib} from "../src/SafeTransferLib.sol";
import {MockERC20, MockPonsEscrow, MockPonsFactory, RevertingEscrow, ReenteringToken} from "./Mocks.sol";

contract HatchTest is Test {
    MockERC20 token;
    MockPonsEscrow escrow;
    MockPonsFactory factory;
    HatchNestVault nest;
    HatchFeeRouter router;

    address hooked = address(0xBEEF);
    address team = address(0xCAFE);
    address governance = address(this);

    uint256[7] THRESHOLDS = [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];

    function setUp() public {
        token = new MockERC20();
        escrow = new MockPonsEscrow(token);
        factory = new MockPonsFactory();
        nest = new HatchNestVault(address(token), THRESHOLDS);
        router = new HatchFeeRouter(
            address(token), address(escrow), address(factory), address(nest), hooked, team, governance
        );
    }

    function _credit(uint256 amount) internal {
        token.mint(address(this), amount);
        token.approve(address(escrow), amount);
        escrow.credit(address(router), amount);
    }

    // --- split correctness -------------------------------------------------

    function test_FeeSplit_70_20_10() public {
        _credit(100 ether);
        router.claimAndSplit();
        assertEq(token.balanceOf(address(nest)), 70 ether, "nest");
        assertEq(token.balanceOf(hooked), 20 ether, "hooked");
        assertEq(token.balanceOf(team), 10 ether, "team");
        assertEq(token.balanceOf(address(router)), 0, "router dust");
    }

    /// @dev Handoff requirement: nest + hooked + team == total, and no router dust, for ANY amount.
    function testFuzz_SplitConservesValueAndLeavesNoDust(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _credit(amount);

        (uint256 total, uint256 n, uint256 h, uint256 t) = router.claimAndSplit();

        assertEq(total, amount, "total != claimed");
        assertEq(n + h + t, total, "split does not conserve value");
        assertEq(token.balanceOf(address(nest)), n, "nest balance");
        assertEq(token.balanceOf(hooked), h, "hooked balance");
        assertEq(token.balanceOf(team), t, "team balance");
        assertEq(token.balanceOf(address(router)), 0, "router retained dust");
    }

    /// @dev Dust values are where integer rounding is most likely to strand or over-pay.
    function testFuzz_DustAmountsNeverStrandValue(uint8 tiny) public {
        uint256 amount = uint256(tiny) + 1; // 1 .. 256 wei
        _credit(amount);

        (uint256 total, uint256 n, uint256 h, uint256 t) = router.claimAndSplit();

        assertEq(n + h + t, total, "dust conservation");
        assertEq(token.balanceOf(address(router)), 0, "dust stranded in router");
        // Rounding favours the team remainder, never the nest.
        assertLe(n, (amount * 7000) / 10000, "nest over-paid");
    }

    function testFuzz_SplitRatiosWithinOneWei(uint256 amount) public {
        amount = bound(amount, 10_000, type(uint128).max);
        _credit(amount);
        (uint256 total, uint256 n, uint256 h, uint256 t) = router.claimAndSplit();
        assertEq(n, (total * 7000) / 10000, "nest bps");
        assertEq(h, (total * 2000) / 10000, "hooked bps");
        assertGe(t, (total * 1000) / 10000, "team gets remainder");
        assertLe(t - (total * 1000) / 10000, 2, "remainder above rounding bound");
    }

    // --- router robustness -------------------------------------------------

    function test_ClaimAndSplit_NoPendingFees_IsNoOp() public {
        (uint256 total,,,) = router.claimAndSplit();
        assertEq(total, 0, "expected no-op");
    }

    /// @dev Tokens sent directly to the router must still be distributable, not stranded.
    function test_StrayTokensAreSwept() public {
        token.mint(address(router), 10 ether);
        (uint256 total,,,) = router.claimAndSplit();
        assertEq(total, 10 ether, "stray not swept");
        assertEq(token.balanceOf(address(nest)), 7 ether, "stray nest share");
        assertEq(token.balanceOf(address(router)), 0, "stray left behind");
    }

    /// @dev A reverting escrow must not brick distribution of the router's existing balance.
    function test_RevertingEscrowDoesNotBlockSplit() public {
        RevertingEscrow bad = new RevertingEscrow();
        HatchFeeRouter r2 = new HatchFeeRouter(
            address(token), address(bad), address(factory), address(nest), hooked, team, governance
        );
        token.mint(address(r2), 100 ether);

        assertEq(r2.pendingPonsFees(), 0, "view must not revert");
        (uint256 total,,,) = r2.claimAndSplit();
        assertEq(total, 100 ether, "split blocked by bad escrow");
    }

    function test_ClaimableTotal_IncludesEscrowAndStray() public {
        _credit(30 ether);
        token.mint(address(router), 5 ether);
        assertEq(router.claimableTotal(), 35 ether, "claimableTotal");
        assertEq(router.pendingPonsFees(), 30 ether, "pendingPonsFees");
    }

    /// @dev A malicious quote token re-entering claimAndSplit must be rejected.
    function test_ReentrancyIsBlocked() public {
        ReenteringToken evil = new ReenteringToken();
        MockPonsEscrow evilEscrow = new MockPonsEscrow(MockERC20(address(evil)));
        HatchFeeRouter r = new HatchFeeRouter(
            address(evil), address(evilEscrow), address(factory), address(nest), hooked, team, governance
        );
        evil.setTarget(address(r));
        evil.mint(address(r), 10 ether);

        // The guard fires inside the re-entrant call; SafeTransferLib surfaces that
        // inner revert to the caller as TransferFailed. Either way the whole call
        // reverts atomically and nothing is distributed twice.
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        r.claimAndSplit();

        assertEq(evil.balanceOf(address(nest)), 0, "nest paid during reentrancy");
        assertEq(evil.balanceOf(hooked), 0, "hooked paid during reentrancy");
        assertEq(evil.balanceOf(team), 0, "team paid during reentrancy");
        assertEq(evil.balanceOf(address(r)), 10 ether, "router balance changed");
    }

    // --- governance --------------------------------------------------------

    function test_BindLaunchAndMigrate() public {
        address hatch = address(0x1234);
        router.bindLaunch(hatch);
        factory.setLaunch(hatch, address(router));
        router.migratePonsRecipient(address(0x9999));
        assertEq(factory.recipient(), address(0x9999), "migration");
    }

    function test_BindLaunch_OnlyOnce() public {
        router.bindLaunch(address(0x1234));
        vm.expectRevert(HatchFeeRouter.AlreadyBound.selector);
        router.bindLaunch(address(0x5678));
    }

    function test_BindLaunch_OnlyGovernance() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(HatchFeeRouter.NotGovernance.selector);
        router.bindLaunch(address(0x1234));
    }

    function test_Migrate_RevertsBeforeBind() public {
        vm.expectRevert(HatchFeeRouter.NotBound.selector);
        router.migratePonsRecipient(address(0x9999));
    }

    function test_Migrate_OnlyGovernance() public {
        router.bindLaunch(address(0x1234));
        vm.prank(address(0xDEAD));
        vm.expectRevert(HatchFeeRouter.NotGovernance.selector);
        router.migratePonsRecipient(address(0x9999));
    }

    /// @dev The split destinations and percentages must be immutable after deployment.
    function test_SplitDestinationsAreImmutable() public view {
        assertEq(router.NEST_BPS() + router.HOOKED_BPS() + router.TEAM_BPS(), router.BPS(), "bps sum");
        assertEq(router.nest(), address(nest), "nest immutable");
        assertEq(router.hookedTreasury(), hooked, "hooked immutable");
        assertEq(router.teamTreasury(), team, "team immutable");
    }

    // --- burned governance --------------------------------------------------

    /// @dev HOOKED ships with router governance burned. The core mechanism must be
    ///      fully functional with NO privileged actor in existence.
    function test_BurnedGovernance_MechanismStillWorks() public {
        address burn = address(0xdEaD);
        HatchNestVault n2 = new HatchNestVault(address(token), THRESHOLDS);
        HatchFeeRouter r = new HatchFeeRouter(
            address(token), address(escrow), address(factory), address(n2), hooked, team, burn
        );

        token.mint(address(this), 100 ether);
        token.approve(address(escrow), 100 ether);
        escrow.credit(address(r), 100 ether);

        // Anyone at all can advance the mechanism.
        vm.prank(address(0xA11CE));
        (uint256 total, uint256 nAmt, uint256 h, uint256 t) = r.claimAndSplit();

        assertEq(total, 100 ether, "claim");
        assertEq(nAmt, 70 ether, "nest 70%");
        assertEq(h, 20 ether, "hooked 20%");
        assertEq(t, 10 ether, "team 10%");
        assertEq(token.balanceOf(address(n2)), 70 ether, "nest funded");
        assertEq(token.balanceOf(address(r)), 0, "no dust");
        assertEq(n2.stage(), 5, "nest stage advanced");
    }

    /// @dev With governance burned, the privileged functions must be unreachable
    ///      by everyone - including the burn address itself having no key.
    function test_BurnedGovernance_PrivilegedFunctionsAreDead() public {
        address burn = address(0xdEaD);
        HatchFeeRouter r = new HatchFeeRouter(
            address(token), address(escrow), address(factory), address(nest), hooked, team, burn
        );

        // The deployer cannot bind.
        vm.expectRevert(HatchFeeRouter.NotGovernance.selector);
        r.bindLaunch(address(0x1234));

        // Nor can any third party.
        vm.prank(address(0xA11CE));
        vm.expectRevert(HatchFeeRouter.NotGovernance.selector);
        r.bindLaunch(address(0x1234));

        // Migration is doubly dead: never bound, and not callable anyway.
        vm.expectRevert(HatchFeeRouter.NotGovernance.selector);
        r.migratePonsRecipient(address(0x9999));

        assertEq(r.hatchToken(), address(0), "must remain unbound forever");
        assertEq(r.governance(), burn, "governance is the burn address");
    }

    /// @dev address(0) is rejected, so a burn MUST use a non-zero burn address.
    function test_ZeroGovernanceIsRejected() public {
        vm.expectRevert(HatchFeeRouter.ZeroAddress.selector);
        new HatchFeeRouter(
            address(token), address(escrow), address(factory), address(nest), hooked, team, address(0)
        );
    }

    // --- nest --------------------------------------------------------------

    function test_NestStages() public {
        token.mint(address(this), 25 ether);
        token.approve(address(nest), 25 ether);
        assertEq(nest.stage(), 0, "s0");
        nest.feed(1 ether);
        assertEq(nest.stage(), 1, "s1");
        nest.feed(4 ether);
        assertEq(nest.stage(), 2, "s2");
        nest.feed(20 ether);
        assertEq(nest.stage(), 4, "s4");
    }

    function testFuzz_StageIsMonotonicInBalance(uint256 amount) public {
        amount = bound(amount, 1, 1_000 ether);
        token.mint(address(this), amount);
        token.approve(address(nest), amount);
        uint8 before = nest.stage();
        nest.feed(amount);
        assertGe(nest.stage(), before, "stage went backwards");
    }

    function testFuzz_StageMatchesThresholdTable(uint256 amount) public {
        amount = bound(amount, 1, 400 ether);
        token.mint(address(this), amount);
        token.approve(address(nest), amount);
        nest.feed(amount);

        uint8 expected;
        for (uint256 i = 0; i < 7; ++i) {
            if (amount >= THRESHOLDS[i]) expected++;
        }
        assertEq(nest.stage(), expected, "stage table mismatch");
    }

    function test_NestHasNoWithdrawalPath() public {
        token.mint(address(this), 5 ether);
        token.approve(address(nest), 5 ether);
        nest.feed(5 ether);
        // No function on the vault can move `asset` out. Assert the balance is sticky.
        assertEq(nest.nestBalance(), 5 ether, "nest balance");
        (bool ok,) = address(nest).call(abi.encodeWithSignature("withdraw(uint256)", 1 ether));
        assertFalse(ok, "a withdraw path exists");
    }

    function test_ProgressBps() public {
        token.mint(address(this), 3 ether);
        token.approve(address(nest), 3 ether);
        nest.feed(3 ether); // stage 1, between 1 and 5 ether
        assertEq(nest.stage(), 1, "stage");
        assertEq(nest.nextThreshold(), 5 ether, "next");
        assertEq(nest.progressBps(), 5000, "halfway 1->5");
    }

    function test_Feed_RevertsOnZero() public {
        vm.expectRevert(HatchNestVault.ZeroAmount.selector);
        nest.feed(0);
    }

    function test_Nest_RejectsNonAscendingThresholds() public {
        uint256[7] memory bad = [uint256(1 ether), 1 ether, 3 ether, 4 ether, 5 ether, 6 ether, 7 ether];
        vm.expectRevert(bytes("THRESHOLDS_NOT_ASCENDING"));
        new HatchNestVault(address(token), bad);
    }

    function test_FinalStageCaps() public {
        token.mint(address(this), 500 ether);
        token.approve(address(nest), 500 ether);
        nest.feed(500 ether);
        assertEq(nest.stage(), 7, "final stage");
        assertEq(nest.nextThreshold(), 0, "no next threshold");
        assertEq(nest.progressBps(), 10_000, "complete");
    }
}
