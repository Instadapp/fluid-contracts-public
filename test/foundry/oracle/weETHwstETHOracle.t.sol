// todo //SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { WeETHWstETHOracle } from "../../../contracts/oracle/oracles/weETHwstETHOracle.sol";
import { OracleUtils } from "../../../contracts/oracle/libraries/oracleUtils.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract weETHwstETHOracleTest is OracleTestSuite {
    function setUp() public override {
        super.setUp();

        oracle = new WeETHWstETHOracle(infoName, WSTETH_TOKEN, WEETH_TOKEN);
    }

    function test_getExchangeRate() public {
        // oracle should return amount of wstETH per 1 weETH. at given block, weETH price is lower than wstETH, so returned
        // rate should come in at < 1: less than 1 wstETH needed for 1 weETH.

        // WstETH -> stETH (1ETH)
        uint256 stEthPerToken = WSTETH_TOKEN.stEthPerToken();
        assertEq(stEthPerToken, 1148070971780498356);

        // weETH -> eETH (1ETH)
        uint256 eEthPerWeEth = WEETH_TOKEN.getEETHByWeETH(1e18);
        assertEq(eEthPerWeEth, 1025233132798815224);

        // weEth -> wstETH
        uint256 expectedRate = (eEthPerWeEth * 10 ** OracleUtils.RATE_OUTPUT_DECIMALS) / stEthPerToken; // 1025233132798815224 * 1e27 / 1148070971780498356 = 893005012755283993366244440
        assertEq(expectedRate, 893005012755283993366244440); // 0.893 wstETH needed for 1 weETH
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
