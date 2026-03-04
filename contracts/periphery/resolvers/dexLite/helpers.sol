// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./immutableVariables.sol";
import { DexLiteSlotsLink as DSL } from "../../../libraries/dexLiteSlotsLink.sol";
import { AddressCalcs as AC } from "../../../libraries/addressCalcs.sol";
import { FixedPointMathLib as FPM } from "solmate/src/utils/FixedPointMathLib.sol";

abstract contract Helpers is ImmutableVariables {
    function _readDexKeyAtIndex(uint256 index) internal view returns (DexKey memory) {
        bytes32 baseSlot = keccak256(abi.encode(DSL.DEX_LITE_DEXES_LIST_SLOT));

        // Each DexKey takes 3 storage slots (token0, token1, salt)
        address token0 = address(uint160(uint256(DEX_LITE.readFromStorage(bytes32(uint256(baseSlot) + index * 3)))));
        address token1 = address(
            uint160(uint256(DEX_LITE.readFromStorage(bytes32(uint256(baseSlot) + index * 3 + 1))))
        );
        bytes32 salt = DEX_LITE.readFromStorage(bytes32(uint256(baseSlot) + index * 3 + 2));

        return DexKey(token0, token1, salt);
    }

    function _calculateDexId(DexKey memory dexKey_) internal pure returns (bytes8) {
        return bytes8(keccak256(abi.encode(dexKey_)));
    }

    function _calculatePoolStateSlot(bytes8 dexId, uint256 baseSlot) internal pure returns (bytes32) {
        return keccak256(abi.encode(bytes32(dexId), baseSlot));
    }

    function _readPoolState(
        bytes8 dexId_
    )
        internal
        view
        returns (uint256 dexVariables_, uint256 centerPriceShift_, uint256 rangeShift_, uint256 thresholdShift_)
    {
        dexVariables_ = uint256(
            DEX_LITE.readFromStorage(_calculatePoolStateSlot(dexId_, DSL.DEX_LITE_DEX_VARIABLES_SLOT))
        );
        centerPriceShift_ = uint256(
            DEX_LITE.readFromStorage(_calculatePoolStateSlot(dexId_, DSL.DEX_LITE_CENTER_PRICE_SHIFT_SLOT))
        );
        rangeShift_ = uint256(DEX_LITE.readFromStorage(_calculatePoolStateSlot(dexId_, DSL.DEX_LITE_RANGE_SHIFT_SLOT)));
        thresholdShift_ = uint256(
            DEX_LITE.readFromStorage(_calculatePoolStateSlot(dexId_, DSL.DEX_LITE_THRESHOLD_SHIFT_SLOT))
        );
    }

    function _unpackDexVariables(uint256 dexVariables_) internal view returns (DexVariables memory) {
        bool isCenterPriceShiftActive_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE) &
            X1 ==
            1;

        uint256 centerPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);

        address centerPriceContractAddress_ = AC.addressCalc(
            DEPLOYER_CONTRACT,
            (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) & X19
        );
        bool isRangePercentShiftActive_ = (dexVariables_ >>
            DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) &
            X1 ==
            1;
        bool isThresholdPercentShiftActive_ = (dexVariables_ >>
            DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE) &
            X1 ==
            1;

        return
            DexVariables(
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) & X13,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) & X7,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) & X2,
                isCenterPriceShiftActive_,
                centerPrice_,
                centerPriceContractAddress_,
                isRangePercentShiftActive_,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) & X14,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) & X14,
                isThresholdPercentShiftActive_,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) & X7,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT) & X7,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60,
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60
            );
    }

    function _unpackCenterPriceShift(uint256 centerPriceShift_) internal pure returns (CenterPriceShift memory) {
        uint256 maxCenterPrice_ = (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE) & X28;
        maxCenterPrice_ = (maxCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (maxCenterPrice_ & DEFAULT_EXPONENT_MASK);

        uint256 minCenterPrice_ = (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE) & X28;
        minCenterPrice_ = (minCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (minCenterPrice_ & DEFAULT_EXPONENT_MASK);

        return
            CenterPriceShift(
                (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33,
                (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) & X24,
                maxCenterPrice_,
                minCenterPrice_,
                (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT) & X20,
                (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIME_TO_SHIFT) & X20,
                (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIMESTAMP) & X33
            );
    }

    function _unpackRangeShift(uint256 rangeShift_) internal pure returns (RangeShift memory) {
        return
            RangeShift(
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_UPPER_RANGE_PERCENT) & X14,
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_LOWER_RANGE_PERCENT) & X14,
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIME_TO_SHIFT) & X20,
                (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIMESTAMP) & X33
            );
    }

    function _unpackThresholdShift(uint256 thresholdShift_) internal pure returns (ThresholdShift memory) {
        return
            ThresholdShift(
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_UPPER_THRESHOLD_PERCENT) & X7,
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_LOWER_THRESHOLD_PERCENT) & X7,
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIME_TO_SHIFT) & X20,
                (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIMESTAMP) & X33
            );
    }

    /// @dev getting reserves outside range.
    /// @param gp_ is geometric mean pricing of upper percent & lower percent
    /// @param pa_ price of upper range or lower range
    /// @param rx_ real reserves of token0 or token1
    /// @param ry_ whatever is rx_ the other will be ry_
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
        uint256 rangeShift_
    ) internal returns (uint256, uint256) {
        // rangeShift_ = _rangeShift[dexId_];
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
        uint256 thresholdShift_
    ) internal returns (uint256, uint256) {
        // uint256 thresholdShift_ = _thresholdShift[dexId_];
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
        uint256 centerPriceShift_
    ) internal returns (uint256 newCenterPrice_) {
        uint256 oldCenterPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);
        // uint256 centerPriceShift_ = _centerPriceShift[dexId_];
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

    /// @notice Calculates and returns the current prices and exchange prices for the pool
    /// @param dexVariables_ The first set of DEX variables containing various pool parameters
    function _getPricesAndReserves(
        DexKey memory dexKey_,
        uint256 dexVariables_,
        uint256 centerPriceShift_,
        uint256 rangeShift_,
        uint256 thresholdShift_,
        uint256 token0Supply_,
        uint256 token1Supply_
    ) internal returns (Prices memory prices_, Reserves memory reserves_) {
        // Fetch center price
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE) & X1) == 0) {
            // prices_.centerPrice => center price nonce
            prices_.centerPrice =
                (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) &
                X19;
            if (prices_.centerPrice == 0) {
                prices_.centerPrice = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
                prices_.centerPrice =
                    (prices_.centerPrice >> DEFAULT_EXPONENT_SIZE) <<
                    (prices_.centerPrice & DEFAULT_EXPONENT_MASK);
            } else {
                // center price should be fetched from external source. For exmaple, in case of wstETH <> ETH pool,
                // we would want the center price to be pegged to wstETH exchange rate into ETH
                prices_.centerPrice = ICenterPrice(AC.addressCalc(DEPLOYER_CONTRACT, prices_.centerPrice))
                    .centerPrice(dexKey_.token0, dexKey_.token1);
            }
        } else {
            // an active prices_.centerPrice shift is going on
            prices_.centerPrice = _calcCenterPrice(dexKey_, dexVariables_, centerPriceShift_);
        }

        uint256 upperRangePercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) & X14;
        uint256 lowerRangePercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) & X14;
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) & X1) == 1) {
            // an active range shift is going on
            (upperRangePercent_, lowerRangePercent_) = _calcRangeShifting(
                upperRangePercent_,
                lowerRangePercent_,
                rangeShift_
            );
        }

        unchecked {
            // 1% = 1e2, 100% = 1e4
            prices_.upperRangePrice = (prices_.centerPrice * FOUR_DECIMALS) / (FOUR_DECIMALS - upperRangePercent_);
            // 1% = 1e2, 100% = 1e4
            prices_.lowerRangePrice = (prices_.centerPrice * (FOUR_DECIMALS - lowerRangePercent_)) / FOUR_DECIMALS;
        }

        // Rebalance center price if rebalancing is on
        // temp_ => rebalancingStatus_
        uint256 temp_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) & X2;
        uint256 temp2_;
        if (temp_ > 1) {
            unchecked {
                // temp2_ => centerPriceShift_
                if (temp_ == 2) {
                    temp2_ = centerPriceShift_;
                    uint256 shiftingTime_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) & X24;
                    uint256 timeElapsed_ = block.timestamp -
                        ((temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33);
                    // price shifting towards upper range
                    if (timeElapsed_ < shiftingTime_) {
                        prices_.centerPrice =
                            prices_.centerPrice +
                            (((prices_.upperRangePrice - prices_.centerPrice) * timeElapsed_) / shiftingTime_);
                    } else {
                        // 100% price shifted
                        prices_.centerPrice = prices_.upperRangePrice;
                    }
                } else if (temp_ == 3) {
                    temp2_ = centerPriceShift_;
                    uint256 shiftingTime_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) & X24;
                    uint256 timeElapsed_ = block.timestamp -
                        ((temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33);
                    // price shifting towards lower range
                    if (timeElapsed_ < shiftingTime_) {
                        prices_.centerPrice =
                            prices_.centerPrice -
                            (((prices_.centerPrice - prices_.lowerRangePrice) * timeElapsed_) / shiftingTime_);
                    } else {
                        // 100% price shifted
                        prices_.centerPrice = prices_.lowerRangePrice;
                    }
                }

                // If rebalancing actually happened then make sure price is within min and max bounds, and update range prices
                if (temp2_ > 0) {
                    // Make sure center price is within min and max bounds
                    // temp_ => max center price
                    temp_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE) & X28;
                    temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
                    if (prices_.centerPrice > temp_) {
                        // if center price is greater than max center price
                        prices_.centerPrice = temp_;
                    } else {
                        // check if center price is less than min center price
                        // temp_ => min center price
                        temp_ = (temp2_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE) & X28;
                        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
                        if (prices_.centerPrice < temp_) prices_.centerPrice = temp_;
                    }

                    // Update range prices as center price moved
                    prices_.upperRangePrice =
                        (prices_.centerPrice * FOUR_DECIMALS) /
                        (FOUR_DECIMALS - upperRangePercent_);
                    prices_.lowerRangePrice =
                        (prices_.centerPrice * (FOUR_DECIMALS - lowerRangePercent_)) /
                        FOUR_DECIMALS;
                }
            }
        }

        // Calculate threshold prices
        uint256 upperThresholdPercent_ = (dexVariables_ >>
            DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) & X7;
        uint256 lowerThresholdPercent_ = (dexVariables_ >>
            DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT) & X7;
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE) & X1) == 1) {
            // if active shift is going on for threshold then calculate threshold real time
            (upperThresholdPercent_, lowerThresholdPercent_) = _calcThresholdShifting(
                upperThresholdPercent_,
                lowerThresholdPercent_,
                thresholdShift_
            );
        }

        unchecked {
            prices_.upperThresholdPrice = (prices_.centerPrice +
                ((prices_.upperRangePrice - prices_.centerPrice) * (TWO_DECIMALS - upperThresholdPercent_)) /
                TWO_DECIMALS);
            prices_.lowerThresholdPrice = (prices_.centerPrice -
                ((prices_.centerPrice - prices_.lowerRangePrice) * (TWO_DECIMALS - lowerThresholdPercent_)) /
                TWO_DECIMALS);
        }

        // temp_ => geometricMeanPrice_
        unchecked {
            if (prices_.upperRangePrice < 1e38) {
                // 1e38 * 1e38 = 1e76 which is less than max uint limit
                temp_ = FPM.sqrt(prices_.upperRangePrice * prices_.lowerRangePrice);
            } else {
                // upperRange_ price is pretty large hence lowerRange_ will also be pretty large
                temp_ =
                    FPM.sqrt((prices_.upperRangePrice / 1e18) * (prices_.lowerRangePrice / 1e18)) *
                    1e18;
            }
        }

        if (temp_ < 1e27) {
            (reserves_.token0ImaginaryReserves, reserves_.token1ImaginaryReserves) = _calculateReservesOutsideRange(
                temp_,
                prices_.upperRangePrice,
                token0Supply_,
                token1Supply_
            );
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            unchecked {
                (reserves_.token1ImaginaryReserves, reserves_.token0ImaginaryReserves) = _calculateReservesOutsideRange(
                    (1e54 / temp_),
                    (1e54 / prices_.lowerRangePrice),
                    token1Supply_,
                    token0Supply_
                );
            }
        }

        unchecked {
            reserves_.token0ImaginaryReserves += token0Supply_;
            reserves_.token1ImaginaryReserves += token1Supply_;
            reserves_.token0RealReserves = token0Supply_;
            reserves_.token1RealReserves = token1Supply_;
        }

        prices_.poolPrice = (reserves_.token1ImaginaryReserves * PRICE_PRECISION) / reserves_.token0ImaginaryReserves;
    }
}
