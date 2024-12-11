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
import { Ratio2xFallbackCLRSOracleL2 } from "../../../contracts/oracle/oraclesL2/ratio2xFallbackCLRSOracleL2.sol";

import "forge-std/console2.sol";

contract Ratio2xFallbackCLRSOracleL2Test is OracleL2TestSuite {
    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_CBETH_ETH =
        IChainlinkAggregatorV3(0xF017fcB346A1885194689bA23Eff2fE6fA5C483b);

    FallbackCLRSOracleL2.CLRSConstructorParams cLRSParams1;
    FallbackCLRSOracleL2.CLRSConstructorParams cLRSParams2;

    function setUp() public virtual override {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        cLRSParams1 = FallbackCLRSOracleL2.CLRSConstructorParams({
            mainSource: 1, // mainsource = chainlink
            chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_STETH_ETH,
                    invertRate: false,
                    token0Decimals: 18 // STETH has 18 decimals
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                }),
                feed3: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                })
            }),
            redstoneOracle: RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(0)),
                invertRate: false,
                token0Decimals: 0
            })
        });

        cLRSParams2 = FallbackCLRSOracleL2.CLRSConstructorParams({
            mainSource: 1, // mainsource = chainlink
            chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_CBETH_ETH,
                    invertRate: false,
                    token0Decimals: 18 // SWETH has 18 decimals
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                }),
                feed3: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                })
            }),
            redstoneOracle: RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(0)),
                invertRate: false,
                token0Decimals: 0
            })
        });

        oracle = new Ratio2xFallbackCLRSOracleL2(
            // configure oracle as stETH / cbETH. -> cbETH per 1 stETH
            infoName,
            cLRSParams1,
            cLRSParams2,
            address(mockFeed)
        );

        oracleL2 = FluidOracleL2(address(oracle));
    }

    function test_getExchangeRate() public {
        // oracle should return amount of cbETH per 1 stETH. at given block, cbETH price is higher than stETH, so returned
        // rate should come in at < 1: less than 1 cbETH needed for 1 stETH.

        (, int256 exchangeRateEthSteth_, , , ) = CHAINLINK_FEED_STETH_ETH.latestRoundData();
        assertEq(exchangeRateEthSteth_, 999668908364503600);
        // 0.999668908364503600 ETH per 1 STETH

        (, int256 exchangeRateEthCbeth_, , , ) = CHAINLINK_FEED_CBETH_ETH.latestRoundData();
        assertEq(exchangeRateEthCbeth_, 1054860635171501000);
        // 1.054860635171501000 ETH per 1 CBETH

        // cbETH per 1 stETH
        // 999668908364503600÷1054860635171501000 = 0,9476786553912648024084647875
        uint256 expectedRate = 947678655391264802408464787;
        assertEq(expectedRate, 947678655391264802408464787); // 0.9476 cbETH needed for 1 stETH
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_FailExchangeRateDividendZero() public {
        cLRSParams1.chainlinkParams.feed1.feed = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED));

        oracle = new Ratio2xFallbackCLRSOracleL2(
            // configure oracle as stETH / cbETH. -> cbETH per 1 stETH
            infoName,
            cLRSParams1,
            cLRSParams2,
            address(mockFeed)
        );

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FallbackCLRSOracle__ExchangeRateZero);
    }

    function test_getExchangeRate_FailExchangeRateDivisorZero() public {
        cLRSParams2.chainlinkParams.feed1.feed = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED));

        oracle = new Ratio2xFallbackCLRSOracleL2(
            // configure oracle as stETH / cbETH. -> cbETH per 1 stETH
            infoName,
            cLRSParams1,
            cLRSParams2,
            address(mockFeed)
        );

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.Ratio2xFallbackCLRSOracleL2__ExchangeRateZero);
    }
}
