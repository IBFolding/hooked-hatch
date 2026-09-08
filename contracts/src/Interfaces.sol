// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPonsV2FeeEscrow {
    function claimToken(address token) external returns (uint256 amount);
    function claimToken(address token, uint256 amount) external returns (uint256 claimed);
    function balanceOfToken(address recipient, address token) external view returns (uint256);
}

interface IPonsV2LaunchFactoryRecipient {
    function transferCreatorFeeRecipient(address token, address newRecipient) external;
}
