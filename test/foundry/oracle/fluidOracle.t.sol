//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidOracle } from "../../../contracts/oracle/fluidOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";

contract FluidOracleHarness is FluidOracle {
    constructor(string memory infoName_) FluidOracle(infoName_, 20) {}

    function getExchangeRate() external view virtual override returns (uint256 exchangeRate_) {
        // not implemented
        return 0;
    }

    function getExchangeRateOperate() external view virtual override returns (uint256 exchangeRate_) {
        // not implemented
        return 0;
    }

    function getExchangeRateLiquidate() external view virtual override returns (uint256 exchangeRate_) {
        // not implemented
        return 0;
    }
}

contract FluidOracleTest is Test {
    string infoName = "someToken / someName";

    function test_infoName() public {
        FluidOracleHarness oracle = new FluidOracleHarness(infoName);
        assertEq(oracle.infoName(), infoName);
    }

    function test_infoName_RevertStringTooLong() public {
        infoName = "some too long string that would not fit the bytes32";
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.FluidOracle__InvalidInfoName)
        );
        new FluidOracleHarness(infoName);
    }

    function test_infoName_RevertStringZero() public {
        infoName = "";
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidOracleError.selector, ErrorTypes.FluidOracle__InvalidInfoName)
        );
        new FluidOracleHarness(infoName);
    }
}
