//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BigMathUnsafe } from "../../../../contracts/libraries/bigMathUnsafe.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

/// @title BigMathTestHelper
/// @notice used to measure gas for BigMath methods via foundry --gas-report (which doesn't work for libraries)
contract BigMathTestHelper {
    function toBigNumberExtended(
        uint256 number,
        uint256 coefficientSize,
        uint256 exponentSize,
        bool roundUp
    ) public pure returns (uint256 coefficient, uint256 exponent, uint256 bigNumber) {
        (coefficient, exponent, bigNumber) = BigMathUnsafe.toBigNumberExtended(
            number,
            coefficientSize,
            exponentSize,
            roundUp
        );
    }

    function toBigNumber(
        uint256 number,
        uint256 coefficientSize,
        uint256 exponentSize,
        bool roundUp
    ) public pure returns (uint256 bigNumber) {
        bigNumber = BigMathMinified.toBigNumber(number, coefficientSize, exponentSize, roundUp);
    }

    function mulDivNormal(
        uint256 normal,
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 exponentSize,
        uint256 exponentMask
    ) public pure returns (uint256 res) {
        (res) = BigMathUnsafe.mulDivNormal(normal, bigNumber1, bigNumber2, exponentSize, exponentMask);
    }

    function fromBigNumber(uint256 coefficient, uint256 exponent) public pure returns (uint256 normal) {
        normal = BigMathUnsafe.fromBigNumber(coefficient, exponent);
    }

    function fromBigNumber(
        uint256 bigNumber,
        uint256 exponentSize,
        uint256 exponentMask
    ) public pure returns (uint256 normal) {
        normal = BigMathMinified.fromBigNumber(bigNumber, exponentSize, exponentMask);
    }

    function decompileBigNumber(
        uint256 bigNumber,
        uint256 exponentSize,
        uint256 exponentMask
    ) public pure returns (uint256 coefficient, uint256 exponent) {
        (coefficient, exponent) = BigMathUnsafe.decompileBigNumber(bigNumber, exponentSize, exponentMask);
    }

    function mostSignificantBit(uint256 normal) public pure returns (uint lastBit) {
        lastBit = BigMathMinified.mostSignificantBit(normal);
    }

    function mulDivBigNumber(
        uint256 bigNumber,
        uint256 number1,
        uint256 number2,
        uint256 precisionBits,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 exponentMask,
        bool roundUp
    ) public pure returns (uint256 result) {
        (result) = BigMathUnsafe.mulDivBigNumber(
            bigNumber,
            number1,
            number2,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            roundUp
        );
    }

    function mulBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 decimal
    ) public pure returns (uint256 res) {
        (res) = BigMathUnsafe.mulBigNumber(bigNumber1, bigNumber2, coefficientSize, exponentSize, decimal);
    }

    function divBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 precision_,
        uint256 decimal
    ) public pure returns (uint256 res) {
        (res) = BigMathUnsafe.divBigNumber(bigNumber1, bigNumber2, coefficientSize, exponentSize, precision_, decimal);
    }
}
