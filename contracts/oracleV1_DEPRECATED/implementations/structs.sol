// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";
import { IRedstoneOracle } from "../interfaces/external/IRedstoneOracle.sol";

abstract contract ChainlinkStructs {
    struct ChainlinkFeedData {
        /// @param feed           address of Chainlink feed.
        IChainlinkAggregatorV3 feed;
        /// @param invertRate     true if rate read from price feed must be inverted.
        bool invertRate;
        /// @param token0Decimals decimals of asset 0. E.g. for a USDC/ETH feed, USDC is token0 and has 6 decimals.
        ///                       (token1Decimals are available directly via Chainlink `FEED.decimals()`)
        uint256 token0Decimals;
    }

    struct ChainlinkConstructorParams {
        /// @param param        hops count of hops, used for sanity checks. Must be 1, 2 or 3.
        uint8 hops;
        /// @param feed1        Chainlink feed 1 data. Required.
        ChainlinkFeedData feed1;
        /// @param feed2        Chainlink feed 2 data. Required if hops > 1.
        ChainlinkFeedData feed2;
        /// @param feed3        Chainlink feed 3 data. Required if hops > 2.
        ChainlinkFeedData feed3;
    }
}

abstract contract RedstoneStructs {
    struct RedstoneOracleData {
        /// @param oracle         address of Redstone oracle.
        IRedstoneOracle oracle;
        /// @param invertRate     true if rate read from price feed must be inverted.
        bool invertRate;
        /// @param token0Decimals decimals of asset 0. E.g. for a USDC/ETH feed, USDC is token0 and has 6 decimals.
        ///                       (token1Decimals are available directly via Redstone `Oracle.decimals()`)
        uint256 token0Decimals;
    }
}
