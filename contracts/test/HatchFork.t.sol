// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HatchEgg} from "../src/HatchEgg.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {PoolKey, Currency} from "../src/IUniswapV4.sol";

interface IFactory {
    struct Socials { string twitter; string telegram; string discord; string website; string farcaster; }
    struct TokenParams {
        string name; string symbol; string logo; string description; Socials socials;
        address creatorFeeRecipient; uint16 creatorTaxBps; bool buybackEnabled;
        bytes32 expectedEconomics; bytes32 salt;
    }
    function launchToken(TokenParams calldata p, uint256 configId, address pairToken)
        external payable returns (address token, address curve);
    function previewLaunchEconomics(uint256, address) external view returns (bytes32);
    function launchFee() external view returns (uint256);
    function approvedPairTokens(address) external view returns (bool);
    function graduate(address token) external;
    function createGraduatedPool(address token) external returns (uint256);
}

interface ICurve {
    function buy(uint256, uint256, address) external returns (uint256);
    function graduated() external view returns (bool);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @notice Cracks the egg against the REAL PONS protocol and the live v4 pool.
contract HatchForkTest is Test {
    IFactory constant FACTORY = IFactory(0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e);
    address constant ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant MEME_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address constant WHALE = 0xFe7E25dE55e5cBbEcCcb661F3679F873f72B9b0D;

    HatchEgg egg;
    HatchFeeRouter router;
    address token;
    address curve;
    bool forked;

    uint256 constant CRACK = 5 ether; // small, so a fork whale can fill it
    uint256[7] T = [uint256(0.1 ether), 0.5 ether, 1 ether, 2 ether, 3 ether, 4 ether, CRACK];

    function setUp() public {
        string memory url = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        try vm.createSelectFork(url) { forked = true; } catch { return; }

        egg = new HatchEgg(NVDA, POOL_MANAGER, address(this), T);
        router = new HatchFeeRouter(
            NVDA, ESCROW, address(FACTORY), address(egg), address(0xA11CE), address(0xB0B), address(0xdEaD)
        );

        IFactory.TokenParams memory p = IFactory.TokenParams({
            name: "HATCH", symbol: "HATCH", logo: "", description: "fork",
            socials: IFactory.Socials("", "", "", "", ""),
            creatorFeeRecipient: address(router),
            creatorTaxBps: 0, buybackEnabled: false,
            expectedEconomics: FACTORY.previewLaunchEconomics(0, NVDA),
            salt: keccak256(abi.encodePacked("hatch-egg-fork", address(this)))
        });
        vm.deal(address(this), 1 ether);
        (token, curve) = FACTORY.launchToken{value: FACTORY.launchFee()}(p, 0, NVDA);
        egg.initialise(token, curve);
    }

    modifier onlyForked() {
        if (!forked) { emit log("SKIP: set ROBINHOOD_RPC_URL"); return; }
        _;
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(WHALE);
        IERC20(NVDA).transfer(to, amount);
    }

    function test_LiveWiring() public onlyForked {
        assertTrue(FACTORY.approvedPairTokens(NVDA), "NVDA not approved");
        assertEq(IERC20(NVDA).decimals(), 18, "decimals");
        assertEq(egg.hatchToken(), token, "egg not bound");
        assertEq(egg.initialiser(), address(0), "initialiser not burned");
    }

    /// @dev Crack on the live bonding curve and prove supply actually falls.
    function test_CrackOnLiveCurve_BurnsRealSupply() public onlyForked {
        _fund(address(egg), CRACK);
        assertTrue(egg.crackable(), "not crackable");

        uint256 supplyBefore = IERC20(token).totalSupply();
        address cracker = address(0xC4AC);

        vm.prank(cracker);
        (uint256 bounty, uint256 spent, uint256 burned) = egg.crackEgg(1);

        assertEq(bounty, (CRACK * 500) / 10_000, "bounty is 5%");
        assertEq(bounty + spent, CRACK, "value conserved");
        assertEq(IERC20(NVDA).balanceOf(cracker), bounty, "cracker not paid");
        assertGt(burned, 0, "nothing bought");

        uint256 supplyAfter = IERC20(token).totalSupply();
        assertEq(supplyBefore - supplyAfter, burned, "supply did not fall by the burn");
        assertEq(IERC20(token).balanceOf(address(egg)), 0, "egg still holds HATCH");
        assertEq(egg.eggBalance(), 0, "egg not emptied");

        emit log_named_decimal_uint("bounty paid  (NVDA)", bounty, 18);
        emit log_named_decimal_uint("HATCH burned       ", burned, 18);
        emit log_named_decimal_uint("supply removed     ", supplyBefore - supplyAfter, 18);
    }

    /// @dev Graduate the curve, wire the real v4 pool, crack through it.
    function test_CrackAfterGraduation_ViaUniswapV4() public onlyForked {
        _fund(address(this), 60 ether);
        IERC20(NVDA).approve(curve, 60 ether);
        ICurve(curve).buy(60 ether, 0, address(this));

        try FACTORY.graduate(token) { emit log("graduate() called"); }
        catch { emit log("already graduated by the buy"); }
        try FACTORY.createGraduatedPool(token) returns (uint256 id) {
            emit log_named_uint("graduated pool id", id);
        } catch { emit log("pool already created"); }
        assertTrue(ICurve(curve).graduated(), "did not graduate");

        (address c0, address c1) = token < NVDA ? (token, NVDA) : (NVDA, token);
        egg.configurePool(PoolKey({
            currency0: Currency.wrap(c0), currency1: Currency.wrap(c1),
            fee: 0, tickSpacing: 200, hooks: MEME_HOOK
        }));

        _fund(address(egg), CRACK);
        uint256 supplyBefore = IERC20(token).totalSupply();

        vm.prank(address(0xC4AC2));
        (uint256 bounty,, uint256 burned) = egg.crackEgg(1);

        assertGt(burned, 0, "v4 crack bought nothing");
        assertEq(supplyBefore - IERC20(token).totalSupply(), burned, "supply did not fall");
        assertEq(egg.eggBalance(), 0, "egg not emptied");
        emit log_named_decimal_uint("HATCH burned via v4", burned, 18);
        emit log_named_decimal_uint("bounty paid (NVDA) ", bounty, 18);
    }

    /// @dev The flywheel must repeat, not fire once.
    function test_MultipleCyclesOnCurve() public onlyForked {
        for (uint256 i = 1; i <= 3; ++i) {
            _fund(address(egg), CRACK);
            vm.prank(address(0xC4AC));
            egg.crackEgg(1);
            assertEq(egg.crackCount(), i, "cycle");
            assertEq(egg.eggBalance(), 0, "not emptied");
        }
        emit log_named_decimal_uint("burned over 3 cracks", egg.totalBurned(), 18);
    }
}
