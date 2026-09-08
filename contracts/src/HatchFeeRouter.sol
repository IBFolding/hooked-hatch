// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal, IPonsV2FeeEscrow, IPonsV2LaunchFactoryRecipient} from "./Interfaces.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

/// @title HatchFeeRouter
/// @notice PONS creatorFeeRecipient for HATCH. Claims quote-asset fees and splits them deterministically.
contract HatchFeeRouter {
    using SafeTransferLib for address;

    uint256 public constant BPS = 10_000;
    uint256 public constant NEST_BPS = 7_000;
    uint256 public constant HOOKED_BPS = 2_000;
    uint256 public constant TEAM_BPS = 1_000;

    error ZeroAddress();
    error NotGovernance();
    error AlreadyBound();
    error NotBound();
    error ReentrantCall();

    address public immutable quoteToken;
    IPonsV2FeeEscrow public immutable ponsEscrow;
    IPonsV2LaunchFactoryRecipient public immutable ponsFactory;
    address public immutable nest;
    address public immutable hookedTreasury;
    address public immutable teamTreasury;
    address public immutable governance;

    address public hatchToken;
    /// @dev 1 = not entered, 2 = entered. Initialised to 1 so the slot is never cold-written mid-call.
    uint256 private _entered = 1;

    event LaunchBound(address indexed hatchToken);
    event FeesSplit(uint256 total, uint256 nestAmount, uint256 hookedAmount, uint256 teamAmount);
    event PonsRecipientMigrated(address indexed hatchToken, address indexed newRecipient);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    modifier nonReentrant() {
        if (_entered != 1) revert ReentrantCall();
        _entered = 2;
        _;
        _entered = 1;
    }

    constructor(
        address quoteToken_,
        address ponsEscrow_,
        address ponsFactory_,
        address nest_,
        address hookedTreasury_,
        address teamTreasury_,
        address governance_
    ) {
        if (
            quoteToken_ == address(0) || ponsEscrow_ == address(0) || ponsFactory_ == address(0)
                || nest_ == address(0) || hookedTreasury_ == address(0) || teamTreasury_ == address(0)
                || governance_ == address(0)
        ) revert ZeroAddress();

        quoteToken = quoteToken_;
        ponsEscrow = IPonsV2FeeEscrow(ponsEscrow_);
        ponsFactory = IPonsV2LaunchFactoryRecipient(ponsFactory_);
        nest = nest_;
        hookedTreasury = hookedTreasury_;
        teamTreasury = teamTreasury_;
        governance = governance_;
    }

    /// @notice Bind the PONS-created HATCH token after launch. Needed only for future recipient migration.
    function bindLaunch(address hatchToken_) external onlyGovernance {
        if (hatchToken != address(0)) revert AlreadyBound();
        if (hatchToken_ == address(0)) revert ZeroAddress();
        hatchToken = hatchToken_;
        emit LaunchBound(hatchToken_);
    }

    /// @notice PONS escrow amount currently credited to this fee recipient.
    /// @dev Returns 0 rather than reverting so a read-only frontend never breaks on escrow changes.
    function pendingPonsFees() external view returns (uint256) {
        try ponsEscrow.balanceOfToken(address(this), quoteToken) returns (uint256 pending) {
            return pending;
        } catch {
            return 0;
        }
    }

    /// @notice Total quote asset this call would distribute right now (escrow credit + stray router balance).
    function claimableTotal() external view returns (uint256) {
        uint256 pending;
        try ponsEscrow.balanceOfToken(address(this), quoteToken) returns (uint256 p) { pending = p; } catch {}
        return pending + IERC20Minimal(quoteToken).balanceOf(address(this));
    }

    /// @notice Claim all PONS NVDA fees and split the router's entire NVDA balance 70/20/10.
    /// @dev Permissionless so any user/keeper can advance the Nest. Caller receives no fee.
    function claimAndSplit()
        external
        nonReentrant
        returns (uint256 total, uint256 nestAmount, uint256 hookedAmount, uint256 teamAmount)
    {
        // A revert here (e.g. PONS reverting on a zero credit) must not block distributing
        // quote tokens the router already holds, including tokens sent here directly.
        try ponsEscrow.claimToken(quoteToken) returns (uint256) {} catch {}

        total = IERC20Minimal(quoteToken).balanceOf(address(this));
        if (total == 0) return (0, 0, 0, 0);

        nestAmount = (total * NEST_BPS) / BPS;
        hookedAmount = (total * HOOKED_BPS) / BPS;
        // Remainder goes to team so integer dust never stays stranded in the router.
        teamAmount = total - nestAmount - hookedAmount;

        quoteToken.safeTransfer(nest, nestAmount);
        quoteToken.safeTransfer(hookedTreasury, hookedAmount);
        quoteToken.safeTransfer(teamTreasury, teamAmount);

        emit FeesSplit(total, nestAmount, hookedAmount, teamAmount);
    }

    /// @notice Governance escape hatch for future PONS creator-fee recipient migration.
    /// @dev Does not unlock or move anything already stored in the Nest.
    function migratePonsRecipient(address newRecipient) external onlyGovernance {
        if (hatchToken == address(0)) revert NotBound();
        if (newRecipient == address(0)) revert ZeroAddress();
        ponsFactory.transferCreatorFeeRecipient(hatchToken, newRecipient);
        emit PonsRecipientMigrated(hatchToken, newRecipient);
    }
}
