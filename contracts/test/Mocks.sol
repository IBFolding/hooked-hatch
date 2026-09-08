// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "../src/Interfaces.sol";

contract MockERC20 is IERC20Minimal {
    string public name = "Mock NVDA";
    string public symbol = "NVDA";
    uint8 public decimals = 18;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; return true; }
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "BAL");
        require(allowance[from][msg.sender] >= amount, "ALLOW");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockPonsEscrow {
    MockERC20 public immutable token;
    mapping(address => uint256) public credits;
    constructor(MockERC20 token_) { token = token_; }
    function credit(address recipient, uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        credits[recipient] += amount;
    }
    function claimToken(address asset) external returns (uint256 amount) {
        require(asset == address(token), "ASSET");
        amount = credits[msg.sender];
        credits[msg.sender] = 0;
        if (amount != 0) token.transfer(msg.sender, amount);
    }
    function claimToken(address asset, uint256 amount) external returns (uint256) {
        require(asset == address(token), "ASSET");
        require(credits[msg.sender] >= amount, "CREDIT");
        credits[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
        return amount;
    }
    function balanceOfToken(address recipient, address asset) external view returns (uint256) {
        return asset == address(token) ? credits[recipient] : 0;
    }
}

contract MockPonsFactory {
    address public token;
    address public recipient;
    function setLaunch(address token_, address recipient_) external { token = token_; recipient = recipient_; }
    function transferCreatorFeeRecipient(address token_, address newRecipient) external {
        require(token_ == token, "TOKEN");
        require(msg.sender == recipient, "RECIPIENT");
        recipient = newRecipient;
    }
}

/// @notice Escrow that always reverts, to prove a bad escrow cannot brick the router.
contract RevertingEscrow {
    error EscrowDown();
    function claimToken(address) external pure returns (uint256) { revert EscrowDown(); }
    function claimToken(address, uint256) external pure returns (uint256) { revert EscrowDown(); }
    function balanceOfToken(address, address) external pure returns (uint256) { revert EscrowDown(); }
}

/// @notice Malicious quote token that re-enters claimAndSplit on transfer.
contract ReenteringToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public target;

    function setTarget(address t) external { target = t; }
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount; return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        // Re-enter on the way out.
        (bool ok, bytes memory err) = target.call(abi.encodeWithSignature("claimAndSplit()"));
        if (!ok) {
            assembly { revert(add(err, 0x20), mload(err)) }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
