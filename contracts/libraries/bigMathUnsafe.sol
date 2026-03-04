// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

// todo: decide for license

// Note: It's advised to use BigMathMinified which covers +90% of use cases, other functions need more thorough audits and testing

/// @title library that represents a number in BigNumber(coefficient and exponent) format to store in smaller bits.
/// @notice the number is divided into two parts: a coefficient and an exponent. This comes at a cost of losing some precision
/// at the end of the number because the exponent simply fills it with zeroes. This precision is oftentimes negligible and can
/// result in significant gas cost reduction due to storage space reduction.
/// Also note, Valid big number is as follows: if the exponent is > 0, then coefficient last bits should be occupied to have max precision
/// @dev roundUp is more like a increase 1, which happens everytime for the same number.
/// roundDown simply sets trailing digits after coefficientSize to zero (floor), only once to the same number.
library BigMathUnsafe {
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

    /// @dev see {BigMathUnsafe-toBigNumber}, but returns coefficient and exponent too
    function toBigNumberExtended(
        uint256 normal,
        uint256 coefficientSize,
        uint256 exponentSize,
        bool roundUp
    ) internal pure returns (uint256 coefficient, uint256 exponent, uint256 bigNumber) {
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
            exponent := sub(lastBit_, coefficientSize)
            coefficient := shr(exponent, normal)
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

    /// @dev get `normal` number from BigNumber `coefficient` and `exponent`.
    /// e.g.:
    /// (coefficient[32bits], exponent[8bits])[40bits] => (normal)
    /// (2236301563, 51) = 100001010100101101000000111110110000000000000000000000000000000000000000000000000
    /// coefficient = 1000,0101,0100,1011,0100,0000,1111,1011 (2236301563)
    /// exponent =    0011,0011 (51)
    /// normal =     10000101010010110100000011111011000000000000000000000000000000000000000000000000000  (5035703442907428892442624)
    ///                                                ^-------------------- 51(exponent) -------------- ^
    function fromBigNumber(uint256 coefficient, uint256 exponent) internal pure returns (uint256 normal) {
        assembly {
            normal := shl(exponent, coefficient)
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

    /// @dev multiplies a `normal` number with a `bigNumber1` and then divides by `bigNumber2`, with `exponentSize` and
    /// `exponentMask` being used for both bigNumbers.
    /// e.g.
    /// res = normal * bigNumber1 / bigNumber2
    /// normal:  normal number 281474976710656
    /// bigNumber1: bigNumber 265046402172 [(0011,1101,1011,0101,1111,1111,0010,0100)Coefficient, (0111,1100)Exponent]
    /// bigNumber2: bigNumber 178478830197 [(0010 1001 1000 1110 0010 1010 1101 0010)Coefficient, (0111 0101)Exponent
    /// @return res normal number 53503841411969141
    function mulDivNormal(
        uint256 normal,
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 exponentSize,
        uint256 exponentMask
    ) internal pure returns (uint256 res) {
        assembly {
            let coefficient1_ := shr(exponentSize, bigNumber1)
            let exponent1_ := and(bigNumber1, exponentMask)
            let coefficient2_ := shr(exponentSize, bigNumber2)
            let exponent2_ := and(bigNumber2, exponentMask)
            let X := gt(exponent1_, exponent2_) // bigNumber2 > bigNumber1
            if X {
                coefficient1_ := shl(sub(exponent1_, exponent2_), coefficient1_)
            }
            if iszero(X) {
                coefficient2_ := shl(sub(exponent2_, exponent1_), coefficient2_)
            }
            // todo should we do this not in assembly so normal SafeMath checks work? e.g. divide by 0 etc.
            res := div(mul(normal, coefficient1_), coefficient2_)
        }
    }

    /// @dev decompiles a `bigNumber` into `coefficient` and `exponent`, based on `exponentSize` and `exponentMask`.
    /// e.g.
    /// bigNumber[40bits] => coefficient[32bits], exponent[8bits]
    /// 1000,0101,0100,1011,0100,0000,1111,1011,0011,0011 =>
    ///   coefficient = 1000,0101,0100,1011,0100,0000,1111,1011 (2236301563)
    ///   exponent =    0011,0011 (51)
    function decompileBigNumber(
        uint256 bigNumber,
        uint256 exponentSize,
        uint256 exponentMask
    ) internal pure returns (uint256 coefficient, uint256 exponent) {
        assembly {
            coefficient := shr(exponentSize, bigNumber)
            exponent := and(bigNumber, exponentMask)
        }
    }

    /// @dev gets the most significant bit `lastBit` of a `normal` number (length of given number of binary format).
    /// e.g.
    /// 5035703444687813576399599 = 10000101010010110100000011111011110010100110100000000011100101001101001101011101111
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

    /// @dev multiplies a `bigNumber` with normal `number1` and then divides by normal `number2`. `exponentSize` and `exponentMask`
    /// are used for the input `bigNumber` and the `result` is a BigNumber with `coefficientSize` and `exponentSize`.
    /// @param bigNumber Coefficient | Exponent. Eg: 8 bits coefficient (1101 0101) and 4 bits exponent (0011)
    /// @param number1 normal number. Eg:- 32421421413532
    /// @param number2 normal number. Eg:- 91897739843913
    /// @param precisionBits precision bits should be set such that, (((Coefficient * number1) << precisionBits) / number2) > max coefficient possible
    /// @param coefficientSize coefficient size. Eg: 8 bits, 56 btits, etc
    /// @param exponentSize exponent size. Eg: 4 bits, 12 btits, etc
    /// @param exponentMask exponent mask. (1 << exponentSize) - 1
    /// @param roundUp is true then roundUp, default it's round down
    /// @return result bigNumber * number1 / number2. Note bigNumber can't get directly multiplied or divide by normal numbers.
    /// TODO: Add an example which can help in better understanding.
    /// Didn't converted into assembly as overflow checks are good to have
    function mulDivBigNumber(
        uint256 bigNumber,
        uint256 number1,
        uint256 number2,
        uint256 precisionBits,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 exponentMask,
        bool roundUp
    ) internal pure returns (uint256 result) {
        uint256 _resultNumerator = (((bigNumber >> exponentSize) * number1) << precisionBits) / number2;
        uint256 diff = mostSignificantBit(_resultNumerator) - coefficientSize;
        _resultNumerator = _resultNumerator >> diff;
        _resultNumerator = roundUp ? _resultNumerator + 1 : _resultNumerator;
        uint256 _exponent = (bigNumber & exponentMask) + diff - precisionBits;

        if (_exponent <= exponentMask) {
            result = (_resultNumerator << exponentSize) + _exponent;
        } else {
            revert("exponent-overflow");
        }
    }

    // TODO: this function probably has some bugs & needs some updates to make it more efficient
    /// @dev multiplies a `bigNumber1` with another `bigNumber2`.
    /// e.g. res = bigNumber1 * bigNumber2 = [(coe1, exp1) * (coe2, exp2)] >> decimal
    ///          = (coe1*coe2>>overflow, exp1+exp2+overflow-decimal)
    /// @param bigNumber1          BigNumber format with coefficient and exponent
    /// @param bigNumber2          BigNumber format with coefficient and exponent
    /// @param coefficientSize     max size of coefficient, same for both `bigNumber1` and `bigNumber2`
    /// @param exponentSize        max size of exponent, same for both `bigNumber1` and `bigNumber2`
    /// @param decimal             decimals in bits
    /// @return res                BigNumber format with coefficient and exponent
    function mulBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 decimal
    ) internal pure returns (uint256 res) {
        uint256 coefficient1_;
        uint256 exponent1_;
        uint256 coefficient2_;
        uint256 exponent2_;

        assembly {
            if eq(bigNumber1, 0) {
                stop()
            }

            if eq(bigNumber2, 0) {
                stop()
            }

            let exponentMask_ := sub(shl(exponentSize, 1), 1)
            coefficient1_ := shr(exponentSize, bigNumber1)
            exponent1_ := and(bigNumber1, exponentMask_)
            coefficient2_ := shr(exponentSize, bigNumber2)
            exponent2_ := and(bigNumber2, exponentMask_)
        }

        // when exponent is 0, it means coefficient last bit could be less than _coefficientSize and we need to calculate the length using mostSignificantBit()
        // when exponent is greater than 0, coefficient length will always be the same as _coefficientSize
        uint256 coefficientLen1_ = exponent1_ == 0 ? mostSignificantBit(coefficient1_) : coefficientSize;
        uint256 coefficientLen2_ = exponent2_ == 0 ? mostSignificantBit(coefficient2_) : coefficientSize;

        assembly {
            let overflowLen_
            let resCoefficient_ := mul(coefficient1_, coefficient2_)
            let midLen_ := add(coefficientLen1_, coefficientLen2_)
            // the (coefficientLen1_ * coefficientLen2_) length will be among
            // (coefficientLen1_'s length + coefficientLen2_'s length) and (coefficientLen1_'s length + coefficientLen2_'s length -1)
            if eq(and(resCoefficient_, shl(sub(midLen_, 1), 1)), 0) {
                midLen_ := sub(midLen_, 1)
            }
            if gt(midLen_, coefficientSize) {
                overflowLen_ := sub(midLen_, coefficientSize)
                resCoefficient_ := shr(overflowLen_, resCoefficient_)
            }
            let resExponent_ := add(add(exponent1_, exponent2_), overflowLen_)
            let cond_ := gt(add(resExponent_, coefficientSize), decimal)
            if iszero(cond_) {
                stop()
            }
            cond_ := gt(decimal, resExponent_)
            if cond_ {
                resCoefficient_ := shr(sub(decimal, resExponent_), resCoefficient_)
                resExponent_ := 0
            }
            if iszero(cond_) {
                resExponent_ := sub(resExponent_, decimal)
                if gt(resExponent_, sub(shl(exponentSize, 1), 1)) {
                    revert(0, 0) // overflow error
                }
            }
            res := add(shl(exponentSize, resCoefficient_), resExponent_)
        }
    }

    /// @dev divides a `bigNumber1` by `bigNumber2`.
    /// e.g. res = bigNumber1 / bigNumber2 = [(coe1, exp1) / (coe2, exp2)] << decimal
    ///          = ((coe1<<precision_)/coe2, exp1+decimal-exp2-precision_)
    /// @param bigNumber1          BigNumber format with coefficient and exponent
    /// @param bigNumber2          BigNumber format with coefficient and exponent
    /// @param coefficientSize     max size of coefficient, same for both `bigNumber1` and `bigNumber2`
    /// @param exponentSize        max size of exponent, same for both `bigNumber1` and `bigNumber2`
    /// @param precision_          precision bit
    /// @param decimal             decimals in bits
    /// @return res                BigNumber format with coefficient and exponent
    function divBigNumber(
        uint256 bigNumber1,
        uint256 bigNumber2,
        uint256 coefficientSize,
        uint256 exponentSize,
        uint256 precision_,
        uint256 decimal
    ) internal pure returns (uint256 res) {
        uint256 coefficient1_;
        uint256 exponent1_;
        uint256 coefficient2_;
        uint256 exponent2_;
        uint256 resCoefficient_;
        uint256 overflowLen_;

        assembly {
            if eq(bigNumber1, 0) {
                stop()
            }

            if eq(bigNumber2, 0) {
                stop()
            }

            let expeontMask_ := sub(shl(exponentSize, 1), 1)
            coefficient1_ := shr(exponentSize, bigNumber1)
            exponent1_ := and(bigNumber1, expeontMask_)
            coefficient2_ := shr(exponentSize, bigNumber2)
            exponent2_ := and(bigNumber2, expeontMask_)

            resCoefficient_ := div(shl(precision_, coefficient1_), coefficient2_)
        }
        uint256 midLen_ = mostSignificantBit(resCoefficient_);
        assembly {
            if gt(midLen_, coefficientSize) {
                let delta_ := sub(midLen_, coefficientSize)
                resCoefficient_ := shr(delta_, resCoefficient_)
                overflowLen_ := delta_
            }
            if gt(add(exponent2_, precision_), add(overflowLen_, add(exponent1_, decimal))) {
                stop()
            }

            let resExponent_ := sub(sub(add(exponent1_, add(decimal, overflowLen_)), exponent2_), precision_)
            res := add(shl(exponentSize, resCoefficient_), resExponent_)
        }
    }
}
