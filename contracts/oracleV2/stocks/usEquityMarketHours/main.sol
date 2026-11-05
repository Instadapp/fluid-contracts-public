// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { BasicAuth } from "../../../libraries/access/basicAuth.sol";
import { IFluidUsEquityMarketHours } from "../interfaces/iFluidUsEquityMarketHours.sol";
import { Structs } from "./structs.sol";
import { Helpers } from "./helpers.sol";
import { Variables } from "./variables.sol";
import { Events } from "./events.sol";
import { Error as OracleError } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @dev Governance + auth week-schedule writes.
abstract contract FluidUsEquityMarketHoursAdmin is BasicAuth, Helpers, Events, OracleError {
    function _authClass(address auth_) internal view override returns (uint256) {
        return _auths[auth_];
    }

    function _setAuthClass(address auth_, uint256 authClass_) internal override {
        _auths[auth_] = authClass_;
    }

    /// @notice Replace the week-ahead session list (typically once on Saturday). Clears previous entries.
    /// @dev Expected writer shape for a weekend rewrite:
    ///      1. **Last completed REGULAR** (e.g. Friday) with `sessionStart ≤ block.timestamp`
    ///      2. **Ongoing weekend HOLIDAY** whose full window (session + extended) contains `block.timestamp`
    ///         (extended usually covers Monday pre-market)
    ///      3. **Next week** Mon–Fri REGULAR (+ optional next weekend HOLIDAY), covering forward
    ///         (≤ `MAX_SESSIONS` = 8 total)
    ///
    ///      Sanity checks (all required):
    ///      - `1 ≤ length ≤ MAX_SESSIONS` (8)
    ///      - each entry: non-zero start/duration; durations ≤ `MAX_DURATION_MINUTES` (8191);
    ///        REGULAR duration ≤ `MAX_REGULAR_DURATION_MINUTES` (24h); type ∈ {REGULAR, HOLIDAY}
    ///      - contiguous: `next.sessionStart == prev.entryEnd` (no gaps, no overlaps)
    ///      - sum of all `(durationMinutes + extendedDurationMinutes) ≥ MIN_SCHEDULE_DURATION_MINUTES` (7 days)
    ///      - sum of `REGULAR` durations ≤ `MAX_REGULAR_DURATION_MINUTES * 5` (5 trading days; REGULAR skips the clamp)
    ///      - **some** entry contains `now` — avoid writing a schedule that is immediately UNKNOWN
    ///      - **some** `REGULAR` has `sessionStart ≤ now` — preserve a cash-session anchor for extended-hours caps
    ///      - every entry starting before `now + PINNED_SESSION_LOOKAHEAD` matches a stored one — no retroactive
    ///        anchor moves (skipped on the first write and for governance / `AUTH_CLASS_SCHEDULE_OVERRIDE`)
    function updateWeekSessions(Session[] calldata sessions_) external onlyAuthClassAbove(AUTH_CLASS_SCHEDULE) {
        uint256 len_ = sessions_.length;
        if (len_ == 0 || len_ > MAX_SESSIONS) {
            revert FluidStockOracleError(ErrorTypes.UsEquityMarketHours__InvalidParams);
        }

        uint256 prevEntryEnd_;
        uint256 totalMinutes_;
        uint256 regularMinutes_;
        bool containsNow_;
        bool hasRegularStarted_;

        // Elapsed sessions set the CLX anchor. Contiguity also pins the next entry as the live one nears its end.
        (uint256 data0_, uint256 data1_, uint256 pinnedUntil_) = _pinnedSessionsWindow();

        for (uint256 i_; i_ < len_; ++i_) {
            Session calldata s_ = sessions_[i_];
            (uint256 entryEnd_, uint256 entryMinutes_) = _validateSession(s_, prevEntryEnd_, i_ == 0);

            if (s_.sessionStart < pinnedUntil_ && !_isStoredSession(data0_, data1_, s_)) {
                revert FluidStockOracleError(ErrorTypes.UsEquityMarketHours__PinnedSessionMutated);
            }

            if (block.timestamp >= s_.sessionStart && block.timestamp < entryEnd_) {
                containsNow_ = true;
            }
            if (s_.sessionType == SESSION_TYPE_REGULAR) {
                regularMinutes_ += s_.durationMinutes;
                if (s_.sessionStart <= block.timestamp) {
                    hasRegularStarted_ = true;
                }
            }

            totalMinutes_ += entryMinutes_;
            prevEntryEnd_ = entryEnd_;
        }

        // `containsNow_`: schedule must cover `block.timestamp` so readers are not left in UNKNOWN
        // right after a write (writer must keep the live window continuous).
        // `hasRegularStarted_`: at least one REGULAR must already have started so oracles have a
        // cash-session window to anchor extended-hours caps (`getLatestRegularHoursWindow`).
        // `regularMinutes_`: REGULAR disables the extended-hours clamp, and the per-entry cap alone does not bound
        // how much of a schedule may be REGULAR (8 entries would be 8 continuous days). Cap at 5 trading days.
        if (
            !containsNow_ ||
            !hasRegularStarted_ ||
            totalMinutes_ < MIN_SCHEDULE_DURATION_MINUTES ||
            regularMinutes_ > MAX_REGULAR_DURATION_MINUTES * 5
        ) {
            revert FluidStockOracleError(ErrorTypes.UsEquityMarketHours__InvalidParams);
        }

        (_sessionData0, _sessionData1) = _storeSessions(sessions_);
        emit LogUpdateWeekSessions(sessions_);
    }

    /// @dev Stored words + timestamp up to which sessions are pinned (`0` = nothing pinned, starts are non-zero).
    function _pinnedSessionsWindow() internal view returns (uint256 data0_, uint256 data1_, uint256 pinnedUntil_) {
        if (_isGovernance() || _authClass(msg.sender) >= AUTH_CLASS_SCHEDULE_OVERRIDE) {
            return (0, 0, 0);
        }
        data0_ = _sessionData0;
        data1_ = _sessionData1;
        if (_loadSession(data0_, data1_, 0).sessionStart != 0) {
            pinnedUntil_ = block.timestamp + PINNED_SESSION_LOOKAHEAD;
        }
    }

    /// @dev Validates fields + contiguity; returns full entry end (seconds) and duration sum (minutes).
    function _validateSession(
        Session calldata s_,
        uint256 prevEntryEnd_,
        bool isFirst_
    ) internal pure returns (uint256 entryEnd_, uint256 entryMinutes_) {
        if (
            s_.sessionStart == 0 ||
            s_.durationMinutes == 0 ||
            s_.durationMinutes > MAX_DURATION_MINUTES ||
            s_.extendedDurationMinutes > MAX_DURATION_MINUTES ||
            (s_.sessionType == SESSION_TYPE_REGULAR && s_.durationMinutes > MAX_REGULAR_DURATION_MINUTES) ||
            (s_.sessionType != SESSION_TYPE_REGULAR && s_.sessionType != SESSION_TYPE_HOLIDAY)
        ) {
            revert FluidStockOracleError(ErrorTypes.UsEquityMarketHours__InvalidParams);
        }

        entryMinutes_ = uint256(s_.durationMinutes) + uint256(s_.extendedDurationMinutes);
        entryEnd_ = uint256(s_.sessionStart) + entryMinutes_ * 1 minutes;

        if (!isFirst_ && uint256(s_.sessionStart) != prevEntryEnd_) {
            revert FluidStockOracleError(ErrorTypes.UsEquityMarketHours__InvalidParams);
        }
    }
}

/// @title FluidUsEquityMarketHours
/// @notice Week-ahead US equity session schedule for Chainlink 24/5 stock oracles.
/// @dev Deploy behind `FluidUsEquityMarketHoursProxy` (ERC1967). UUPS upgrades are
///      `onlyGovernance` (governance of constructor-bound Liquidity). Off-chain sync is
///      complementary — missing/undefined schedule returns UNKNOWN (fail-open).
contract FluidUsEquityMarketHours is FluidUsEquityMarketHoursAdmin, IFluidUsEquityMarketHours {
    /// @param liquidity_ Liquidity proxy whose EIP-1967 admin is governance for this contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address liquidity_) Variables(liquidity_) {}

    /// @inheritdoc IFluidUsEquityMarketHours
    function getSessions() external view returns (Session[] memory sessions_) {
        uint256 data0_ = _sessionData0;
        uint256 data1_ = _sessionData1;
        sessions_ = new Session[](MAX_SESSIONS);
        for (uint256 i_; i_ < MAX_SESSIONS; ++i_) {
            sessions_[i_] = _loadSession(data0_, data1_, i_);
        }
    }

    /// @inheritdoc IFluidUsEquityMarketHours
    function getCurrentSessionType() external view returns (uint256 sessionType_) {
        return getSessionType(block.timestamp);
    }

    /// @inheritdoc IFluidUsEquityMarketHours
    function getSessionType(uint256 timestamp_) public view returns (uint256 sessionType_) {
        (sessionType_, , , ) = _resolve(timestamp_, false);
    }

    /// @inheritdoc IFluidUsEquityMarketHours
    function getLatestRegularHoursWindow(
        uint256 timestamp_
    ) external view returns (uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) {
        (, latestRegularHoursStart_, latestRegularHoursEnd_) = getSessionInfo(timestamp_);
    }

    /// @inheritdoc IFluidUsEquityMarketHours
    function getSessionInfo(
        uint256 timestamp_
    ) public view returns (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) {
        (sessionType_, latestRegularHoursStart_, latestRegularHoursEnd_, ) = _resolve(timestamp_, true);
    }

    /// @inheritdoc IFluidUsEquityMarketHours
    function getCurrentSession()
        external
        returns (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_)
    {
        uint256 data0_ = _sessionData0;
        uint256 index_;
        (sessionType_, latestRegularHoursStart_, latestRegularHoursEnd_, index_) = _resolve(block.timestamp, true);

        if (index_ != _currentIndex(data0_)) {
            _sessionData0 = _setCurrentIndex(data0_, index_);
        }
    }

    /// @dev Walks down from `fromIndex_` for the latest REGULAR with `sessionStart <= timestamp_`.
    ///      Returns `(data1_, data1Loaded_, latestRegularHoursStart_, latestRegularHoursEnd_)`;
    ///      `latestRegularHoursStart_ == 0` means none found.
    function _regularWindowBack(
        uint256 timestamp_,
        uint256 data0_,
        uint256 data1_,
        bool data1Loaded_,
        uint256 fromIndex_
    ) internal view returns (uint256, bool, uint32, uint32) {
        while (true) {
            Session memory s_;
            (data1_, data1Loaded_, s_) = _getSession(data0_, data1_, data1Loaded_, fromIndex_);
            if (s_.sessionStart != 0 && s_.sessionType == SESSION_TYPE_REGULAR && s_.sessionStart <= timestamp_) {
                return (data1_, data1Loaded_, s_.sessionStart, _regularSessionEnd(s_));
            }
            if (fromIndex_ == 0) break;
            unchecked {
                --fromIndex_;
            }
        }
        return (data1_, data1Loaded_, 0, 0);
    }

    /// @dev Regular-hours end (exclusive) for a packed REGULAR entry. Durations ≤ 8191.
    function _regularSessionEnd(Session memory s_) internal pure returns (uint32) {
        unchecked {
            return uint32(uint256(s_.sessionStart) + uint256(s_.durationMinutes) * 1 minutes);
        }
    }

    /// @dev Classifies `timestamp_` inside one entry. `sessionTypeIdentified_ == false` means before start or after entry end.
    function _getSessionTypeWithinSession(
        uint256 sessionStart_,
        uint256 durationMinutes_,
        uint256 extendedDurationMinutes_,
        uint256 storedSessionType_,
        uint256 timestamp_
    ) internal pure returns (uint256 sessionType_, bool sessionTypeIdentified_) {
        // Durations are ≤ 8191 (13-bit packed); products and sums cannot overflow uint256.
        uint256 sessionEnd_;
        uint256 entryEnd_;
        unchecked {
            sessionEnd_ = sessionStart_ + durationMinutes_ * 1 minutes;
            entryEnd_ = sessionEnd_ + extendedDurationMinutes_ * 1 minutes;
        }

        if (timestamp_ < sessionStart_ || timestamp_ >= entryEnd_) {
            return (0, false);
        }
        if (timestamp_ < sessionEnd_) {
            sessionType_ = storedSessionType_ == SESSION_TYPE_REGULAR ? SESSION_TYPE_REGULAR : SESSION_TYPE_HOLIDAY;
        } else {
            sessionType_ = SESSION_TYPE_EXTENDED;
        }
        sessionTypeIdentified_ = true;
    }

    /// @dev Bidirectional walk from stored `currentIndex`.
    ///      Sloads `_sessionData1` only when a session in slots 4..7 is read.
    ///      When `needRegularWindow_`: covering REGULAR entry supplies the window directly;
    ///      HOLIDAY / UNKNOWN resolve via `_regularWindowBack`.
    ///      `latestRegularHoursStart_ == 0` means none found (also before-coverage / empty).
    function _resolve(
        uint256 timestamp_,
        bool needRegularWindow_
    )
        internal
        view
        returns (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_, uint256 index_)
    {
        uint256 data0_ = _sessionData0;
        uint256 data1_;
        bool data1Loaded_;

        index_ = _currentIndex(data0_);

        while (true) {
            Session memory s_;
            (data1_, data1Loaded_, s_) = _getSession(data0_, data1_, data1Loaded_, index_);

            if (s_.sessionStart == 0) {
                // Unused slot → past end of schedule (or empty).
                if (index_ > 0) {
                    unchecked {
                        --index_; // keep cursor on last valid entry
                    }
                    if (needRegularWindow_) {
                        (data1_, data1Loaded_, latestRegularHoursStart_, latestRegularHoursEnd_) = _regularWindowBack(
                            timestamp_,
                            data0_,
                            data1_,
                            data1Loaded_,
                            index_
                        );
                    }
                }
                return (SESSION_TYPE_UNKNOWN, latestRegularHoursStart_, latestRegularHoursEnd_, index_);
            }

            if (timestamp_ < s_.sessionStart) {
                // Started at a later cursor — walk back toward the covering entry.
                if (index_ == 0) {
                    return (SESSION_TYPE_UNKNOWN, 0, 0, 0); // before schedule coverage
                }
                unchecked {
                    --index_;
                }
                continue;
            }

            bool sessionTypeIdentified_;
            (sessionType_, sessionTypeIdentified_) = _getSessionTypeWithinSession(
                s_.sessionStart,
                s_.durationMinutes,
                s_.extendedDurationMinutes,
                s_.sessionType,
                timestamp_
            );
            if (sessionTypeIdentified_) {
                if (needRegularWindow_) {
                    if (s_.sessionType == SESSION_TYPE_REGULAR) {
                        // Covering entry is the latest REGULAR (in cash hours or its EXTENDED tail).
                        latestRegularHoursStart_ = s_.sessionStart;
                        latestRegularHoursEnd_ = _regularSessionEnd(s_);
                    } else {
                        // HOLIDAY entry (main or Monday-pre EXTENDED) — walk back to prior REGULAR.
                        (data1_, data1Loaded_, latestRegularHoursStart_, latestRegularHoursEnd_) = _regularWindowBack(
                            timestamp_,
                            data0_,
                            data1_,
                            data1Loaded_,
                            index_
                        );
                    }
                }
                return (sessionType_, latestRegularHoursStart_, latestRegularHoursEnd_, index_);
            }

            // After this entry — walk forward (or UNKNOWN if already on the last slot).
            if (index_ + 1 >= MAX_SESSIONS) {
                if (needRegularWindow_) {
                    (data1_, data1Loaded_, latestRegularHoursStart_, latestRegularHoursEnd_) = _regularWindowBack(
                        timestamp_,
                        data0_,
                        data1_,
                        data1Loaded_,
                        index_
                    );
                }
                return (SESSION_TYPE_UNKNOWN, latestRegularHoursStart_, latestRegularHoursEnd_, index_);
            }
            unchecked {
                ++index_;
            }
        }
    }
}
