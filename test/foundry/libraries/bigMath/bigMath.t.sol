//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BigMathUnsafe } from "../../../../contracts/libraries/bigMathUnsafe.sol";
import { BigMathTolerance } from "./bigMathTolerance.sol";
import { BigMathTestHelper } from "./bigMathTestHelper.sol";

contract LibraryBigMathBaseTest is Test {
    // use testHelper contract to measure gas for library methods via forge --gas-report
    BigMathTestHelper testHelper;

    function setUp() public {
        testHelper = new BigMathTestHelper();
    }
}

contract LibraryBigMathTest is LibraryBigMathBaseTest {
    uint256 DEFAULT_TOLERANCE = 1e9; // 9 digits tolerance
    uint256 DEFAULT_NUMBER = 5035703444687813576399599; // 5035703444687813,576399599
    uint8 DEFAULT_COEFFICIENT_SIZE = 56;
    uint8 DEFAULT_EXPONENT_SIZE = 8;
    uint256 DEFAULT_EXPONENT_MASK = 0xFF;

    // ======== toBigNumber
    /// @dev see comments in BigMathUnsafe.sol for examples of results that are used as assert results here
    function test_toBigNumber() public {
        uint256 bigNumber = testHelper.toBigNumber(DEFAULT_NUMBER, 32, 8, BigMathUnsafe.ROUND_DOWN);
        assertEq(bigNumber, 572493200179);
    }

    function test_toBigNumber_Basic() public {
        uint256 normal = 1000;
        uint256 coefficientSize = 56;
        uint256 exponentSize = 8;
        bool roundUp = false;

        uint256 bigNumber = testHelper.toBigNumber(normal, coefficientSize, exponentSize, roundUp);

        uint256 expectedBigNumber = 256000;

        assertEq(bigNumber, expectedBigNumber, "BigNumber conversion failed");
    }

    function test_toBigNumber_LargeNumber() public {
        uint256 normal = uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + 1;
        uint256 coefficientSize = 56;
        uint256 exponentSize = 8;
        bool roundUp = false;

        // coefficient[56bits]
        // exponent[8bits]
        // 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF + 1 = 340282366920938463463374607431768211455 + 1 = 340282366920938463463374607431768211456
        /// 340282366920938463463374607431768211456 (decimal) => 100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 (binary)
        /// => 10000000000000000000000000000000000000000000000000000000,0000000000000000000000000000000000000000000000000000000000000000000000000
        ///                                                             ^------------------------------ 51(exponent) ---------------------------^
        /// coefficient = 10000000000000000000000000000000000000000000000000000000    (36028797018963968)
        /// exponent =                                                                                  0000000000000000000000000000000000000000000000000000000000000000000000000     (73)
        /// bigNumber =   10000000000000000000000000000000000000000000000000000000     (10000000000000000000000000000000000000000000000000000000)

        // bigNumber := shl(exponentSize, coefficient) => bigNumber := shl(8, 36028797018963968) => 36028797018963968 * 2**8
        // bigNumber := add(bigNumber, exponent) => 9223372036854775808 + 73 => 9223372036854775881
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            normal,
            coefficientSize,
            exponentSize,
            roundUp
        );

        uint256 expectedBigNumber = 9223372036854775881;
        uint256 expectedExponent = 73;
        uint256 expectedCoefficient = 36028797018963968;

        assertEq(bigNumber, expectedBigNumber, "BigNumber conversion failed");
        assertEq(exponent, expectedExponent, "Exponent conversion failed");
        assertEq(coefficient, expectedCoefficient, "Coefficient conversion failed");
    }

    function test_toBigNumber_WithRoundUp() public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            32,
            8,
            BigMathUnsafe.ROUND_UP
        );
        // coefficient in binary is rounded up by 1, so the effect is not a increase of 1 in decimal
        // but rather an increase of 1 in the coefficient binary.

        // 5035703444687813576399599 = 10000101010010110100000011111011110010100110100000000011100101001101001101011101111
        // coefficient first 32 bits = 10000101010010110100000011111011
        // exponent rest of digits count = 51 (in decimal)
        // so bigNumber would be            10000101010010110100000011111011 (2236301563) | 00110011 (51)
        // -> with coefficient rounded up:  10000101010010110100000011111100 (2236301564) | 00110011 (51)
        // 1000010101001011010000001111110000110011 binary in decimal = 572493200435
        assertEq(bigNumber, 572493200435);

        // converted back it would be 10000101010010110100000011111100 000000000000000000000000000000000000000000000000000 (5035703445159228706127872)
        //                                            coefficient     +     51 zeroes
        // difference at converted back number to original number is 471415129728273 (or 0.00000000936145535388051813%)
        assertEq(testHelper.fromBigNumber(coefficient, exponent), 5035703445159228706127872);
        assertEq(testHelper.fromBigNumber(bigNumber, 8, 0xFF), 5035703445159228706127872);
    }

    function test_toBigNumber_WithRoundUpReachCoefficientSize() public {
        uint256 normalNumber = 32754; // 111111111110010
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            normalNumber,
            8,
            4,
            BigMathUnsafe.ROUND_UP
        );
        // coefficient first 8 bits = 11111111
        // exponent rest of digits count = 7 (in decimal)
        // so bigNumber would be            11111111 (255) | 0111 (7) (in decimal 4087)
        // -> with coefficient rounded up: 100000000 (256) | 0111 (7). -> Coefficient overflows coefficientsize of 8 bits
        // new value should be coefficient reduced by 1 digit, exponent increased by 1
        //                               => 10000000 (128) | 1000 (8) (in decimal 2056)
        assertEq(bigNumber, 2056);
        assertEq(coefficient, 128);
        assertEq(exponent, 8);

        // converted back it would be 10000000 00000000 (32768)
        //                        coefficient + 8 zeroes
        assertEq(testHelper.fromBigNumber(coefficient, exponent), 32768);
        assertEq(testHelper.fromBigNumber(bigNumber, 4, 0xF), 32768);
    }

    function test_toBigNumber_ExponentOverflow() public {
        uint256 normalNumber = 32754; // 111111111110010
        // coefficient first 8 bits = 11111111
        // exponent rest of digits count = 7 (in decimal)
        // so bigNumber would be            11111111 (255) | 111 (7) -> Exponent overflows exponentSize of 2 bits
        vm.expectRevert();
        testHelper.toBigNumber(normalNumber, 8, 2, BigMathUnsafe.ROUND_DOWN);
    }

    // TODO: fuzzing test for toBigNumber. Fix calculating inaccuracy
    // function testFuzz_toBigNumber(uint256 normal, uint8 coefficientSize, uint8 exponentSize, bool roundUp) public {
    //     vm.assume(normal > 0);
    //     vm.assume(coefficientSize >= 8 && coefficientSize <= 64);
    //     vm.assume(exponentSize >= 8 && exponentSize <= 64);
    //     vm.assume(coefficientSize + exponentSize <= 256); // TODO: Condition here or we can even directly require it in the 'toBigNumber' function like below
    //     vm.assume(normal <= type(uint256).max >> exponentSize); // Ensure normal is within a manageable range

    //     try testHelper.toBigNumber(normal, coefficientSize, exponentSize, roundUp) returns (
    //         uint256 coefficient,
    //         uint256 exponent,
    //         uint256 bigNumber
    //     ) {
    //         // uint256 reconstructedNormal = (coefficient << exponent);
    //         // // TODO: Fix calculating inaccuracy
    //         // uint256 bigNumberTolerance = BigMathTolerance.calculateMaxInaccuracyMulDivBigNumber(
    //         //     normal,
    //         //     coefficientSize,
    //         //     roundUp
    //         // );
    //         // assertTrue(
    //         //     reconstructedNormal >= normal - bigNumberTolerance &&
    //         //         reconstructedNormal <= normal + bigNumberTolerance,
    //         //     "Reconstructed normal does not match the original value within tolerance"
    //         // );
    //     } catch Error(string memory reason) {
    //         emit log_named_string("Reverted with reason", reason);
    //         assertTrue(true == false);
    //     }
    // }

    // ======== toBigNumberExtended
    function test_toBigNumberExtended_SameBigNumberAsFromToBigNumberFunction() public {
        uint256 normal = uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + 1;
        uint256 coefficientSize = 56;
        uint256 exponentSize = 8;
        bool roundUp = false;

        (, , uint256 bigNumberFromExtended) = testHelper.toBigNumberExtended(
            normal,
            coefficientSize,
            exponentSize,
            roundUp
        );

        uint256 bigNumber = testHelper.toBigNumber(normal, coefficientSize, exponentSize, roundUp);

        uint256 expectedBigNumber = 9223372036854775881;

        assertEq(bigNumber, expectedBigNumber, "BigNumber conversion failed");
        assertEq(bigNumberFromExtended, bigNumber, "BigNumber is not the same as from toBigNumber function");
    }

    // ======== fromBigNumber (2 params)

    function test_fromBigNumber() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, DEFAULT_NUMBER, DEFAULT_TOLERANCE);
    }

    function test_fromBigNumber_WithRoundUp() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_UP
        );

        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_UP
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function test_fromBigNumber_SmallNumber() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            7,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertEq(normal, 7);
    }

    function testFuzz_fromBigNumber(uint128 inputNumber) public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE * 2, // use bigger coefficient and exponent
            DEFAULT_EXPONENT_SIZE * 2,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, inputNumber, DEFAULT_TOLERANCE);
    }

    function test_fromBigNumber_WithDecompile() public {
        (, , uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(
            bigNumber,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, DEFAULT_NUMBER, DEFAULT_TOLERANCE);
    }

    // ======== fromBigNumber (3 params)

    function test_fromBigNumber_ThreeParams() public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function test_fromBigNumber_ThreeParams_WithRoundUp() public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_UP
        );
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_UP
        );
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function testFuzz_fromBigNumber_ThreeParams(uint128 inputNumber) public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 normal6 = testHelper.fromBigNumber(coefficient, exponent);
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );
        assertApproxEqAbs(normal, inputNumber, difference);
    }

    function test_fromBigNumber_ThreeParams_SmallNonZero() public {
        uint256 exponentSize = 4;
        uint256 exponentMask = 0x0F;
        uint256 smallNumber = 1;
        uint256 bigNumber = smallNumber << exponentSize;

        uint256 normal = testHelper.fromBigNumber(bigNumber, exponentSize, exponentMask);
        assertEq(normal, 1);
    }

    function test_fromBigNumber_ThreeParams_Zero() public {
        uint256 bigNumber = 0;

        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        assertEq(normal, 0);
    }

    // === mulDivNormal

    function test_mulDivNormal_BigNumber2IsGreaterThanBigNumber1() public {
        // formula: res = _number * _bigNumber1 / _bigNumber2
        // res is normal number

        uint256 divisor = 1e18;

        uint256 bigNumber1e18 = testHelper.toBigNumber(
            23456789 * 1e18,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 bigNumberDivisor = testHelper.toBigNumber(
            divisor,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        // let coefficient1_ := shr(exponentSize, bigNumber1) => (bigNumber1 >> exponentSize) => 11185068607330322205 / 2^8 = 43691674247384071
        // let exponent1_ := and(bigNumber1, exponentMask) => 11185068607330322205 AND 0xFF => 11185068607330322205 AND 11111111 => 29
        // let coefficient2_ := shr(exponentSize, bigNumber2) => (bigNumber2 >> exponentSize) => 16000000000000000004 / 2^8 => 62500000000000000
        // let exponent2_ := and(bigNumber2, exponentMask) => 16000000000000000004 AND 0xFF => 16000000000000000004 AND 11111111 => 4
        // let X := gt(exponent1_, exponent2_) // bigNumber2 > bigNumber1 => 29 > 4 => true
        // if X {
        //     coefficient1_ := shl(sub(exponent1_, exponent2_), coefficient1_) => 43691674247384071 << (29 - 4) => 43691674247384071 * 2^25 => 1466049312499999988252672
        // }
        // if iszero(X) {
        //     coefficient2_ := shl(sub(exponent2_, exponent1_), coefficient2_)
        // }
        // res := div(mul(normal, coefficient1_), coefficient2_) => div(mul(5035703444687813576399599, 1466049312499999988252672), 62500000000000000) => 118121433168615212986443812219969

        uint256 result = testHelper.mulDivNormal(
            DEFAULT_NUMBER,
            bigNumber1e18,
            bigNumberDivisor,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 expected = (DEFAULT_NUMBER * 23456789 * 1e18) / divisor; // 118121433168615212986443812219969
        // TODO: Isn't 16 decimals too much?
        assertApproxEqAbs(result, expected, 1e16);
        // assertApproxEqAbs(result, expected, DEFAULT_TOLERANCE);
    }

    function test_mulDivNormal_BigNumber1IsGreaterThanBigNumber2() public {
        // formula: res = _number * _bigNumber1 / _bigNumber2
        // res is normal number

        uint256 divisor = 25879 * 1e18;

        uint256 bigNumber1e18 = testHelper.toBigNumber(
            1e18,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 bigNumberDivisor = testHelper.toBigNumber(
            divisor,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        // let coefficient1_ := shr(exponentSize, bigNumber1) => (bigNumber1 >> exponentSize) => 16000000000000000004 / 2^8 = 62500000000000000
        // let exponent1_ := and(bigNumber1, exponentMask) => 16000000000000000004 AND 0xFF => 16000000000000000004 AND 11111111 => 4
        // let coefficient2_ := shr(exponentSize, bigNumber2) => (bigNumber2 >> exponentSize) => 12636230468749999891 / 2^8 => 49360275268554687
        // let exponent2_ := and(bigNumber2, exponentMask) => 12636230468749999891 AND 0xFF => 12636230468749999891 AND 11111111 => 19
        // let X := gt(exponent1_, exponent2_) // bigNumber2 > bigNumber1 => 4 > 19 => false
        // if X {
        //     coefficient1_ := shl(sub(exponent1_, exponent2_), coefficient1_)
        // }
        // if iszero(X) {
        //     coefficient2_ := shl(sub(exponent2_, exponent1_), coefficient2_) => 49360275268554687 << (19 - 4) => 49360275268554687 * 2^15 => 1617437499999999983616
        // }
        // res := div(mul(normal, coefficient1_), coefficient2_) => div(mul(5035703444687813576399599, 62500000000000000), 1617437499999999983616) => 194586477247490769635

        uint256 result = testHelper.mulDivNormal(
            DEFAULT_NUMBER,
            bigNumber1e18,
            bigNumberDivisor,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 expected = (DEFAULT_NUMBER * 1e18) / divisor; // 194586477247490767664
        //result 194586477247490769635
        assertApproxEqAbs(result, expected, DEFAULT_TOLERANCE);
    }

    struct MulDivNormalTestParams {
        uint256 normal;
        uint256 number1;
        uint256 number2;
        uint8 coefficientSize;
        uint8 exponentSize;
    }

    // TODO: Fix testFuzz_mulDivNormal test
    // function testFuzz_mulDivNormal(MulDivNormalTestParams memory params) public {
    //     vm.assume(params.normal > 1);
    //     vm.assume(params.number1 > 1);
    //     vm.assume(params.number2 > 1);
    //     vm.assume(params.coefficientSize >= 8 && params.coefficientSize <= 64);
    //     vm.assume(params.exponentSize >= 8 && params.exponentSize <= 64);
    //     vm.assume(params.coefficientSize + params.exponentSize <= 256);

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory paramsForBigNumsCalcs = BigMathTolerance.CalculateBigNumbersAndMaskParams({
    //         number1: params.number1,
    //         number2: params.number2,
    //         coefficientSize: params.coefficientSize,
    //         exponentSize: params.exponentSize
    //     });

    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(paramsForBigNumsCalcs);
    //     results.number1 = params.number1;
    //     results.number2 = params.number2;

    //     performMulDivNormalTest(params, results);
    // }

    // function performMulDivNormalTest(MulDivNormalTestParams memory params, BigMathTolerance.BigNumberResults memory results) internal {
    //     try
    //         testHelper.mulDivNormal(
    //             params.normal,
    //             results.bigNumber1,
    //             results.bigNumber2,
    //             params.exponentSize,
    //             results.mask
    //         )
    //     returns (uint256 result) {
    //         (uint256 multiplied, bool success) = BigMathTolerance.safeMultiply(params.normal, params.number1);
    //         if (success) {
    //             uint256 expected = multiplied / params.number2;
    //             BigMathTolerance.BigNumberCalculationForMulDivNormal memory calc = BigMathTolerance
    //                 .BigNumberCalculationForMulDivNormal({
    //                     normal: params.normal,
    //                     number1: results.number1,
    //                     number2: results.number2,
    //                     bigNumber1: results.bigNumber1,
    //                     bigNumber2: results.bigNumber2,
    //                     coefficientSize: params.coefficientSize,
    //                     exponentSize: params.exponentSize,
    //                     roundUp: BigMathUnsafe.ROUND_DOWN,
    //                     mask: results.mask
    //                 });

    //             //
    //             (uint256 maxInaccuracy, bool success2) = BigMathTolerance.calculateMaxInaccuracy(calc);
    //             if (success2) {
    //                 assertApproxEqAbs(result, expected, maxInaccuracy);
    //             }
    //         }
    //     } catch Error(string memory reason) {
    //         emit log_named_string("Reverted with reason", reason);
    //     }
    // }

    // ========= decompileBigNumber

    function test_decompileBigNumber_KnownNumber() public {
        uint256 exponentSize = 8; // Example value
        uint256 exponentMask = 0xFF; // Example mask for 8-bit exponent
        uint256 bigNumber = 572493200179; // Example BigNumber (coefficient: 2236301563, exponent: 51)

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(bigNumber, exponentSize, exponentMask);

        assertEq(coefficient, 2236301563, "Incorrect coefficient");
        assertEq(exponent, 51, "Incorrect exponent");
    }

    function test_decompileBigNumber_EdgeCases() public {
        uint256 exponentSize = 8;
        uint256 exponentMask = 0xFF;

        // Smallest BigNumber (exponent = 0, coefficient = 0)
        uint256 smallBigNumber = 0;
        (uint256 smallCoefficient, uint256 smallExponent) = testHelper.decompileBigNumber(
            smallBigNumber,
            exponentSize,
            exponentMask
        );
        assertEq(smallCoefficient, 0, "Incorrect coefficient for smallest BigNumber");
        assertEq(smallExponent, 0, "Incorrect exponent for smallest BigNumber");

        // Assuming the exponent is the least significant bits
        uint256 largeBigNumber = (((1 << (256 - exponentSize)) - 1) << exponentSize) | ((1 << exponentSize) - 1);
        (uint256 largeCoefficient, uint256 largeExponent) = testHelper.decompileBigNumber(
            largeBigNumber,
            exponentSize,
            exponentMask
        );
        assertEq(largeCoefficient, (1 << (256 - exponentSize)) - 1, "Incorrect coefficient for largest BigNumber");
        assertEq(largeExponent, (1 << exponentSize) - 1, "Incorrect exponent for largest BigNumber");
    }

    function test_decompileBigNumber_ZeroBigNumber() public {
        uint256 exponentSize = 8;
        uint256 exponentMask = 0xFF;
        uint256 bigNumber = 0;

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(bigNumber, exponentSize, exponentMask);

        assertEq(coefficient, 0, "Coefficient should be 0 for zero BigNumber");
        assertEq(exponent, 0, "Exponent should be 0 for zero BigNumber");
    }

    function test_decompileBigNumber_MaxCoefficientZeroExponent() public {
        uint256 exponentSize = 8;
        uint256 exponentMask = 0xFF;

        uint256 bigNumber = ((1 << (256 - exponentSize)) - 1) << exponentSize;

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(bigNumber, exponentSize, exponentMask);

        assertEq(
            coefficient,
            (1 << (256 - exponentSize)) - 1,
            "Incorrect coefficient for max coefficient and zero exponent"
        );
        assertEq(exponent, 0, "Exponent should be 0 for max coefficient and zero exponent");
    }

    function testFuzz_decompileBigNumber(uint256 bigNumber) public {
        uint256 exponentSize = 8;
        uint256 exponentMask = 0xFF;

        // To ensure BigNumber is within a valid range, mask it with the maximum possible value
        uint256 maxBigNumber = (1 << (256 - exponentSize)) - 1 + ((1 << exponentSize) - 1);
        bigNumber &= maxBigNumber;

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(bigNumber, exponentSize, exponentMask);

        // Reconstruct the BigNumber from coefficient and exponent
        uint256 reconstructedBigNumber = (coefficient << exponentSize) | exponent;

        // The reconstructed BigNumber should match the original input
        assertEq(reconstructedBigNumber, bigNumber, "BigNumber reconstruction mismatch");
    }

    // ============= mostSignificantBit

    function test_mostSignificantBit_Zero() public {
        uint lastBit = testHelper.mostSignificantBit(0);
        assertEq(0, lastBit, "MSB of zero should be zero");
    }

    function test_mostSignificantBit_One() public {
        uint lastBit = testHelper.mostSignificantBit(1);
        assertEq(1, lastBit, "MSB of one should be one");
    }

    function test_mostSignificantBit_LargeNumber() public {
        uint lastBit = testHelper.mostSignificantBit(5035703444687813576399599);
        assertEq(83, lastBit, "MSB of 5035703444687813576399599 should be 83");
    }

    function test_mostSignificantBit_SmallNumber() public {
        uint lastBit = testHelper.mostSignificantBit(15539);
        assertEq(14, lastBit, "MSB of 15539 should be 14");
    }

    function test_mostSignificantBit_PowersOfTwo() public {
        for (uint8 i = 0; i < 128; i++) {
            uint256 num = 1 << i;
            uint lastBit = testHelper.mostSignificantBit(num);
            assertEq(i + 1, lastBit, "Incorrect MSB for power of two");
        }
    }

    function test_mostSignificantBit_MaxUint() public {
        // TODO: as lastBit is uint8 there is overflow and from 255 logic function wants to add 1 to it (overflow) and the result is 0
        uint256 num = type(uint256).max;
        uint lastBit = testHelper.mostSignificantBit(num);
        assertEq(256, lastBit, "Incorrect MSB for max uint256");
    }

    // ============= mulDivBigNumber

    function test_mulDivBigNumber_ZeroNumber1() public {
        uint256 number1 = 0;
        uint256 divisor = 1e18;
        uint256 precisionBits = 96;

        uint256 bigNumber = testHelper.toBigNumber(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(
            bigNumber,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);

        // TODO: Should we revert when number1 = 0?
        vm.expectRevert(stdError.arithmeticError);
        testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            divisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_DivisionByZero() public {
        uint256 number1 = 1;
        uint256 divisor = 0;
        uint256 precisionBits = 96;

        uint256 bigNumber = testHelper.toBigNumber(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        vm.expectRevert(stdError.divisionError);
        testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            divisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_VerySmallDivisor() public {
        uint256 number1 = 1e18; // A normal number
        uint256 verySmallDivisor = 1; // Very small divisor
        uint256 precisionBits = 96;

        uint256 bigNumber = testHelper.toBigNumber(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 result = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            verySmallDivisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );

        assertTrue(result > bigNumber, "Result should be larger due to small divisor");
    }

    function test_mulDivBigNumber_MaxBigNumber() public {
        uint256 maxBigNumber = type(uint256).max; // Maximum BigNumber
        uint256 number1 = 23456 * 1e18;
        uint256 divisor = 1e18;
        uint256 precisionBits = 96;

        vm.expectRevert(stdError.arithmeticError);
        testHelper.mulDivBigNumber(
            maxBigNumber,
            number1,
            divisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_EqualNumber1AndDivisor() public {
        uint256 number1 = 1;
        uint256 divisor = 1;
        uint256 precisionBits = 96;

        uint256 bigNumber = testHelper.toBigNumber(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        uint256 result = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            divisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );

        (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(
            result,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        uint256 expected = (DEFAULT_NUMBER * number1) / divisor;

        // uint256 conversionTolerance = BigMathTolerance.calculateTolerance(
        //     DEFAULT_NUMBER,
        //     DEFAULT_COEFFICIENT_SIZE,
        //     DEFAULT_EXPONENT_SIZE,
        //     BigMathUnsafe.ROUND_DOWN
        // );

        // uint256 divisionTolerance = BigMathTolerance.calculateMulDivBigNumberTolerance(
        //     bigNumber,
        //     number1,
        //     divisor,
        //     DEFAULT_COEFFICIENT_SIZE,
        //     DEFAULT_EXPONENT_SIZE
        // );

        // uint256 totalTolerance = conversionTolerance + divisionTolerance;

        // //TODO: Maybe add line if number1 == number2 then return same bigNumber in the function logic?
        // assertApproxEqAbs(normal, expected, totalTolerance);
    }

    function test_mulDivBigNumber_ZeroBigNumber() public {
        uint256 zeroBigNumber = 0;
        uint256 number1 = 23456 * 1e18;
        uint256 number2 = 1e18;
        uint256 precisionBits = 96;

        // TODO: Should we revert when bigNumber = 0 or we dont care?
        vm.expectRevert(stdError.arithmeticError);
        testHelper.mulDivBigNumber(
            zeroBigNumber,
            number1,
            number2,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_RevertIfExponentBelowZero() public {
        // Formula: res = bigNumber * number1 / number2
        // res is bigNumber

        uint256 number1 = 1e18;
        uint256 divisor = 25879 * 1e35;
        uint256 precisionBits = 96;

        uint256 bigNumber = testHelper.toBigNumber(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathUnsafe.ROUND_DOWN
        );

        vm.expectRevert(stdError.arithmeticError);
        testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            divisor,
            precisionBits,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_RevertExponentOverflow() public {
        uint256 bigNumber = 20275702527;
        uint256 number1 = 9426476730653339656575757836286015522;
        uint256 divisor = 2;
        uint256 precisionBits = 2;
        uint256 coefficientSize = 64;
        uint256 exponentSize = 8;
        uint256 exponentMask = 255;

        vm.expectRevert("exponent-overflow");
        testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            divisor,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            BigMathUnsafe.ROUND_DOWN
        );
    }

    function test_mulDivBigNumber_PrecisionLoss() public {
        uint256 bigNumber = 1000000e18;
        uint256 number1 = 1e18;
        uint256 number2 = 1e18;
        uint256 precisionBits = 64;
        uint256 coefficientSize = 64;
        uint256 exponentSize = 8;
        uint256 exponentMask = 255;

        uint256 result = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            number2,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            BigMathUnsafe.ROUND_DOWN
        );

        precisionBits = 8; // Lower precision
        uint256 result2 = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            number2,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            BigMathUnsafe.ROUND_DOWN
        );

        assert(result == result2);
    }

    function test_mulDivBigNumber_Rounding() public {
        uint256 bigNumber = 10000e18;
        uint256 number1 = 1e18;
        uint256 number2 = 1e18;
        uint256 precisionBits = 2;
        uint256 coefficientSize = 64;
        uint256 exponentSize = 8;
        uint256 exponentMask = 255;

        uint256 resultRoundUp = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            number2,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            BigMathUnsafe.ROUND_UP
        );

        uint256 resultRoundDown = testHelper.mulDivBigNumber(
            bigNumber,
            number1,
            number2,
            precisionBits,
            coefficientSize,
            exponentSize,
            exponentMask,
            BigMathUnsafe.ROUND_DOWN
        );

        // Assert the results for both rounding scenarios
        assert(resultRoundUp > resultRoundDown);
    }

    // function test_mulDivBigNumber_Revert() public {
    //     // Formula: res = bigNumber * number1 / number2
    //     // res is bigNumber

    //     uint256 number1 = 1e18;
    //     uint256 divisor = 25879 * 1e35;
    //     uint256 precisionBits = 96;

    //     (, , uint256 bigNumber) = testHelper.toBigNumber(
    //         DEFAULT_NUMBER,
    //         DEFAULT_COEFFICIENT_SIZE,
    //         DEFAULT_EXPONENT_SIZE,
    //         BigMathUnsafe.ROUND_DOWN
    //     );

    //     uint256 result = testHelper.mulDivBigNumber(
    //         bigNumber,
    //         number1,
    //         divisor,
    //         precisionBits,
    //         DEFAULT_COEFFICIENT_SIZE,
    //         DEFAULT_EXPONENT_SIZE,
    //         DEFAULT_EXPONENT_MASK,
    //         BigMathUnsafe.ROUND_DOWN
    //     );

    //     (uint256 coefficient, uint256 exponent) = testHelper.decompileBigNumber(
    //         result,
    //         DEFAULT_EXPONENT_SIZE,
    //         DEFAULT_EXPONENT_MASK
    //     );

    //     uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
    //     uint256 expected = (DEFAULT_NUMBER * number1) / divisor;

    //     // TODO: significant difference: expected = 1945 but the result = 1024
    //     assertApproxEqAbs(normal, expected, 1);
    //     // assertApproxEqAbs(normal, expected, DEFAULT_TOLERANCE);
    // }

    // struct MulDivInputs {
    //     uint256 normal;
    //     uint256 number1;
    //     uint256 divisor;
    //     uint256 precisionBits;
    //     uint8 coefficientSize;
    //     uint8 exponentSize;
    //     bool roundUp;
    // }

    // struct CalcInputs {
    //     uint256 bigNumber;
    //     uint256 normalFromResult;
    //     uint256 multiplied;
    //     uint256 divisionTolerance;
    // }

    // // tests to check if addition of two tolerances works
    // TODO: Implement mulDivBigNumber
    // function testFuzz_mulDivBigNumber(MulDivInputs memory inputs) public {
    //     vm.assume(inputs.normal > 1e8);
    //     vm.assume(inputs.number1 > 1e8);
    //     vm.assume(inputs.divisor > 1e8);
    //     vm.assume(inputs.coefficientSize >= 8 && inputs.coefficientSize <= 64);
    //     vm.assume(inputs.exponentSize >= 8 && inputs.exponentSize <= 64);
    //     vm.assume(inputs.coefficientSize + inputs.exponentSize <= 256);

    //     inputs.precisionBits = 96;

    //     // inputs.normal = 16003823243679492718104185;
    //     // inputs.number1 = 2103469618542;
    //     // inputs.divisor = 100000001;
    //     // inputs.coefficientSize = 28;
    //     // inputs.exponentSize = 8;
    //     // inputs.roundUp = false;

    //     try testHelper.toBigNumber(inputs.normal, inputs.coefficientSize, inputs.exponentSize, inputs.roundUp) returns (
    //         uint256 coefficient,
    //         uint256 exponent,
    //         uint256 bigNumber
    //     ) {
    //         uint256 reconstructedNormal = (coefficient << exponent);
    //         uint256 mask = BigMathTolerance.calculateMask(inputs.exponentSize);
    //         BigMathTolerance.BigNumberCalculationForMulBigNumberInaccuracy memory calc = BigMathTolerance
    //             .BigNumberCalculationForMulBigNumberInaccuracy({
    //                 bigNumber: bigNumber,
    //                 precisionBits: inputs.precisionBits,
    //                 coefficientSize: inputs.coefficientSize,
    //                 exponentSize: inputs.exponentSize,
    //                 exponentMask: mask
    //             });
    //         (uint256 tolerance, bool success) = BigMathTolerance.calculateMaxInaccuracyMulDivBigNumber(
    //             calc,
    //             inputs.number1,
    //             inputs.divisor,
    //             inputs.roundUp
    //         );
    //         if (success) {
    //             (uint256 numberWithTolerance1, bool subtractSuccess) = BigMathTolerance.safeSubtract(
    //                 inputs.normal,
    //                 tolerance
    //             );
    //             (uint256 numberWithTolerance2, bool addSuccess) = BigMathTolerance.safeAdd(inputs.normal, tolerance);
    //             if (addSuccess && subtractSuccess) {
    //                 if (reconstructedNormal >= numberWithTolerance1 && reconstructedNormal <= numberWithTolerance2) {
    //                     (uint256 _resultNumerator, bool success) = BigMathTolerance.safeMultiply(
    //                         bigNumber >> inputs.exponentSize,
    //                         inputs.number1
    //                     );
    //                     if (success) {
    //                         if (_resultNumerator != 0) {
    //                             performCalculation(inputs, bigNumber, inputs.roundUp, tolerance, mask);
    //                         }
    //                     }
    //                 }
    //             }
    //         }
    //     } catch Error(string memory reason) {
    //         emit log_named_string("Reverted with reason", reason);
    //     }
    // }

    // function performCalculation(
    //     MulDivInputs memory inputs,
    //     uint256 bigNumber,
    //     bool roundUp,
    //     uint256 tolerance,
    //     uint256 mask
    // ) internal {
    //     CalcInputs memory calcInputs;
    //     calcInputs.bigNumber = bigNumber;
    //     bool success;
    //     (calcInputs.multiplied, success) = BigMathTolerance.safeMultiply(inputs.normal, inputs.number1);
    //     if (success) {
    //         try
    //             testHelper.mulDivBigNumber(
    //                 bigNumber,
    //                 inputs.number1,
    //                 inputs.divisor,
    //                 inputs.precisionBits,
    //                 inputs.coefficientSize,
    //                 inputs.exponentSize,
    //                 mask,
    //                 roundUp
    //             )
    //         returns (uint256 result) {
    //             uint256 normalFromMulDiv = testHelper.fromBigNumber(result, inputs.exponentSize, mask);
    //             uint256 expectedNormal = calcInputs.multiplied / inputs.divisor;
    //             assertApproxEqAbs(normalFromMulDiv, expectedNormal, calcInputs.divisionTolerance + tolerance);
    //         } catch Panic(uint errorCode) {
    //             if (errorCode != 17) {
    //                 // we ignore Arithmetic over/under flow
    //                 assertEq(true, false);
    //             }
    //         }
    //     }
    // }

    // ============= mulBigNumber

    /*
        We have two ordinary numbers 'a' and 'b', and a function 'toBigNumber' that converts 
        these numbers into a BigNumber format. However, after converting back 
        from BigNumber to ordinary numbers, there's a loss of precision. 
        We're interested in calculating the maximum difference in the 
        multiplication result due to this precision loss.

        Example:

        - Original numbers: a = 123, b = 456
        - After conversion to BigNumber and back to ordinary numbers: a'' = 120, b'' = 450

        Analysis:

        1. Direct Multiplication of Original Numbers:
           - Multiplying a and b directly gives: 123 * 456 = 56088

        2. Multiplication After Conversion:
           - Multiplying a'' and b'' gives: 120 * 450 = 54000

        3. Calculating the Maximum Error:
           - The conversion error for a is: Error_a = |123 - 120| = 3
           - The conversion error for b is: Error_b = |456 - 450| = 6
           - The maximum multiplication error can be calculated as:
             Maximum Multiplication Error = (123 + 3) * (456 + 6) - 123 * 456 = 2124

        This calculation indicates that the maximum potential difference in the 
        multiplication result, due to precision loss in conversion, could be as 
        high as 2124. 

        In this example, the multiplication of the original numbers 
        (a and b) results in 56088, while the multiplication of the converted 
        numbers (a'' and b'') results in 54000. The actual observed difference 
        in this case is 56088 - 54000 = 2088, which is within the calculated 
        maximum error range.

        Above described case is calculated via 'calculateMaxInaccuracyForBigNumbersConversion' function.

        But also inaccuracy can appear in mulBigNumber function itself and 'calculateMaxInaccuracyForMulBigNumber' function is responsible for that.
    */

    function test_mulBigNumber_NormalCase() public {
        uint256 number1 = 123456789;
        uint256 number2 = 456789999;
        uint8 coefficientSize = 64;
        uint8 exponentSize = 16;
        uint256 decimal = 0;

        BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
            .CalculateBigNumbersAndMaskParams({
                number1: number1,
                number2: number2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize
            });

        // Calculate big numbers and mask
        BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

        // result its BigNumber format with coefficient and exponent
        uint256 resultBigNumber = testHelper.mulBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            decimal
        );

        uint256 maxInaccuracyForMulBigNumber = BigMathTolerance.calculateMaxInaccuracyForMulBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize
        );

        uint256 resultInNormalFormat = testHelper.fromBigNumber(resultBigNumber, exponentSize, results.mask);

        BigMathTolerance.BigNumberCalculationForBigNumbersConversion memory calc = BigMathTolerance
            .BigNumberCalculationForBigNumbersConversion({
                number1: number1,
                number2: number2,
                bigNumber1: results.bigNumber1,
                bigNumber2: results.bigNumber2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize,
                roundUp: false,
                mask: results.mask
            });

        (uint256 maxInaccuracyForBigNumbersConversion, bool success) = BigMathTolerance
            .calculateMaxInaccuracyForBigNumbersConversion(calc);
        if (success) {
            uint256 expected = number1 * number2;
            assertApproxEqAbs(
                resultInNormalFormat,
                expected,
                maxInaccuracyForMulBigNumber + maxInaccuracyForBigNumbersConversion,
                "The result of mulBigNumber does not match the expected value."
            );
        }
    }

    // TODO: Fix function to properly calculate inaccuracy in 'mulBigNumber' function
    // function test_mulBigNumber_NormalCase2() public {
    //     uint256 number1 = 4575686587646347568679463453474568;
    //     uint256 number2 = 9865735435436457346534523654764573;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 0;

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance.CalculateBigNumbersAndMaskParams({
    //         number1: number1,
    //         number2: number2,
    //         coefficientSize: coefficientSize,
    //         exponentSize: exponentSize
    //     });

    //     // Calculate big numbers and mask
    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

    //     // result its BigNumber format with coefficient and exponent
    //     uint256 resultBigNumber = testHelper.mulBigNumber(
    //         results.bigNumber1,
    //         results.bigNumber2,
    //         coefficientSize,
    //         exponentSize,
    //         decimal
    //     );

    //     uint256 maxInaccuracyForMulBigNumber = BigMathTolerance.calculateMaxInaccuracyForMulBigNumber(
    //         results.bigNumber1,
    //         results.bigNumber2,
    //         coefficientSize,
    //         exponentSize
    //     );

    //     uint256 resultInNormalFormat = testHelper.fromBigNumber(resultBigNumber, exponentSize, results.mask);

    //     BigMathTolerance.BigNumberCalculationForBigNumbersConversion memory calc = BigMathTolerance
    //         .BigNumberCalculationForBigNumbersConversion({
    //             number1: number1,
    //             number2: number2,
    //             bigNumber1: results.bigNumber1,
    //             bigNumber2: results.bigNumber2,
    //             coefficientSize: coefficientSize,
    //             exponentSize: exponentSize,
    //             roundUp: false,
    //             mask: results.mask
    //         });

    //     (uint256 maxInaccuracyForBigNumbersConversion, bool success) = BigMathTolerance
    //         .calculateMaxInaccuracyForBigNumbersConversion(calc);
    //     if (success) {
    //         uint256 expected = number1 * number2;
    //         assertApproxEqAbs(
    //             resultInNormalFormat,
    //             expected,
    //             maxInaccuracyForBigNumbersConversion + maxInaccuracyForMulBigNumber,
    //             "The result of mulBigNumber does not match the expected value."
    //         );
    //     }
    // }

    // TODO: test decimals
    // function test_mulBigNumber_Decimals() public {
    //     uint256 number1 = 4575686587646347568679463453474568;
    //     uint256 number2 = 9865735435436457346534523654764573;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 8;

    // }

    // TODO: Test zero values
    // function test_mulBigNumber_ZeroBigNumber1() public {
    //     uint256 number1 = 0;
    //     uint256 number2 = 456789999;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 0;

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
    //         .CalculateBigNumbersAndMaskParams({
    //             number1: number1,
    //             number2: number2,
    //             coefficientSize: coefficientSize,
    //             exponentSize: exponentSize
    //         });

    //     // Calculate big numbers and mask
    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

    //     // TODO: Shouldn't we revert if first number is 0?
    //     vm.expectRevert();
    //     testHelper.mulBigNumber(results.bigNumber1, results.bigNumber2, coefficientSize, exponentSize, decimal);
    // }

    // function test_mulBigNumber_ZeroBigNumber2() public {
    //     uint256 number1 = 456789999;
    //     uint256 number2 = 0;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 0;

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
    //         .CalculateBigNumbersAndMaskParams({
    //             number1: number1,
    //             number2: number2,
    //             coefficientSize: coefficientSize,
    //             exponentSize: exponentSize
    //         });

    //     // Calculate big numbers and mask
    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

    //     // TODO: Shouldn't we revert if second number is 0?
    //     vm.expectRevert();
    //     testHelper.mulBigNumber(results.bigNumber1, results.bigNumber2, coefficientSize, exponentSize, decimal);
    // }

    // function test_mulBigNumber_Decimals(
    //     uint256 number1,
    //     uint256 number2,
    //     uint8 coefficientSize,
    //     uint8 exponentSize
    // ) public {
    //     // TODO: test decimals
    // }

    struct MulBigNumberTestParams {
        uint256 number1;
        uint256 number2;
        uint8 coefficientSize;
        uint8 exponentSize;
    }

    // ============= divBigNumber

    function test_divBigNumber_ZeroPrecision() public {
        uint256 number1 = 45678999999999999999999;
        uint256 number2 = 6546456456;
        uint8 coefficientSize = 64;
        uint8 exponentSize = 16;
        uint256 precision = 0;
        uint256 decimal = 0;

        BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
            .CalculateBigNumbersAndMaskParams({
                number1: number1,
                number2: number2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize
            });

        // Calculate big numbers and mask
        BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

        // result its BigNumber format with coefficient and exponent
        uint256 resultBigNumber = testHelper.divBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 maxInaccuracyForDivBigNumber = BigMathTolerance.calculateMaxInaccuracyForDivBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 resultInNormalFormat = testHelper.fromBigNumber(resultBigNumber, exponentSize, results.mask);

        BigMathTolerance.BigNumberCalculationForBigNumbersConversion memory calc = BigMathTolerance
            .BigNumberCalculationForBigNumbersConversion({
                number1: number1,
                number2: number2,
                bigNumber1: results.bigNumber1,
                bigNumber2: results.bigNumber2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize,
                roundUp: false,
                mask: results.mask
            });

        (uint256 maxInaccuracyForBigNumbersConversion, bool success) = BigMathTolerance
            .calculateMaxInaccuracyForBigNumbersConversion(calc);
        if (success) {
            uint256 expected = number1 / number2;
            assertApproxEqAbs(
                resultInNormalFormat,
                expected,
                maxInaccuracyForDivBigNumber + maxInaccuracyForBigNumbersConversion,
                "The result of mulBigNumber does not match the expected value."
            );
        }
    }

    function test_divBigNumber_WithPrecision() public {
        uint256 number1 = 45678999999999999999999999999999;
        uint256 number2 = 6546456456999999999999;
        uint8 coefficientSize = 64;
        uint8 exponentSize = 16;
        uint256 precision = 18;
        uint256 decimal = 0;

        BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
            .CalculateBigNumbersAndMaskParams({
                number1: number1,
                number2: number2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize
            });

        // Calculate big numbers and mask
        BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

        // result its BigNumber format with coefficient and exponent
        uint256 resultBigNumber = testHelper.divBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 maxInaccuracyForDivBigNumber = BigMathTolerance.calculateMaxInaccuracyForDivBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 resultInNormalFormat = testHelper.fromBigNumber(resultBigNumber, exponentSize, results.mask);

        BigMathTolerance.BigNumberCalculationForBigNumbersConversion memory calc = BigMathTolerance
            .BigNumberCalculationForBigNumbersConversion({
                number1: number1,
                number2: number2,
                bigNumber1: results.bigNumber1,
                bigNumber2: results.bigNumber2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize,
                roundUp: false,
                mask: results.mask
            });

        (uint256 maxInaccuracyForBigNumbersConversion, bool success) = BigMathTolerance
            .calculateMaxInaccuracyForBigNumbersConversion(calc);
        if (success) {
            uint256 expected = number1 / number2;
            assertApproxEqAbs(
                resultInNormalFormat,
                expected,
                maxInaccuracyForDivBigNumber + maxInaccuracyForBigNumbersConversion,
                "The result of mulBigNumber does not match the expected value."
            );
        }
    }

    function test_divBigNumber_NormalCase2() public {
        uint256 number1 = 45678999999999999999999;
        uint256 number2 = 6546456456;
        uint8 coefficientSize = 64;
        uint8 exponentSize = 16;
        uint256 precision = 0;
        uint256 decimal = 0;

        BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
            .CalculateBigNumbersAndMaskParams({
                number1: number1,
                number2: number2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize
            });

        // Calculate big numbers and mask
        BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

        // result its BigNumber format with coefficient and exponent
        uint256 resultBigNumber = testHelper.divBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 maxInaccuracyForDivBigNumber = BigMathTolerance.calculateMaxInaccuracyForDivBigNumber(
            results.bigNumber1,
            results.bigNumber2,
            coefficientSize,
            exponentSize,
            precision,
            decimal
        );

        uint256 resultInNormalFormat = testHelper.fromBigNumber(resultBigNumber, exponentSize, results.mask);

        BigMathTolerance.BigNumberCalculationForBigNumbersConversion memory calc = BigMathTolerance
            .BigNumberCalculationForBigNumbersConversion({
                number1: number1,
                number2: number2,
                bigNumber1: results.bigNumber1,
                bigNumber2: results.bigNumber2,
                coefficientSize: coefficientSize,
                exponentSize: exponentSize,
                roundUp: false,
                mask: results.mask
            });

        (uint256 maxInaccuracyForBigNumbersConversion, bool success) = BigMathTolerance
            .calculateMaxInaccuracyForBigNumbersConversion(calc);
        if (success) {
            uint256 expected = number1 / number2;
            assertApproxEqAbs(
                resultInNormalFormat,
                expected,
                maxInaccuracyForBigNumbersConversion + maxInaccuracyForDivBigNumber,
                "The result of mulBigNumber does not match the expected value."
            );
        }
    }

    // TODO: test decimals
    // function test_divBigNumber_Decimals() public {
    //     uint256 number1 = 45678999999999999999999;
    //     uint256 number2 = 6546456456;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 8;

    // }

    // TODO: test zero values
    // function test_divBigNumber_ZeroBigNumber1() public {
    //     uint256 number1 = 0;
    //     uint256 number2 = 456789999;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 precision = 0;
    //     uint256 decimal = 0;

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
    //         .CalculateBigNumbersAndMaskParams({
    //             number1: number1,
    //             number2: number2,
    //             coefficientSize: coefficientSize,
    //             exponentSize: exponentSize
    //         });

    //     // Calculate big numbers and mask
    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

    //     // TODO: Should we revert in case when number1 = 0?
    //     vm.expectRevert();
    //     testHelper.divBigNumber(
    //         results.bigNumber1,
    //         results.bigNumber2,
    //         coefficientSize,
    //         exponentSize,
    //         precision,
    //         decimal
    //     );
    // }

    // function test_divBigNumber_ZeroBigNumber2() public {
    //     uint256 number1 = 456789999;
    //     uint256 number2 = 0;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 precision = 0;
    //     uint256 decimal = 0;

    //     BigMathTolerance.CalculateBigNumbersAndMaskParams memory params = BigMathTolerance
    //         .CalculateBigNumbersAndMaskParams({
    //             number1: number1,
    //             number2: number2,
    //             coefficientSize: coefficientSize,
    //             exponentSize: exponentSize
    //         });

    //     // Calculate big numbers and mask
    //     BigMathTolerance.BigNumberResults memory results = BigMathTolerance.calculateBigNumbersAndMask(params);

    //     // TODO: Should we revert in case when number2 = 0?
    //     vm.expectRevert();
    //     testHelper.divBigNumber(
    //         results.bigNumber1,
    //         results.bigNumber2,
    //         coefficientSize,
    //         exponentSize,
    //         precision,
    //         decimal
    //     );
    // }

    // TODO: test decimals
    // function test_divBigNumber_Decimals(
    //     uint256 number1,
    //     uint256 number2,
    //     uint8 coefficientSize,
    //     uint8 exponentSize
    // ) public {
    //     uint256 number1 = 9865735435436457346534523654764573;
    //     uint256 number2 = 45;
    //     uint8 coefficientSize = 64;
    //     uint8 exponentSize = 16;
    //     uint256 decimal = 8;

    // }
}
