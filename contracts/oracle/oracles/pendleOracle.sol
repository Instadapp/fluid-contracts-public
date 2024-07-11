// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { IPendleMarketV3 } from "../interfaces/external/IPendleMarketV3.sol";
import { IPendlePYLpOracle } from "../interfaces/external/IPendlePYLpOracle.sol";
import { PendleOracleImpl } from "../implementations/pendleOracleImpl.sol";

/// @title   PendleOracle
/// @notice  Gets the exchange rate between Pendle and the underlying asset for the Pendle Market.
contract PendleOracle is FluidOracle, PendleOracleImpl {
    constructor(
        string memory infoName_,
        IPendlePYLpOracle pendleOracle_,
        IPendleMarketV3 pendleMarket_,
        uint32 twapDuration_,
        uint256 maxExpectedBorrowRate_,
        uint256 minYieldRate_,
        uint256 maxYieldRate_,
        uint8 debtTokenDecimals_
    )
        PendleOracleImpl(
            pendleOracle_,
            pendleMarket_,
            twapDuration_,
            maxExpectedBorrowRate_,
            minYieldRate_,
            maxYieldRate_,
            debtTokenDecimals_
        )
        FluidOracle(infoName_)
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        return _getPendleExchangeRateOperate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        return _getPendleExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return _getPendleExchangeRateOperate();
    }
}
