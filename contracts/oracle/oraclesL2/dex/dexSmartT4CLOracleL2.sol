// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../../fluidOracleL2.sol";
import { DexSmartT4CLOracle } from "../../oracles/dex/dexSmartT4CLOracle.sol";

/// @title   Fluid Dex Smart Col Debt VaultT4 Oracle on L2s
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral and smart debt for a T4 vault.
///          returns amount of debt shares per 1 col share.
/// @dev -> Reserves from Liquidity, adjusted for conversion price.
///      -> Reserves conversion price from Chainlink feeds.
contract DexSmartT4CLOracleL2 is FluidOracleL2, DexSmartT4CLOracle {
    constructor(
        DexSmartT4CLOracle.DexSmartT4CLOracleParams memory params_,
        address sequencerUptimeFeed_
    ) DexSmartT4CLOracle(params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(DexSmartT4CLOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(DexSmartT4CLOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate() public view override(DexSmartT4CLOracle, FluidOracleL2) returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
