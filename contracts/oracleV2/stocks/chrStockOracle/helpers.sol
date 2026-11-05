// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Variables, Constants } from "./variables.sol";
import { Events } from "./events.sol";
import { IFluidUsEquityMarketHours } from "../interfaces/iFluidUsEquityMarketHours.sol";
import { Error as OracleError } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { DeviationHelpers } from "../../../libraries/utils/deviationHelpers.sol";

abstract contract Helpers is Variables, Events, OracleError {
    constructor(CHRStockOracleConstructorParams memory p_) Constants(p_) {}

    /// @dev No-op here; the L2 variant (`mainL2.sol`) gates on the sequencer.
    function _beforeGuardedPriceRead() internal view virtual {}

    /// @dev Guarded read, SPEC §4 steps 1–9. Returns the (possibly clamped) rate plus the live value and print time.
    function _getPrice(
        bool isOperate_,
        bool isDebt_
    ) internal view returns (uint256 rate_, uint256 liveValue_, uint256 age_) {
        _beforeGuardedPriceRead();

        if (_paused != 0) revert FluidStockOracleError(ErrorTypes.CHRStockOracle__Paused);

        _revertIfRealityFlag();

        uint256 multiplier_ = RTOKEN.uiMultiplier();
        // accepted is always non-zero and fits uint104, so this also catches an invalid multiplier; `_readLive`
        // re-checks the bounds for the raw paths
        if (multiplier_ != _acceptedMultiplier) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__MultiplierChanged);
        }

        bool valid_;
        (valid_, age_, liveValue_) = _readLive(multiplier_);
        if (!valid_) revert FluidStockOracleError(ErrorTypes.CHRStockOracle__InvalidPrice);

        (uint256 anchor_, uint256 anchorTime_) = _effectiveAnchor();
        bool armed_ = _isAnchorArmed(anchorTime_);

        if (armed_ && _isBeyondBreak(anchor_, liveValue_)) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__PriceBreak);
        }

        // a valid print has age_ <= block.timestamp
        unchecked {
            if (block.timestamp - age_ > (isOperate_ ? MAX_OPERATE_AGE : MAX_LIQUIDATE_AGE)) {
                revert FluidStockOracleError(ErrorTypes.CHRStockOracle__StalePrice);
            }
        }

        rate_ = liveValue_;

        if (armed_) {
            (uint256 floor_, uint256 ceiling_) = _capBounds(anchor_);

            if (liveValue_ < floor_ || liveValue_ > ceiling_) {
                if (isOperate_) revert FluidStockOracleError(ErrorTypes.CHRStockOracle__OutsideCap);

                // liquidate is clamped only in the direction that would hurt the user
                if (isDebt_) {
                    if (liveValue_ > ceiling_) rate_ = ceiling_;
                } else {
                    if (liveValue_ < floor_) rate_ = floor_;
                }
            }
        }
    }

    function _getPriceWrite(bool isOperate_, bool isDebt_) internal returns (uint256 rate_) {
        uint256 liveValue_;
        uint256 age_;
        (rate_, liveValue_, age_) = _getPrice(isOperate_, isDebt_);

        _sealIfSealable();
        _recordHint(liveValue_, age_);
    }

    /// @dev Unguarded live value, optionally clamped like the directional raw getters; 0 if invalid.
    function _getRawValue(bool capUp_, bool floorDown_) internal view returns (uint256) {
        (bool valid_, , uint256 liveValue_) = _readLive(RTOKEN.uiMultiplier());
        if (!valid_) return 0;

        (uint256 anchor_, uint256 anchorTime_) = _effectiveAnchor();
        if (!_isAnchorArmed(anchorTime_)) return liveValue_;

        (uint256 floor_, uint256 ceiling_) = _capBounds(anchor_);
        if (capUp_ && liveValue_ > ceiling_) return ceiling_;
        if (floorDown_ && liveValue_ < floor_) return floor_;

        return liveValue_;
    }

    /// @dev Chronicle print × `multiplier_`; `valid_` false on any SPEC §4 step 6 failure or a zero / oversized multiplier.
    function _readLive(uint256 multiplier_) internal view returns (bool valid_, uint256 age_, uint256 liveValue_) {
        (bool ok_, uint256 price_, uint256 printAge_) = CHRONICLE.tryReadWithAge();
        age_ = printAge_;

        if (
            !ok_ ||
            price_ == 0 ||
            price_ > type(uint128).max ||
            printAge_ == 0 ||
            printAge_ > block.timestamp ||
            multiplier_ == 0 ||
            multiplier_ > type(uint104).max
        ) {
            return (false, age_, 0);
        }

        // price ≤ uint128 and multiplier ≤ uint104 keep the product far below 2^256
        unchecked {
            liveValue_ = (price_ * multiplier_) / PRICE_TIMES_MULTIPLIER_TO_RATE;
        }
        valid_ = liveValue_ != 0;
    }

    function _revertIfRealityFlag() internal view {
        if (RTOKEN.paused()) revert FluidStockOracleError(ErrorTypes.CHRStockOracle__RtokenPaused);

        if (REALITY_TOKEN_TRADE.tradePaused(address(RTOKEN))) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__TradePaused);
        }
    }

    /// @dev A sealable hint already counts as the anchor, so views agree with what the next write stores.
    function _effectiveAnchor() internal view returns (uint256 value_, uint256 time_) {
        uint256 hintAge_ = _hintAge;
        // uint32 + 2 minutes, evaluated in uint256
        unchecked {
            if (hintAge_ != 0 && block.timestamp > _hintRegularEnd + REGULAR_HOURS_ANCHOR_BUFFER) {
                return (_hintValue, hintAge_);
            }
        }
        return (_anchorValue, _anchorTime);
    }

    /// @dev Cap and break apply only against an anchor younger than ANCHOR_MAX_AGE. Before the first anchor (a fresh
    ///      deployment, until its first regular-session close is sealed) and after age-out they are skipped (fail-open).
    function _isAnchorArmed(uint256 anchorTime_) internal view returns (bool) {
        // anchor times are print ages, stored only once they were <= block.timestamp
        unchecked {
            return anchorTime_ != 0 && block.timestamp - anchorTime_ <= ANCHOR_MAX_AGE;
        }
    }

    function _isBeyondBreak(uint256 anchor_, uint256 value_) internal view returns (bool) {
        return DeviationHelpers.isOutsideDeviation(anchor_, value_, MAX_BREAK_PERCENT, FOUR_DECIMALS);
    }

    function _capBounds(uint256 anchor_) internal view returns (uint256 floor_, uint256 ceiling_) {
        // anchor ≤ uint128 and cap < 100% (constructor): no overflow, and delta_ < anchor_
        unchecked {
            uint256 delta_ = (anchor_ * MAX_CAP_PERCENT) / FOUR_DECIMALS;

            floor_ = anchor_ - delta_;
            ceiling_ = anchor_ + delta_;
        }
    }

    function _sealIfSealable() internal returns (bool sealed_) {
        uint256 hintAge_ = _hintAge;
        // uint32 + 2 minutes, evaluated in uint256
        unchecked {
            if (hintAge_ == 0 || block.timestamp <= _hintRegularEnd + REGULAR_HOURS_ANCHOR_BUFFER) return false;
        }

        uint256 value_ = _hintValue;
        _anchorValue = uint128(value_);
        _anchorTime = uint32(hintAge_);
        _clearHint();

        emit LogSealAnchor(value_, hintAge_);
        return true;
    }

    /// @dev SPEC §7 conditions 3–5 plus the `uint128` bound; the caller has checked 1–2. Seals again when the
    ///      recorded print's session and its buffer are already over.
    function _recordHint(uint256 liveValue_, uint256 age_) internal returns (bool recorded_) {
        // called first because it also advances the schedule cursor
        (, uint32 regularStart_, uint32 regularEnd_) = MARKET_HOURS.getCurrentSession();

        if (liveValue_ > type(uint128).max || regularStart_ == 0 || regularStart_ > regularEnd_) return false;
        // uint32 + 2 minutes, evaluated in uint256
        unchecked {
            if (age_ < regularStart_ || age_ > regularEnd_ + REGULAR_HOURS_ANCHOR_BUFFER) return false;
        }
        if (age_ <= _hintAge || age_ <= _anchorTime) return false;

        _hintValue = uint128(liveValue_);
        _hintAge = uint32(age_);
        _hintRegularEnd = uint32(regularEnd_);
        emit LogRecordHint(liveValue_, age_, regularEnd_);

        // a call after regularEnd + buffer records the last in-session print and seals it at once
        _sealIfSealable();
        return true;
    }

    function _clearHint() internal {
        _hintValue = 0;
        _hintAge = 0;
        _hintRegularEnd = 0;
    }

    /// @dev Latch causes with plain calls: a reverting dependency reverts the caller (`unpause`).
    function _causes() internal view returns (uint256 causes_) {
        if (REALITY_TOKEN_TRADE.tradePaused(address(RTOKEN))) causes_ |= CAUSE_TRADE_PAUSED;
        if (RTOKEN.paused()) causes_ |= CAUSE_RTOKEN_PAUSED;
        if (RTOKEN.uiMultiplier() != _acceptedMultiplier) causes_ |= CAUSE_MULTIPLIER_CHANGED;
    }
}
