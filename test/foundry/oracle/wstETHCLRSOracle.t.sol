//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IWstETH } from "../../../contracts/oracle/interfaces/external/IWstETH.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { WstETHCLRSOracle } from "../../../contracts/oracle/oracles/wstETHCLRSOracle.sol";
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

contract WstETHCLRSOracleTest is OracleTestSuite {
    function setUp() public override {
        super.setUp();

        oracle = new WstETHCLRSOracle(
            infoName,
            WSTETH_TOKEN,
            1,
            ChainlinkStructs.ChainlinkConstructorParams({
                hops: 2,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_STETH_ETH,
                    invertRate: false,
                    token0Decimals: 18 // STETH has 18 decimals
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: CHAINLINK_FEED_ETH_USD,
                    invertRate: false,
                    token0Decimals: 18 // ETH has 18 decimals
                }),
                feed3: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                })
            }),
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                invertRate: false,
                token0Decimals: 1
            })
        );
    }

    function test_getExchangeRate() public {
        (, int256 exchangeRateStEthEth_, , , ) = CHAINLINK_FEED_STETH_ETH.latestRoundData();
        assertEq(exchangeRateStEthEth_, 999668908364503600);
        // 0.999668908364503600 -> STETH -> ETH
        // 0.999668908364503600 = 999668908364503600

        (, int256 exchangeRateEthUsd_, , , ) = CHAINLINK_FEED_ETH_USD.latestRoundData();
        assertEq(exchangeRateEthUsd_, 201805491600);
        // 2018,05491600 -> ETH -> USD

        uint256 rateStEthEth = (uint256(exchangeRateStEthEth_) * (1e27)) / 1e18; // 1e27 -> Oracle precision,  1e6 -> USD decimals
        assertEq(rateStEthEth, 999668908364503600000000000);
        uint256 rateEthUsd = (uint256(exchangeRateEthUsd_) * (1e27)) / 1e18; // 1e27 -> Oracle precision,  1e6 -> USD decimals
        assertEq(rateEthUsd, 201805491600000000000);

        // STETH -> USD
        uint256 rateStEthUsd = (rateEthUsd * rateStEthEth) / 1e27;
        assertEq(rateStEthUsd, 201738675489734000987);
        // 201738675489734000987.96976

        uint256 stEthPerToken = WSTETH_TOKEN.stEthPerToken();
        assertEq(stEthPerToken, 1148070971780498356);
        uint256 expectedRate = ((rateStEthUsd * stEthPerToken * 1e27) / 1e18) / 1e27;
        // 231610317215209519606.214931024655877372
        assertEq(expectedRate, 231610317215209519606); // 2316.10317215209519606. 17 decimals because would be 6 decimals but scaled by 11 decimals more
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_FailExchangeRateZero() public {
        oracle = new WstETHCLRSOracle(
            infoName,
            WSTETH_TOKEN,
            1,
            ChainlinkStructs.ChainlinkConstructorParams({
                hops: 1,
                feed1: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(MOCK_CHAINLINK_FEED)),
                    invertRate: false,
                    token0Decimals: 18
                }),
                feed2: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 18 // ETH has 18 decimals
                }),
                feed3: ChainlinkStructs.ChainlinkFeedData({
                    feed: IChainlinkAggregatorV3(address(0)),
                    invertRate: false,
                    token0Decimals: 0
                })
            }),
            RedstoneStructs.RedstoneOracleData({
                oracle: IRedstoneOracle(address(MOCK_REDSTONE_FEED)),
                invertRate: false,
                token0Decimals: 1
            })
        );
        MOCK_CHAINLINK_FEED.setExchangeRate(0);

        _assertExchangeRatesAllMethodsReverts(oracle, ErrorTypes.WstETHCLRSOracle__ExchangeRateZero);
    }
}
