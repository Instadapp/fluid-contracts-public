// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

/// @dev Shared Chainlink read for capped-rate implementations (same sign rule as `ChainlinkSourceReader`).
library ChainlinkRateRead {
    function positiveRateFromLatestRound(address feed_) internal view returns (uint256 rate_) {
        int256 answer_;
        (, answer_, , , ) = IChainlinkAggregatorV3(feed_).latestRoundData();
        if (answer_ < 1) {
            revert Error.FluidOracleError(ErrorTypes.CappedRate__NewRateZero);
        }
        return uint256(answer_);
    }
}
