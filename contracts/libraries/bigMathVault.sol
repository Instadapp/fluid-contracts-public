// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { BigMathMinified } from "./bigMathMinified.sol";

/// @title Extended version of BigMathMinified. Implements functions for normal operators (*, /, etc) modified to interact with big numbers.
/// @notice this is an optimized version mainly created by taking Fluid vault's codebase into consideration so it's use is limited for other cases.
// 
// @dev IMPORTANT: for any change here, make sure to uncomment and run the fuzz tests in bigMathVault.t.sol
library BigMathVault {
    uint private constant COEFFICIENT_SIZE_DEBT_FACTOR = 35;
    uint private constant EXPONENT_SIZE_DEBT_FACTOR = 15;
    uint private constant COEFFICIENT_MAX_DEBT_FACTOR = (1 << COEFFICIENT_SIZE_DEBT_FACTOR) - 1;
    uint private constant EXPONENT_MAX_DEBT_FACTOR = (1 << EXPONENT_SIZE_DEBT_FACTOR) - 1;
    uint private constant DECIMALS_DEBT_FACTOR = 16384;
    uint internal constant MAX_MASK_DEBT_FACTOR = (1 << (COEFFICIENT_SIZE_DEBT_FACTOR + EXPONENT_SIZE_DEBT_FACTOR)) - 1;

    // Having precision as 2**64 on vault
    uint internal constant PRECISION = 64;
    uint internal constant TWO_POWER_64 = 1 << PRECISION;
    // Max bit for 35 bits * 35 bits number will be 70
    // why do we use 69 then here instead of 70
    uint internal constant TWO_POWER_69_MINUS_1 = (1 << 69) - 1;

    uint private constant COEFFICIENT_PLUS_PRECISION = COEFFICIENT_SIZE_DEBT_FACTOR + PRECISION; // 99
    uint private constant COEFFICIENT_PLUS_PRECISION_MINUS_1 = COEFFICIENT_PLUS_PRECISION - 1; // 98
    uint private constant TWO_POWER_COEFFICIENT_PLUS_PRECISION_MINUS_1 = (1 << COEFFICIENT_PLUS_PRECISION_MINUS_1) - 1; // (1 << 98) - 1;
    uint private constant TWO_POWER_COEFFICIENT_PLUS_PRECISION_MINUS_1_MINUS_1 =
        (1 << (COEFFICIENT_PLUS_PRECISION_MINUS_1 - 1)) - 1; // (1 << 97) - 1;

    /// @dev multiplies a `normal` number with a `bigNumber1` and then divides by `bigNumber2`.
    /// @dev For vault's use case MUST always:
    ///      - bigNumbers have exponent size 15 bits
    ///      - bigNumbers have coefficient size 35 bits and have 35th bit always 1 (when exponent > 0 BigMath numbers have max precision)
    ///        so coefficients must always be in range 17179869184 <= coefficient <= 34359738367.
    ///      - bigNumber1 (debt factor) always have exponent >= 1 & <= 16384
    ///      - bigNumber2 (connection factor) always have exponent >= 1 & <= 32767 (15 bits)
    ///      - bigNumber2 always >= bigNumber1 (connection factor can never be < base branch debt factor)
    ///      - as a result of previous points, numbers must never be 0
    ///      - normal is positionRawDebt and is always within 10000 and type(int128).max
    /// @return normal * bigNumber1 / bigNumber2
    function mulDivNormal(uint256 normal, uint256 bigNumber1, uint256 bigNumber2) internal pure returns (uint256) {
        unchecked {
            // exponent2_ - exponent1_
            uint netExponent_ = (bigNumber2 & EXPONENT_MAX_DEBT_FACTOR) - (bigNumber1 & EXPONENT_MAX_DEBT_FACTOR);
            if (netExponent_ < 129) {
                // (normal * coefficient1_) / (coefficient2_ << netExponent_);
                return ((normal * (bigNumber1 >> EXPONENT_SIZE_DEBT_FACTOR)) /
                    ((bigNumber2 >> EXPONENT_SIZE_DEBT_FACTOR) << netExponent_));
            }
            // else:
            // biggest possible nominator: type(int128).max * 35bits max      =  5846006549323611672814739330865132078589370433536
            // smallest possible denominator: 17179869184 << 129 (= 1 << 163) = 11692013098647223345629478661730264157247460343808
            // -> can only ever be 0
            return 0;
        }
    }

    /// @dev multiplies a `bigNumber` with normal `number1` and then divides by `TWO_POWER_64`.
    /// @dev For vault's use case (calculating new branch debt factor after liquidation):
    ///      - number1 is debtFactor, intialized as TWO_POWER_64 and reduced from there, hence it's always <= TWO_POWER_64 and always > 0.
    ///      - bigNumber is branch debt factor, which starts as ((X35 << 15) | (1 << 14)) and reduces from there.
    ///      - bigNumber must have have exponent size 15 bits and be >= 1 & <= 16384
    ///      - bigNumber must have coefficient size 35 bits and have 35th bit always 1 (when exponent > 0 BigMath numbers have max precision)
    ///        so coefficients must always be in range 17179869184 <= coefficient <= 34359738367.
    /// @param bigNumber Coefficient | Exponent.
    /// @param number1 normal number.
    /// @return result bigNumber * number1 / TWO_POWER_64.
    function mulDivBigNumber(uint256 bigNumber, uint256 number1) internal pure returns (uint256 result) {
        // using unchecked as we are only at 1 place in Vault and it won't overflow there.
        unchecked {
            uint256 _resultNumerator = (bigNumber >> EXPONENT_SIZE_DEBT_FACTOR) * number1; // bigNumber coefficient * normal number
            // 99% chances are that most sig bit should be 64 + 35 - 1 or 64 + 35 - 2
            // diff = mostSigBit. Can only ever be >= 35 and <= 98
            uint256 diff = (_resultNumerator > TWO_POWER_COEFFICIENT_PLUS_PRECISION_MINUS_1)
                ? COEFFICIENT_PLUS_PRECISION
                : (_resultNumerator > TWO_POWER_COEFFICIENT_PLUS_PRECISION_MINUS_1_MINUS_1)
                    ? COEFFICIENT_PLUS_PRECISION_MINUS_1
                    : BigMathMinified.mostSignificantBit(_resultNumerator);

            // diff = difference in bits to make the _resultNumerator 35 bits again
            diff = diff - COEFFICIENT_SIZE_DEBT_FACTOR;
            _resultNumerator = _resultNumerator >> diff;
            // starting exponent is 16384, so exponent should never get 0 here
            result = (bigNumber & EXPONENT_MAX_DEBT_FACTOR) + diff;
            if (result > PRECISION) {
                result = (_resultNumerator << EXPONENT_SIZE_DEBT_FACTOR) + result - PRECISION; // divides by TWO_POWER_64 by reducing exponent by 64
            } else {
                // if number1 is small, e.g. 1e4 and bigNumber is also small e.g. coefficient = 17179869184 & exponent is at 50
                // then: resultNumerator = 171798691840000, diff most significant bit = 48, ending up with diff = 13
                // for exponent in result we end up doing: 50 + 13 - 64 -> underflowing exponent.
                // this should never happen anyway, but if it does better to revert than to continue with unknown effects.
                revert(); // debt factor should never become a BigNumber with exponent <= 0
            }
        }
    }

    /// @dev multiplies a `bigNumber1` with another `bigNumber2`.
    /// @dev For vault's use case (calculating connection factor of merged branches userTickDebtFactor * connectionDebtFactor *... connectionDebtFactor):
    ///      - bigNumbers must have have exponent size 15 bits and be >= 1 & <= 32767
    ///      - bigNumber must have coefficient size 35 bits and have 35th bit always 1 (when exponent > 0 BigMath numbers have max precision)
    ///        so coefficients must always be in range 17179869184 <= coefficient <= 34359738367.
    /// @dev sum of exponents from `bigNumber1` `bigNumber2` should be > 16384.
    /// e.g. res = bigNumber1 * bigNumber2 = [(coe1, exp1) * (coe2, exp2)] >> decimal
    ///          = (coe1*coe2>>overflow, exp1+exp2+overflow-decimal)
    /// @param bigNumber1          BigNumber format with coefficient and exponent.
    /// @param bigNumber2          BigNumber format with coefficient and exponent.
    /// @return                    BigNumber format with coefficient and exponent
    function mulBigNumber(uint256 bigNumber1, uint256 bigNumber2) internal pure returns (uint256) {
        unchecked {
            // coefficient1_ * coefficient2_
            uint resCoefficient_ = (bigNumber1 >> EXPONENT_SIZE_DEBT_FACTOR) *
                (bigNumber2 >> EXPONENT_SIZE_DEBT_FACTOR);
            // res coefficient at min can be 17179869184 * 17179869184 =  295147905179352825856 (= 1 << 68; 69th bit as 1)
            // res coefficient at max can be 34359738367 * 34359738367 = 1180591620648691826689 (X35 * X35 fits in 70 bits)
            uint overflowLen_ = resCoefficient_ > TWO_POWER_69_MINUS_1
                ? COEFFICIENT_SIZE_DEBT_FACTOR
                : COEFFICIENT_SIZE_DEBT_FACTOR - 1;
            // overflowLen_ is either 34 or 35
            resCoefficient_ = resCoefficient_ >> overflowLen_;

            // bigNumber2 is connection factor
            // exponent1_ + exponent2_ + overflowLen_ - decimals
            uint resExponent_ = ((bigNumber1 & EXPONENT_MAX_DEBT_FACTOR) +
                (bigNumber2 & EXPONENT_MAX_DEBT_FACTOR) +
                overflowLen_);
            if (resExponent_ < DECIMALS_DEBT_FACTOR) {
                // for this ever to happen, the debt factors used to calculate connection factors would have to be at extremely
                // unrealistic values. Like e.g.
                // branch3 (debt factor X35 << 15 | 16383) got merged into branch2 (debt factor X35 << 15 | 8190)
                // -> connection factor (divBigNumber): ((coe1<<precision_)/coe2>>overflowLen, exp1+decimal+overflowLen-exp2-precision_) so:
                // coefficient: (X35<<64)/X35 >> 30 = 17179869184
                // exponent: 8190+16384+30-16383-64 = 8157.
                // result: 17179869184 << 15 | 8157
                // and then branch2 into branch1 (debt factor X35 << 15 | 22). -> connection factor:
                // coefficient: (X35<<64)/X35 >> 30 = 17179869184
                // exponent: 22+16384+30-8190-64 = 8182.
                // result: 17179869184 << 15 | 8182
                // connection factors sum up (mulBigNumber): (coe1*coe2>>overflow, exp1+exp2+overflow-decimal)
                // exponent: 8182+8157+35-16384=16374-16384=-10. underflow.
                // this should never happen anyway, but if it does better to revert than to continue with unknown effects.
                revert();
            }
            resExponent_ = resExponent_ - DECIMALS_DEBT_FACTOR;

            if (resExponent_ > EXPONENT_MAX_DEBT_FACTOR) {
                // if resExponent_ is not within limits that means user's got ~100% (something like 99.999999999999...)
                // this situation will probably never happen and this basically means user's position is ~100% liquidated
                return MAX_MASK_DEBT_FACTOR;
            }

            return ((resCoefficient_ << EXPONENT_SIZE_DEBT_FACTOR) | resExponent_);
        }
    }

    /// @dev divides a `bigNumber1` by `bigNumber2`.
    /// @dev For vault's use case (calculating connectionFactor_ = baseBranchDebtFactor / currentBranchDebtFactor) bigNumbers MUST always:
    ///      - have exponent size 15 bits and be >= 1 & <= 16384
    ///      - have coefficient size 35 bits and have 35th bit always 1 (when exponent > 0 BigMath numbers have max precision)
    ///        so coefficients must always be in range 17179869184 <= coefficient <= 34359738367.
    ///      - as a result of previous points, numbers must never be 0
    /// e.g. res = bigNumber1 / bigNumber2 = [(coe1, exp1) / (coe2, exp2)] << decimal
    ///          = ((coe1<<precision_)/coe2, exp1+decimal-exp2-precision_)
    /// @param bigNumber1          BigNumber format with coefficient and exponent
    /// @param bigNumber2          BigNumber format with coefficient and exponent
    /// @return                    BigNumber format with coefficient and exponent
    /// Returned connection factor can only ever be >= baseBranchDebtFactor (c = x*100/y with both x,y > 0 & x,y <= 100: c can only ever be >= x)
    function divBigNumber(uint256 bigNumber1, uint256 bigNumber2) internal pure returns (uint256) {
        unchecked {
            // (coefficient1_ << PRECISION) / coefficient2_
            uint256 resCoefficient_ = ((bigNumber1 >> EXPONENT_SIZE_DEBT_FACTOR) << PRECISION) /
                (bigNumber2 >> EXPONENT_SIZE_DEBT_FACTOR);
            // nominator at min 17179869184 << 64 = 316912650057057350374175801344. at max 34359738367 << 64 = 633825300095667956674642051072.
            // so min value resCoefficient_ 9223372037123211264 (64 bits) vs max 36893488146345361408 (fits in 65 bits)

            // mostSigBit will be PRECISION + 1 or PRECISION
            uint256 overflowLen_ = ((resCoefficient_ >> PRECISION) == 1) ? (PRECISION + 1) : PRECISION;
            // Overflow will be PRECISION - COEFFICIENT_SIZE_DEBT_FACTOR or (PRECISION + 1) - COEFFICIENT_SIZE_DEBT_FACTOR
            // Meaning 64 - 35 = 29 or 65 - 35 = 30
            overflowLen_ = overflowLen_ - COEFFICIENT_SIZE_DEBT_FACTOR;
            resCoefficient_ = resCoefficient_ >> overflowLen_;

            // exponent1_ will always be less than or equal to 16384
            // exponent2_ will always be less than or equal to 16384
            // Even if exponent2_ is 0 (not possible) & resExponent_ = DECIMALS_DEBT_FACTOR then also resExponent_ will be less than max limit, so no overflow
            // result exponent = (exponent1_ + DECIMALS_DEBT_FACTOR + overflowLen_) - (exponent2_ + PRECISION);
            uint256 resExponent_ = ((bigNumber1 & EXPONENT_MAX_DEBT_FACTOR) + // exponent1_
                DECIMALS_DEBT_FACTOR + // DECIMALS_DEBT_FACTOR is 100% as it is percentage value
                overflowLen_); // addition part resExponent_ here min 16414, max 32798
            // reuse overFlowLen_ variable for subtraction sum of exponent
            overflowLen_ = (bigNumber2 & EXPONENT_MAX_DEBT_FACTOR) + PRECISION; // subtraction part overflowLen_ here: min 65, max 16448
            if (resExponent_ > overflowLen_) {
                resExponent_ = resExponent_ - overflowLen_;

                return ((resCoefficient_ << EXPONENT_SIZE_DEBT_FACTOR) | resExponent_);
            }

            // Can happen if bigNumber1 exponent is < 35 (35+16384+29 = 16448) and bigNumber2 exponent is e.g. max 16384.
            // this would mean a branch with a normal big debt factor (bigNumber2) is merged into a base branch with an extremely small
            // debt factor (bigNumber1).
            // this should never happen anyway, but if it does better to revert than to continue with unknown effects.
            revert(); // connection factor should never become a BigNumber with exponent <= 0
        }
    }
}
