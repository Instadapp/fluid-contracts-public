// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract VaultT3Events {
    /// @notice emitted when the supply rate magnifier config is updated
    event LogUpdateSupplyRateMagnifier(uint supplyRateMagnifier_);

    /// @notice emitted when the borrow rate config is updated
    event LogUpdateBorrowRate(int borrowRate_);

    /// @notice emitted when the core setting configs are updated
    event LogUpdateCoreSettings(
        uint supplyRateMagnifier_,
        int borrowRate_,
        uint collateralFactor_,
        uint liquidationThreshold_,
        uint liquidationMaxLimit_,
        uint withdrawGap_,
        uint liquidationPenalty_,
        uint borrowFee_
    );
}
