//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { FallbackCLRSOracle } from "../../../contracts/oracle/oracles/fallbackCLRSOracle.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { FluidOracleL2 } from "../../../contracts/oracle/fluidOracleL2.sol";
import { OracleL2TestSuite } from "./oracleL2TestSuite.t.sol";
import { OracleTestSuite } from "../oracle/oracleTestSuite.t.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

import { FallbackCLRSOracleL2 } from "../../../contracts/oracle/oraclesL2/fallbackCLRSOracleL2.sol";
import { FallbackCLRS_Chainlink2Hops_OracleTest, FallbackCLRS_Chainlink2Hops_OracleTest2, FallbackCLRS_Chainlink2Hops_OracleTest3, FallbackCLRS_Chainlink3Hops_OracleTest } from "../oracle/fallbackCLRSOracle.t.sol";

import "forge-std/console2.sol";

contract FallbackCLRS_Chainlink2Hops_OracleL2Test is FallbackCLRS_Chainlink2Hops_OracleTest, OracleL2TestSuite {
    function setUp() public virtual override(FallbackCLRS_Chainlink2Hops_OracleTest, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        oracle = new FallbackCLRSOracleL2(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            FallbackCLRSOracleL2.CLRSConstructorParams({
                mainSource: 1, // mainsource = chainlink
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
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
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
                    invertRate: false,
                    token0Decimals: 1
                })
            }),
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }
}

contract FallbackCLRS_Chainlink2Hops_OracleL2Test2 is FallbackCLRS_Chainlink2Hops_OracleTest2, OracleL2TestSuite {
    function setUp() public virtual override(FallbackCLRS_Chainlink2Hops_OracleTest2, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        oracle = new FallbackCLRSOracleL2(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            FallbackCLRSOracleL2.CLRSConstructorParams({
                mainSource: 1, // mainsource = chainlink
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 2,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_CRV_USD,
                        invertRate: false,
                        token0Decimals: 18 // CRV has 18 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_SXP_USD,
                        invertRate: true,
                        token0Decimals: 18 // SXP has 18 decimals
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: false,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED_SXP_USD)),
                    invertRate: false,
                    token0Decimals: 1
                })
            }),
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }
}

contract FallbackCLRS_Chainlink2Hops_OracleL2Test3 is FallbackCLRS_Chainlink2Hops_OracleTest3, OracleL2TestSuite {
    function setUp() public virtual override(FallbackCLRS_Chainlink2Hops_OracleTest3, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        oracle = new FallbackCLRSOracleL2(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            FallbackCLRSOracleL2.CLRSConstructorParams({
                mainSource: 1, // mainsource = chainlink
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 2,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_WBTC_BTC,
                        invertRate: false,
                        token0Decimals: 8 // WBTC has 8 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_BTC_USD,
                        invertRate: true,
                        token0Decimals: 8 // BTC has 8 decimals
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: false,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED_BTC_USD)),
                    invertRate: false,
                    token0Decimals: 1
                })
            }),
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }
}

contract FallbackCLRS_Chainlink3Hops_OracleL2Test is FallbackCLRS_Chainlink3Hops_OracleTest, OracleL2TestSuite {
    function setUp() public virtual override(FallbackCLRS_Chainlink3Hops_OracleTest, OracleTestSuite) {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        oracle = new FallbackCLRSOracleL2(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            FallbackCLRSOracleL2.CLRSConstructorParams({
                mainSource: 1, // mainsource = chainlink
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 3,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_WBTC_BTC,
                        invertRate: false,
                        token0Decimals: 8 // WBTC has 8 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_BTC_USD,
                        invertRate: false,
                        token0Decimals: 8 // BTC has 8 decimals
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED_USDC_USD,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
                    invertRate: false,
                    token0Decimals: 1
                })
            }),
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }
}
