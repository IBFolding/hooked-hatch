// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Minimal deployment helper. Codex can wrap this in forge-std/Script for broadcast.
import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {HookedLaunchRegistry} from "../src/HookedLaunchRegistry.sol";

contract DeployHatch {
    struct Deployment {
        address nest;
        address router;
        address registry;
    }

    function deploy(
        address nvda,
        address ponsEscrow,
        address ponsFactory,
        address hookedTreasury,
        address teamTreasury,
        address governance
    ) external returns (Deployment memory d) {
        uint256[7] memory thresholds = [
            uint256(1 ether),
            5 ether,
            10 ether,
            25 ether,
            50 ether,
            100 ether,
            250 ether
        ];
        HatchNestVault nest = new HatchNestVault(nvda, thresholds);
        HatchFeeRouter router = new HatchFeeRouter(
            nvda, ponsEscrow, ponsFactory, address(nest), hookedTreasury, teamTreasury, governance
        );
        HookedLaunchRegistry registry = new HookedLaunchRegistry(governance);
        d = Deployment(address(nest), address(router), address(registry));
    }
}
