//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IWeETH } from "../../../contracts/oracle/interfaces/external/IWeETH.sol";
import { WeETHOracle } from "../../../contracts/oracle/oracles/weETHOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract WeETHOracleTest is OracleTestSuite {
    function setUp() public override {
        super.setUp();

        oracle = new WeETHOracle(infoName, WEETH_TOKEN);
    }

    function test_constructor() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.WeETHOracle__InvalidParams));
        oracle = new WeETHOracle(infoName, IWeETH(address(0)));
    }

    function test_getExchangeRate() public {
        uint256 eEthPerWeEth = WEETH_TOKEN.getEETHByWeETH(1e18);

        uint256 expectedRate = (eEthPerWeEth * 1e27) / 1e18;
        assertEq(expectedRate, 1025233132798815224000000000); // 1.025233132798815224000000000
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
