// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract VaultT4Events {
    /// @notice emitted when the supply rate config is updated
    event LogUpdateSupplyRate(int supplyRate_);

    /// @notice emitted when the borrow rate config is updated
    event LogUpdateBorrowRate(int borrowRate_);

    /// @notice emitted when the core setting configs are updated
    event LogUpdateCoreSettings(
        int supplyRate_,
        int borrowRate_,
        uint collateralFactor_,
        uint liquidationThreshold_,
        uint liquidationMaxLimit_,
        uint withdrawGap_,
        uint liquidationPenalty_,
        uint borrowFee_
    );
}
