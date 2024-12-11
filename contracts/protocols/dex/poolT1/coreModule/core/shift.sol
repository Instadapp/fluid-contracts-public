// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { Variables } from "../../common/variables.sol";
import { ConstantVariables } from "../../common/constantVariables.sol";
import { Events } from "../events.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { ICenterPrice } from "../interfaces.sol";
import { AddressCalcs } from "../../../../../libraries/addressCalcs.sol";
import { Error } from "../../../error.sol";

contract FluidDexT1Shift is Variables, ConstantVariables, Events, Error {
    address private immutable DEPLOYER_CONTRACT;

    address private immutable THIS_CONTRACT;

    constructor(address deployerContract_) {
        DEPLOYER_CONTRACT = deployerContract_;
        THIS_CONTRACT = address(this);
    }

    modifier _onlyDelegateCall() {
        // also indirectly checked by `_check` because pool can never be initialized as long as the initialize method
        // is delegate call only, but just to be sure on Admin logic we add the modifier everywhere nonetheless.
        if (address(this) == THIS_CONTRACT) {
            revert FluidDexError(ErrorTypes.DexT1__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev This function calculates the new value of a parameter after a shifting process.
    /// @param current_ The current value is the final value where the shift ends
    /// @param old_ The old value from where shifting started.
    /// @param timePassed_ The time passed since shifting started.
    /// @param shiftDuration_ The total duration of the shift when old_ reaches current_
    /// @return The new value of the parameter after the shift.
    function _calcShiftingDone(
        uint current_,
        uint old_,
        uint timePassed_,
        uint shiftDuration_
    ) internal pure returns (uint) {
        if (current_ > old_) {
            uint diff_ = current_ - old_;
            current_ = old_ + ((diff_ * timePassed_) / shiftDuration_);
        } else {
            uint diff_ = old_ - current_;
            current_ = old_ - ((diff_ * timePassed_) / shiftDuration_);
        }
        return current_;
    }

    /// @dev Calculates the new upper and lower range values during an active range shift
    /// @param upperRange_ The target upper range value
    /// @param lowerRange_ The target lower range value
    /// @param dexVariables2_ needed in case shift is ended and we need to update dexVariables2
    /// @return The updated upper range, lower range, and dexVariables2
    /// @notice This function handles the gradual shifting of range values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcRangeShifting(
        uint upperRange_,
        uint lowerRange_,
        uint dexVariables2_
    ) public payable _onlyDelegateCall returns (uint, uint, uint) {
        uint rangeShift_ = _rangeShift;
        uint oldUpperRange_ = rangeShift_ & X20;
        uint oldLowerRange_ = (rangeShift_ >> 20) & X20;
        uint shiftDuration_ = (rangeShift_ >> 40) & X20;
        uint startTimeStamp_ = ((rangeShift_ >> 60) & X33);
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            delete _rangeShift;
            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcThresholdShifting.
            dexVariables2_ = dexVariables2 & ~uint(1 << 26);
            dexVariables2 = dexVariables2_;
            return (upperRange_, lowerRange_, dexVariables2_);
        }
        uint timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperRange_, oldUpperRange_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerRange_, oldLowerRange_, timePassed_, shiftDuration_),
            dexVariables2_
        );
    }

    /// @dev Calculates the new upper and lower threshold values during an active threshold shift
    /// @param upperThreshold_ The target upper threshold value
    /// @param lowerThreshold_ The target lower threshold value
    /// @param thresholdTime_ The time passed since shifting started
    /// @return The updated upper threshold, lower threshold, and threshold time
    /// @notice This function handles the gradual shifting of threshold values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcThresholdShifting(
        uint upperThreshold_,
        uint lowerThreshold_,
        uint thresholdTime_
    ) public payable _onlyDelegateCall returns (uint, uint, uint) {
        uint thresholdShift_ = _thresholdShift;
        uint oldUpperThreshold_ = thresholdShift_ & X20;
        uint oldLowerThreshold_ = (thresholdShift_ >> 20) & X20;
        uint shiftDuration_ = (thresholdShift_ >> 40) & X20;
        uint startTimeStamp_ = ((thresholdShift_ >> 60) & X33);
        uint oldThresholdTime_ = (thresholdShift_ >> 93) & X24;
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            delete _thresholdShift;
            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcRangeShifting.
            dexVariables2 = dexVariables2 & ~uint(1 << 67);
            return (upperThreshold_, lowerThreshold_, thresholdTime_);
        }
        uint timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperThreshold_, oldUpperThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerThreshold_, oldLowerThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(thresholdTime_, oldThresholdTime_, timePassed_, shiftDuration_)
        );
    }

    /// @dev Calculates the new center price during an active price shift
    /// @param dexVariables_ The current state of dex variables
    /// @param dexVariables2_ Additional dex variables
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
        uint dexVariables_,
        uint dexVariables2_
    ) public payable _onlyDelegateCall returns (uint newCenterPrice_) {
        uint oldCenterPrice_ = (dexVariables_ >> 81) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);
        uint centerPriceShift_ = _centerPriceShift;
        uint startTimeStamp_ = centerPriceShift_ & X33;
        uint percent_ = (centerPriceShift_ >> 33) & X20;
        uint time_ = (centerPriceShift_ >> 53) & X20;

        uint fromTimeStamp_ = (dexVariables_ >> 121) & X33;
        fromTimeStamp_ = fromTimeStamp_ > startTimeStamp_ ? fromTimeStamp_ : startTimeStamp_;

        newCenterPrice_ = ICenterPrice(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((dexVariables2_ >> 112) & X30)))
            .centerPrice();
        uint priceShift_ = (oldCenterPrice_ * percent_ * (block.timestamp - fromTimeStamp_)) / (time_ * SIX_DECIMALS);

        if (newCenterPrice_ > oldCenterPrice_) {
            // shift on positive side
            oldCenterPrice_ += priceShift_;
            if (newCenterPrice_ > oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            } else {
                // shifting fully done
                delete _centerPriceShift;
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                dexVariables2 = dexVariables2 & ~uint(1 << 248);
            }
        } else {
            unchecked {
                oldCenterPrice_ = oldCenterPrice_ > priceShift_ ? oldCenterPrice_ - priceShift_ : 0;
                // In case of oldCenterPrice_ ending up 0, which could happen when a lot of time has passed (pool has no swaps for many days or weeks)
                // then below we get into the else logic which will fully conclude shifting and return newCenterPrice_
                // as it was fetched from the external center price source.
                // not ideal that this would ever happen unless the pool is not in use and all/most users have left leaving not enough liquidity to trade on
            }
            if (newCenterPrice_ < oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            } else {
                // shifting fully done
                delete _centerPriceShift;
                // making active shift as 0 because shift is over
                // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates these shift function.
                dexVariables2 = dexVariables2 & ~uint(1 << 248);
            }
        }
    }
}
