//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BigMathVault } from "../../../../contracts/libraries/bigMathVault.sol";

/// @title BigMathTestHelper
/// @notice used to measure gas for BigMath methods via foundry --gas-report (which doesn't work for libraries)
contract BigMathVaultTestHelper {
    function mulDivNormal(uint256 normal, uint256 bigNumber1, uint256 bigNumber2) public pure returns (uint256 res) {
        (res) = BigMathVault.mulDivNormal(normal, bigNumber1, bigNumber2);
    }

    function mulDivBigNumber(uint256 bigNumber, uint256 number1) public view returns (uint256 result) {
        (result) = BigMathVault.mulDivBigNumber(bigNumber, number1);
    }

    function mulBigNumber(uint256 bigNumber1, uint256 bigNumber2) public view returns (uint256) {
        return BigMathVault.mulBigNumber(bigNumber1, bigNumber2);
    }

    function divBigNumber(uint256 bigNumber1, uint256 bigNumber2) public view returns (uint256) {
        return BigMathVault.divBigNumber(bigNumber1, bigNumber2);
    }
}
