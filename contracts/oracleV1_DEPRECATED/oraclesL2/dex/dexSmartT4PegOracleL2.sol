// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../../fluidOracleL2.sol";
import { DexSmartT4PegOracle } from "../../oracles/dex/dexSmartT4PegOracle.sol";

/// @title   Fluid Dex Smart Col Debt Pegged Oracle for assets ~1=~1 on L2s
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and smart debt shares.
/// @dev -> Reserves from Liquidity with Peg buffer percent.
///      -> Reserves conversion price from separately deployed FluidOracle (optional e.g. needed for wstETH-ETH).
contract DexSmartT4PegOracleL2 is FluidOracleL2, DexSmartT4PegOracle {
    constructor(
        DexSmartT4PegOracle.DexSmartT4PegOracleParams memory params_,
        address sequencerUptimeFeed_
    ) DexSmartT4PegOracle(params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(DexSmartT4PegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(DexSmartT4PegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        override(DexSmartT4PegOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
