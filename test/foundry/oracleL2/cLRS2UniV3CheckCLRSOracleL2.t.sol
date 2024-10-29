// todo //SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { FluidOracleL2 } from "../../../contracts/oracle/fluidOracleL2.sol";
import { OracleL2TestSuite } from "./oracleL2TestSuite.t.sol";
import { OracleTestSuite } from "../oracle/oracleTestSuite.t.sol";
import { MockChainlinkSequencerUptimeFeed } from "./mocks/mockChainlinkSequencerUptimeFeed.sol";

import { CLRS2UniV3CheckCLRSOracleL2 } from "../../../contracts/oracle/oraclesL2/cLRS2UniV3CheckCLRSOracleL2.sol";
import { UniV3CheckCLRSOracleL2 } from "../../../contracts/oracle/oraclesL2/uniV3CheckCLRSOracleL2.sol";
import { UniV3CheckCLRSOracleTest } from "../oracle/uniV3CheckCLRSOracle.t.sol";

import "forge-std/console2.sol";

contract CLRS2UniV3CheckCLRSOracleL2Test is OracleL2TestSuite {
    UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams uniV3CheckOracleParams;
    CLRS2UniV3CheckCLRSOracleL2.CLRS2ConstructorParams cLRS2Params;

    IChainlinkAggregatorV3 internal constant CHAINLINK_FEED_BTC_ETH =
        IChainlinkAggregatorV3(0xdeb288F737066589598e9214E782fa5A8eD689e8);

    function setUp() public override {
        super.setUp();

        mockFeed = new MockChainlinkSequencerUptimeFeed();

        // ETH -> USDC
        uniV3CheckOracleParams = UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams({
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
        });

        cLRS2Params = CLRS2UniV3CheckCLRSOracleL2.CLRS2ConstructorParams({
            fallbackMainSource: 1,
            chainlinkParams: ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_BTC_ETH,
                    invertRate: false,
                    token0Decimals: 8 // BTC has 8 decimals
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
                oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                invertRate: false,
                token0Decimals: 1
            })
        });

        oracle = new CLRS2UniV3CheckCLRSOracleL2(infoName, cLRS2Params, uniV3CheckOracleParams, address(mockFeed));

        oracleL2 = FluidOracleL2(address(oracle));
    }

    function test_getExchangeRate() public {
        // @dev Note test runs at block 18664561 from oracleTestSuite.t.sol rollFork. (Nov-27-2023 05:46:47 PM +UTC)

        // BTC -> ETH
        (, int256 exchangeRateBtcEth_, , , ) = CHAINLINK_FEED_BTC_ETH.latestRoundData();
        assertEq(exchangeRateBtcEth_, 18360186110774997000); // 18.36 ETH for 1 BTC

        // uniV3 Oracle for ETH -> USDC
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 uniV3RateEthUsdc = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        assertEq(uniV3RateEthUsdc, 2016507218835155315); // ETH -> USDC, scaled to 1e27 precision (* 1e27 / 1e18), 9 decimals more

        (, , , , , uint256 uniV3OracleexchangeRate_) = UniV3OracleImpl(address(oracle)).uniV3OracleData();
        assertEq(uniV3OracleexchangeRate_, uniV3RateEthUsdc);

        // final rate combines BTC rate and uniV3 oracle rate.
        uint256 expectedRate = (uint256(exchangeRateBtcEth_) * uniV3RateEthUsdc) / 1e8;
        // 3,70234478315347360392312635137×10¹⁹
        assertEq(expectedRate, 370234478315347360392312635136); // 37.023.447 USDC.
        // result is in 25 decimals: BTC 8 decimals to USDC 6 decimals, scaled to 1e27 -> (1e6* 1e27 / 1e8), 33-8 = 25
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_FailExchangeRatesWEETHChainlinkZero() public {
        cLRS2Params.chainlinkParams.feed1.feed = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED));

        oracle = new CLRS2UniV3CheckCLRSOracleL2(infoName, cLRS2Params, uniV3CheckOracleParams, address(mockFeed));

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.CLRS2UniV3CheckCLRSOracleL2__ExchangeRateZero);
    }
}
