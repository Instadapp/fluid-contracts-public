// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./immutableVariables.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";
import { DexLiteSlotsLink as DSL } from "../../../libraries/dexLiteSlotsLink.sol";
import { AddressCalcs as AC } from "../../../libraries/addressCalcs.sol";
import { FixedPointMathLib as FPM } from "solmate/src/utils/FixedPointMathLib.sol";

abstract contract AdminModuleHelpers is AdminModuleImmutableVariables {
    modifier _onlyDelegateCall() {
        if (address(this) == THIS_ADDRESS) revert OnlyDelegateCallAllowed();
        _;
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check)
    function _checkIsContract(address value_) internal view {
        if (value_.code.length == 0) {
            revert AddressNotAContract(value_);
        }
    }

    function _calculateNumeratorAndDenominatorPrecisions(uint256 decimals_) internal pure returns (uint256 numerator_, uint256 denominator_) {
        if (decimals_ > TOKENS_DECIMALS_PRECISION) {
            numerator_ = 1;
            denominator_ = 10 ** (decimals_ - TOKENS_DECIMALS_PRECISION);
        } else {
            numerator_ = 10 ** (TOKENS_DECIMALS_PRECISION - decimals_);
            denominator_ = 1;
        }
    }

    function _transferTokenIn(address token_, uint256 amount_) internal {
        if (amount_ == 0) return;

        if (token_ == NATIVE_TOKEN) {
            if (msg.value < amount_) revert InsufficientMsgValue(msg.value, amount_);
            if (msg.value > amount_) SafeTransfer.safeTransferNative(msg.sender, msg.value - amount_);
        } else SafeTransfer.safeTransferFrom(token_, msg.sender, address(this), amount_);
    }

    function _transferTokenOut(address token_, uint256 amount_, address to_) internal {
        if (amount_ == 0) return;

        if (token_ == NATIVE_TOKEN) SafeTransfer.safeTransferNative(to_, amount_);
        else SafeTransfer.safeTransfer(token_, to_, amount_);
    }

    function _calculateReservesOutsideRange(
        uint256 gp_,
        uint256 pa_,
        uint256 rx_,
        uint256 ry_
    ) internal pure returns (uint256 xa_, uint256 yb_) {
        // equations we have:
        // 1. x*y = k
        // 2. xa*ya = k
        // 3. xb*yb = k
        // 4. Pa = ya / xa = upperRange_ (known)
        // 5. Pb = yb / xb = lowerRange_ (known)
        // 6. x - xa = rx = real reserve of x (known)
        // 7. y - yb = ry = real reserve of y (known)
        // With solving we get:
        // ((Pa*Pb)^(1/2) - Pa)*xa^2 + (rx * (Pa*Pb)^(1/2) + ry)*xa + rx*ry = 0
        // yb = yb = xa * (Pa * Pb)^(1/2)

        // xa = (GP⋅rx + ry + (-rx⋅ry⋅4⋅(GP - Pa) + (GP⋅rx + ry)^2)^0.5) / (2Pa - 2GP)
        // multiply entire equation by 1e27 to remove the price decimals precision of 1e27
        // xa = (GP⋅rx + ry⋅1e27 + (rx⋅ry⋅4⋅(Pa - GP)⋅1e27 + (GP⋅rx + ry⋅1e27)^2)^0.5) / 2*(Pa - GP)
        // dividing the equation with 2*(Pa - GP). Pa is always > GP so answer will be positive.
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅4⋅(Pa - GP)⋅1e27) / 4*(Pa - GP)^2) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅1e27) / (Pa - GP)) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)

        // dividing in 3 parts for simplification:
        // part1 = (Pa - GP)
        // part2 = (GP⋅rx + ry⋅1e27) / (2*part1)
        // part3 = rx⋅ry
        // note: part1 will almost always be < 1e28 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e29
        unchecked {
            uint256 p1_ = pa_ - gp_;
            uint256 p2_ = ((gp_ * rx_) + (ry_ * PRICE_PRECISION)) / (2 * p1_);

            // removed <1e50 check becuase rx_ * ry_ will never be greater than 1e50
            // Directly used p3_ below instead of using a variable for it
            // uint256 p3_ = (rx_ * ry_ * PRICE_PRECISION) / p1_;

            // xa = part2 + (part3 + (part2 * part2))^(1/2)
            // yb = xa_ * gp_
            xa_ = p2_ + FPM.sqrt((((rx_ * ry_ * PRICE_PRECISION) / p1_) + (p2_ * p2_)));
            yb_ = (xa_ * gp_) / PRICE_PRECISION;
        }
    }

    function _calcShiftingDone(
        uint256 current_,
        uint256 old_,
        uint256 timePassed_,
        uint256 shiftDuration_
    ) internal pure returns (uint256) {
        unchecked {
            if (current_ > old_) {
                return (old_ + (((current_ - old_) * timePassed_) / shiftDuration_));
            } else {
                return (old_ - (((old_ - current_) * timePassed_) / shiftDuration_));
            }
        }
    }

    function _calcRangeShifting(
        uint256 upperRange_,
        uint256 lowerRange_,
        bytes8 dexId_
    ) internal view returns (uint256, uint256) {
        uint256 rangeShift_ = _rangeShift[dexId_];
        uint256 shiftDuration_ = (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIME_TO_SHIFT) & X20;
        uint256 startTimeStamp_ = (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIMESTAMP) & X33;

        uint256 timePassed_;
        unchecked {
            if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
                // shifting fully done
                // delete _rangeShift[dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables only updates from this function and _calcThresholdShifting.
                // _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE);
                return (upperRange_, lowerRange_);
            }
            timePassed_ = block.timestamp - startTimeStamp_;
        }
        return (
            _calcShiftingDone(
                upperRange_,
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_UPPER_RANGE_PERCENT) & X14,
                timePassed_,
                shiftDuration_
            ),
            _calcShiftingDone(
                lowerRange_,
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_LOWER_RANGE_PERCENT) & X14,
                timePassed_,
                shiftDuration_
            )
        );
    }

    function _calcThresholdShifting(
        uint256 upperThreshold_,
        uint256 lowerThreshold_,
        bytes8 dexId_
    ) internal view returns (uint256, uint256) {
        uint256 thresholdShift_ = _thresholdShift[dexId_];
        uint256 shiftDuration_ = (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIME_TO_SHIFT) & X20;
        uint256 startTimeStamp_ = (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIMESTAMP) & X33;

        uint256 timePassed_;
        unchecked {
            if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
                // shifting fully done
                // delete _thresholdShift[dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcRangeShifting.
                // _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE);
                return (upperThreshold_, lowerThreshold_);
            }
            timePassed_ = block.timestamp - startTimeStamp_;
        }
        return (
            _calcShiftingDone(
                upperThreshold_,
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_UPPER_THRESHOLD_PERCENT) & X7,
                timePassed_,
                shiftDuration_
            ),
            _calcShiftingDone(
                lowerThreshold_,
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_LOWER_THRESHOLD_PERCENT) & X7,
                timePassed_,
                shiftDuration_
            )
        );
    }

    function _calcCenterPrice(
        DexKey memory dexKey_,
        uint256 dexVariables_,
        bytes8 dexId_
    ) internal returns (uint256 newCenterPrice_) {
        uint256 oldCenterPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);
        uint256 centerPriceShift_ = _centerPriceShift[dexId_];
        uint256 startTimeStamp_ = (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIMESTAMP) & X33;

        uint256 fromTimeStamp_ = (centerPriceShift_ >>
            DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33;
        fromTimeStamp_ = fromTimeStamp_ > startTimeStamp_ ? fromTimeStamp_ : startTimeStamp_;

        newCenterPrice_ = ICenterPrice(
            AC.addressCalc(
                DEPLOYER_CONTRACT,
                ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) & X19)
            )
        ).centerPrice(dexKey_.token0, dexKey_.token1);

        unchecked {
            uint256 priceShift_ = (oldCenterPrice_ *
                ((centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT) & X20) *
                (block.timestamp - fromTimeStamp_)) /
                (((centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIME_TO_SHIFT) & X20) * SIX_DECIMALS);

            if (newCenterPrice_ > oldCenterPrice_) {
                // shift on positive side
                oldCenterPrice_ += priceShift_;
                if (newCenterPrice_ > oldCenterPrice_) {
                    newCenterPrice_ = oldCenterPrice_;
                } else {
                    // shifting fully done
                    // _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT);
                    // making active shift as 0 because shift is over
                    // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                    // _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE);
                }
            } else {
                oldCenterPrice_ = oldCenterPrice_ > priceShift_ ? oldCenterPrice_ - priceShift_ : 0;
                // In case of oldCenterPrice_ ending up 0, which could happen when a lot of time has passed (pool has no swaps for many days or weeks)
                // then below we get into the else logic which will fully conclude shifting and return newCenterPrice_
                // as it was fetched from the external center price source.
                // not ideal that this would ever happen unless the pool is not in use and all/most users have left leaving not enough liquidity to trade on
                if (newCenterPrice_ < oldCenterPrice_) {
                    newCenterPrice_ = oldCenterPrice_;
                } else {
                    // shifting fully done
                    // _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT);
                    // making active shift as 0 because shift is over
                    // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                    // _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE);
                }
            }
        }
    }

    function _getPrice(
        DexKey calldata dexKey_,
        uint256 dexVariables_,
        bytes8 dexId_,
        uint256 token0Supply_,
        uint256 token1Supply_
    ) internal returns (uint256 price_) {
        uint256 centerPrice_;
        // Fetch center price
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE) & X1) == 0) {
            // centerPrice_ => center price nonce
            centerPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) & X19;
            if (centerPrice_ == 0) {
                centerPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
                centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
            } else {
                // center price should be fetched from external source. For exmaple, in case of wstETH <> ETH pool,
                // we would want the center price to be pegged to wstETH exchange rate into ETH
                centerPrice_ = 
                    ICenterPrice(AC.addressCalc(DEPLOYER_CONTRACT, centerPrice_)).centerPrice(dexKey_.token0, dexKey_.token1);
            }
        } else {
            // an active centerPrice_ shift is going on
            centerPrice_ = _calcCenterPrice(dexKey_, dexVariables_, dexId_);
        }

        uint256 upperRangePercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) & X14;
        uint256 lowerRangePercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) & X14;
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) & X1) == 1) {
            // an active range shift is going on
            (upperRangePercent_, lowerRangePercent_) = _calcRangeShifting(upperRangePercent_, lowerRangePercent_, dexId_);
        }

        uint256 upperRangePrice_;
        uint256 lowerRangePrice_;
        unchecked {
            // 1% = 1e2, 100% = 1e4
            upperRangePrice_ = (centerPrice_ * FOUR_DECIMALS) / (FOUR_DECIMALS - upperRangePercent_);
            // 1% = 1e2, 100% = 1e4
            lowerRangePrice_ = (centerPrice_ * (FOUR_DECIMALS - lowerRangePercent_)) / FOUR_DECIMALS;
        }

        // Rebalance center price if rebalancing is on
        // temp_ => rebalancingStatus_
        uint256 temp_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) & X2;
        uint256 temp2_;
        if (temp_ > 1) {
            unchecked {
                // temp2_ => centerPriceShift_
                if (temp_ == 2) {
                    temp2_ = _centerPriceShift[dexId_];
                    uint256 shiftingTime_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) & X24;
                    uint256 timeElapsed_ = block.timestamp - ((temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33);
                    // price shifting towards upper range
                    if (timeElapsed_ < shiftingTime_) {
                        centerPrice_ = centerPrice_ + (((upperRangePrice_ - centerPrice_) * timeElapsed_) / shiftingTime_);
                    } else {
                        // 100% price shifted
                        centerPrice_ = upperRangePrice_;
                    }
                } else if (temp_ == 3) {
                    temp2_ = _centerPriceShift[dexId_];
                    uint256 shiftingTime_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) & X24;
                    uint256 timeElapsed_ = block.timestamp - ((temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33);
                    // price shifting towards lower range
                    if (timeElapsed_ < shiftingTime_) {
                        centerPrice_ = centerPrice_ - (((centerPrice_ - lowerRangePrice_) * timeElapsed_) / shiftingTime_);
                    } else {
                        // 100% price shifted
                        centerPrice_ = lowerRangePrice_;
                    }
                }

                // If rebalancing actually happened then make sure price is within min and max bounds, and update range prices
                if (temp2_ > 0) {
                    // Make sure center price is within min and max bounds
                    // temp_ => max center price
                    temp_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE) & X28;
                    temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
                    if (centerPrice_ > temp_) {
                        // if center price is greater than max center price
                        centerPrice_ = temp_;
                    } else {
                        // check if center price is less than min center price
                        // temp_ => min center price
                        temp_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE) & X28;
                        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
                        if (centerPrice_ < temp_) centerPrice_ = temp_;
                    }

                    // Update range prices as center price moved
                    upperRangePrice_ = (centerPrice_ * FOUR_DECIMALS) / (FOUR_DECIMALS - upperRangePercent_);
                    lowerRangePrice_ = (centerPrice_ * (FOUR_DECIMALS - lowerRangePercent_)) / FOUR_DECIMALS;
                }
            }  
        }

        // temp_ => geometricMeanPrice_
        unchecked {         
            if (upperRangePrice_ < 1e38) {
                // 1e38 * 1e38 = 1e76 which is less than max uint limit
                temp_ = FPM.sqrt(upperRangePrice_ * lowerRangePrice_);
            } else {
                // upperRange_ price is pretty large hence lowerRange_ will also be pretty large
                temp_ = FPM.sqrt((upperRangePrice_ / 1e18) * (lowerRangePrice_ / 1e18)) * 1e18;
            }
        }

        uint256 token0ImaginaryReserves_;
        uint256 token1ImaginaryReserves_;

        if (temp_ < 1e27) {
            (token0ImaginaryReserves_, token1ImaginaryReserves_) = 
                _calculateReservesOutsideRange(temp_, upperRangePrice_, token0Supply_, token1Supply_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            unchecked {
                (token1ImaginaryReserves_, token0ImaginaryReserves_) = _calculateReservesOutsideRange(
                    (1e54 / temp_),
                    (1e54 / lowerRangePrice_),
                    token1Supply_,
                    token0Supply_
                );
            }
        }

        unchecked {
            token0ImaginaryReserves_ += token0Supply_;
            token1ImaginaryReserves_ += token1Supply_;
        }

        price_ = token1ImaginaryReserves_ * PRICE_PRECISION / token0ImaginaryReserves_;
    }
}
