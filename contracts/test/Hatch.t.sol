// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {HatchNestVault} from "../src/HatchNestVault.sol";
import {HatchFeeRouter} from "../src/HatchFeeRouter.sol";
import {MockERC20, MockPonsEscrow, MockPonsFactory} from "./Mocks.sol";

contract HatchTest {
    MockERC20 token;
    MockPonsEscrow escrow;
    MockPonsFactory factory;
    HatchNestVault nest;
    HatchFeeRouter router;

    address hooked = address(0xBEEF);
    address team = address(0xCAFE);

    constructor() {
        token = new MockERC20();
        escrow = new MockPonsEscrow(token);
        factory = new MockPonsFactory();
        uint256[7] memory t = [uint256(1 ether), 5 ether, 10 ether, 25 ether, 50 ether, 100 ether, 250 ether];
        nest = new HatchNestVault(address(token), t);
        router = new HatchFeeRouter(address(token), address(escrow), address(factory), address(nest), hooked, team, address(this));
    }

    function testFeeSplit701020() public {
        token.mint(address(this), 100 ether);
        token.approve(address(escrow), 100 ether);
        escrow.credit(address(router), 100 ether);

        router.claimAndSplit();

        require(token.balanceOf(address(nest)) == 70 ether, "nest != 70%");
        require(token.balanceOf(hooked) == 20 ether, "hooked != 20%");
        require(token.balanceOf(team) == 10 ether, "team != 10%");
        require(token.balanceOf(address(router)) == 0, "router dust");
    }

    function testNestStages() public {
        token.mint(address(this), 25 ether);
        token.approve(address(nest), 25 ether);
        require(nest.stage() == 0, "stage0");
        nest.feed(1 ether);
        require(nest.stage() == 1, "stage1");
        nest.feed(4 ether);
        require(nest.stage() == 2, "stage2");
        nest.feed(20 ether);
        require(nest.stage() == 4, "stage4");
    }

    function testMigrationAfterBind() public {
        address hatch = address(0x1234);
        router.bindLaunch(hatch);
        factory.setLaunch(hatch, address(router));
        router.migratePonsRecipient(address(0x9999));
        require(factory.recipient() == address(0x9999), "migration failed");
    }
}
