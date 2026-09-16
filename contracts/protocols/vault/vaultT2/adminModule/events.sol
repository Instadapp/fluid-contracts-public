// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract VaultT2Events {
    /// @notice emitted when the supply rate config is updated
    event LogUpdateSupplyRate(int supplyRate_);

    /// @notice emitted when the borrow rate magnifier config is updated
    event LogUpdateBorrowRateMagnifier(uint borrowRateMagnifier_);

    /// @notice emitted when the core setting configs are updated
    event LogUpdateCoreSettings(
        int supplyRate_,
        uint borrowRateMagnifier_,
        uint collateralFactor_,
        uint liquidationThreshold_,
        uint liquidationMaxLimit_,
        uint withdrawGap_,
        uint liquidationPenalty_,
        uint borrowFee_
    );
}
