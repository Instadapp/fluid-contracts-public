// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";

abstract contract ChainlinkSourceReader {
    function _readChainlinkSource(address feed_) internal view returns (uint256 rate_) {
        try IChainlinkAggregatorV3(feed_).latestRoundData() returns (
            uint80,
            int256 exchangeRate_,
            uint256,
            uint256,
            uint80
        ) {
            // Return the price in `OracleUtils.RATE_OUTPUT_DECIMALS`
            return uint256(exchangeRate_);
        } catch {}
    }
}
