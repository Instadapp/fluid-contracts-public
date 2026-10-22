// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ChainlinkRateRead } from "../chainlinkRateRead.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a Chainlink Feed source
contract FluidChainlinkCappedRate is FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {}

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return ChainlinkRateRead.positiveRateFromLatestRound(_RATE_SOURCE);
    }
}
