// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {IERC20Minimal, IPonsV2FeeEscrow} from "../src/Interfaces.sol";

interface IPonsFactoryView {
    function launchFee() external view returns (uint256);
    function approvedPairTokens(address token) external view returns (bool);
    function pairTokenEconomics(address token) external view returns (uint256, uint256, uint8);
    function getLaunchConfig(uint256 id) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool);
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

/// @notice Live integration checks against Robinhood Chain.
/// @dev Requires ROBINHOOD_RPC_URL. Run with: forge test --match-contract PonsFork
///      These assert the EXTERNAL protocol state HATCH depends on. They are expected to
///      be re-run immediately before launch, since they read mutable mainnet state.
contract PonsForkTest is Test {
    address constant FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    uint256 constant CHAIN_ID = 4663;

    bool forked;

    function setUp() public {
        string memory url = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        try vm.createSelectFork(url) { forked = true; } catch { forked = false; }
    }

    modifier onlyForked() {
        if (!forked) {
            emit log("SKIP: set ROBINHOOD_RPC_URL to run live PONS checks");
            return;
        }
        _;
    }

    function test_ChainId() public onlyForked {
        assertEq(block.chainid, CHAIN_ID, "wrong chain");
    }

    function test_CodeExistsAtCanonicalAddresses() public onlyForked {
        assertGt(FACTORY.code.length, 0, "no code at PONS factory");
        assertGt(ESCROW.code.length, 0, "no code at PONS fee escrow");
        assertGt(NVDA.code.length, 0, "no code at NVDA");
        assertGt(POOL_MANAGER.code.length, 0, "no code at v4 PoolManager");
    }

    function test_NvdaIsAn18DecimalToken() public onlyForked {
        assertEq(IERC20Meta(NVDA).decimals(), 18, "NVDA decimals != 18");
        assertEq(IERC20Meta(NVDA).symbol(), "NVDA", "unexpected symbol");
    }

    function test_NvdaIsApprovedAsPairToken() public onlyForked {
        assertTrue(IPonsFactoryView(FACTORY).approvedPairTokens(NVDA), "NVDA not approved by PONS");
    }

    /// @dev Reads live economics. Deliberately asserts only sanity, never a hard-coded threshold.
    function test_PairEconomicsAreReadableAndSane() public onlyForked {
        (uint256 a, uint256 b, uint8 dec) = IPonsFactoryView(FACTORY).pairTokenEconomics(NVDA);
        assertEq(dec, 18, "economics decimals");
        assertGt(a, 0, "economics word0 is zero");
        assertGt(b, 0, "economics word1 is zero");
        emit log_named_decimal_uint("pair economics [0]", a, 18);
        emit log_named_decimal_uint("pair economics [1]", b, 18);
    }

    function test_LaunchFeeIsReadable() public onlyForked {
        uint256 fee = IPonsFactoryView(FACTORY).launchFee();
        emit log_named_decimal_uint("launchFee (native)", fee, 18);
        assertLt(fee, 1 ether, "launch fee unexpectedly large - re-verify before launching");
    }

    function test_LaunchConfigZeroIsActive() public onlyForked {
        (uint256 supply,,,,,, bool active) = IPonsFactoryView(FACTORY).getLaunchConfig(0);
        assertGt(supply, 0, "config supply zero");
        assertTrue(active, "launch config 0 inactive");
        emit log_named_decimal_uint("config0 total supply", supply, 18);
    }

    /// @dev Binds our real interface to the real escrow. Proves the ABI matches production.
    function test_EscrowInterfaceMatchesProduction() public onlyForked {
        uint256 pending = IPonsV2FeeEscrow(ESCROW).balanceOfToken(address(this), NVDA);
        assertEq(pending, 0, "unexpected credit for a random address");
    }

    /// @dev Deploy the real HATCH contracts against live addresses and read through them.
    function test_HatchContractsBindToLiveProtocol() public onlyForked {
        uint256[7] memory t =
            [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];
        HatchNestVault nest = new HatchNestVault(NVDA, t);
        HatchFeeRouter router = new HatchFeeRouter(
            NVDA, ESCROW, FACTORY, address(nest), address(0xA11CE), address(0xB0B), address(this)
        );

        assertEq(nest.nestBalance(), 0, "fresh nest not empty");
        assertEq(nest.stage(), 0, "fresh nest not dormant");
        assertEq(nest.nextThreshold(), 1 ether, "next threshold");

        // These must read through the live escrow without reverting.
        assertEq(router.pendingPonsFees(), 0, "pendingPonsFees on live escrow");
        assertEq(router.claimableTotal(), 0, "claimableTotal on live escrow");

        // Claiming with no credit must be a safe no-op against the real escrow.
        (uint256 total,,,) = router.claimAndSplit();
        assertEq(total, 0, "no-op claim against live escrow");
    }
}
