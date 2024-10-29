//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { CLFallbackUniV3Oracle } from "../../../contracts/oracle/oracles/cLFallbackUniV3Oracle.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { ChainlinkStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract CLFallbackUniV3OracleTest is OracleTestSuite {
    function setUp() public virtual override {
        super.setUp();

        oracle = new CLFallbackUniV3Oracle(
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
        assertEq(2018239080316078842, expectedRate); // 2018239080316078842
        _assertExchangeRatesAllMethods(oracle, expectedRate);
        // 15 decimals (27 + 6 - 18)
        // 2018.239080316078842
    }

    function test_getExchangeRate_ReturnUniExchangeRateWhenChainlinkRateIsZero() public {
        oracle = new CLFallbackUniV3Oracle(
            infoName,
            ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: MOCK_CHAINLINK_FEED,
                    invertRate: false,
                    token0Decimals: 6 // ETH has 18 decimals
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
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
            })
        );

        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(UNIV3_POOL).observe(_getDefaultSecondAgos());
        // tick(imprecise as it's an integer) to price
        int256 twapInterval = 1; // <- prev last (seconds ago) - last (seconds ago), looking at default values its 1 - 0
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[4] - tickCumulatives[3]) / int56(twapInterval))
        );
        uint256 expectedRate = _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96));
        _assertExchangeRatesAllMethods(oracle, expectedRate); // checks rate with chainlink oracle
    }
}
