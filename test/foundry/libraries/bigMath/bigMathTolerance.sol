//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { BigMathUnsafe } from "../../../../contracts/libraries/bigMathUnsafe.sol";

library BigMathTolerance {
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

    function mostSignificantBit(uint256 number) internal pure returns (uint8) {
        uint8 msb = 0;
        if (number >= 0x100000000000000000000000000000000) {
            number >>= 128;
            msb += 128;
        }
        if (number >= 0x10000000000000000) {
            number >>= 64;
            msb += 64;
        }
        if (number >= 0x100000000) {
            number >>= 32;
            msb += 32;
        }
        if (number >= 0x10000) {
            number >>= 16;
            msb += 16;
        }
        if (number >= 0x100) {
            number >>= 8;
            msb += 8;
        }
        if (number >= 0x10) {
            number >>= 4;
            msb += 4;
        }
        if (number >= 0x4) {
            number >>= 2;
            msb += 2;
        }
        if (number >= 0x2) {
            msb += 1;
        }
        return msb;
    }

    struct BigNumberCalculationForMulBigNumberInaccuracy {
        uint256 bigNumber;
        uint256 precisionBits;
        uint256 coefficientSize;
        uint256 exponentSize;
        uint256 exponentMask;
    }

    function calculateMaxInaccuracyMulDivBigNumber(
        BigNumberCalculationForMulBigNumberInaccuracy memory params,
        uint256 number1,
        uint256 number2,
        bool roundUp
    ) public pure returns (uint256, bool) {
        uint256 coefficient = params.bigNumber >> params.exponentSize;
        uint256 exponent = params.bigNumber & params.exponentMask;

        // Adjust coefficient with the exponent
        uint256 adjustedCoefficient;
        bool multiplySuccess;
        (adjustedCoefficient, multiplySuccess) = safeMultiply(coefficient, 2 ** exponent);
        if (!multiplySuccess) {
            return (0, false);
        }

        // Calculate the maximum possible value after multiplication and shifting
        uint256 product;
        (product, multiplySuccess) = safeMultiply(adjustedCoefficient * number1, 1 << params.precisionBits);
        if (!multiplySuccess) {
            return (0, false);
        }

        // Perform division
        uint256 result;
        bool divideSuccess;
        (result, divideSuccess) = safeDivide(product, number2);
        if (!divideSuccess) {
            return (0, false);
        }

        // Consider rounding
        if (roundUp && (product % number2) != 0) {
            result += 1;
        }

        // Calculate inaccuracy based on coefficient size
        uint256 maxInaccuracy = result >> (256 - params.coefficientSize);

        return (maxInaccuracy, true);
    }

    struct BigNumberCalculationForMulDivNormal {
        uint256 normal;
        uint256 number1;
        uint256 number2;
        uint256 bigNumber1;
        uint256 bigNumber2;
        uint8 coefficientSize;
        uint8 exponentSize;
        bool roundUp;
        uint256 mask;
    }

    struct BigNumberCalculationForBigNumbersConversion {
        uint256 number1;
        uint256 number2;
        uint256 bigNumber1;
        uint256 bigNumber2;
        uint256 coefficientSize;
        uint256 exponentSize;
        bool roundUp;
        uint256 mask;
    }

    struct RoundingErrors {
        uint256 error1;
        uint256 error2;
    }

    function calculateMaxInaccuracy(
        BigNumberCalculationForMulDivNormal memory calc
    ) external pure returns (uint256 maxInaccuracy, bool success) {
        CalculateRoundingErrorsViaConversionParams memory params = CalculateRoundingErrorsViaConversionParams({
            number1: calc.number1,
            number2: calc.number2,
            coefficientSize: calc.coefficientSize,
            exponentSize: calc.exponentSize,
            roundUp: calc.roundUp
        });
        RoundingErrors memory errors = calculateRoundingErrorsViaConversion(params);

        if (calc.number2 < errors.error2) {
            return (0, false);
        }

        return calculateInaccuracy(calc, errors);
    }

    function calculateMaxInaccuracyForMulBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize
    ) internal pure returns (uint256 maxInaccuracy) {
        uint256 coefficient1 = bigNumber1 >> exponentSize;
        uint256 coefficient2 = bigNumber2 >> exponentSize;

        uint256 product = coefficient1 * coefficient2;
        uint256 truncatedProduct = product & ((1 << coefficientSize) - 1);

        maxInaccuracy = product - truncatedProduct;
        return maxInaccuracy;
    }

    function calculateMaxInaccuracyForDivBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 precision_,
        uint256 decimal
    ) internal pure returns (uint256 maxInaccuracy) {
        uint256 coefficient1 = bigNumber1 >> exponentSize;
        uint256 exponent1 = bigNumber1 & ((1 << exponentSize) - 1);
        uint256 coefficient2 = bigNumber2 >> exponentSize;
        uint256 exponent2 = bigNumber2 & ((1 << exponentSize) - 1);

        // Calculate the length of the coefficients
        uint256 coefficientLen1 = exponent1 == 0 ? mostSignificantBit(coefficient1) : coefficientSize;
        uint256 coefficientLen2 = exponent2 == 0 ? mostSignificantBit(coefficient2) : coefficientSize;

        // Calculate the effective coefficient after division
        uint256 resCoefficient = (coefficient1 << precision_) / coefficient2;
        uint256 midLen = mostSignificantBit(resCoefficient);

        // Determine potential overflow length
        uint256 overflowLen = midLen > coefficientSize ? midLen - coefficientSize : 0;

        // Calculate the potential maximum inaccuracy due to rounding and overflow
        // This is a rough estimation and might not cover all edge cases
        if (overflowLen > 0) {
            // In case of overflow, the inaccuracy is at least 1 << overflowLen
            maxInaccuracy = 1 << overflowLen;
        } else {
            // If there's no overflow, inaccuracy might come from the rounding of coefficients
            maxInaccuracy = 1; // Minimal inaccuracy due to rounding
        }

        // Adjust the inaccuracy based on the decimal adjustment
        uint256 exponentAdjustment = (exponent1 + decimal) > exponent2 ? (exponent1 + decimal - exponent2) : 0;
        maxInaccuracy += exponentAdjustment;

        return maxInaccuracy;
    }

    function calculateMaxInaccuracyForBigNumbersConversion(
        BigNumberCalculationForBigNumbersConversion memory calc
    ) external pure returns (uint256 maxInaccuracy, bool success) {
        CalculateRoundingErrorsViaConversionParams memory params = CalculateRoundingErrorsViaConversionParams({
            number1: calc.number1,
            number2: calc.number2,
            coefficientSize: calc.coefficientSize,
            exponentSize: calc.exponentSize,
            roundUp: calc.roundUp
        });
        RoundingErrors memory errors = calculateRoundingErrorsViaConversion(params);

        if (calc.number1 < errors.error1) {
            return (0, false);
        }

        if (calc.number2 < errors.error2) {
            return (0, false);
        }

        return calculateInaccuracyForMulBigNumber(calc, errors);
    }

    struct CalculateRoundingErrorsViaConversionParams {
        uint256 number1;
        uint256 number2;
        uint256 coefficientSize;
        uint256 exponentSize;
        bool roundUp;
    }

    function calculateRoundingErrorsViaConversion(
        CalculateRoundingErrorsViaConversionParams memory calc
    ) internal pure returns (RoundingErrors memory errors) {
        errors.error1 = estimateRoundingErrorViaConversion(
            calc.number1,
            calc.coefficientSize,
            calc.exponentSize,
            calc.roundUp
        );
        errors.error2 = estimateRoundingErrorViaConversion(
            calc.number2,
            calc.coefficientSize,
            calc.exponentSize,
            calc.roundUp
        );
        return errors;
    }

    function estimateRoundingErrorViaConversion(
        uint256 normal,
        uint256 coefficientSize,
        uint256 exponentSize,
        bool roundUp
    ) public pure returns (uint256) {
        // Convert the normal number to a BigNumber
        (uint256 coefficient, uint256 exponent, ) = BigMathUnsafe.toBigNumberExtended(
            normal,
            coefficientSize,
            exponentSize,
            roundUp
        );

        // Convert the BigNumber back to a normal number
        uint256 convertedBack = BigMathUnsafe.fromBigNumber(coefficient, exponent);

        // Calculate the absolute difference as the rounding error
        if (convertedBack > normal) {
            return convertedBack - normal;
        } else {
            return normal - convertedBack;
        }
    }

    function calculateInaccuracy(
        BigNumberCalculationForMulDivNormal memory calc,
        RoundingErrors memory errors
    ) internal pure returns (uint256 maxInaccuracy, bool success) {
        uint256 adjustedNumber1 = calc.number1 + errors.error1;
        uint256 adjustedNumber2 = calc.number2 - errors.error2;

        (uint256 adjustedProduct, bool successAdjusted) = safeMultiply(calc.normal, adjustedNumber1);
        (uint256 originalProduct, bool successOriginal) = safeMultiply(calc.normal, calc.number1);

        if (!successAdjusted || !successOriginal) {
            return (0, false);
        }

        uint256 adjustedResult = adjustedProduct / adjustedNumber2;
        uint256 originalResult = originalProduct / calc.number2;
        maxInaccuracy = adjustedResult > originalResult
            ? (adjustedResult - originalResult)
            : (originalResult - adjustedResult);

        return (maxInaccuracy, true);
    }

    function calculateInaccuracyForMulBigNumber(
        BigNumberCalculationForBigNumbersConversion memory calc,
        RoundingErrors memory errors
    ) internal pure returns (uint256 maxInaccuracy, bool success) {
        (uint256 adjustedNumber1, bool success1) = safeAdd(calc.number1, errors.error1);
        (uint256 adjustedNumber2, bool success2) = safeAdd(calc.number2, errors.error2);

        if (!success1 || !success2) {
            return (type(uint256).max, true);
        }
        (uint256 adjustedProduct, bool successAdjusted) = safeMultiply(adjustedNumber1, adjustedNumber2);
        (uint256 originalProduct, bool successOriginal) = safeMultiply(calc.number1, calc.number2);

        if (!successAdjusted || !successOriginal) {
            return (type(uint256).max, true);
        }

        maxInaccuracy = adjustedProduct - originalProduct;

        return (maxInaccuracy, true);
    }

    function calculateMask(uint size) public pure returns (uint) {
        require(size <= 256, "Size too large");
        return (1 << size) - 1;
    }

    function calculateBigNumbersAndMask(
        CalculateBigNumbersAndMaskParams memory params
    ) internal returns (BigNumberResults memory results) {
        results.mask = calculateMask(params.exponentSize);

        results.bigNumber1 = BigMathUnsafe.toBigNumber(
            params.number1,
            params.coefficientSize,
            params.exponentSize,
            BigMathUnsafe.ROUND_DOWN
        );
        results.bigNumber2 = BigMathUnsafe.toBigNumber(
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

    function safePow(uint256 a, uint256 b) public pure returns (uint256, bool) {
        if (a == 0) {
            return (b == 0 ? (1, true) : (0, true)); // 0^0 is 1 by convention, 0^b is 0
        }
        uint256 result = 1;
        uint256 base = a;

        while (b > 0) {
            if (b % 2 == 1) {
                // Multiply result by current base, check for overflow
                (uint256 newResult, bool multiplyOk) = safeMultiply(result, base);
                if (!multiplyOk) {
                    return (0, false); // Overflow occurred
                }
                result = newResult;
            }
            // Square the base for next iteration, check for overflow
            (uint256 newBase, bool squareOk) = safeMultiply(base, base);
            if (!squareOk) {
                return (0, false); // Overflow occurred
            }
            base = newBase;
            b /= 2; // Equivalent to shifting right by 1 (b >>= 1)
        }
        return (result, true);
    }
}
