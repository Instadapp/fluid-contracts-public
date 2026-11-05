// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";

/// @dev NYSE calendar helpers + week schedule builder for integration tests (Jul 2025 – Jul 2026).
library UsEquityMarketHoursCalendarLib {
    uint16 internal constant REGULAR_MINUTES = 390; // 09:30–16:00 ET
    uint16 internal constant EARLY_CLOSE_MINUTES = 210; // 09:30–13:00 ET
    uint16 internal constant POST_MINUTES = 240; // 16:00–20:00 ET
    uint16 internal constant PRE_MINUTES = 330; // 04:00–09:30 ET
    uint16 internal constant WEEKDAY_EXTENDED_MINUTES = 1050; // 16:00 → next 09:30

    uint8 internal constant SESSION_TYPE_REGULAR = 1;
    uint8 internal constant SESSION_TYPE_HOLIDAY = 3;

    uint256 internal constant MAX_SESSIONS = 8;

    /// @dev Mirrors `FluidUsEquityMarketHours.MIN_SCHEDULE_DURATION_MINUTES`, which is internal.
    uint256 internal constant MIN_SCHEDULE_DURATION_MINUTES = 7 days / 1 minutes;

    /// @dev Full NYSE holidays in test span (packed YYYYMMDD).
    function fullHolidays() internal pure returns (uint32[20] memory) {
        return [
            20250101, // New Year's
            20250120, // MLK
            20250217, // Presidents'
            20250418, // Good Friday
            20250526, // Memorial
            20250619, // Juneteenth
            20250704, // Independence Day
            20250901, // Labor
            20251127, // Thanksgiving
            20251225, // Christmas
            20260101, // New Year's
            20260119, // MLK
            20260216, // Presidents'
            20260403, // Good Friday
            20260525, // Memorial
            20260619, // Juneteenth
            20260703, // Independence Day (observed; Jul 4 is Saturday)
            20260907, // Labor
            20261126, // Thanksgiving
            20261225 // Christmas
        ];
    }

    /// @dev Early-close days (13:00 ET) in test span (official NYSE cash equity calendar).
    function earlyCloses() internal pure returns (uint32[5] memory) {
        return [
            20250703, // day before Independence Day
            20251128, // Black Friday
            20251224, // Christmas Eve
            20261127, // Black Friday
            20261224 // Christmas Eve
            // Note: 2026 has no early close before Independence Day (Jul 3 is full holiday observed).
        ];
    }

    struct Date {
        uint16 year;
        uint8 month;
        uint8 day;
        uint8 weekday; // 0 = Mon … 6 = Sun (ISO)
    }

    function isFullHoliday(uint16 year_, uint8 month_, uint8 day_) internal pure returns (bool) {
        uint32 packed_ = _packDate(year_, month_, day_);
        uint32[20] memory holidays_ = fullHolidays();
        for (uint256 i_; i_ < holidays_.length; ++i_) {
            if (holidays_[i_] == packed_) return true;
        }
        return false;
    }

    function isEarlyClose(uint16 year_, uint8 month_, uint8 day_) internal pure returns (bool) {
        uint32 packed_ = _packDate(year_, month_, day_);
        uint32[5] memory earlys_ = earlyCloses();
        for (uint256 i_; i_ < earlys_.length; ++i_) {
            if (earlys_[i_] == packed_) return true;
        }
        return false;
    }

    function isTradingDay(uint16 year_, uint8 month_, uint8 day_) internal pure returns (bool) {
        Date memory d_ = dateFromYmd(year_, month_, day_);
        if (d_.weekday >= 5) return false;
        if (isFullHoliday(year_, month_, day_)) return false;
        return true;
    }

    /// @dev Civil ET → unix (handles DST for 2025–2026 span).
    function etToUnix(
        uint16 year_,
        uint8 month_,
        uint8 day_,
        uint8 hour_,
        uint8 minute_
    ) internal pure returns (uint32) {
        uint256 days_ = _daysFromCivil(year_, month_, day_);
        int256 utcOffset_ = _etUtcOffsetForYmd(year_, month_, day_);
        int256 ts_ = int256(days_ * 86400 + uint256(hour_) * 3600 + uint256(minute_) * 60) + utcOffset_;
        return uint32(uint256(ts_));
    }

    function marketOpen(uint16 year_, uint8 month_, uint8 day_) internal pure returns (uint32) {
        return etToUnix(year_, month_, day_, 9, 30);
    }

    function mondayOpenOfWeek(uint16 year_, uint8 month_, uint8 day_) internal pure returns (uint32) {
        Date memory d_ = dateFromYmd(year_, month_, day_);
        uint256 daysBack_ = d_.weekday;
        uint256 days_ = _daysFromCivil(year_, month_, day_) - daysBack_;
        (uint16 y_, uint8 m_, uint8 dOut_) = _civilFromDays(days_);
        return marketOpen(y_, m_, dOut_);
    }

    /// @dev `dayOffset_` = 0 Mon … 4 Fri; preserves ET wall clock across DST.
    function weekdayOpenFromMonday(uint32 monOpen_, uint8 dayOffset_) internal pure returns (uint32) {
        Date memory d_ = dateFromTimestamp(monOpen_);
        uint256 days_ = _daysFromCivil(d_.year, d_.month, d_.day) + dayOffset_;
        (uint16 y_, uint8 m_, uint8 day_) = _civilFromDays(days_);
        return marketOpen(y_, m_, day_);
    }

    function dateFromTimestamp(uint32 ts_) internal pure returns (Date memory) {
        int256 utcOffset_ = _etUtcOffsetForUnix(ts_);
        uint256 civil_ = uint256(int256(uint256(ts_)) - utcOffset_);
        uint256 days_ = civil_ / 86400;
        (uint16 y_, uint8 m_, uint8 d_) = _civilFromDays(days_);
        uint8 wd_ = uint8((_daysFromCivil(y_, m_, d_) + 3) % 7); // 0=Mon
        return Date({ year: y_, month: m_, day: d_, weekday: wd_ });
    }

    function dateFromYmd(uint16 year_, uint8 month_, uint8 day_) internal pure returns (Date memory) {
        uint8 wd_ = uint8((_daysFromCivil(year_, month_, day_) + 3) % 7);
        return Date({ year: year_, month: month_, day: day_, weekday: wd_ });
    }

    function nextTradingDayOpen(uint16 year_, uint8 month_, uint8 day_) internal pure returns (uint32) {
        uint256 days_ = _daysFromCivil(year_, month_, day_) + 1;
        while (true) {
            (uint16 y_, uint8 m_, uint8 d_) = _civilFromDays(days_);
            if (isTradingDay(y_, m_, d_)) return marketOpen(y_, m_, d_);
            ++days_;
        }
    }

    /// @dev Mon–Fri (+ weekend / holiday HOLIDAY bridges) for calendar week containing `weekStartOpen_`.
    ///      `weekStartOpen_` is normally that week’s Monday open; after a Monday holiday Saturday-rewrite
    ///      it may be the first trading open (e.g. Tuesday).
    ///      If the next session day is a trading day: REGULAR + overnight EXTENDED until next open.
    ///      If the next day is a holiday or weekend: REGULAR + post only, then HOLIDAY from after post
    ///      through the next trading day’s pre-market (no overnight EXTENDED into a closed day).
    function buildWeekWithWeekend(uint32 weekStartOpen_) internal pure returns (Structs.Session[] memory sessions_) {
        Structs.Session[MAX_SESSIONS] memory buf_;
        uint256 count_;
        uint32 cursor_ = weekStartOpen_;
        Date memory startD_ = dateFromTimestamp(weekStartOpen_);
        uint32 weekMon_ = mondayOpenOfWeek(startD_.year, startD_.month, startD_.day);
        uint32 nextWeekMon_ = weekdayOpenFromMonday(weekMon_, 7);

        for (uint256 step_; step_ < 5; ++step_) {
            if (cursor_ >= nextWeekMon_) break;

            Date memory d_ = dateFromTimestamp(cursor_);

            // Mid-week / Monday holiday fallback if cursor lands on a closed cash open.
            // Prefer arriving here via a prior day’s post → HOLIDAY bridge (see below).
            if (isFullHoliday(d_.year, d_.month, d_.day)) {
                uint32 nextOpen_ = nextTradingDayOpen(d_.year, d_.month, d_.day);
                buf_[count_++] = _holidayThroughPre(cursor_, nextOpen_);
                cursor_ = nextOpen_;
                continue;
            }

            uint16 regDur_ = isEarlyClose(d_.year, d_.month, d_.day) ? EARLY_CLOSE_MINUTES : REGULAR_MINUTES;
            uint32 regEnd_ = cursor_ + uint32(regDur_) * 60;

            if (_followedByClosedBridge(d_.year, d_.month, d_.day)) {
                // End like Friday: cash + post, then HOLIDAY covers overnight / holiday / weekend
                // until the next trading open’s pre-market.
                buf_[count_++] = Structs.Session({
                    sessionStart: cursor_,
                    durationMinutes: regDur_,
                    extendedDurationMinutes: POST_MINUTES,
                    sessionType: SESSION_TYPE_REGULAR
                });
                uint32 holStart_ = regEnd_ + uint32(POST_MINUTES) * 60;
                uint32 nextOpen_ = nextTradingDayOpen(d_.year, d_.month, d_.day);
                buf_[count_++] = _holidayThroughPre(holStart_, nextOpen_);
                cursor_ = nextOpen_;
                continue;
            }

            // Next weekday is a trading day — overnight EXTENDED until that open.
            uint32 nextOpen_ = nextTradingDayOpen(d_.year, d_.month, d_.day);
            buf_[count_++] = Structs.Session({
                sessionStart: cursor_,
                durationMinutes: regDur_,
                extendedDurationMinutes: uint16((nextOpen_ - regEnd_) / 60),
                sessionType: SESSION_TYPE_REGULAR
            });
            cursor_ = nextOpen_;
        }

        sessions_ = new Structs.Session[](count_);
        for (uint256 i_; i_ < count_; ++i_) {
            sessions_[i_] = buf_[i_];
        }
    }

    /// @dev True when after this cash day we bridge with HOLIDAY (weekend or next weekday is a full holiday).
    function _followedByClosedBridge(uint16 year_, uint8 month_, uint8 day_) private pure returns (bool) {
        Date memory d_ = dateFromYmd(year_, month_, day_);
        if (d_.weekday == 4) return true; // Friday → weekend HOLIDAY
        uint256 days_ = _daysFromCivil(year_, month_, day_) + 1;
        (uint16 y_, uint8 m_, uint8 dNext_) = _civilFromDays(days_);
        return isFullHoliday(y_, m_, dNext_);
    }

    /// @dev Saturday-style rewrite: anchor REGULAR + live HOLIDAY + next calendar week (≤ 8).
    ///      If `nextMonOpen_` is a holiday, the HOLIDAY bridge runs to the next trading open and the
    ///      following week is built from that open (avoids overlap/gap with a second Monday HOLIDAY).
    function buildSaturdayRewrite(uint32 nextMonOpen_) internal pure returns (Structs.Session[] memory sessions_) {
        Date memory nextMon_ = dateFromTimestamp(nextMonOpen_);
        // Step by calendar days, not seconds — a raw `- 3 days` lands an hour off across a DST boundary.
        (uint16 fy_, uint8 fm_, uint8 fd_) = _civilFromDays(
            _daysFromCivil(nextMon_.year, nextMon_.month, nextMon_.day) - 3
        );
        uint32 friOpen_ = marketOpen(fy_, fm_, fd_);

        uint32 weekStart_ = nextMonOpen_;
        if (isFullHoliday(nextMon_.year, nextMon_.month, nextMon_.day)) {
            weekStart_ = nextTradingDayOpen(nextMon_.year, nextMon_.month, nextMon_.day);
        }

        Structs.Session[] memory nextWeek_ = buildWeekWithWeekend(weekStart_);
        Structs.Session[] memory prevTail_ = _prevWeekTail(friOpen_, weekStart_);

        sessions_ = new Structs.Session[](prevTail_.length + nextWeek_.length);
        for (uint256 i_; i_ < prevTail_.length; ++i_) {
            sessions_[i_] = prevTail_[i_];
        }
        for (uint256 j_; j_ < nextWeek_.length; ++j_) {
            sessions_[prevTail_.length + j_] = nextWeek_[j_];
        }
    }

    /// @dev Schedule covering `tip_`, and the instant it has to be written at. `updateWeekSessions`
    ///      wants both an entry containing `now` and a REGULAR that has already started, and on a
    ///      holiday Monday the first REGULAR is Tuesday’s.
    ///      Both builders bridge a holiday Monday themselves and derive the rest of the week from the
    ///      Monday open, so neither may be handed an open past it.
    function scheduleForTip(uint32 tip_) internal pure returns (Structs.Session[] memory sessions_, uint32 writeAt_) {
        Date memory d_ = dateFromTimestamp(tip_);
        uint32 monOpen_ = mondayOpenOfWeek(d_.year, d_.month, d_.day);

        if (d_.weekday >= 5) {
            // Re-derive through `marketOpen` rather than adding 7 days of seconds: a DST boundary in
            // between would otherwise land the open an hour off.
            Date memory nm_ = dateFromTimestamp(uint32(uint256(monOpen_) + 7 days));
            return (buildSaturdayRewrite(marketOpen(nm_.year, nm_.month, nm_.day)), tip_);
        }

        Date memory md_ = dateFromTimestamp(monOpen_);
        uint32 firstRegularOpen_ = isFullHoliday(md_.year, md_.month, md_.day)
            ? nextTradingDayOpen(md_.year, md_.month, md_.day)
            : monOpen_;

        sessions_ = buildWeekWithWeekend(monOpen_);
        // A Monday-to-Monday ET week is 7 days of wall clock but only 167 hours across spring
        // forward, which is under the contract's minimum. Reach back to the prior Friday for those.
        if (_totalMinutes(sessions_) < MIN_SCHEDULE_DURATION_MINUTES) {
            sessions_ = buildSaturdayRewrite(monOpen_);
        }

        return (sessions_, uint32(uint256(firstRegularOpen_) + 1 hours));
    }

    function _totalMinutes(Structs.Session[] memory sessions_) private pure returns (uint256 total_) {
        for (uint256 i_; i_ < sessions_.length; ++i_) {
            total_ += uint256(sessions_[i_].durationMinutes) + sessions_[i_].extendedDurationMinutes;
        }
    }

    /// @dev Last trading REGULAR before `weekStartOpen_` (+ post) plus HOLIDAY through that open’s pre.
    function _prevWeekTail(
        uint32 friOpen_,
        uint32 weekStartOpen_
    ) private pure returns (Structs.Session[] memory tail_) {
        Date memory fri_ = dateFromTimestamp(friOpen_);

        if (isFullHoliday(fri_.year, fri_.month, fri_.day)) {
            // Friday holiday — anchor is previous trading day with post, then HOLIDAY from after post.
            Date memory thu_ = dateFromTimestamp(friOpen_ - 1 days);
            uint32 thuOpen_ = marketOpen(thu_.year, thu_.month, thu_.day);
            uint16 regDur_ = isEarlyClose(thu_.year, thu_.month, thu_.day) ? EARLY_CLOSE_MINUTES : REGULAR_MINUTES;
            uint32 regEnd_ = thuOpen_ + uint32(regDur_) * 60;
            uint32 holStart_ = regEnd_ + uint32(POST_MINUTES) * 60;

            tail_ = new Structs.Session[](2);
            tail_[0] = Structs.Session({
                sessionStart: thuOpen_,
                durationMinutes: regDur_,
                extendedDurationMinutes: POST_MINUTES,
                sessionType: SESSION_TYPE_REGULAR
            });
            tail_[1] = _holidayThroughPre(holStart_, weekStartOpen_);
            return tail_;
        }

        uint16 regDur_ = isEarlyClose(fri_.year, fri_.month, fri_.day) ? EARLY_CLOSE_MINUTES : REGULAR_MINUTES;
        uint32 regEnd_ = friOpen_ + uint32(regDur_) * 60;
        tail_ = new Structs.Session[](2);
        tail_[0] = Structs.Session({
            sessionStart: friOpen_,
            durationMinutes: regDur_,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: SESSION_TYPE_REGULAR
        });
        tail_[1] = _holidayThroughPre(regEnd_ + uint32(POST_MINUTES) * 60, weekStartOpen_);
    }

    function _holidayThroughPre(
        uint32 holStart_,
        uint32 nextTradingOpen_
    ) private pure returns (Structs.Session memory) {
        uint32 preStart_ = nextTradingOpen_ - uint32(PRE_MINUTES) * 60;
        return
            Structs.Session({
                sessionStart: holStart_,
                durationMinutes: uint16((preStart_ - holStart_) / 60),
                extendedDurationMinutes: PRE_MINUTES,
                sessionType: SESSION_TYPE_HOLIDAY
            });
    }

    function _packDate(uint16 year_, uint8 month_, uint8 day_) private pure returns (uint32) {
        return uint32(year_) * 10000 + uint32(month_) * 100 + uint32(day_);
    }

    function _etUtcOffsetForUnix(uint32 ts_) private pure returns (int256) {
        // Approximate ET date from UTC, then refine (sufficient for 2025–2026 span).
        uint256 days_ = uint256(ts_) / 86400;
        (uint16 y_, uint8 m_, uint8 d_) = _civilFromDays(days_);
        return _etUtcOffsetForYmd(y_, m_, d_);
    }

    /// @dev Seconds to add to local ET civil time to obtain UTC (EDT=+14400, EST=+18000).
    function _etUtcOffsetForYmd(uint16 year_, uint8 month_, uint8 day_) private pure returns (int256) {
        int256 est_ = 5 * 3600;
        int256 edt_ = 4 * 3600;
        if (year_ == 2025) {
            if (month_ < 3 || (month_ == 3 && day_ < 9)) return est_;
            if (month_ < 11 || (month_ == 11 && day_ < 2)) return edt_;
            return est_;
        }
        if (year_ == 2026) {
            if (month_ < 3 || (month_ == 3 && day_ < 8)) return est_;
            if (month_ < 11 || (month_ == 11 && day_ < 1)) return edt_;
            return est_;
        }
        return est_;
    }

    function _daysFromCivil(uint16 year_, uint8 month_, uint8 day_) private pure returns (uint256) {
        int256 y_ = int256(uint256(year_));
        int256 m_ = int256(uint256(month_));
        y_ -= m_ <= 2 ? int256(1) : int256(0);
        int256 era_ = y_ >= 0 ? y_ / 400 : (y_ - 399) / 400;
        uint256 yoe_ = uint256(y_ - era_ * 400);
        uint256 doy_ = (153 * uint256(m_ + (m_ > 2 ? int256(-3) : int256(9))) + 2) / 5 + uint256(day_) - 1;
        uint256 doe_ = yoe_ * 365 + yoe_ / 4 - yoe_ / 100 + doy_;
        return uint256(era_ * 146097 + int256(doe_) - 719468);
    }

    function _civilFromDays(uint256 days_) private pure returns (uint16 year_, uint8 month_, uint8 day_) {
        int256 z_ = int256(days_) + 719468;
        int256 era_ = (z_ >= 0 ? z_ : z_ - 146096) / 146097;
        uint256 doe_ = uint256(z_ - era_ * 146097);
        uint256 yoe_ = (doe_ - doe_ / 1460 + doe_ / 36524 - doe_ / 146096) / 365;
        uint256 y_ = yoe_ + uint256(era_) * 400;
        uint256 doy_ = doe_ - (yoe_ * 365 + yoe_ / 4 - yoe_ / 100);
        uint256 mp_ = (5 * doy_ + 2) / 153;
        day_ = uint8(doy_ - (153 * mp_ + 2) / 5 + 1);
        month_ = uint8(mp_ < 10 ? mp_ + 3 : mp_ - 9);
        year_ = uint16(y_ + (mp_ < 10 ? 0 : 1));
    }
}
