// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";
import { FluidCappedRateL2 } from "../fluidCappedRateL2.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a Chainlink Feed source
/// for L2 with sequencer uptime feed.
contract FluidChainlinkCappedRateL2 is FluidCappedRateL2 {
    constructor(
        FluidCappedRateL2.CappedRateConstructorParams memory params_,
        address sequencerUptimeFeed_
    ) FluidCappedRateL2(params_, sequencerUptimeFeed_) {}

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        (, int256 rate_, , , ) = IChainlinkAggregatorV3(_RATE_SOURCE).latestRoundData();
        return uint256(rate_);
    }
}
