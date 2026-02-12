//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { FallbackCLRSOracle } from "../../../contracts/oracle/oracles/fallbackCLRSOracle.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { MockChainlinkFeed } from "./mocks/mockChainlinkFeed.sol";
import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract FallbackCLRS_Chainlink2Hops_OracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        oracle = new FallbackCLRSOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            1, // mainsource = chainlink
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
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
                invertRate: false,
                token0Decimals: 1
            })
        );
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateEthUsd_, , , ) = CHAINLINK_FEED_ETH_USD.latestRoundData();
        assertEq(exchangeRateEthUsd_, 201805491600);
        // 2018,05491600 -> USD -> ETH
        // 2018,05491600 = 201805491600

        (, int256 exchangeRateUsdcUsd_, , , ) = CHAINLINK_FEED_USDC_USD.latestRoundData();
        assertEq(exchangeRateUsdcUsd_, 99990875);
        // 0,99990875 -> USD -> USDC

        uint256 rateEthUsd = uint256(exchangeRateEthUsd_) * (1e27) * (1e6); // 1e27 -> Oracle precision,  1e6 -> USDC decimals
        uint256 expectedRate = rateEthUsd / uint256(exchangeRateUsdcUsd_) / 1e18;
        assertEq(expectedRate, 2018239080316078842);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
        // 15 decimals (27 + 6 - 18)
        // 2018.239080316078842
    }
}

contract FallbackCLRS_Chainlink2Hops_OracleTest2 is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        oracle = new FallbackCLRSOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            1, // mainsource = chainlink
            ChainlinkStructs.ChainlinkConstructorParams({
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
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(CHAINLINK_FEED_SXP_USD)),
                invertRate: false,
                token0Decimals: 1
            })
        );
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateCrvUsd_, , , ) = CHAINLINK_FEED_CRV_USD.latestRoundData();
        assertEq(exchangeRateCrvUsd_, 56035000);
        // 0.56035000 -> CRV -> USD
        // 0.56035000 = 56035000

        (, int256 exchangeRateSxpUsd_, , , ) = CHAINLINK_FEED_SXP_USD.latestRoundData();
        assertEq(exchangeRateSxpUsd_, 33365151);
        // 0,33365151 -> USD -> USDC

        uint256 rateEthUsd = uint256(exchangeRateCrvUsd_) * (1e27) * (1e18); // 1e27 -> Oracle precision,  1e18 -> SXP decimals
        uint256 expectedRate = rateEthUsd / uint256(exchangeRateSxpUsd_) / 1e18; // 1e18 -> CRV decimals
        assertEq(expectedRate, 1679446917533806455723817944);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}

contract FallbackCLRS_Chainlink2Hops_OracleTest3 is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        oracle = new FallbackCLRSOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            1, // mainsource = chainlink
            ChainlinkStructs.ChainlinkConstructorParams({
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
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(CHAINLINK_FEED_BTC_USD)),
                invertRate: false,
                token0Decimals: 1
            })
        );
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateWbtcBtc_, , , ) = CHAINLINK_FEED_WBTC_BTC.latestRoundData();
        assertEq(exchangeRateWbtcBtc_, 99841321);
        // 0.99841321 -> WBTC -> BTC
        // 0.99841321 = 99841321

        (, int256 exchangeRateBtcUsd_, , , ) = CHAINLINK_FEED_BTC_USD.latestRoundData();
        assertEq(exchangeRateBtcUsd_, 3704705000000);
        // 37047,05000000 -> BTC -> USD
        // 37047,05000000 = 3704705000000

        //check WBTC -> USD
        uint256 rateWbtcBtc = uint256(exchangeRateWbtcBtc_) * (1e27) * (1e8); // 1e27 -> Oracle precision,  1e8 -> BTC decimals
        uint256 expectedRate = rateWbtcBtc / uint256(exchangeRateBtcUsd_) / 1e8; // 1e8 -> WBTC decimals

        assertEq(expectedRate, 26949870772436671745793);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}

contract FallbackCLRS_Chainlink3Hops_OracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        oracle = new FallbackCLRSOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            1, // mainsource = chainlink
            ChainlinkStructs.ChainlinkConstructorParams({
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
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(CHAINLINK_FEED_USDC_USD)),
                invertRate: false,
                token0Decimals: 1
            })
        );
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateWbtcBtc_, , , ) = CHAINLINK_FEED_WBTC_BTC.latestRoundData();
        assertEq(exchangeRateWbtcBtc_, 99841321);
        // 0.99841321 -> WBTC -> BTC
        // 0.99841321 = 99841321

        (, int256 exchangeRateBtcUsd_, , , ) = CHAINLINK_FEED_BTC_USD.latestRoundData();
        assertEq(exchangeRateBtcUsd_, 3704705000000);
        // 37047,05000000 -> BTC -> USD
        // 37047,05000000 = 3704705000000

        //convert WBTC -> BTC (wbtc/btc rate)
        uint256 rateWbtcBtc = (uint256(exchangeRateWbtcBtc_) * (1e27)) / 1e8; // 1e27 -> Oracle precision

        //convert BTC -> USD (btc/usd rate)
        exchangeRateBtcUsd_ = (exchangeRateBtcUsd_ * 1e27) / 1e8;
        uint256 wbtcUsdRate = (rateWbtcBtc * uint256(exchangeRateBtcUsd_)) / 1e27; // 1e8 -> BTC decimals

        (, int256 exchangeRateUsdcUsd_, , , ) = CHAINLINK_FEED_USDC_USD.latestRoundData();
        assertEq(exchangeRateUsdcUsd_, 99990875);

        //invert USDC/USD rate to get USD to USDC rate
        uint256 usdUsdcRate = (1e27 * 1e6) / uint256(exchangeRateUsdcUsd_); // 1e6 -> USDC decimals

        // WBTC -> USDC rate
        uint256 expectedRate = (wbtcUsdRate * usdUsdcRate) / 1e27; // 1e27 division adjusts for the Oracle's precision and 1e8 division was introduced by BTC's 8 decimal

        assertEq(expectedRate, 369916395986438762537081487906);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
        // 36991.6395986438762537081487906
    }

    function test_getExchangeRate_ThrowExchangeRateZero() public {
        // USDC / ETH feed
        IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
        oracle = new FallbackCLRSOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            1, // mainsource = chainlink
            ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: MOCK_CHAINLINK_FEED,
                    invertRate: false,
                    token0Decimals: 6 // USDC has 6 decimals
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
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(0)),
                invertRate: false,
                token0Decimals: 0
            })
        );

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.FallbackCLRSOracle__ExchangeRateZero);
    }
}
