// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { FluidGenericOracle } from "../oracles/genericOracle.sol";

/// @notice generic configurable Oracle for Layer 2 (with sequencer outage detection)
/// combines up to 4 hops from sources such as
///  - an existing IFluidOracle (e.g. ContractRate)
///  - Redstone
///  - Chainlink
contract FluidGenericOracleL2 is FluidOracleL2, FluidGenericOracle {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        OracleHopSource[] memory sources_,
        address sequencerUptimeFeed_
    ) FluidGenericOracle(infoName_, targetDecimals_, sources_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(FluidGenericOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(FluidGenericOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate() public view override(FluidGenericOracle, FluidOracleL2) returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
