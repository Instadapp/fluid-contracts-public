//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidLendingStaticRateModel {
    /// @notice Signed APR offset feed for static-wired fTokens. Input `totalAssets_` is ignored (TVL-independent).
    /// @return rate_ signed APR offset with `1e12` = 1%. Positive = on top of Liquidity yield; negative = below.
    ///         The fToken applies Liquidity supply yield ± this offset. Stays the configured offset even when
    ///         `ended_` is true so the fToken can settle accrual exactly up to `endTime_`.
    /// @return ended_ true after `startTime + duration` (mirrors streaming `getRateV2` ended semantics).
    /// @return startTime_ accrual start time for the current rate period
    /// @return endTime_ end time of the current rate period (`startTime + duration`)
    function getRateV2(
        uint256 totalAssets_
    ) external view returns (int256 rate_, bool ended_, uint256 startTime_, uint256 endTime_);

    /// @notice Static-model config read. Named distinctly from legacy streaming `getConfig()` (7-tuple) so both
    ///         can coexist on the same contract without selector / ABI-decode collisions.
    /// @return staticRate_ signed APR offset (`1e12` = 1%), same value as `getRateV2` while the period is current
    /// @return duration_ duration in seconds for the current rate period
    /// @return startTime_ when the current rate period started
    /// @return configurator_ address with authority to configure the static rate
    /// @return maxRate_ hard ceiling on `|offset|` (`MAX_RATE`, currently 50%) with `1e12` = 1%
    function getStaticConfig()
        external
        view
        returns (int256 staticRate_, uint256 duration_, uint256 startTime_, address configurator_, uint256 maxRate_);
}
