//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { BigMathUnsafe } from "../../../../contracts/libraries/bigMathUnsafe.sol";

library BigMathVaultTolerance {
    struct BigNumberResults {
        uint256 number1;
        uint256 number2;
        uint256 bigNumber1; //bigNumber of number1
        uint256 bigNumber2; //bigNumber of number1
        uint256 mask;
    }

    struct CalculateBigNumbersAndMaskParams {
        uint256 number1;
        uint256 number2;
        uint256 coefficientSize;
        uint256 exponentSize;
    }

    function calculateMaxInaccuracyForDivBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2
    ) internal pure returns (uint256) {
        uint256 EXPONENT_SIZE_DEBT_FACTOR = 15;
        uint256 EXPONENT_MAX_DEBT_FACTOR = (1 << EXPONENT_SIZE_DEBT_FACTOR) - 1;
        uint256 PRECISION = 64;

        if (bigNumber2 == 0) {
            return type(uint256).max;
        }

        uint256 coefficient1 = bigNumber1 >> EXPONENT_SIZE_DEBT_FACTOR;
        uint256 exponent1 = bigNumber1 & EXPONENT_MAX_DEBT_FACTOR;
        uint256 coefficient2 = bigNumber2 >> EXPONENT_SIZE_DEBT_FACTOR;
        uint256 exponent2 = bigNumber2 & EXPONENT_MAX_DEBT_FACTOR;

        uint256 scaledCoefficient1 = coefficient1 << PRECISION;

        uint256 remainder = scaledCoefficient1 % coefficient2;
        uint256 errorEstimate = remainder == 0 ? 0 : 1;

        return errorEstimate << (exponent1 - exponent2 - PRECISION);
    }

    function calculateMask(uint size) public pure returns (uint) {
        require(size <= 256, "Size too large");
        return (1 << size) - 1;
    }

    function calculateBigNumbersAndMask(
        CalculateBigNumbersAndMaskParams memory params
    ) internal returns (BigNumberResults memory results) {
        results.mask = calculateMask(params.exponentSize);

        (, , results.bigNumber1) = BigMathUnsafe.toBigNumberExtended(
            params.number1,
            params.coefficientSize,
            params.exponentSize,
            BigMathUnsafe.ROUND_DOWN
        );
        (, , results.bigNumber2) = BigMathUnsafe.toBigNumberExtended(
            params.number2,
            params.coefficientSize,
            params.exponentSize,
            BigMathUnsafe.ROUND_DOWN
        );

        return results;
    }

    function safeDivide(uint256 numerator, uint256 denominator) internal pure returns (uint256, bool) {
        if (denominator == 0) {
            // Division by zero, return false to indicate error
            return (0, false);
        }
        return (numerator / denominator, true);
    }

    function safeMultiply(uint256 a, uint256 b) public pure returns (uint256, bool) {
        if (a == 0 || b == 0) {
            return (0, true);
        }
        if (a > type(uint256).max / b) {
            // Overflow condition
            return (0, false);
        }
        return (a * b, true);
    }

    function safeSubtract(uint256 a, uint256 b) public pure returns (uint256, bool) {
        if (b > a) {
            // Underflow condition
            return (0, false);
        }
        return (a - b, true);
    }

    function safeAdd(uint256 a, uint256 b) public pure returns (uint256, bool) {
        if (a > type(uint256).max - b) {
            // Overflow condition
            return (0, false);
        }
        return (a + b, true);
    }
}
