// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import "./errors.sol";
import { DexLiteSlotsLink as DSL } from "../../../libraries/dexLiteSlotsLink.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { ReentrancyLock } from "../../../libraries/reentrancyLock.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";

abstract contract Helpers is CommonImport {
    using BigMathMinified for uint256;

    modifier _reentrancyLock() {
        ReentrancyLock.lock();
        _;
        ReentrancyLock.unlock();
    }

    function _getExtraDataSlot() internal view returns (address extraDataAddress_) {
        assembly {
            extraDataAddress_ := sload(EXTRA_DATA_SLOT)
        }
    }

    function _getGovernanceAddr() internal view returns (address governance_) {
        governance_ = address(uint160(LIQUIDITY.readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }

    function _callExtraDataSlot(bytes memory data_) internal {
        address extraDataAddress_ = _getExtraDataSlot();
        if (extraDataAddress_ == address(0)) {
            revert ZeroAddress();
        }
        _spell(extraDataAddress_, data_);
    }

    function _tenPow(uint256 power_) internal pure returns (uint256) {
        // keeping the most used powers at the top for better gas optimization
        if (power_ == 3) {
            return 1_000; // used for 6 or 12 decimals (USDC, USDT)
        }
        if (power_ == 9) {
            return 1_000_000_000; // used for 18 decimals (ETH, and many more)
        }
        if (power_ == 1) {
            return 10; // used for 1 decimals (WBTC and more)
        }

        if (power_ == 0) {
            return 1;
        }
        if (power_ == 2) {
            return 100;
        }
        if (power_ == 4) {
            return 10_000;
        }
        if (power_ == 5) {
            return 100_000;
        }
        if (power_ == 6) {
            return 1_000_000;
        }
        if (power_ == 7) {
            return 10_000_000;
        }
        if (power_ == 8) {
            return 100_000_000;
        }

        // We will only need powers from 0 to 9 as token decimals can only be 6 to 18
        revert InvalidPower(power_);
    }

    /// @dev getting reserves outside range.
    /// @param gp_ is geometric mean pricing of upper percent & lower percent
    /// @param pa_ price of upper range or lower range
    /// @param rx_ real reserves of token0 or token1
    /// @param ry_ whatever is rx_ the other will be ry_
    function _calculateReservesOutsideRange(uint256 gp_, uint256 pa_, uint256 rx_, uint256 ry_) internal pure returns (uint256 xa_, uint256 yb_) {
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
            xa_ = p2_ + FixedPointMathLib.sqrt((((rx_ * ry_ * PRICE_PRECISION) / p1_) + (p2_ * p2_)));
            yb_ = (xa_ * gp_) / PRICE_PRECISION;
        }
    }
    

    /// @dev This function calculates the new value of a parameter after a shifting process
    /// @param current_ The current value is the final value where the shift ends
    /// @param old_ The old value from where shifting started
    /// @param timePassed_ The time passed since shifting started
    /// @param shiftDuration_ The total duration of the shift when old_ reaches current_
    /// @return The new value of the parameter after the shift
    function _calcShiftingDone(uint256 current_, uint256 old_, uint256 timePassed_, uint256 shiftDuration_) internal pure returns (uint256) {
        unchecked {
            if (current_ > old_) {
                return (old_ + (((current_ - old_) * timePassed_) / shiftDuration_));
            } else {
                return (old_ - (((old_ - current_) * timePassed_) / shiftDuration_));
            }
        }
    }

    /// @dev Calculates the new upper and lower range values during an active range shift
    /// @param upperRange_ The target upper range value
    /// @param lowerRange_ The target lower range value
    /// @notice This function handles the gradual shifting of range values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcRangeShifting(
        uint256 upperRange_,
        uint256 lowerRange_,
        bytes8 dexId_
    ) internal returns (uint256, uint256) {
        uint256 rangeShift_ = _rangeShift[dexId_];
        uint256 shiftDuration_ = (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIME_TO_SHIFT) & X20;
        uint256 startTimeStamp_ = (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_TIMESTAMP) & X33;

        uint256 timePassed_;
        unchecked {
            if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
                // shifting fully done
                delete _rangeShift[dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables only updates from this function and _calcThresholdShifting.
                _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE);
                return (upperRange_, lowerRange_);
            }
            timePassed_ = block.timestamp - startTimeStamp_;
        }
        return (
            _calcShiftingDone(upperRange_, (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_UPPER_RANGE_PERCENT) & X14, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerRange_, (rangeShift_ >> DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_LOWER_RANGE_PERCENT) & X14, timePassed_, shiftDuration_)
        );
    }

    /// @dev Calculates the new upper and lower threshold values during an active threshold shift
    /// @param upperThreshold_ The target upper threshold value
    /// @param lowerThreshold_ The target lower threshold value
    /// @return The updated upper threshold, lower threshold
    /// @notice This function handles the gradual shifting of threshold values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcThresholdShifting(
        uint256 upperThreshold_,
        uint256 lowerThreshold_,
        bytes8 dexId_
    ) internal returns (uint256, uint256) {
        uint256 thresholdShift_ = _thresholdShift[dexId_];
        uint256 shiftDuration_ = (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIME_TO_SHIFT) & X20;
        uint256 startTimeStamp_ = (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIMESTAMP) & X33;

        uint256 timePassed_;
        unchecked {
            if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
                // shifting fully done
                delete _thresholdShift[dexId_];
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcRangeShifting.
                _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE);
                return (upperThreshold_, lowerThreshold_);
            }
            timePassed_ = block.timestamp - startTimeStamp_;
        }
        return (
            _calcShiftingDone(upperThreshold_, (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_UPPER_THRESHOLD_PERCENT) & X7, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerThreshold_, (thresholdShift_ >> DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_LOWER_THRESHOLD_PERCENT) & X7, timePassed_, shiftDuration_)
        );
    }

    /// @dev Calculates the new center price during an active price shift
    /// @param dexVariables_ The current state of dex variables
    /// @return newCenterPrice_ The updated center price
    /// @notice This function gradually shifts the center price towards a new target price over time
    /// @notice It uses an external price source (via ICenterPrice) to determine the target price
    /// @notice The shift continues until the current price reaches the target, or the shift duration ends
    /// @notice Once the shift is complete, it updates the state and clears the shift data
    /// @notice The shift rate is dynamic and depends on:
    /// @notice - Time remaining in the shift duration
    /// @notice - The new center price (fetched externally, which may change)
    /// @notice - The current (old) center price
    /// @notice This results in a fuzzy shifting mechanism where the rate can change as these parameters evolve
    /// @notice The externally fetched new center price is expected to not differ significantly from the last externally fetched center price
    function _calcCenterPrice(
        DexKey calldata dexKey_,
        uint256 dexVariables_,
        bytes8 dexId_
    ) internal returns (uint256 newCenterPrice_) {
        uint256 oldCenterPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);
        uint256 centerPriceShift_ = _centerPriceShift[dexId_];
        uint256 startTimeStamp_ = (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIMESTAMP) & X33;

        uint256 fromTimeStamp_ = (centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) & X33;
        fromTimeStamp_ = fromTimeStamp_ > startTimeStamp_ ? fromTimeStamp_ : startTimeStamp_;

        newCenterPrice_ = ICenterPrice(
            AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) & X19)))
            .centerPrice(dexKey_.token0, dexKey_.token1);
        
        unchecked {
            uint256 priceShift_ = (oldCenterPrice_ * ((centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT) & X20) * (block.timestamp - fromTimeStamp_)) 
                                    / (((centerPriceShift_ >> DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIME_TO_SHIFT) & X20) * SIX_DECIMALS);

            if (newCenterPrice_ > oldCenterPrice_) {
                // shift on positive side
                oldCenterPrice_ += priceShift_;
                if (newCenterPrice_ > oldCenterPrice_) {
                    newCenterPrice_ = oldCenterPrice_;
                } else {
                    // shifting fully done
                    _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT);
                    // making active shift as 0 because shift is over
                    // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                    _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE);
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
                    _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT);
                    // making active shift as 0 because shift is over
                    // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                    _dexVariables[dexId_] = _dexVariables[dexId_] & ~uint256(1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE);
                }
            }
        }
    }

    /// @notice Calculates and returns the current prices and exchange prices for the pool
    /// @param dexVariables_ The first set of DEX variables containing various pool parameters
    function _getPricesAndReserves(
        DexKey calldata dexKey_,
        uint256 dexVariables_,
        bytes8 dexId_,
        uint256 token0Supply_,
        uint256 token1Supply_
    ) internal returns (uint256 centerPrice_, uint256 token0ImaginaryReserves_, uint256 token1ImaginaryReserves_) {
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
                    ICenterPrice(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, centerPrice_)).centerPrice(dexKey_.token0, dexKey_.token1);
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
                temp_ = FixedPointMathLib.sqrt(upperRangePrice_ * lowerRangePrice_);
            } else {
                // upperRange_ price is pretty large hence lowerRange_ will also be pretty large
                temp_ = FixedPointMathLib.sqrt((upperRangePrice_ / 1e18) * (lowerRangePrice_ / 1e18)) * 1e18;
            }
        }

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
    }

    function _getRebalancingStatus(
        uint256 dexVariables_, 
        bytes8 dexId_, 
        uint256 rebalancingStatus_, 
        uint256 price_, 
        uint256 centerPrice_
    ) internal returns (uint256) {
        uint256 upperRange_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) & X14;
        uint256 lowerRange_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) & X14;

        // NOTE: we are using dexVariables_ and not _dexVariables[dexId_] here to check if the range shift is active
        // range shift might have already ended in this transaction above, but still calling _calcRangeShifting again because we don't want to use _dexVariables[dexId_] here because of gas
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) & X1) == 1) {
            // an active range shift is going on
            (upperRange_, lowerRange_) = _calcRangeShifting(upperRange_, lowerRange_, dexId_);
        }

        unchecked {
            // adding into unchecked because upperRangePercent_ & lowerRangePercent_ can only be > 0 & < FOUR_DECIMALS
            // 1% = 1e2, 100% = 1e4
            upperRange_ = (centerPrice_ * FOUR_DECIMALS) / (FOUR_DECIMALS - upperRange_);
            // 1% = 1e2, 100% = 1e4
            lowerRange_ = (centerPrice_ * (FOUR_DECIMALS - lowerRange_)) / FOUR_DECIMALS;
        }

        // Calculate threshold prices
        uint256 upperThreshold_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) & X7;
        uint256 lowerThreshold_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT) & X7;
        if (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE) & X1) == 1) {
            // if active shift is going on for threshold then calculate threshold real time
            (upperThreshold_, lowerThreshold_) = _calcThresholdShifting(upperThreshold_, lowerThreshold_, dexId_);
        }

        unchecked {
            upperThreshold_ = 
                (centerPrice_ + ((upperRange_ - centerPrice_) * (TWO_DECIMALS - upperThreshold_)) / TWO_DECIMALS);
            lowerThreshold_ = 
                (centerPrice_ - ((centerPrice_ - lowerRange_) * (TWO_DECIMALS - lowerThreshold_)) / TWO_DECIMALS);
        }

        if (price_ > upperThreshold_) {
            if (rebalancingStatus_ != 2) {
                _dexVariables[dexId_] = _dexVariables[dexId_] & ~(X2 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) | 
                    (2 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS);
                return 2;
            }
        } else if (price_ < lowerThreshold_) {
            if (rebalancingStatus_ != 3) {
                _dexVariables[dexId_] = _dexVariables[dexId_] & ~(X2 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) | 
                    (3 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS);
                return 3;
            }
        } else {
            if (rebalancingStatus_ != 1) {
                _dexVariables[dexId_] = _dexVariables[dexId_] & ~(X2 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) | 
                    (1 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS);
                return 1;
            }
        }

        return rebalancingStatus_;
    }

    function _transferTokens(
        address tokenIn_,
        uint256 amountIn_,
        address tokenOut_,
        uint256 amountOut_,
        address to_,
        bool isCallback_,
        bytes calldata callbackData_
    ) internal {
        if (to_ == address(0)) {
            to_ = msg.sender;
        }

        // Transfer tokens out first
        if (tokenOut_ == NATIVE_TOKEN) {
            SafeTransfer.safeTransferNative(to_, amountOut_);
        } else {
            SafeTransfer.safeTransfer(tokenOut_, to_, amountOut_);
        }

        // Transfer tokens in
        if (tokenIn_ == NATIVE_TOKEN) {
            if (isCallback_ && msg.value == 0) {
                uint256 ethBalance_ = address(this).balance;
                IDexLiteCallback(msg.sender).dexCallback(tokenIn_, amountIn_, callbackData_);
                if (address(this).balance - ethBalance_ < amountIn_) revert InsufficientNativeTokenReceived(address(this).balance - ethBalance_, amountIn_);
            }  else {
                if (msg.value < amountIn_) {
                    revert InsufficientNativeTokenReceived(msg.value, amountIn_);
                }
                if (msg.value > amountIn_) {
                    SafeTransfer.safeTransferNative(msg.sender, msg.value - amountIn_);
                }
                // if msg.value == amountIn_ then that means the transfer has already happened
            }
        } else {
            if (msg.value > 0) {
                revert InvalidMsgValue(); // msg.value should be 0 for non native tokens
            }
            if (isCallback_) {
                uint256 tokenInBalance_ = IERC20(tokenIn_).balanceOf(address(this));
                IDexLiteCallback(msg.sender).dexCallback(tokenIn_, amountIn_, callbackData_);
                if ((IERC20(tokenIn_).balanceOf(address(this)) - tokenInBalance_) < amountIn_) {
                    revert InsufficientERC20Received(IERC20(tokenIn_).balanceOf(address(this)) - tokenInBalance_, amountIn_);
                }
            } else {
                SafeTransfer.safeTransferFrom(tokenIn_, msg.sender, address(this), amountIn_);
            }
        }
    }

    /// @dev            do any arbitrary call
    /// @param target_  Address to which the call needs to be delegated
    /// @param data_    Data to execute at the delegated address
    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            if iszero(succeeded) {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }
}
