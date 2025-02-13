// todo //SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { WeETHsWstETHOracle } from "../../../contracts/oracle/oracles/weETHsWstETHOracle.sol";
import { OracleUtils } from "../../../contracts/oracle/libraries/oracleUtils.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

contract weETHsWstETHOracleTest is OracleTestSuite {
    function setUp() public override {
        super.setUp();

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20410999);

        oracle = new WeETHsWstETHOracle(infoName, WSTETH_TOKEN, WEETHS_ACCOUNTANT, WEETHS_TOKEN);
    }

    function test_getExchangeRate() public {
        // oracle should return amount of wstETH per 1 weETHs. at given block, weETHs price is lower than wstETH, so returned
        // rate should come in at < 1: less than 1 wstETH needed for 1 weETHs.

        // WstETH -> stETH (1ETH)
        uint256 stEthPerToken = WSTETH_TOKEN.stEthPerToken();
        assertEq(stEthPerToken, 1174056306294661112);

        // weETHs -> ETH
        uint256 ethPerWeEths = WEETHS_ACCOUNTANT.getRate();
        assertEq(ethPerWeEths, 1002814706394192775);

        // weEths -> wstETH
        uint256 expectedRate = (ethPerWeEths * 10 ** OracleUtils.RATE_OUTPUT_DECIMALS) / stEthPerToken; // 1002814706394192775 * 1e27 / 1174056306294661112 = 854145325924861872385682473
        assertEq(expectedRate, 854145325924861872385682473); // 0.854 wstETH needed for 1 weETHs
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
