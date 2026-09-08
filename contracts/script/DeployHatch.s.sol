// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {HookedLaunchRegistry} from "../src/HookedLaunchRegistry.sol";

interface IPonsFactoryView {
    function approvedPairTokens(address token) external view returns (bool);
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
}

/// @notice Deploys the HATCH mechanism contracts in the required order.
/// @dev Deployment order is Nest -> Router -> Registry, because the router takes the
///      nest address as an immutable constructor argument.
///
/// Usage:
///   forge script script/DeployHatch.s.sol:DeployHatch \
///     --rpc-url $ROBINHOOD_RPC_URL --broadcast --verify
///
/// Required environment:
///   PRIVATE_KEY        deployer key
///   GOVERNANCE         governance Safe address (operator supplied)
///   HOOKED_TREASURY    HOOKED treasury address
///   TEAM_TREASURY      team/ops address
/// Optional:
///   NVDA, PONS_ESCROW, PONS_FACTORY  override the canonical mainnet addresses
contract DeployHatch is Script {
    address constant NVDA_DEFAULT = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant ESCROW_DEFAULT = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant FACTORY_DEFAULT = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    uint256 constant EXPECTED_CHAIN_ID = 4663;

    function run() external {
        address nvda = vm.envOr("NVDA", NVDA_DEFAULT);
        address escrow = vm.envOr("PONS_ESCROW", ESCROW_DEFAULT);
        address factory = vm.envOr("PONS_FACTORY", FACTORY_DEFAULT);

        address governance = vm.envAddress("GOVERNANCE");
        address hookedTreasury = vm.envAddress("HOOKED_TREASURY");
        address teamTreasury = vm.envAddress("TEAM_TREASURY");

        _preflight(nvda, escrow, factory, governance, hookedTreasury, teamTreasury);

        uint256[7] memory thresholds =
            [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        HatchNestVault nest = new HatchNestVault(nvda, thresholds);
        HatchFeeRouter router = new HatchFeeRouter(
            nvda, escrow, factory, address(nest), hookedTreasury, teamTreasury, governance
        );
        HookedLaunchRegistry registry = new HookedLaunchRegistry(governance);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== HATCH DEPLOYMENT ===");
        console2.log("chain id        ", block.chainid);
        console2.log("HatchNestVault  ", address(nest));
        console2.log("HatchFeeRouter  ", address(router));
        console2.log("LaunchRegistry  ", address(registry));
        console2.log("");
        console2.log("Next: launch HATCH on PONS with creatorFeeRecipient =", address(router));
        console2.log("Then: call router.bindLaunch(<hatch token>) from governance", governance);
        console2.log("Then: record all addresses + tx hashes in docs/DEPLOYMENTS.md");
    }

    /// @dev Fails fast before spending gas if the environment is not what we expect.
    function _preflight(
        address nvda,
        address escrow,
        address factory,
        address governance,
        address hookedTreasury,
        address teamTreasury
    ) internal view {
        require(governance != address(0), "GOVERNANCE unset");
        require(hookedTreasury != address(0), "HOOKED_TREASURY unset");
        require(teamTreasury != address(0), "TEAM_TREASURY unset");

        require(nvda.code.length > 0, "no code at NVDA");
        require(escrow.code.length > 0, "no code at PONS escrow");
        require(factory.code.length > 0, "no code at PONS factory");

        if (block.chainid == EXPECTED_CHAIN_ID) {
            require(IERC20Meta(nvda).decimals() == 18, "NVDA decimals != 18");
            require(IPonsFactoryView(factory).approvedPairTokens(nvda), "NVDA not approved by PONS");
        } else {
            console2.log("WARNING: chain id is not 4663, skipping live PONS assertions");
        }
    }
}
