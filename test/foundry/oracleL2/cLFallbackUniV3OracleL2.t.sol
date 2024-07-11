//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../../../contracts/oracle/fluidOracleL2.sol";
import { CLFallbackUniV3OracleL2 } from "../../../contracts/oracle/oraclesL2/cLFallbackUniV3OracleL2.sol";
import { CLFallbackUniV3OracleTest } from "../oracle/cLFallbackUniV3Oracle.t.sol";
import { OracleL2TestSuite } from "./oracleL2TestSuite.t.sol";
import { OracleTestSuite } from "../oracle/oracleTestSuite.t.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

import { ChainlinkStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";

import "forge-std/console2.sol";

contract CLFallbackUniV3OracleL2Test is CLFallbackUniV3OracleTest, OracleL2TestSuite {
    function setUp() public virtual override(CLFallbackUniV3OracleTest, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        oracle = new CLFallbackUniV3OracleL2(
            infoName,
            ChainlinkStructs.ChainlinkConstructorParams({
                hops: 2,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_ETH_USD,
                    invertRate: false,
                    token0Decimals: 18 // ETH has 18 decimals
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_USDC_USD,
                    invertRate: true,
                    token0Decimals: 6 // USDC has 6 decimals
                }),
                feed3: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                })
            }),
            UniV3OracleImpl.UniV3ConstructorParams({
                pool: UNIV3_POOL,
                invertRate: true,
                tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                secondsAgos: _getDefaultSecondAgosFixed()
            }),
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }
}
