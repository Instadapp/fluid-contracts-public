//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidLendingRewardsRateModel {
    /// @notice Calculates the current rewards rate (APR)
    /// @param totalAssets_ amount of assets in the lending
    /// @return rate_ rewards rate percentage per year with 1e12 RATE_PRECISION, e.g. 1e12 = 1%, 1e14 = 100%
    /// @return ended_ flag to signal that rewards have ended (always 0 going forward)
    /// @return startTime_ start time of rewards to compare against last update timestamp
    function getRate(uint256 totalAssets_) external view returns (uint256 rate_, bool ended_, uint256 startTime_);

    /// @notice Returns config constants for rewards rate model
    function getConfig()
        external
        view
        returns (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            uint256 maxRate_,
            uint256 rewardAmount_,
            address initiator_
        );
}
