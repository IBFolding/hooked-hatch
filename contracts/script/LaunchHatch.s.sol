// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/// @dev Mirrors the deployed PONS V2 factory. Struct field order is taken from the
///      official source (ponsdotdev/ponsfamily, contractsV2/src/v2/PonsV2LaunchFactory.sol)
///      and the 3-argument overload selector 0xf35abbcf was confirmed present in the
///      deployed bytecode. Do not reorder these fields.
interface IPonsV2LaunchFactory {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct TokenParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address creatorFeeRecipient;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        bytes32 expectedEconomics;
        bytes32 salt;
    }

    function launchToken(TokenParams calldata params, uint256 launchConfigId, address pairToken)
        external
        payable
        returns (address token, address curve);

    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        external
        view
        returns (bytes32);

    function launchFee() external view returns (uint256);
    function launchEnabled() external view returns (bool);
    function canLaunch(address account) external view returns (bool);
    function approvedPairTokens(address token) external view returns (bool);
}

/// @notice Launches HATCH on PONS V2 with the deployed HatchFeeRouter as creator-fee recipient.
///
/// Run AFTER DeployHatch, because this needs the router address.
///
///   FEE_ROUTER=0x... SALT_SEED="hatch-001" \
///   forge script script/LaunchHatch.s.sol:LaunchHatch \
///     --rpc-url $ROBINHOOD_RPC_URL --broadcast
///
/// Required env: PRIVATE_KEY, FEE_ROUTER
/// Optional env: LAUNCH_CONFIG_ID (default 0), SALT_SEED, LOGO_URI, WEBSITE, TWITTER
contract LaunchHatch is Script {
    IPonsV2LaunchFactory constant FACTORY =
        IPonsV2LaunchFactory(0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e);
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    uint256 constant EXPECTED_CHAIN_ID = 4663;

    function run() external {
        require(block.chainid == EXPECTED_CHAIN_ID, "wrong chain");

        address router = vm.envAddress("FEE_ROUTER");
        require(router.code.length > 0, "FEE_ROUTER has no code - deploy it first");

        uint256 configId = vm.envOr("LAUNCH_CONFIG_ID", uint256(0));
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address launcher = vm.addr(pk);

        // --- preflight against live protocol state -------------------------
        require(FACTORY.launchEnabled(), "PONS launches are disabled");
        require(FACTORY.canLaunch(launcher), "this account is not permitted to launch");
        require(FACTORY.approvedPairTokens(NVDA), "NVDA is not an approved pair token");

        uint256 fee = FACTORY.launchFee();
        require(launcher.balance > fee, "launcher cannot cover the launch fee + gas");

        // Read the economics digest fresh, at signing time. Never hard-code it:
        // it pins every owner-controlled term so an owner re-peg cannot land
        // underneath this launch.
        bytes32 economics = FACTORY.previewLaunchEconomics(configId, NVDA);
        require(economics != bytes32(0), "no economics for this config/pair");

        // Salt is namespaced per initiating account, so it only needs to be
        // unused by THIS launcher.
        bytes32 salt = keccak256(
            abi.encodePacked(vm.envOr("SALT_SEED", string("HOOKED-HATCH-001")), launcher, block.chainid)
        );

        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: "HATCH",
            symbol: "HATCH",
            logo: vm.envOr("LOGO_URI", string("https://hooked-lab.vercel.app/assets/hatch-pfp.svg")),
            description: "Feed the egg. Every trade routes creator-fee NVDA into the HATCH Nest. The Nest has no withdrawal function.",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: vm.envOr("TWITTER", string("")),
                telegram: "",
                discord: "",
                website: vm.envOr("WEBSITE", string("https://hooked-lab.vercel.app/hatch")),
                farcaster: ""
            }),
            creatorFeeRecipient: router,
            creatorTaxBps: 0,          // locked product decision: 0% additional creator tax
            buybackEnabled: false,     // locked product decision: buyback OFF for V1
            expectedEconomics: economics,
            salt: salt
        });

        console2.log("=== LAUNCHING HATCH ON PONS ===");
        console2.log("launcher           ", launcher);
        console2.log("creatorFeeRecipient", router);
        console2.log("pairToken (NVDA)   ", NVDA);
        console2.log("launchConfigId     ", configId);
        console2.log("creatorTaxBps       0");
        console2.log("buybackEnabled      false");
        console2.log("launchFee (wei)    ", fee);
        console2.logBytes32(economics);

        vm.startBroadcast(pk);
        (address token, address curve) = FACTORY.launchToken{value: fee}(params, configId, NVDA);
        vm.stopBroadcast();

        console2.log("");
        console2.log("HATCH token        ", token);
        console2.log("bonding curve      ", curve);
        console2.log("");
        console2.log("Next: put the token address in web/config.js as hatchToken, redeploy the site,");
        console2.log("and record token + curve + tx hash in docs/DEPLOYMENTS.md.");
        console2.log("NOTE: governance is burned, so bindLaunch() is intentionally NOT called.");
    }
}
