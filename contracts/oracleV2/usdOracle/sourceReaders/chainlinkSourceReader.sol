// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IChainlinkAggregatorV3 } from "../../interfaces/external/IChainlinkAggregatorV3.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Variables } from "../variables.sol";

abstract contract ChainlinkSourceReader is Variables, Error {
    /// @dev Reads the latest price from a Chainlink aggregator (staleness + sign checks).
    ///      When doRevert_ is true, reverts on stale/invalid data. When false, returns 0 instead.
    function _readChainlink(address feed_, bool isOperate_, bool doRevert_) internal view returns (uint256 rate_) {
        int256 exchangeRate_;
        uint256 updatedAt_;

        try IChainlinkAggregatorV3(feed_).latestRoundData() returns (
            uint80,
            int256 exchangeRateResult_,
            uint256,
            uint256 updatedAtResult_,
            uint80
        ) {
            exchangeRate_ = exchangeRateResult_;
            updatedAt_ = updatedAtResult_;
        } catch {}
        if (updatedAt_ == 0) {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__RateInvalid);
        }

        if (isOperate_) {
            if (updatedAt_ + MAX_UPDATE_TIMESPAN_OPERATE < block.timestamp) {
                if (!doRevert_) return 0;
                _revert(ErrorTypes.UsdOracle__ChainlinkStale);
            }
        } else if (updatedAt_ + MAX_UPDATE_TIMESPAN_LIQUIDATE < block.timestamp) {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__ChainlinkStale);
        }

        if (exchangeRate_ < 0) {
            if (!doRevert_) return 0;
            _revert(ErrorTypes.UsdOracle__RateInvalid);
        }

        rate_ = uint256(exchangeRate_);
    }

    /// @dev Raw Chainlink read: liquidate timespan only, returns 0 on failure/stale/non-positive (no revert).
    function _readChainlinkRaw(address feed_) internal view returns (uint256 rate_) {
        int256 exchangeRate_;
        uint256 updatedAt_;

        try IChainlinkAggregatorV3(feed_).latestRoundData() returns (
            uint80,
            int256 exchangeRateResult_,
            uint256,
            uint256 updatedAtResult_,
            uint80
        ) {
            exchangeRate_ = exchangeRateResult_;
            updatedAt_ = updatedAtResult_;
        } catch {
            return 0;
        }
        if (updatedAt_ == 0 || updatedAt_ + MAX_UPDATE_TIMESPAN_LIQUIDATE < block.timestamp || exchangeRate_ <= 0) {
            return 0;
        }

        rate_ = uint256(exchangeRate_);
    }
}
