// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Variables, Constants } from "./variables.sol";
import { Events } from "./events.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/external/IChainlinkAggregatorV3.sol";
import { IBackedAutoFeeToken } from "../interfaces/external/IBackedAutoFeeToken.sol";
import { Error as OracleError } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { DeviationHelpers } from "../../../libraries/utils/deviationHelpers.sol";

abstract contract Helpers is Variables, Events, OracleError {
    constructor(CLXStockOracleConstructorParams memory p_) Constants(p_) {}

    function _requireNotPaused() internal view {
        if (_paused != 0) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__Paused);
        }
    }

    /// @dev Current-session price. Debt inverts extended-hours clamp vs collateral.
    ///      `isRaw_`: skip pause / band / staleness; return 0 if CL/multiplier invalid.
    function _getPrice(
        bool isOperate_,
        bool isDebt_,
        bool isRaw_
    ) internal view returns (uint256 price_, uint256 liveMultiplier_) {
        if (!isRaw_) _requireNotPaused();
        (uint256 sessionType_, uint32 regularStart_, uint32 regularEnd_) = MARKET_HOURS.getSessionInfo(block.timestamp);
        (price_, liveMultiplier_, , ) = _getPriceForSession(
            isOperate_,
            isDebt_,
            sessionType_,
            regularStart_,
            regularEnd_,
            isRaw_
        );
    }

    /// @dev Write path: MH cursor, in-band multiplier sync, optional RTH store / fallback event.
    function _getPriceWrite(bool isOperate_, bool isDebt_) internal returns (uint256 price_) {
        _requireNotPaused();
        (uint256 sessionType_, uint32 regularStart_, uint32 regularEnd_) = MARKET_HOURS.getCurrentSession();
        uint256 liveMultiplier_;
        uint80 roundId_;
        bool regularHoursNotFoundFallback_;
        (price_, liveMultiplier_, roundId_, regularHoursNotFoundFallback_) = _getPriceForSession(
            isOperate_,
            isDebt_,
            sessionType_,
            regularStart_,
            regularEnd_,
            false
        );

        _syncAcceptedMultiplier(liveMultiplier_);

        if (regularHoursNotFoundFallback_) emit LogExtendedHoursFallback(sessionType_);

        if (roundId_ != 0 && _mayRollRegularHoursReference(roundId_, sessionType_, regularStart_)) {
            // REGULAR: sync = `block.timestamp` (hint only — close may still print).
            // Else: sync = `regularEnd_` (fully discovered → cache hit on later reads).
            _storeRegularHoursReference(
                roundId_,
                sessionType_ == SESSION_TYPE_REGULAR ? uint32(block.timestamp) : regularEnd_
            );
        }
    }

    /// @dev Session price. `persistRoundId_` = 0 & `regularHoursNotFoundFallback_` = true when RTH clamp skipped.
    function _getPriceForSession(
        bool isOperate_,
        bool isDebt_,
        uint256 sessionType_,
        uint32 regularStart_,
        uint32 regularEnd_,
        bool isRaw_
    )
        internal
        view
        returns (uint256 price_, uint256 liveMultiplier_, uint80 persistRoundId_, bool regularHoursNotFoundFallback_)
    {
        uint256 updatedAt_;
        (price_, liveMultiplier_, updatedAt_, persistRoundId_) = _readLatestPrice(isRaw_);
        if (price_ == 0) return (0, liveMultiplier_, 0, false);

        if (!isRaw_) {
            // a stock split moves Chainlink and the Backed multiplier at independent moments; each guard freezes
            // pricing across one desync ordering: multiplier first (band), announced (scheduled), CL first (gap)
            // Band before staleness so out-of-band jumps surface as NeedsConfirmation even if CL is old.
            if (_isLiveMultiplierOutsideBand(liveMultiplier_)) {
                revert FluidStockOracleError(ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation);
            }
            _revertIfScheduledMultiplierOutsideBand(liveMultiplier_);
            // gap guard: reference scaled by the same live multiplier as price_ — units only, deviation is CL vs CL
            uint256 referenceAnswer_ = _freshAnchorReferenceAnswer();
            if (referenceAnswer_ != 0) {
                referenceAnswer_ = (referenceAnswer_ * liveMultiplier_ * RATE_MULTIPLIER) / MULTIPLIER_PRECISION;
                if (_isPriceGapOutside(referenceAnswer_, price_)) {
                    revert FluidStockOracleError(ErrorTypes.CLXStockOracle__PriceGapBreak);
                }
            }
        }

        if (sessionType_ == SESSION_TYPE_REGULAR) {
            if (!isRaw_) _revertIfStalePrice(updatedAt_, isOperate_, sessionType_, false);
            return (price_, liveMultiplier_, persistRoundId_, false);
        }

        // Extended hours (any non-REGULAR): clamp live to ±`MAX_EXTENDED_HOURS_CAP_PERCENT` around RTH.
        // Cap upside when `isOperate_ != isDebt_` (XOR of the two flags):
        //   col  operate   → cap up   (don't overvalue collateral for borrows)
        //   col  liquidate → floor dn (don't undervalue collateral into forced liqs)
        //   debt operate   → floor dn (don't undervalue debt / underprice borrows)
        //   debt liquidate → cap up   (don't overvalue debt into forced liqs)
        if (_isRegularWindowTrusted(regularStart_, regularEnd_)) {
            bool found_;
            uint256 clamped_;
            (found_, persistRoundId_, clamped_) = _clampExtendedHoursPrice(
                price_,
                liveMultiplier_,
                isOperate_,
                isDebt_,
                regularStart_,
                regularEnd_
            );
            if (found_) {
                if (!isRaw_) _revertIfStalePrice(updatedAt_, isOperate_, sessionType_, false);
                return (clamped_, liveMultiplier_, persistRoundId_, false);
            }
        }

        // No usable RTH ref: live, no clamp. Untrusted / malformed MH window (MH failure) keeps operate on the
        // 5d fail-open rule; trusted window with no anchor is a feed anomaly → operate stays heartbeat-fresh.
        if (!isRaw_) {
            _revertIfStalePrice(
                updatedAt_,
                isOperate_,
                sessionType_,
                !_isRegularWindowTrusted(regularStart_, regularEnd_)
            );
        }
        return (price_, liveMultiplier_, 0, true);
    }

    /// @dev Op Regular/Extended: heartbeat-fresh. Else (liq / Holiday/Unknown / MH window failure): 5d extended.
    function _revertIfStalePrice(
        uint256 updatedAt_,
        bool isOperate_,
        uint256 sessionType_,
        bool mhWindowFailure_
    ) internal view {
        if (updatedAt_ == 0) revert FluidStockOracleError(ErrorTypes.CLXStockOracle__StalePrice);

        uint256 maxAge_ = MAX_UPDATE_TIMESPAN_EXTENDED;
        if (
            isOperate_ &&
            !mhWindowFailure_ &&
            sessionType_ != SESSION_TYPE_HOLIDAY &&
            sessionType_ != SESSION_TYPE_UNKNOWN
        ) {
            maxAge_ = MIN_CHAINLINK_HEARTBEAT;
        }
        if (block.timestamp > updatedAt_ + maxAge_) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__StalePrice);
        }
    }

    /// @dev MH window metadata ok to use for clamp (non-empty, well-formed, `regularEnd` < 5d old).
    ///      Does not look up Chainlink — that is `_findLatestRegularHoursRound`.
    function _isRegularWindowTrusted(uint32 regularStart_, uint32 regularEnd_) internal view returns (bool) {
        if (regularStart_ == 0 || regularEnd_ == 0 || regularEnd_ < regularStart_) return false;
        if (regularEnd_ >= block.timestamp) return true;
        unchecked {
            return block.timestamp - regularEnd_ < REGULAR_HOURS_HINT_MAX_AGE;
        }
    }

    /// @dev Resolve RTH CL answer + clamp. `found_=false` if no CL round in the RTH time window.
    function _clampExtendedHoursPrice(
        uint256 price_,
        uint256 liveMultiplier_,
        bool isOperate_,
        bool isDebt_,
        uint32 regularStart_,
        uint32 regularEnd_
    ) internal view returns (bool found_, uint80 resolvedRoundId_, uint256 clamped_) {
        uint256 regularHoursReferencePrice_;
        (found_, resolvedRoundId_, regularHoursReferencePrice_) = _resolveRegularHoursReference(
            regularStart_,
            regularEnd_
        );
        if (!found_) return (false, 0, price_);

        // Mul stays checked; after that, cap ≤ 100% of `anchor_` so ±delta cannot under/overflow.
        uint256 anchor_ = regularHoursReferencePrice_ * liveMultiplier_ * RATE_MULTIPLIER;
        unchecked {
            anchor_ /= MULTIPLIER_PRECISION;
        }
        uint256 delta_ = anchor_ * MAX_EXTENDED_HOURS_CAP_PERCENT;
        unchecked {
            delta_ /= SIX_DECIMALS;
            clamped_ = price_;
            if (isOperate_ != isDebt_) {
                uint256 upCap_ = anchor_ + delta_;
                if (clamped_ > upCap_) clamped_ = upCap_;
            } else {
                uint256 downFloor_ = anchor_ - delta_;
                if (clamped_ < downFloor_) clamped_ = downFloor_;
            }
        }
    }

    /// @dev `syncTime_` = `regularEnd` (verified) or `block.timestamp` (REGULAR hint).
    function _storeRegularHoursReference(uint80 roundId_, uint32 syncTime_) internal {
        _lastRegularHoursRoundId = roundId_;
        _lastVerifiedRegularHoursEnd = syncTime_;
    }

    /// @dev Rate limit on gap-reference rolls: without it, a split that CL prints as several quick rounds
    ///      can be walked past the gap guard by re-anchoring onto an intermediate print (one in-band hop
    ///      covers a 2:1). Same-round stores only refresh the marker; gov / class ≥ 3 rolls skip this gate.
    ///      A blocked roll is skipped silently — pricing itself is never affected.
    function _mayRollRegularHoursReference(
        uint80 newRoundId_,
        uint256 sessionType_,
        uint32 regularStart_
    ) internal view returns (bool) {
        uint80 storedRoundId_ = _lastRegularHoursRoundId;
        if (newRoundId_ == storedRoundId_) return true;
        unchecked {
            // uint32 `regularStart_` + 20m cannot overflow; the subtraction is short-circuit guarded.
            if (
                sessionType_ == SESSION_TYPE_REGULAR &&
                block.timestamp < uint256(regularStart_) + PRICE_GAP_REFERENCE_ROLL_DELAY
            ) {
                return false;
            }
            if (storedRoundId_ == 0) return true;
            (bool ok_, , , uint256 updatedAt_) = _tryReadChainlinkRound(storedRoundId_);
            // unreadable / phantom / future stored round is no usable reference for the guard — don't wedge rolls
            return
                !ok_ ||
                updatedAt_ == 0 ||
                updatedAt_ > block.timestamp ||
                block.timestamp - updatedAt_ >= PRICE_GAP_REFERENCE_ROLL_DELAY;
        }
    }

    /// @dev RTH answer for `regularEnd_`. Cache hit on matching end; else discover.
    function _resolveRegularHoursReference(
        uint32 regularStart_,
        uint32 regularEnd_
    ) internal view returns (bool found_, uint80 roundId_, uint256 answer_) {
        uint80 cachedRoundId_ = _lastRegularHoursRoundId;
        uint32 syncTime_ = _lastVerifiedRegularHoursEnd;
        // Verified for this exact regular close — trust stored round (no walk). Pre-window anchors must
        // still pass the liveness check (feed may have gone silent after the store).
        if (cachedRoundId_ != 0 && syncTime_ == regularEnd_) {
            bool ok_;
            uint256 updatedAt_;
            (ok_, , answer_, updatedAt_) = _tryReadChainlinkRound(cachedRoundId_);
            if (
                ok_ &&
                answer_ > 0 &&
                (updatedAt_ >= regularStart_ || _isPreWindowAnchorTrusted(cachedRoundId_, updatedAt_))
            ) return (true, cachedRoundId_, answer_);
        }

        // Prefer stored hint when its sync marker is fresh (REGULAR `block.timestamp` or prior `regularEnd`).
        return _findLatestRegularHoursRound(regularStart_, regularEnd_, cachedRoundId_, syncTime_);
    }

    /// @dev Walk CL history for latest round with `updatedAt ∈ [windowStart, regularEnd_ + buffer]`.
    ///      `windowStart` = `regularStart_`; once the window is fully past it widens to `windowEnd - MIN_CHAINLINK_HEARTBEAT`
    ///      (quiet session ⇒ CL deviation certifies the last pre-window print as the session price).
    ///      Pre-window anchors must additionally pass `_isPreWindowAnchorTrusted`.
    /// @param hintRoundId_ `0` = start from latest. @param hintSyncedAt_ Sync age, or `0` → age by round `updatedAt`.
    ///      Stale beyond `REGULAR_HOURS_HINT_MAX_AGE` → ignore hint, start from latest.
    function _findLatestRegularHoursRound(
        uint32 regularStart_,
        uint32 regularEnd_,
        uint80 hintRoundId_,
        uint32 hintSyncedAt_
    ) internal view returns (bool found_, uint80 roundId_, uint256 answer_) {
        if (regularStart_ == 0 || regularEnd_ == 0 || regularEnd_ < regularStart_) {
            return (false, 0, 0);
        }

        uint256 windowEnd_;
        unchecked {
            windowEnd_ = uint256(regularEnd_) + REGULAR_HOURS_ANCHOR_BUFFER;
        }

        uint256 windowStart_ = regularStart_;
        if (block.timestamp > windowEnd_) {
            // Window fully past (never during live REGULAR): pre-window print within heartbeat is a valid anchor.
            // MH caps REGULAR duration at 24h, so this always widens below `regularStart_`.
            unchecked {
                windowStart_ = windowEnd_ - MIN_CHAINLINK_HEARTBEAT;
            }
        }

        uint256 updatedAt_;
        (found_, roundId_, answer_, updatedAt_) = _getRegularHoursRoundCursor(hintRoundId_, hintSyncedAt_);
        if (!found_) return (found_, roundId_, answer_);

        // Started after the window → walk back; first round at/before `windowEnd_` is the latest in-window candidate.
        if (updatedAt_ > windowEnd_) {
            (found_, roundId_, answer_, updatedAt_) = _walkBackToLatestInWindow(
                roundId_,
                answer_,
                updatedAt_,
                windowStart_,
                windowEnd_
            );
        } else {
            // Started at/before window end → walk forward to the last still-in-window round.
            (found_, roundId_, answer_, updatedAt_) = _walkForwardToLatestInWindow(
                roundId_,
                answer_,
                updatedAt_,
                windowStart_,
                windowEnd_
            );
        }

        // Pre-window anchor: quiet-session certification requires proven feed heartbeat liveness.
        if (found_ && updatedAt_ < regularStart_ && !_isPreWindowAnchorTrusted(roundId_, updatedAt_)) {
            return (false, 0, 0);
        }
    }

    /// @dev Pre-window anchor is rejected only if the feed *provably* missed a print it owed: the next print
    ///      was due by `print + heartbeat` (deadline); a deadline passed during trading hours with no print is
    ///      a violation that voids the quiet-session certification. A deadline in HOLIDAY (weekend — feed
    ///      expectedly silent) or UNKNOWN (MH cannot classify) proves nothing. See EDGE_CASES.md.
    function _isPreWindowAnchorTrusted(uint80 roundId_, uint256 updatedAt_) internal view returns (bool) {
        uint256 deadline_;
        unchecked {
            // Callers only pass `updatedAt_ < regularStart_` (uint32 MH timestamp) — no overflow.
            deadline_ = updatedAt_ + MIN_CHAINLINK_HEARTBEAT;
        }
        // Deadline not passed yet — no violation provable.
        if (block.timestamp < deadline_) return true;
        if (roundId_ < type(uint80).max) {
            (bool ok_, , , uint256 nextUpdatedAt_) = _tryReadChainlinkRound(roundId_ + 1);
            // Next print landed before its deadline — feed was provably live across the session.
            if (ok_ && nextUpdatedAt_ != 0 && nextUpdatedAt_ < deadline_) return true;
        }
        uint256 deadlineSession_ = MARKET_HOURS.getSessionType(deadline_);
        return deadlineSession_ != SESSION_TYPE_REGULAR && deadlineSession_ != SESSION_TYPE_EXTENDED;
    }

    /// @dev Fresh hint if age-ok; else latest. `hintSyncedAt_ != 0` ages by sync, else by CL `updatedAt`.
    function _getRegularHoursRoundCursor(
        uint80 hintRoundId_,
        uint32 hintSyncedAt_
    ) internal view returns (bool found_, uint80 roundIdCursor_, uint256 answerAtCursor_, uint256 updatedAt_) {
        if (hintRoundId_ != 0) {
            (found_, , answerAtCursor_, updatedAt_) = _tryReadChainlinkRound(hintRoundId_);
            // Future `updatedAt` should not happen; treat as unusable.
            if (found_ && updatedAt_ <= block.timestamp) {
                uint256 ageRef_ = hintSyncedAt_ != 0 ? uint256(hintSyncedAt_) : updatedAt_;
                unchecked {
                    if (
                        ageRef_ != 0 &&
                        ageRef_ <= block.timestamp &&
                        block.timestamp - ageRef_ < REGULAR_HOURS_HINT_MAX_AGE
                    ) {
                        return (true, hintRoundId_, answerAtCursor_, updatedAt_);
                    }
                }
            }
        }
        return _tryReadChainlinkRound(0);
    }

    /// @dev From after `windowEnd_`, walk back to first `updatedAt <= windowEnd_` (latest in-window candidate).
    ///      Stops on read failure or `updatedAt == 0` (post-tip phantom rounds some CL feeds return as success).
    function _walkBackToLatestInWindow(
        uint80 roundIdCursor_,
        uint256 answerAtCursor_,
        uint256 updatedAt_,
        uint256 windowStart_,
        uint256 windowEnd_
    ) internal view returns (bool found_, uint80 roundId_, uint256 answer_, uint256 foundUpdatedAt_) {
        unchecked {
            bool ok_;
            for (uint256 steps_; updatedAt_ > windowEnd_; ++steps_) {
                if (roundIdCursor_ == 0 || steps_ >= MAX_REGULAR_HOURS_ROUND_LOOKBACK) return (false, 0, 0, 0);
                --roundIdCursor_;
                (ok_, , answerAtCursor_, updatedAt_) = _tryReadChainlinkRound(roundIdCursor_);
                // `updatedAt == 0`: treat as tip/gap (same as revert) — do not keep walking phantoms.
                if (!ok_ || updatedAt_ == 0) return (false, 0, 0, 0);
            }
        }

        if (answerAtCursor_ > 0 && updatedAt_ >= windowStart_) {
            return (true, roundIdCursor_, answerAtCursor_, updatedAt_);
        }
        return (false, 0, 0, 0); // no CL round with updatedAt in [windowStart, windowEnd]
    }

    /// @dev From at/before `windowEnd_`, walk forward; keep last in `[windowStart_, windowEnd_]`.
    ///      Stops on read failure or `updatedAt == 0` (post-tip phantom rounds some CL feeds return as success).
    function _walkForwardToLatestInWindow(
        uint80 roundIdCursor_,
        uint256 answerAtCursor_,
        uint256 updatedAt_,
        uint256 windowStart_,
        uint256 windowEnd_
    ) internal view returns (bool found_, uint80 roundId_, uint256 answer_, uint256 foundUpdatedAt_) {
        uint80 latestInWindowRoundId_;
        uint256 latestInWindowAnswer_;
        uint256 latestInWindowUpdatedAt_;

        uint256 steps_;
        unchecked {
            bool ok_;
            for (; steps_ < MAX_REGULAR_HOURS_ROUND_LOOKBACK; ++steps_) {
                // Also stop if the starting cursor itself is a phantom (`updatedAt == 0`).
                if (updatedAt_ == 0 || updatedAt_ > windowEnd_) break;
                if (answerAtCursor_ > 0 && updatedAt_ >= windowStart_) {
                    latestInWindowRoundId_ = roundIdCursor_;
                    latestInWindowAnswer_ = answerAtCursor_;
                    latestInWindowUpdatedAt_ = updatedAt_;
                }
                if (roundIdCursor_ == type(uint80).max) break;

                ++roundIdCursor_;
                (ok_, , answerAtCursor_, updatedAt_) = _tryReadChainlinkRound(roundIdCursor_);
                // no more rounds (revert) or phantom post-tip success with `updatedAt == 0`
                if (!ok_ || updatedAt_ == 0) break;
            }
        }

        if (latestInWindowRoundId_ == 0) {
            return (false, 0, 0, 0); // no CL round with updatedAt in [windowStart, windowEnd]
        }
        if (steps_ == MAX_REGULAR_HOURS_ROUND_LOOKBACK) {
            // lookback exhausted: a later in-window round may exist, so this one is not provably the close.
            // Fail open like the back walk instead of certifying a non-latest round as the RTH anchor.
            return (false, 0, 0, 0);
        }
        return (true, latestInWindowRoundId_, latestInWindowAnswer_, latestInWindowUpdatedAt_);
    }

    function _syncAcceptedMultiplier(uint256 live_) internal {
        if (live_ == _acceptedMultiplier) return;
        if (live_ > type(uint104).max) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__StorageOverflow);
        }
        uint256 old_ = _acceptedMultiplier;
        _acceptedMultiplier = uint104(live_);
        _lastMultiplierUpdateTime = uint32(block.timestamp);
        emit LogUpdateAcceptedMultiplier(old_, live_);
    }

    /// @dev `roundId_ == 0` → latest. Revert → success false. Answer ≤ 0 → `answer_ == 0`.
    ///      `updatedAt == 0` is returned as-is: callers decide (walkers treat it as tip/gap, live price path
    ///      surfaces it as `StalePrice`).
    function _tryReadChainlinkRound(uint80 roundId_) internal view returns (bool, uint80, uint256, uint256) {
        if (roundId_ == 0) {
            try IChainlinkAggregatorV3(CHAINLINK_FEED).latestRoundData() returns (
                uint80 id_,
                int256 ans_,
                uint256,
                uint256 at_,
                uint80
            ) {
                return (true, id_, ans_ > 0 ? uint256(ans_) : 0, at_);
            } catch {
                return (false, 0, 0, 0);
            }
        }

        try IChainlinkAggregatorV3(CHAINLINK_FEED).getRoundData(roundId_) returns (
            uint80 id_,
            int256 ans_,
            uint256,
            uint256 at_,
            uint80
        ) {
            return (true, id_, ans_ > 0 ? uint256(ans_) : 0, at_);
        } catch {
            return (false, 0, 0, 0);
        }
    }

    /// @dev CL × live multiplier × `RATE_MULTIPLIER`. Raw soft-fails to zeros; else `InvalidPrice`.
    function _readLatestPrice(
        bool isRaw_
    ) internal view returns (uint256 price_, uint256 multiplier_, uint256 updatedAt_, uint80 roundId_) {
        bool ok_;
        (ok_, roundId_, price_, updatedAt_) = _tryReadChainlinkRound(0);
        (multiplier_, , ) = IBackedAutoFeeToken(BACKED_UNDERLYING).getCurrentMultiplier();

        price_ = price_ * multiplier_ * RATE_MULTIPLIER;
        unchecked {
            price_ /= MULTIPLIER_PRECISION;
        }

        // After scaling: `price_ == 0` also covers a product the division truncates below `MULTIPLIER_PRECISION`.
        if (!ok_ || price_ == 0 || multiplier_ == 0) {
            if (isRaw_) return (0, 0, updatedAt_, roundId_);
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidPrice);
        }
    }

    /// @dev Pending schedule within `SCHEDULED_MULTIPLIER_FREEZE_BUFFER` and outside absolute `MAX%` vs live.
    function _revertIfScheduledMultiplierOutsideBand(uint256 live_) internal view {
        uint256 activation_ = IBackedAutoFeeToken(BACKED_UNDERLYING).newMultiplierActivationTime();
        if (activation_ < block.timestamp || activation_ > block.timestamp + SCHEDULED_MULTIPLIER_FREEZE_BUFFER) {
            return;
        }
        if (
            DeviationHelpers.isOutsideDeviation(
                live_,
                IBackedAutoFeeToken(BACKED_UNDERLYING).newMultiplier(),
                MAX_MULTIPLIER_CHANGE_PERCENT,
                FOUR_DECIMALS
            )
        ) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__ScheduledMultiplierPending);
        }
    }

    /// @dev Anchor-round answer as gap reference; `0` = unset / unreadable / too old.
    function _freshAnchorReferenceAnswer() internal view returns (uint256 answer_) {
        uint80 roundId_ = _lastRegularHoursRoundId;
        if (roundId_ == 0) return 0;
        bool ok_;
        uint256 updatedAt_;
        (ok_, , answer_, updatedAt_) = _tryReadChainlinkRound(roundId_);
        if (
            !ok_ ||
            updatedAt_ == 0 ||
            updatedAt_ > block.timestamp ||
            block.timestamp - updatedAt_ > PRICE_GAP_REFERENCE_MAX_AGE
        ) {
            return 0;
        }
    }

    /// @dev Strictly outside `−down% / +up%` of `reference_`.
    function _isPriceGapOutside(uint256 reference_, uint256 value_) internal view returns (bool) {
        uint256 maxPercent_ = value_ < reference_ ? MAX_PRICE_GAP_DOWN_PERCENT : MAX_PRICE_GAP_UP_PERCENT;
        return DeviationHelpers.isOutsideDeviation(reference_, value_, maxPercent_, FOUR_DECIMALS);
    }

    /// @dev Outside time-accrued band of `_acceptedMultiplier`. `MAX% == 0` → freeze (`live != accepted`).
    ///      Accrues absolute `maxDiff = accepted * MAX% * elapsed / (PERIOD * 1e4)` (not floored percent).
    function _isLiveMultiplierOutsideBand(uint256 live_) internal view returns (bool) {
        if (MAX_MULTIPLIER_CHANGE_PERCENT == 0) {
            return live_ != _acceptedMultiplier;
        }

        uint256 elapsed_;
        unchecked {
            // `_lastMultiplierUpdateTime` is only ever written as `uint32(block.timestamp)`.
            elapsed_ = block.timestamp - _lastMultiplierUpdateTime;
            if (elapsed_ > MULTIPLIER_BAND_PERIOD) {
                elapsed_ = MULTIPLIER_BAND_PERIOD;
            }
            // `MAX%` ≤ 1000, `elapsed_` ≤ 30 days → scaled args fit uint256.
            return
                DeviationHelpers.isOutsideDeviation(
                    _acceptedMultiplier,
                    live_,
                    MAX_MULTIPLIER_CHANGE_PERCENT * elapsed_,
                    FOUR_DECIMALS * MULTIPLIER_BAND_PERIOD
                );
        }
    }
}
