//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { SUSDeOracle } from "../../../contracts/oracle/oracles/sUSDeOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";
import { IStakedUSDe } from "../../../contracts/config/ethenaRateHandler/interfaces/iStakedUSDe.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import { OracleTestSuite } from "./oracleTestSuite.t.sol";

import "forge-std/console2.sol";

contract SUSDeOracleTest is OracleTestSuite {
    IStakedUSDe internal constant SUSDE_TOKEN = IStakedUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19478687);

        // create sUSDeOracle for a debt token with 6 decimals (e.g. for USDC / USDT)
        oracle = new SUSDeOracle(infoName, SUSDE_TOKEN, 6);
    }

    function test_getExchangeRate() public {
        uint256 USDePerSUSDE = SUSDE_TOKEN.convertToAssets(1e18);

        uint256 rate = oracle.getExchangeRate();
        // result should have 1e15 decimals, and amount of USDC / USDT needed for 1 sUSDe should be > 1
        uint256 expectedRate = USDePerSUSDE / 1e3;

        assertGt(rate, 1e15);
        assertEq(expectedRate, 1031586919571882);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }

    function test_getExchangeRate_18Decimals() public {
        // create sUSDeOracle for a debt token with 6 decimals (e.g. for USDe / DAI)
        oracle = new SUSDeOracle(infoName, SUSDE_TOKEN, 18);

        uint256 USDePerSUSDE = SUSDE_TOKEN.convertToAssets(1e18);

        uint256 rate = oracle.getExchangeRate();
        // result should have 1e27 decimals, and amount of USDe / DAI needed for 1 sUSDe should be > 1
        uint256 expectedRate = (USDePerSUSDE / 1e3) * 1e12;

        assertGt(rate, 1e27);
        assertEq(expectedRate, 1031586919571882000000000000);
        _assertExchangeRatesAllMethods(oracle, expectedRate);
    }
}
