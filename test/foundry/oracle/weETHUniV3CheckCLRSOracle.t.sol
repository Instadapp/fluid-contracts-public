// todo //SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IWstETH } from "../../../contracts/oracle/interfaces/external/IWstETH.sol";
import { IWeETH } from "../../../contracts/oracle/interfaces/external/IWeETH.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { UniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/uniV3CheckCLRSOracle.sol";
import { WeETHUniV3CheckCLRSOracle } from "../../../contracts/oracle/oracles/weETHUniV3CheckCLRSOracle.sol";
import { ChainlinkStructs, RedstoneStructs } from "../../../contracts/oracle/implementations/structs.sol";
import { ChainlinkOracleImpl } from "../../../contracts/oracle/implementations/chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "../../../contracts/oracle/implementations/redstoneOracleImpl.sol";
import { UniV3OracleImpl } from "../../../contracts/oracle/implementations/uniV3OracleImpl.sol";
import { TickMath } from "../../../contracts/oracle/libraries/TickMath.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

import "forge-std/console2.sol";

contract WeETHUniV3CheckCLRSOracleTest is OracleTestSuite {
    UniV3CheckCLRSOracle.UniV3CheckCLRSConstructorParams uniV3CheckOracleParams;

    function setUp() public override {
        super.setUp();

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

        oracle = new WeETHUniV3CheckCLRSOracle(infoName, WEETH_TOKEN, uniV3CheckOracleParams);
    }

    function test_getExchangeRate() public {
        // @dev Note test runs at block 18664561 from oracleTestSuite.t.sol rollFork. (Nov-27-2023 05:46:47 PM +UTC)

        // WeETH -> eETH = ETH
        uint256 eEthPerToken = WEETH_TOKEN.getEETHByWeETH(1e18);
        assertEq(eEthPerToken, 1025233132798815224);

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

        // final rate combines weETH rate and uniV3 oracle rate.
        uint256 expectedRate = (eEthPerToken * uniV3RateEthUsdc) / 1e18;
        // 2067390013277792341,01531819203
        assertEq(expectedRate, 2067390013277792341); // 2067.390 USDC.
        // result is in 15 decimals: WeETH 18 decimals to USDC 6 decimals, scaled to 1e27 -> (1e6* 1e27 / 1e18), 33-18 = 15
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
