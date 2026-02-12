// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Events {
    /// @notice emitted when the supply rate magnifier config is updated
    event LogUpdateSupplyRateMagnifier(uint supplyRateMagnifier_);

    /// @notice emitted when the borrow rate magnifier config is updated
    event LogUpdateBorrowRateMagnifier(uint borrowRateMagnifier_);

    /// @notice emitted when the collateral factor config is updated
    event LogUpdateCollateralFactor(uint collateralFactor_);

    /// @notice emitted when the liquidation threshold config is updated
    event LogUpdateLiquidationThreshold(uint liquidationThreshold_);

    /// @notice emitted when the liquidation max limit config is updated
    event LogUpdateLiquidationMaxLimit(uint liquidationMaxLimit_);

    /// @notice emitted when the withdrawal gap config is updated
    event LogUpdateWithdrawGap(uint withdrawGap_);

    /// @notice emitted when the liquidation penalty config is updated
    event LogUpdateLiquidationPenalty(uint liquidationPenalty_);

    /// @notice emitted when the borrow fee config is updated
    event LogUpdateBorrowFee(uint borrowFee_);

    /// @notice emitted when the core setting configs are updated
    event LogUpdateCoreSettings(
        uint supplyRateMagnifier_,
        uint borrowRateMagnifier_,
        uint collateralFactor_,
        uint liquidationThreshold_,
        uint liquidationMaxLimit_,
        uint withdrawGap_,
        uint liquidationPenalty_,
        uint borrowFee_
    );

    /// @notice emitted when the oracle is updated
    event LogUpdateOracle(address indexed newOracle_);

    /// @notice emitted when the allowed rebalancer is updated
    event LogUpdateRebalancer(address indexed newRebalancer_);

    /// @notice emitted when funds are rescued
    event LogRescueFunds(address indexed token_);

    /// @notice emitted when dust debt is absorbed for `nftIds_`
    event LogAbsorbDustDebt(uint256[] nftIds_, uint256 absorbedDustDebt_);
}
