// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HatchEgg} from "../src/HatchEgg.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";

interface IPonsFactoryView {
    function approvedPairTokens(address token) external view returns (bool);
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
}

/// @notice Deploys the HATCH mechanism: the egg, then the fee router that fills it.
///
/// @dev Order is Egg -> Router, because the router takes the egg as an immutable
///      constructor argument.
///
///      The egg's initialiser is the deployer. It is a ONE-SHOT role: LaunchHatch
///      calls initialise() in the same run as the launch, which zeroes it forever.
///
///      Router governance is BURNED by default. bindLaunch/migratePonsRecipient can
///      never be called. The mechanism does not need them: claimAndSplit and
///      crackEgg are both permissionless.
///
/// Usage:
///   forge script script/DeployHatch.s.sol:DeployHatch \
///     --rpc-url $ROBINHOOD_RPC_URL --broadcast --verify
///
/// Required env: PRIVATE_KEY, HOOKED_TREASURY, TEAM_TREASURY
/// Optional env: ROUTER_GOVERNANCE (default burn), CRACK_THRESHOLD_ETHER (default 50),
///               NVDA, PONS_ESCROW, PONS_FACTORY, POOL_MANAGER
contract DeployHatch is Script {
    address constant NVDA_DEFAULT = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant ESCROW_DEFAULT = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant FACTORY_DEFAULT = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant POOL_MANAGER_DEFAULT = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    uint256 constant EXPECTED_CHAIN_ID = 4663;

    function run() external {
        address nvda = vm.envOr("NVDA", NVDA_DEFAULT);
        address escrow = vm.envOr("PONS_ESCROW", ESCROW_DEFAULT);
        address factory = vm.envOr("PONS_FACTORY", FACTORY_DEFAULT);
        address poolManager = vm.envOr("POOL_MANAGER", POOL_MANAGER_DEFAULT);

        address governance = vm.envOr("ROUTER_GOVERNANCE", BURN);
        address hookedTreasury = vm.envAddress("HOOKED_TREASURY");
        address teamTreasury = vm.envAddress("TEAM_TREASURY");
        // Round 1's size, how much each later round grows, and the ceiling.
        uint256 base = vm.envOr("CRACK_THRESHOLD_ETHER", uint256(5)) * 1 ether;
        uint256 growthBps = vm.envOr("CRACK_GROWTH_BPS", uint256(20_000)); // 2x per round
        uint256 maxCrack = vm.envOr("CRACK_MAX_ETHER", uint256(250)) * 1 ether;

        _preflight(nvda, escrow, factory, governance, hookedTreasury, teamTreasury);
        require(hookedTreasury != teamTreasury, "treasury and team must differ - the 20% must be auditable");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        HatchEgg egg = new HatchEgg(nvda, poolManager, vm.addr(pk), base, growthBps, maxCrack);
        HatchFeeRouter router =
            new HatchFeeRouter(nvda, escrow, factory, address(egg), hookedTreasury, teamTreasury, governance);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== HATCH DEPLOYMENT ===");
        console2.log("chain id        ", block.chainid);
        console2.log("HatchEgg        ", address(egg));
        console2.log("HatchFeeRouter  ", address(router));
        console2.log("");
        console2.log("egg      70%  ->", address(egg));
        console2.log("hooked   20%  ->", hookedTreasury);
        console2.log("team     10%  ->", teamTreasury);
        console2.log("round 1 cracks at (NVDA wei)", base);
        console2.log("each round grows by (bps)   ", growthBps);
        console2.log("capped at (NVDA wei)        ", maxCrack);
        console2.log("cracker bounty  5% of the egg");
        console2.log("");
        if (governance == BURN) {
            console2.log("GOVERNANCE IS BURNED:", governance);
            console2.log("No admin exists. claimAndSplit and crackEgg are permissionless.");
        } else {
            console2.log("governance      ", governance);
        }
        console2.log("");
        console2.log("Next: launch HATCH on PONS with creatorFeeRecipient =", address(router));
        console2.log("      LaunchHatch then calls egg.initialise(token, curve)");
    }

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
