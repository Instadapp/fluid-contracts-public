// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @title library that represents a number in BigNumber(coefficient and exponent) format to store in smaller bits.
/// @notice the number is divided into two parts: a coefficient and an exponent. This comes at a cost of losing some precision
/// at the end of the number because the exponent simply fills it with zeroes. This precision is oftentimes negligible and can
/// result in significant gas cost reduction due to storage space reduction.
/// Also note, a valid big number is as follows: if the exponent is > 0, then coefficient last bits should be occupied to have max precision.
/// @dev roundUp is more like a increase 1, which happens everytime for the same number.
/// roundDown simply sets trailing digits after coefficientSize to zero (floor), only once for the same number.
library BigMathMinified {
    /// @dev constants to use for `roundUp` input param to increase readability
    bool internal constant ROUND_DOWN = false;
    bool internal constant ROUND_UP = true;

    /// @dev converts `normal` number to BigNumber with `exponent` and `coefficient` (or precision).
    /// e.g.:
    /// 5035703444687813576399599 (normal) = (coefficient[32bits], exponent[8bits])[40bits]
    /// 5035703444687813576399599 (decimal) => 10000101010010110100000011111011110010100110100000000011100101001101001101011101111 (binary)
    ///                                     => 10000101010010110100000011111011000000000000000000000000000000000000000000000000000
    ///                                                                        ^-------------------- 51(exponent) -------------- ^
    /// coefficient = 1000,0101,0100,1011,0100,0000,1111,1011               (2236301563)
    /// exponent =                                            0011,0011     (51)
    /// bigNumber =   1000,0101,0100,1011,0100,0000,1111,1011,0011,0011     (572493200179)
    ///
    /// @param normal number which needs to be converted into Big Number
    /// @param coefficientSize at max how many bits of precision there should be (64 = uint64 (64 bits precision))
    /// @param exponentSize at max how many bits of exponent there should be (8 = uint8 (8 bits exponent))
    /// @param roundUp signals if result should be rounded down or up
    /// @return bigNumber converted bigNumber (coefficient << exponent)
    function toBigNumber(
        uint256 normal,
        uint256 coefficientSize,
        uint256 exponentSize,
        bool roundUp
    ) internal pure returns (uint256 bigNumber) {
        assembly {
            let lastBit_
            let number_ := normal
            if gt(number_, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                number_ := shr(0x80, number_)
                lastBit_ := 0x80
            }
            if gt(number_, 0xFFFFFFFFFFFFFFFF) {
                number_ := shr(0x40, number_)
                lastBit_ := add(lastBit_, 0x40)
            }
            if gt(number_, 0xFFFFFFFF) {
                number_ := shr(0x20, number_)
                lastBit_ := add(lastBit_, 0x20)
            }
            if gt(number_, 0xFFFF) {
                number_ := shr(0x10, number_)
                lastBit_ := add(lastBit_, 0x10)
            }
            if gt(number_, 0xFF) {
                number_ := shr(0x8, number_)
                lastBit_ := add(lastBit_, 0x8)
            }
            if gt(number_, 0xF) {
                number_ := shr(0x4, number_)
                lastBit_ := add(lastBit_, 0x4)
            }
            if gt(number_, 0x3) {
                number_ := shr(0x2, number_)
                lastBit_ := add(lastBit_, 0x2)
            }
            if gt(number_, 0x1) {
                lastBit_ := add(lastBit_, 1)
            }
            if gt(number_, 0) {
                lastBit_ := add(lastBit_, 1)
            }
            if lt(lastBit_, coefficientSize) {
                // for throw exception
                lastBit_ := coefficientSize
            }
            let exponent := sub(lastBit_, coefficientSize)
            let coefficient := shr(exponent, normal)
            if and(roundUp, gt(exponent, 0)) {
                // rounding up is only needed if exponent is > 0, as otherwise the coefficient fully holds the original number
                coefficient := add(coefficient, 1)
                if eq(shl(coefficientSize, 1), coefficient) {
                    // case were coefficient was e.g. 111, with adding 1 it became 1000 (in binary) and coefficientSize 3 bits
                    // final coefficient would exceed it's size. -> reduce coefficent to 100 and increase exponent by 1.
                    coefficient := shl(sub(coefficientSize, 1), 1)
                    exponent := add(exponent, 1)
                }
            }
            if iszero(lt(exponent, shl(exponentSize, 1))) {
                // if exponent is >= exponentSize, the normal number is too big to fit within
                // BigNumber with too small sizes for coefficient and exponent
                revert(0, 0)
            }
            bigNumber := shl(exponentSize, coefficient)
            bigNumber := add(bigNumber, exponent)
        }
    }

    /// @dev get `normal` number from `bigNumber`, `exponentSize` and `exponentMask`
    function fromBigNumber(
        uint256 bigNumber,
        uint256 exponentSize,
        uint256 exponentMask
    ) internal pure returns (uint256 normal) {
        assembly {
            let coefficient := shr(exponentSize, bigNumber)
            let exponent := and(bigNumber, exponentMask)
            normal := shl(exponent, coefficient)
        }
    }

    /// @dev gets the most significant bit `lastBit` of a `normal` number (length of given number of binary format).
    /// e.g.
    /// 5035703444687813576399584 = 10000101010010110100000011111011110010100110100000000011100101001101001101011100000
    /// lastBit =                   ^---------------------------------   83   ----------------------------------------^
    function mostSignificantBit(uint256 normal) internal pure returns (uint lastBit) {
        assembly {
            let number_ := normal
            if gt(normal, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                number_ := shr(0x80, number_)
                lastBit := 0x80
            }
            if gt(number_, 0xFFFFFFFFFFFFFFFF) {
                number_ := shr(0x40, number_)
                lastBit := add(lastBit, 0x40)
            }
            if gt(number_, 0xFFFFFFFF) {
                number_ := shr(0x20, number_)
                lastBit := add(lastBit, 0x20)
            }
            if gt(number_, 0xFFFF) {
                number_ := shr(0x10, number_)
                lastBit := add(lastBit, 0x10)
            }
            if gt(number_, 0xFF) {
                number_ := shr(0x8, number_)
                lastBit := add(lastBit, 0x8)
            }
            if gt(number_, 0xF) {
                number_ := shr(0x4, number_)
                lastBit := add(lastBit, 0x4)
            }
            if gt(number_, 0x3) {
                number_ := shr(0x2, number_)
                lastBit := add(lastBit, 0x2)
            }
            if gt(number_, 0x1) {
                lastBit := add(lastBit, 1)
            }
            if gt(number_, 0) {
                lastBit := add(lastBit, 1)
            }
        }
    }

    /// @dev gets the least significant bit `firstBit` of a `normal` number (position of rightmost 1 in binary format).
    /// e.g.
    /// 5035703444687813576399584 = 10000101010010110100000011111011110010100110100000000011100101001101001101011100000
    /// firstBit =                                                                                               ^-6--^
    function leastSignificantBit(uint256 normal) internal pure returns (uint firstBit) {
        assembly {
            // If number is 0, revert as there is no least significant bit
            if iszero(normal) {
                revert(0, 0)
            }

            // Find first set bit using binary search
            let number_ := normal
            firstBit := 0

            // Check if lower 128 bits are all zero
            if iszero(and(number_, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) {
                number_ := shr(0x80, number_)
                firstBit := 0x80
            }
            // Check if lower 64 bits are all zero
            if iszero(and(number_, 0xFFFFFFFFFFFFFFFF)) {
                number_ := shr(0x40, number_)
                firstBit := add(firstBit, 0x40)
            }
            // Check if lower 32 bits are all zero
            if iszero(and(number_, 0xFFFFFFFF)) {
                number_ := shr(0x20, number_)
                firstBit := add(firstBit, 0x20)
            }
            // Check if lower 16 bits are all zero
            if iszero(and(number_, 0xFFFF)) {
                number_ := shr(0x10, number_)
                firstBit := add(firstBit, 0x10)
            }
            // Check if lower 8 bits are all zero
            if iszero(and(number_, 0xFF)) {
                number_ := shr(0x8, number_)
                firstBit := add(firstBit, 0x8)
            }
            // Check if lower 4 bits are all zero
            if iszero(and(number_, 0xF)) {
                number_ := shr(0x4, number_)
                firstBit := add(firstBit, 0x4)
            }
            // Check if lower 2 bits are all zero
            if iszero(and(number_, 0x3)) {
                number_ := shr(0x2, number_)
                firstBit := add(firstBit, 0x2)
            }
            // Check if lowest bit is zero
            if iszero(and(number_, 0x1)) {
                firstBit := add(firstBit, 1)
            }
            // Add 1 to match the 1-based position counting
            firstBit := add(firstBit, 1)
        }
    }
}
