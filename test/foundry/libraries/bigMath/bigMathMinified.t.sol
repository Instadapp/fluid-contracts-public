//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { BigMathTolerance } from "./bigMathTolerance.sol";
import { BigMathTestHelper } from "./bigMathTestHelper.sol";

contract LibraryBigMathBaseTest is Test {
    // use testHelper contract to measure gas for library methods via forge --gas-report
    BigMathTestHelper testHelper;

    function setUp() public {
        testHelper = new BigMathTestHelper();
    }
}

contract LibraryBigMathMinifiedTest is LibraryBigMathBaseTest {
    uint256 DEFAULT_TOLERANCE = 1e9; // 9 digits tolerance
    uint256 DEFAULT_NUMBER = 5035703444687813576399599; // 5035703444687813,576399599
    uint8 DEFAULT_COEFFICIENT_SIZE = 56;
    uint8 DEFAULT_EXPONENT_SIZE = 8;
    uint256 DEFAULT_EXPONENT_MASK = 0xFF;

    // ======== toBigNumber
    /// @dev see comments in BigMathMinified.sol for examples of results that are used as assert results here
    function test_toBigNumber() public {
        uint256 bigNumber = testHelper.toBigNumber(DEFAULT_NUMBER, 32, 8, BigMathMinified.ROUND_DOWN);
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
            BigMathMinified.ROUND_UP
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
            BigMathMinified.ROUND_UP
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
        testHelper.toBigNumber(normalNumber, 8, 2, BigMathMinified.ROUND_DOWN);
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

    // ======== fromBigNumber (2 params)

    function test_fromBigNumber() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, DEFAULT_NUMBER, DEFAULT_TOLERANCE);
    }

    function test_fromBigNumber_WithRoundUp() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );

        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function test_fromBigNumber_SmallNumber() public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            7,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertEq(normal, 7);
    }

    function testFuzz_fromBigNumber(uint128 inputNumber) public {
        (uint256 coefficient, uint256 exponent, ) = testHelper.toBigNumberExtended(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE * 2, // use bigger coefficient and exponent
            DEFAULT_EXPONENT_SIZE * 2,
            BigMathMinified.ROUND_DOWN
        );

        uint256 normal = testHelper.fromBigNumber(coefficient, exponent);
        assertApproxEqAbs(normal, inputNumber, DEFAULT_TOLERANCE);
    }

    function test_fromBigNumber_WithDecompile() public {
        (, , uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
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
            BigMathMinified.ROUND_DOWN
        );
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function test_fromBigNumber_ThreeParams_WithRoundUp() public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            DEFAULT_NUMBER,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );
        assertApproxEqAbs(normal, DEFAULT_NUMBER, difference);
    }

    function testFuzz_fromBigNumber_ThreeParams(uint128 inputNumber) public {
        (uint256 coefficient, uint256 exponent, uint256 bigNumber) = testHelper.toBigNumberExtended(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        uint256 normal6 = testHelper.fromBigNumber(coefficient, exponent);
        uint256 normal = testHelper.fromBigNumber(bigNumber, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
        uint256 difference = BigMathTolerance.estimateRoundingErrorViaConversion(
            inputNumber,
            DEFAULT_COEFFICIENT_SIZE,
            DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
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
}
