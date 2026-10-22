// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title Oracle utils library
/// @notice implements common utility methods for Fluid Oracles
library OracleUtils {
    /// @dev The scaler for max delta point math (100%)
    uint256 internal constant HUNDRED_PERCENT_DELTA_SCALER = 10_000;
    /// @dev output precision of rates
    uint256 internal constant RATE_OUTPUT_DECIMALS = 27;

    /// @dev checks if `mainSourceRate_` is within a `maxDeltaPercent_` of `checkSourceRate_`. Returns true if so.
    function isRateOutsideDelta(
        uint256 mainSourceRate_,
        uint256 checkSourceRate_,
        uint256 maxDeltaPercent_
    ) internal pure returns (bool) {
        uint256 offset_ = (checkSourceRate_ * maxDeltaPercent_) / HUNDRED_PERCENT_DELTA_SCALER;
        return (mainSourceRate_ > (checkSourceRate_ + offset_) || mainSourceRate_ < (checkSourceRate_ - offset_));
    }
}
