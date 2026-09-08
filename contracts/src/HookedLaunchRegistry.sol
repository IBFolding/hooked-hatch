// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title HookedLaunchRegistry
/// @notice Lightweight registry for HOOKED experiments. It does not custody tokens or fees.
contract HookedLaunchRegistry {
    error NotGovernance();
    error ZeroAddress();
    error SlugTaken();
    error LaunchNotFound();

    struct Launch {
        uint256 id;
        bytes32 slug;
        address token;
        address quoteToken;
        address feeRouter;
        address mechanismVault;
        bool live;
    }

    address public immutable governance;
    uint256 public launchCount;
    mapping(uint256 => Launch) public launches;
    mapping(bytes32 => uint256) public idBySlug;

    event LaunchRegistered(uint256 indexed id, bytes32 indexed slug, address indexed token, address quoteToken);
    event LaunchStatusChanged(uint256 indexed id, bool live);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    constructor(address governance_) {
        if (governance_ == address(0)) revert ZeroAddress();
        governance = governance_;
    }

    function register(
        bytes32 slug,
        address token,
        address quoteToken,
        address feeRouter,
        address mechanismVault
    ) external onlyGovernance returns (uint256 id) {
        if (slug == bytes32(0) || token == address(0) || quoteToken == address(0)) revert ZeroAddress();
        if (idBySlug[slug] != 0) revert SlugTaken();

        id = ++launchCount;
        launches[id] = Launch({
            id: id,
            slug: slug,
            token: token,
            quoteToken: quoteToken,
            feeRouter: feeRouter,
            mechanismVault: mechanismVault,
            live: true
        });
        idBySlug[slug] = id;
        emit LaunchRegistered(id, slug, token, quoteToken);
    }

    function setLive(uint256 id, bool live) external onlyGovernance {
        if (launches[id].id == 0) revert LaunchNotFound();
        launches[id].live = live;
        emit LaunchStatusChanged(id, live);
    }
}
