// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../../fluidOracleL2.sol";
import { DexSmartDebtPegOracle } from "../../oracles/dex/dexSmartDebtPegOracle.sol";

/// @title   Fluid Dex Smart Debt Pegged Oracle for assets ~1=~1 on L2s
/// @notice  Gets the exchange rate between a Fluid Dex normal collateral and smart debt shares.
/// @dev -> Reserves from Liquidity with Peg buffer percent.
///      -> Reserves conversion price from separately deployed FluidOracle (optional e.g. needed for wstETH-ETH).
///      -> colDebt Price Oracle is an IFluidOracle.
contract DexSmartDebtPegOracleL2 is FluidOracleL2, DexSmartDebtPegOracle {
    constructor(
        DexSmartDebtPegOracle.DexSmartDebtPegOracleParams memory params_,
        address sequencerUptimeFeed_
    ) DexSmartDebtPegOracle(params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(DexSmartDebtPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(DexSmartDebtPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        override(DexSmartDebtPegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
