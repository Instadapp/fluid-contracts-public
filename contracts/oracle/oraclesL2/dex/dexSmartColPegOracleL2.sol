// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../../fluidOracleL2.sol";
import { DexSmartColPegOracle } from "../../oracles/dex/dexSmartColPegOracle.sol";

/// @title   Fluid Dex Smart Col Pegged Oracle for assets ~1=~1 on L2s
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and normal debt.
/// @dev -> Reserves from Liquidity with Peg buffer percent.
///      -> Reserves conversion price from separately deployed FluidOracle (optional e.g. needed for wstETH-ETH).
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartColPegOracleL2 is FluidOracleL2, DexSmartColPegOracle {
    constructor(
        DexSmartColPegOracle.DexSmartColPegOracleParams memory params_,
        address sequencerUptimeFeed_
    ) DexSmartColPegOracle(params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        
        override(DexSmartColPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        
        override(DexSmartColPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        
        override(DexSmartColPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
