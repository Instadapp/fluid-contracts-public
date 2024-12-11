// todo //SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IWstETH } from "../../../contracts/oracle/interfaces/external/IWstETH.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { WstETHCLRS2UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/wstETHCLRS2UniV3CheckCLRSOracle.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { MockChainlinkFeed } from "./mocks/mockChainlinkFeed.sol";
import { MockRedstoneFeed } from "./mocks/mockRedstoneFeed.sol";
import { OracleTestSuite } from "./oracleTestSuite.t.sol";

import "forge-std/console2.sol";

contract WstETHCLRS2UniV3CheckCLRSOracleTest is OracleTestSuite {
    UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams uniV3CheckOracleParams;
    WstETHCLRS2UniV3CheckCLRSOracle.WstETHCLRS2ConstructorParams wstETHCLRS2Params;

    function setUp() public override {
        super.setUp();

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

        wstETHCLRS2Params = WstETHCLRS2UniV3CheckCLRSOracle.WstETHCLRS2ConstructorParams({
            wstETH: WSTETH_TOKEN,
            fallbackMainSource: 1,
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
                oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                invertRate: false,
                token0Decimals: 1
            })
        });

        oracle = new WstETHCLRS2UniV3CheckCLRSOracle(infoName, wstETHCLRS2Params, uniV3CheckOracleParams);
    }

    function test_getExchangeRate() public {
        // WstETH -> stETH
        uint256 stEthPerToken = WSTETH_TOKEN.stEthPerToken();
        assertEq(stEthPerToken, 1148070971780498356);

        // STETH -> ETH
        (, int256 exchangeRateStEthEth_, , , ) = CHAINLINK_FEED_STETH_ETH.latestRoundData();
        assertEq(exchangeRateStEthEth_, 999668908364503600);
        // 0.999668908364503600 -> STETH -> ETH
        // 0.999668908364503600 = 999668908364503600

        // uniV3 Oracle for ETH -> USDC
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 uniV3RateEthUsdc = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        assertEq(uniV3RateEthUsdc, 2016507218835155315); // ETH -> USDC, scaled to 1e27 precision (* 1e27 / 1e18), 9 decimals more

        // final rate combines all 3.
        uint256 expectedRate = (stEthPerToken * uint256(exchangeRateStEthEth_) * uniV3RateEthUsdc) / 1e18 / 1e18;
        // 2314326894269562301.155972309458013841622815323813704
        assertEq(expectedRate, 2314326894269562301);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_FailExchangeRatesStETHChainlinkZero() public {
        wstETHCLRS2Params.chainlinkParams.feed1.feed = IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED));

        oracle = new WstETHCLRS2UniV3CheckCLRSOracle(infoName, wstETHCLRS2Params, uniV3CheckOracleParams);

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.WstETHCLRS2UniV3CheckCLRSOracle__ExchangeRateZero);
    }
}
