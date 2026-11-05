// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Structs {
    struct CHRStockOracleConstructorParams {
        string infoName;
        uint8 targetDecimals;
        address chronicle;
        address rtoken;
        address realityTokenTrade;
        address marketHours;
        address authGate;
        /// @dev 1e4 = 100%. Operate reverts and liquidate clamps beyond it.
        uint256 maxCapPercent;
        /// @dev 1e4 = 100%, either direction. Every guarded read reverts beyond it.
        uint256 maxBreakPercent;
        uint256 maxOperateAge;
        uint256 maxLiquidateAge;
    }

    /// @dev Immutables plus stored state, as `CLXStockOracleConfig`.
    struct CHRStockOracleConfig {
        address chronicle;
        address rtoken;
        address realityTokenTrade;
        address marketHours;
        address authGate;
        uint256 maxCapPercent;
        uint256 maxBreakPercent;
        uint256 maxOperateAge;
        uint256 maxLiquidateAge;
        uint104 acceptedMultiplier;
        bool paused;
        uint128 anchorValue;
        uint32 anchorTime;
        uint128 hintValue;
        uint32 hintAge;
        uint32 hintRegularEnd;
    }
}
