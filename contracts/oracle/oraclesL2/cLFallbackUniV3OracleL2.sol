// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { CLFallbackUniV3Oracle } from "../oracles/cLFallbackUniV3Oracle.sol";

/// @title   Chainlink with Fallback to UniV3 Oracle for Layer 2 (with sequencer outage detection)
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a Chainlink price feed or, if that feed fails, the price from a UniV3 TWAP delta checked Oracle.
contract CLFallbackUniV3OracleL2 is FluidOracleL2, CLFallbackUniV3Oracle {
    /// @notice                       sets the Chainlink and UniV3 Oracle configs.
    /// @param infoName_         Oracle identify helper name.
    /// @param chainlinkParams_       ChainlinkOracle constructor params struct.
    /// @param uniV3Params_           UniV3Oracle constructor params struct.
    /// @param sequencerUptimeFeed_   L2 sequencer uptime Chainlink feed
    constructor(
        string memory infoName_,
        ChainlinkConstructorParams memory chainlinkParams_,
        UniV3ConstructorParams memory uniV3Params_,
        address sequencerUptimeFeed_
    ) CLFallbackUniV3Oracle(infoName_, chainlinkParams_, uniV3Params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(CLFallbackUniV3Oracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(CLFallbackUniV3Oracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        override(CLFallbackUniV3Oracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
