//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IRedstoneOracle } from "../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/oracle/interfaces/external/IChainlinkAggregatorV3.sol";
import { IWstETH } from "../../../contracts/oracle/interfaces/external/IWstETH.sol";
import { IUniswapV3Pool } from "../../../contracts/oracle/interfaces/external/IUniswapV3Pool.sol";
import { WstETHOracle } from "../../../contracts/oracle/oracles/wstETHOracle.sol";
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

contract WstETHOracleTest is OracleTestSuite {
    function setUp() public override {
        super.setUp();

        oracle = new WstETHOracle(infoName, WSTETH_TOKEN);
    }

    function test_getExchangeRate() public {
        uint256 stEthPerToken = WSTETH_TOKEN.stEthPerToken();

        uint256 expectedRate = (stEthPerToken * 1e27) / 1e18;
        assertEq(expectedRate, 1148070971780498356000000000); // 1.148070971780498356000000000
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
