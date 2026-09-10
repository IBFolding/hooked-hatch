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

interface IPonsV2BondingCurve {
    function getReserves() external view returns (uint256 quoteReserve, uint256 tokenReserve);
    function feeBps() external view returns (uint256);
    function creatorTaxBps() external view returns (uint256);
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256 tokensOut);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IHatchEgg {
    function initialise(address hatchToken, address curve) external;
    function initialiser() external view returns (address);
    function hatchToken() external view returns (address);
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
/// Optional env: HATCH_EGG - if set, initialise() is called in this same run,
///               which permanently burns the locker's initialiser role
/// Optional env: LAUNCH_CONFIG_ID (default 0), SALT_SEED, LOGO_URI, WEBSITE, TWITTER,
///               DESCRIPTION, DEV_BUY_NVDA_WEI, DEV_BUY_SLIPPAGE_BPS
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
            logo: vm.envOr("LOGO_URI", string("https://raw.githubusercontent.com/IBFolding/hooked-hatch/main/web/assets/png/hatch-pfp-robin.png")),
            description: vm.envOr(
                "DESCRIPTION",
                string(
                    "A robin's egg on Robinhood Chain, fattened on tokenized NVDA with every trade. "
                    "Creator fees split 70% Nest / 20% HOOKED / 10% team. The Nest has no withdrawal "
                    "function, no admin, governance burned. Feed the egg. Nobody knows what hatches."
                )
            ),
            socials: IPonsV2LaunchFactory.Socials({
                twitter: vm.envOr("TWITTER", string("")),
                telegram: "",
                discord: "",
                website: vm.envOr("WEBSITE", string("https://hookedlabs.vercel.app/hatch")),
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

        // Optional opening buy, in NVDA wei. The launcher is exempted from the
        // snipe tax automatically by the factory, so this clears at the untaxed
        // price without needing an exemption list.
        uint256 devBuy = vm.envOr("DEV_BUY_NVDA_WEI", uint256(0));
        uint256 slippageBps = vm.envOr("DEV_BUY_SLIPPAGE_BPS", uint256(300));
        if (devBuy > 0) {
            uint256 held = IERC20(NVDA).balanceOf(launcher);
            require(held >= devBuy, "launcher does not hold enough NVDA for the opening buy");
        }

        vm.startBroadcast(pk);
        (address token, address curve) = FACTORY.launchToken{value: fee}(params, configId, NVDA);

        // Bind the buyback locker to the launch it will buy from. This is the only
        // moment it can be done, and it burns the initialiser role permanently.
        address egg = vm.envOr("HATCH_EGG", address(0));
        if (egg != address(0)) {
            IHatchEgg(egg).initialise(token, curve);
        }

        uint256 bought;
        if (devBuy > 0) bought = _openingBuy(curve, devBuy, slippageBps, launcher);
        vm.stopBroadcast();

        if (egg != address(0)) {
            require(IHatchEgg(egg).hatchToken() == token, "egg not bound to this launch");
            require(IHatchEgg(egg).initialiser() == address(0), "egg initialiser not burned");
        }

        console2.log("");
        console2.log("HATCH token        ", token);
        console2.log("bonding curve      ", curve);
        if (devBuy > 0) {
            console2.log("opening buy (NVDA) ", devBuy);
            console2.log("HATCH received     ", bought);
        }
        console2.log("");
        console2.log("Next: put the token address in web/config.js as hatchToken, redeploy the site,");
        console2.log("and record token + curve + tx hash in docs/DEPLOYMENTS.md.");
        console2.log("NOTE: governance is burned, so bindLaunch() is intentionally NOT called.");
        if (egg != address(0)) {
            console2.log("egg bound and its initialiser is now burned:", egg);
            console2.log("After the curve graduates, call egg.configurePool(PoolKey) once so the");
            console2.log("egg can buy on the v4 pool. Before graduation it buys on the curve.");
        }
    }

    /// @dev Opening buy from the launcher, which the factory exempts from the snipe
    ///      tax automatically. Split out of run() to stay under the stack limit.
    function _openingBuy(address curve, uint256 amountIn, uint256 slippageBps, address recipient)
        internal
        returns (uint256 bought)
    {
        IPonsV2BondingCurve c = IPonsV2BondingCurve(curve);
        (uint256 qr, uint256 tr) = c.getReserves();

        uint256 netIn = amountIn
            - (amountIn * c.feeBps()) / 10_000
            - (amountIn * c.creatorTaxBps()) / 10_000;

        // Constant product, matching PonsV2BondingCurveMath.getAmountOut.
        uint256 expected = (netIn * tr) / (qr + netIn);
        uint256 minOut = (expected * (10_000 - slippageBps)) / 10_000;
        require(minOut > 0, "computed minTokensOut is zero");

        IERC20(NVDA).approve(curve, amountIn);
        bought = c.buy(amountIn, minOut, recipient);
    }
}
