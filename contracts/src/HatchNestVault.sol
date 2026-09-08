// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Minimal} from "./Interfaces.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

/// @title HatchNestVault
/// @notice Permanently accumulates the HATCH quote asset (NVDA).
/// @dev There is intentionally no withdrawal function for `asset`.
contract HatchNestVault {
    using SafeTransferLib for address;

    error ZeroAddress();
    error ZeroAmount();

    address public immutable asset;

    // Thresholds are expressed in the quote token's native units. NVDA uses 18 decimals.
    uint256[7] public thresholds;

    event Fed(address indexed feeder, uint256 amount, uint256 newBalance, uint8 stage);

    constructor(address asset_, uint256[7] memory thresholds_) {
        if (asset_ == address(0)) revert ZeroAddress();
        for (uint256 i = 1; i < thresholds_.length; ++i) {
            require(thresholds_[i] > thresholds_[i - 1], "THRESHOLDS_NOT_ASCENDING");
        }
        asset = asset_;
        thresholds = thresholds_;
    }

    /// @notice Anyone may directly feed NVDA to the egg after approving this vault.
    function feed(uint256 amount) external returns (uint256 newBalance) {
        if (amount == 0) revert ZeroAmount();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        newBalance = nestBalance();
        emit Fed(msg.sender, amount, newBalance, stage());
    }

    function nestBalance() public view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @return Current stage 0-7. Stage 7 means all configured milestones are cleared.
    function stage() public view returns (uint8) {
        uint256 balance = nestBalance();
        uint8 s;
        for (uint8 i = 0; i < 7; ++i) {
            if (balance < thresholds[i]) break;
            unchecked { ++s; }
        }
        return s;
    }

    function nextThreshold() external view returns (uint256) {
        uint8 s = stage();
        return s >= 7 ? 0 : thresholds[s];
    }

    function progressBps() external view returns (uint256) {
        uint8 s = stage();
        if (s >= 7) return 10_000;
        uint256 low = s == 0 ? 0 : thresholds[s - 1];
        uint256 high = thresholds[s];
        uint256 balance = nestBalance();
        if (balance <= low) return 0;
        return ((balance - low) * 10_000) / (high - low);
    }
}
