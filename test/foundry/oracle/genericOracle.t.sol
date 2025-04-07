//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { FluidGenericOracle } from "../../../contracts/oracle/oracles/genericOracle.sol";
import { FluidGenericUniV3CheckedOracle } from "../../../contracts/oracle/oracles/genericUniV3CheckedOracle.sol";
import { GenericOracleStructs } from "../../../contracts/oracle/oracles/genericOracleBase.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";

import { MockChainlinkFeed } from "./mocks/mockChainlinkFeed.sol";
import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract GenericOracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](2);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_ETH_USD),
            invertRate: false,
            multiplier: 1e9, // scale token 0 ETH to 18
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });
        oracleHopSources[1] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_USDC_USD),
            invertRate: true,
            multiplier: 1e21, // scale token 0 USDC to 18
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericOracle(infoName, SAMPLE_TARGET_DECIMALS, oracleHopSources);
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateEthUsd_, , , ) = CHAINLINK_FEED_ETH_USD.latestRoundData();
        assertEq(exchangeRateEthUsd_, 201805491600);
        // 2018,05491600 -> USD -> ETH
        // 2018,05491600 = 201805491600

        (, int256 exchangeRateUsdcUsd_, , , ) = CHAINLINK_FEED_USDC_USD.latestRoundData();
        assertEq(exchangeRateUsdcUsd_, 99990875);
        // 0,99990875 -> USD -> USDC

        FluidGenericOracle(address(oracle)).getOracleHopSources();

        (uint256 rateSource1Operate, , uint256 rateSource2Operate, , , , , , , ) = FluidGenericOracle(address(oracle))
            .getHopExchangeRates();
        assertEq(rateSource1Operate, 201805491600 * 1e9); // expected 17 decimals (8 from USD + 9 scaling 18 ETH to 1e27)
        assertEq(rateSource2Operate, uint256(1e54) / (99990875 * 1e21)); // expected 29 decimals (8 from USD + 21 scaling USDC to 1e27)

        uint256 rateEthUsd = uint256(exchangeRateEthUsd_) * (1e27) * (1e6); // 1e27 -> Oracle precision,  1e6 -> USDC decimals
        uint256 expectedRate = rateEthUsd / uint256(exchangeRateUsdcUsd_) / 1e18;
        assertEq(expectedRate, 2018239080316078842);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
        // 15 decimals (27 + 6 - 18)
        // 2018.239080316078842
    }
}

contract GenericOracle2Hops_OracleTest2 is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](2);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_CRV_USD),
            invertRate: false,
            multiplier: 1e9,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });
        oracleHopSources[1] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_SXP_USD),
            invertRate: true,
            multiplier: 1e9,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericOracle(infoName, SAMPLE_TARGET_DECIMALS, oracleHopSources);
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

contract GenericOracle2Hops_OracleTest3 is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](2);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_WBTC_BTC),
            invertRate: false,
            multiplier: 1e19,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });
        oracleHopSources[1] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_BTC_USD),
            invertRate: true,
            multiplier: 1e19,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericOracle(infoName, SAMPLE_TARGET_DECIMALS, oracleHopSources);
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

contract GenericOracle3Hops_OracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](3);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_WBTC_BTC),
            invertRate: false,
            multiplier: 1e19,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });
        oracleHopSources[1] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_BTC_USD),
            invertRate: false,
            multiplier: 1e19,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });
        oracleHopSources[2] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_USDC_USD),
            invertRate: true,
            multiplier: 1e21,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericOracle(infoName, SAMPLE_TARGET_DECIMALS, oracleHopSources);
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
        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](1);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(MOCK_CHAINLINK_FEED),
            invertRate: false,
            multiplier: 1e9,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericOracle(infoName, SAMPLE_TARGET_DECIMALS, oracleHopSources);

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.GenericOracle__RateZero);
    }
}

contract GenericOracleUniV3Checked_OracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        GenericOracleStructs.OracleHopSource[] memory oracleHopSources = new GenericOracleStructs.OracleHopSource[](2);
        oracleHopSources[0] = GenericOracleStructs.OracleHopSource({
            source: address(0), // going from ETH -> USDC
            invertRate: false,
            multiplier: 1,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.UniV3Checked
        });
        oracleHopSources[1] = GenericOracleStructs.OracleHopSource({
            source: address(CHAINLINK_FEED_USDC_USD),
            invertRate: false, // going to USD
            multiplier: 1e21,
            divisor: 1,
            sourceType: GenericOracleStructs.SourceType.Chainlink
        });

        oracle = new FluidGenericUniV3CheckedOracle(
            infoName,
            SAMPLE_TARGET_DECIMALS,
            oracleHopSources,
            UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
                uniV3Params: UniV3OracleImpl.UniV3ConstructorParams({
                    pool: UNIV3_POOL,
                    invertRate: true,
                    tWAPMaxDeltaPercents: _getDefaultUniswapTwapDeltasFixed(),
                    secondsAgos: _getDefaultSecondAgosFixed()
                }),
                chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                    hops: 1,
                    feed1: ChainlinkStructs.ChainlinkFeedData({
                        feed: CHAINLINK_FEED,
                        invertRate: true,
                        token0Decimals: 6 // USDC has 6 decimals
                    }),
                    feed2: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    }),
                    feed3: ChainlinkStructs.ChainlinkFeedData({
                        feed: IChainlinkAggregatorV3(address(0)),
                        invertRate: true,
                        token0Decimals: 0
                    })
                }),
                redstoneOracle: RedstoneStructs.RedstoneOracleData({
                    oracle: IRedstoneOracle(address(CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 1
                }),
                /// @param rateSource_                  which oracle to use as final rate source:
                ///                                         - 1 = UniV3 ONLY (no check),
                ///                                         - 2 = UniV3 with Chainlink / Redstone check
                ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
                rateSource: 2, // which oracle to use as final rate source
                /// @param mainSource_          which oracle to use as main source:
                ///                                  - 1 = Chainlink ONLY (no fallback)
                ///                                  - 2 = Chainlink with Redstone Fallback
                ///                                  - 3 = Redstone with Chainlink Fallback
                fallbackMainSource: 1, // which oracle to use as CL/RS main source
                rateCheckMaxDeltaPercent: 300 // 3% max delta
            })
        );
    }

    function test_getExchangeRate() public {
        (uint256 rateSource1Operate, , uint256 rateSource2Operate, , , , , , , ) = FluidGenericOracle(address(oracle))
            .getHopExchangeRates();
        assertEq(rateSource1Operate, 2016507218835155315);
        assertEq(rateSource2Operate, (99990875 * 1e21));

        uint256 expectedRate = (rateSource1Operate * rateSource2Operate) / 1e27;
        assertEq(expectedRate, 201632321255143660707);

        assertEq(expectedRate, oracle.getExchangeRateOperate());
    }
}
