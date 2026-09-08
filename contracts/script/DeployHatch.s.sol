// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouterV2} from "../src/HatchFeeRouterV2.sol";
import {HatchBuybackLocker} from "../src/HatchBuybackLocker.sol";
import {HookedLaunchRegistry} from "../src/HookedLaunchRegistry.sol";

interface IPonsFactoryView {
    function approvedPairTokens(address token) external view returns (bool);
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
}

/// @notice Deploys the HATCH mechanism contracts in the required order.
/// @dev Deployment order is Nest -> BuybackLocker -> Router, because each takes the
///      previous addresses as immutable constructor arguments.
///
///      The locker's initialiser is the deployer. It is a ONE-SHOT role: calling
///      initialise() after the PONS launch zeroes it permanently. The launch script
///      does that in the same run, so the window is a single transaction wide.
///
/// Usage:
///   forge script script/DeployHatch.s.sol:DeployHatch \
///     --rpc-url $ROBINHOOD_RPC_URL --broadcast --verify
///
/// Required environment:
///   PRIVATE_KEY         deployer key
///   HOOKED_TREASURY     HOOKED community treasury (receives 20%)
///   TEAM_TREASURY       team/ops address (receives 10%)
/// Optional:
///   ROUTER_GOVERNANCE   defaults to the burn address - see below
///   DEPLOY_REGISTRY     "true" to also deploy HookedLaunchRegistry (default false)
///   REGISTRY_GOVERNANCE required only when DEPLOY_REGISTRY is true
///   NVDA, PONS_ESCROW, PONS_FACTORY  override the canonical mainnet addresses
///
/// GOVERNANCE IS BURNED BY DEFAULT.
/// HOOKED ships HATCH with no privileged actor. The consequence is permanent:
/// bindLaunch() and migratePonsRecipient() can never be called, so PONS creator
/// fees can never be redirected away from this router. The mechanism itself is
/// unaffected - claimAndSplit() is permissionless and the split is immutable.
/// Note the router rejects address(0), so a burn uses 0x...dEaD.
contract DeployHatch is Script {
    address constant NVDA_DEFAULT = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant ESCROW_DEFAULT = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant FACTORY_DEFAULT = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant POOL_MANAGER_DEFAULT = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    uint256 constant EXPECTED_CHAIN_ID = 4663;

    /// @dev The router constructor rejects address(0), so a burn must be a real address.
    address constant BURN = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        address nvda = vm.envOr("NVDA", NVDA_DEFAULT);
        address escrow = vm.envOr("PONS_ESCROW", ESCROW_DEFAULT);
        address factory = vm.envOr("PONS_FACTORY", FACTORY_DEFAULT);
        address poolManager = vm.envOr("POOL_MANAGER", POOL_MANAGER_DEFAULT);

        address governance = vm.envOr("ROUTER_GOVERNANCE", BURN);
        address hookedTreasury = vm.envAddress("HOOKED_TREASURY");
        address teamTreasury = vm.envAddress("TEAM_TREASURY");
        bool deployRegistry = vm.envOr("DEPLOY_REGISTRY", false);

        _preflight(nvda, escrow, factory, governance, hookedTreasury, teamTreasury);

        uint256[7] memory thresholds =
            [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        HatchNestVault nest = new HatchNestVault(nvda, thresholds);

        // The deployer is the locker's one-shot initialiser; LaunchHatch burns it.
        HatchBuybackLocker locker =
            new HatchBuybackLocker(nvda, address(nest), poolManager, vm.addr(vm.envUint("PRIVATE_KEY")));

        HatchFeeRouterV2 router = new HatchFeeRouterV2(
            nvda, escrow, factory, address(nest), address(locker), hookedTreasury, teamTreasury, governance
        );

        // The registry is optional and NOT required to launch. Its governance must
        // stay live: a burned registry can never register a launch, which would make
        // it permanently useless.
        address registry;
        if (deployRegistry) {
            registry = address(new HookedLaunchRegistry(vm.envAddress("REGISTRY_GOVERNANCE")));
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== HATCH DEPLOYMENT ===");
        console2.log("chain id        ", block.chainid);
        console2.log("HatchNestVault  ", address(nest));
        console2.log("BuybackLocker   ", address(locker));
        console2.log("HatchFeeRouter  ", address(router));
        if (deployRegistry) console2.log("LaunchRegistry  ", registry);
        console2.log("");
        console2.log("nest     50%  ->", address(nest));
        console2.log("buyback  20%  ->", address(locker));
        console2.log("hooked   20%  ->", hookedTreasury);
        console2.log("team     10%  ->", teamTreasury);
        console2.log("");
        if (governance == BURN) {
            console2.log("GOVERNANCE IS BURNED:", governance);
            console2.log("bindLaunch and migratePonsRecipient are permanently unreachable.");
            console2.log("claimAndSplit stays permissionless - the mechanism is unaffected.");
        } else {
            console2.log("governance      ", governance);
        }
        console2.log("");
        console2.log("Next: launch HATCH on PONS with creatorFeeRecipient =", address(router));
        console2.log("      then LaunchHatch calls locker.initialise(token, curve)");
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
        require(governance != address(0), "governance cannot be address(0) - use 0x..dEaD to burn");
        require(hookedTreasury != address(0), "HOOKED_TREASURY unset");
        require(teamTreasury != address(0), "TEAM_TREASURY unset");
        require(hookedTreasury != teamTreasury, "treasury and team must differ - the 20% must be auditable");

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
