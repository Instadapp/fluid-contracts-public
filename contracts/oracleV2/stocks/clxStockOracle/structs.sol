// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Structs {
    struct CLXStockOracleConstructorParams {
        string infoName;
        uint8 targetDecimals;
        address liquidity;
        address chainlinkFeed;
        address backedWrapper;
        address marketHours;
        uint256 rateMultiplier;
        /// @dev 1e2: 1% = 100. Max drift over 30d (capped). Construct max 10% (`1000`).
        uint256 maxMultiplierChangePercent;
        /// @dev 1e6: 1% = 1e4. Extended-hours ± vs RTH. `SIX_DECIMALS` (100%) is allowed and floors at 0 /
        ///      caps at 2x the anchor, i.e. the clamp never binds — only set it to opt out deliberately.
        uint256 maxExtendedHoursCapPercent;
        /// @dev 1e4: 42% = 4200. Strict lower gap bound vs anchor reference; required, < 100%. Sized inside
        ///      2:1 (-50%, smallest ratio large caps still use) with margin: the check is strict and drift
        ///      shifts the net move, so a bound sitting on the split slips through whenever drift helps.
        uint256 maxPriceGapDownPercent;
        /// @dev 1e4: 68% = 6800. Strict upper gap bound; required. Reciprocal mirror of the lower bound
        ///      (`up = 4 * down - 1`, since 2:1 is -50% and its 1:2 reverse is +100%), so both directions
        ///      tolerate the same ~16% concurrent drift.
        uint256 maxPriceGapUpPercent;
    }

    struct CLXStockOracleConfig {
        address chainlinkFeed;
        address backedWrapper;
        address marketHours;
        uint256 rateMultiplier;
        uint256 maxMultiplierChangePercent;
        uint256 maxExtendedHoursCapPercent;
        uint256 maxPriceGapDownPercent;
        uint256 maxPriceGapUpPercent;
        uint104 acceptedMultiplier;
        uint32 lastMultiplierUpdateTime;
        uint80 lastRegularHoursRoundId;
        uint32 lastVerifiedRegularHoursEnd;
        bool paused;
    }
}
