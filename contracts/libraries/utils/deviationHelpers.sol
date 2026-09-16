// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

/// @title DeviationHelpers
/// @notice Whether a value lies outside a percent band of a base (`|value − base| / base`).
/// @dev `precision_` = 100% scale (e.g. `1e4` or `1e6`). Same magnitude as config `_percentDiffForValue` helpers.
library DeviationHelpers {
    /// @param maxDeviationPercent_ Max `|value − base| / base` in `precision_` units (e.g. `100` @ `1e4` → 1%).
    /// @return True if `|value − base| >` allowed band (exact ±band is still in-band).
    function isOutsideDeviation(
        uint256 base_,
        uint256 value_,
        uint256 maxDeviationPercent_,
        uint256 precision_
    ) internal pure returns (bool) {
        if (base_ == 0) return value_ != 0;
        if (precision_ == 0) return true;

        // Checked: reverts on `base_ * maxDeviationPercent_` overflow.
        uint256 maxDiff_ = base_ * maxDeviationPercent_;

        unchecked {
            maxDiff_ /= precision_;
            uint256 diff_ = value_ > base_ ? value_ - base_ : base_ - value_;
            return diff_ > maxDiff_;
        }
    }
}
