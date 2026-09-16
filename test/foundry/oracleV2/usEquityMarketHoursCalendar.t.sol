// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

/// @dev Calendar-year integration tests for FluidUsEquityMarketHours (Jul 2025 – Jul 2026).
contract UsEquityMarketHoursCalendarTest is Test {
    using Cal for *;

    FluidUsEquityMarketHours marketHours;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    /// @dev Plain schedule writer (class 1) — subject to the pinned-session rule.
    address constant WRITER = address(0xBEEF);

    /// @dev Pranked by the write helpers; class 2 by default since most tests jump between unrelated weeks.
    address scheduleWriter = AUTH;

    uint8 constant sessionTypeUnknown = 0;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

    uint256 assertionCount_;

    function setUp() public {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(GOVERNANCE)))
        );
        FluidUsEquityMarketHours impl_ = new FluidUsEquityMarketHours(LIQUIDITY);
        FluidUsEquityMarketHoursProxy proxy_ = new FluidUsEquityMarketHoursProxy(
            address(impl_),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        marketHours = FluidUsEquityMarketHours(address(proxy_));
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 2);
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(WRITER, 1);
    }

    // -------- helpers --------

    function _assertSession(
        uint32 ts_,
        uint8 expectedType_,
        bool expectRegularWindow_,
        uint32 expectedRegStart_,
        uint32 expectedRegEnd_
    ) internal {
        ++assertionCount_;
        (uint256 type_, uint32 regStart_, uint32 regEnd_) = marketHours.getSessionInfo(ts_);
        assertEq(type_, expectedType_, _tsLabel(ts_));
        if (expectRegularWindow_) {
            assertTrue(regStart_ != 0, _tsLabel(ts_));
            assertEq(regStart_, expectedRegStart_, _tsLabel(ts_));
            assertEq(regEnd_, expectedRegEnd_, _tsLabel(ts_));
        }
    }

    function _assertLatestRegular(uint32 ts_, uint32 expStart_, uint32 expEnd_) internal {
        ++assertionCount_;
        (uint32 regStart_, uint32 regEnd_) = marketHours.getLatestRegularHoursWindow(ts_);
        assertEq(regStart_, expStart_, _tsLabel(ts_));
        assertEq(regEnd_, expEnd_, _tsLabel(ts_));
    }

    function _tsLabel(uint32 ts_) internal pure returns (string memory) {
        Cal.Date memory d_ = Cal.dateFromTimestamp(ts_);
        return
            string(
                abi.encodePacked(
                    "ts=",
                    vm.toString(ts_),
                    " ",
                    vm.toString(d_.year),
                    "-",
                    vm.toString(d_.month),
                    "-",
                    vm.toString(d_.day)
                )
            );
    }

    function _writeWeek(uint32 monOpen_) internal {
        vm.warp(uint256(monOpen_) + 1 hours);
        vm.prank(scheduleWriter);
        marketHours.updateWeekSessions(Cal.buildWeekWithWeekend(monOpen_));
    }

    function _writeSaturdayRewrite(uint32 nextMonOpen_) internal {
        vm.warp(uint256(nextMonOpen_) - 2 days + 12 hours); // Saturday noon
        vm.prank(scheduleWriter);
        marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(nextMonOpen_));
    }

    function _regularEnd(uint32 open_) internal pure returns (uint32) {
        return open_ + uint32(Cal.REGULAR_MINUTES) * 60;
    }

    function _earlyEnd(uint32 open_) internal pure returns (uint32) {
        return open_ + uint32(Cal.EARLY_CLOSE_MINUTES) * 60;
    }

    function _sessionEnd(uint32 open_) internal pure returns (uint32) {
        Cal.Date memory d_ = Cal.dateFromTimestamp(open_);
        if (Cal.isEarlyClose(d_.year, d_.month, d_.day)) return _earlyEnd(open_);
        return _regularEnd(open_);
    }

    function _weekAnchorOpen(uint32 monOpen_) internal pure returns (uint32) {
        for (uint8 offset_ = 4; offset_ > 0; --offset_) {
            uint32 open_ = Cal.weekdayOpenFromMonday(monOpen_, offset_);
            Cal.Date memory d_ = Cal.dateFromTimestamp(open_);
            if (!Cal.isFullHoliday(d_.year, d_.month, d_.day)) return open_;
        }
        return monOpen_;
    }

    function _sampleNormalWeek(uint32 monOpen_) internal {
        Cal.Date memory monDate_ = Cal.dateFromTimestamp(monOpen_);
        if (Cal.isFullHoliday(monDate_.year, monDate_.month, monDate_.day)) {
            // Monday holiday week: Tue–Fri samples only.
            uint32 tueOpen_ = Cal.nextTradingDayOpen(monDate_.year, monDate_.month, monDate_.day);
            uint32 wedOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 2);
            uint32 thuOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 3);
            uint32 friOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 4);

            _assertSession(tueOpen_ + 2 hours, sessionTypeRegular, true, tueOpen_, _sessionEnd(tueOpen_));
            _assertSession(wedOpen_ + 1 hours, sessionTypeRegular, true, wedOpen_, _sessionEnd(wedOpen_));
            Cal.Date memory thuMon_ = Cal.dateFromTimestamp(thuOpen_);
            if (!Cal.isFullHoliday(thuMon_.year, thuMon_.month, thuMon_.day)) {
                _assertSession(thuOpen_ + 3 hours, sessionTypeRegular, true, thuOpen_, _sessionEnd(thuOpen_));
            }
            Cal.Date memory friMon_ = Cal.dateFromTimestamp(friOpen_);
            if (!Cal.isFullHoliday(friMon_.year, friMon_.month, friMon_.day)) {
                _assertSession(friOpen_ + 2 hours, sessionTypeRegular, true, friOpen_, _sessionEnd(friOpen_));
                if (!Cal.isEarlyClose(friMon_.year, friMon_.month, friMon_.day)) {
                    _assertSession(friOpen_ + 11 hours, sessionTypeHoliday, true, friOpen_, _sessionEnd(friOpen_));
                }
            }
            return;
        }

        uint32 tueOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 1);
        uint32 wedOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 2);
        uint32 thuOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 3);
        uint32 friOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 4);
        uint32 anchorOpen_ = _weekAnchorOpen(monOpen_);
        uint32 nextMonOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 7);

        // Pre-market of the following Monday: EXTENDED only if that Monday is a trading day.
        // If it is a holiday (e.g. Labor Day), the weekend HOLIDAY bridge already covers it.
        Cal.Date memory nextMonD_ = Cal.dateFromTimestamp(nextMonOpen_);
        if (Cal.isFullHoliday(nextMonD_.year, nextMonD_.month, nextMonD_.day)) {
            _assertSession(nextMonOpen_ - 2 hours, sessionTypeHoliday, true, anchorOpen_, _sessionEnd(anchorOpen_));
        } else {
            _assertSession(nextMonOpen_ - 2 hours, sessionTypeExtended, true, anchorOpen_, _sessionEnd(anchorOpen_));
        }

        // Regular hours samples
        _assertSession(monOpen_ + 2 hours, sessionTypeRegular, true, monOpen_, _sessionEnd(monOpen_));
        _assertSession(tueOpen_ + 3 hours, sessionTypeRegular, true, tueOpen_, _sessionEnd(tueOpen_));
        _assertSession(wedOpen_ + 1 hours, sessionTypeRegular, true, wedOpen_, _sessionEnd(wedOpen_));

        Cal.Date memory thuD_ = Cal.dateFromTimestamp(thuOpen_);
        if (!Cal.isFullHoliday(thuD_.year, thuD_.month, thuD_.day)) {
            _assertSession(thuOpen_ + 2 hours, sessionTypeRegular, true, thuOpen_, _sessionEnd(thuOpen_));
        }

        // Post regular / overnight extended
        _assertSession(monOpen_ + 7 hours, sessionTypeExtended, true, monOpen_, _sessionEnd(monOpen_));
        _assertSession(tueOpen_ - 2 hours, sessionTypeExtended, true, monOpen_, _sessionEnd(monOpen_));

        Cal.Date memory friD_ = Cal.dateFromTimestamp(friOpen_);
        if (Cal.isFullHoliday(friD_.year, friD_.month, friD_.day)) {
            _assertSession(friOpen_ + 2 hours, sessionTypeHoliday, true, anchorOpen_, _sessionEnd(anchorOpen_));
            _assertSession(friOpen_ + 30 hours, sessionTypeHoliday, true, anchorOpen_, _sessionEnd(anchorOpen_));
        } else {
            _assertSession(friOpen_ + 2 hours, sessionTypeRegular, true, friOpen_, _sessionEnd(friOpen_));
            if (Cal.isEarlyClose(friD_.year, friD_.month, friD_.day)) {
                _assertSession(friOpen_ + 4 hours, sessionTypeExtended, true, friOpen_, _sessionEnd(friOpen_));
            } else {
                _assertSession(friOpen_ + 7 hours, sessionTypeExtended, true, friOpen_, _sessionEnd(friOpen_));
                _assertSession(friOpen_ + 11 hours, sessionTypeHoliday, true, anchorOpen_, _sessionEnd(anchorOpen_));
                _assertSession(friOpen_ + 36 hours, sessionTypeHoliday, true, anchorOpen_, _sessionEnd(anchorOpen_));
            }
        }
    }

    // -------- ET conversion sanity --------

    function test_EtConversionMatchesKnownTimestamps() public pure {
        assertEq(Cal.etToUnix(2025, 7, 3, 9, 30), 1751549400);
        assertEq(Cal.etToUnix(2025, 7, 3, 13, 0), 1751562000);
        assertEq(Cal.etToUnix(2025, 7, 7, 9, 30), 1751895000);
        assertEq(Cal.etToUnix(2025, 7, 7, 4, 0), 1751875200);
    }

    // -------- major scenario tests --------

    function test_NormalWeekJanuary2026() public {
        uint32 mon_ = Cal.marketOpen(2026, 1, 5);
        _writeWeek(mon_);
        _sampleNormalWeek(mon_);
    }

    function test_IndependenceDayWeek2025() public {
        uint32 mon_ = Cal.marketOpen(2025, 6, 30);
        _writeWeek(mon_);

        uint32 thuOpen_ = Cal.marketOpen(2025, 7, 3);
        uint32 friOpen_ = Cal.marketOpen(2025, 7, 4);
        uint32 monJul7_ = Cal.marketOpen(2025, 7, 7);
        uint32 holStart_ = _earlyEnd(thuOpen_) + uint32(Cal.POST_MINUTES) * 60;

        // Early close Thursday + post EXTENDED, then HOLIDAY (not overnight EXTENDED into Fri 09:30).
        _assertSession(thuOpen_ + 1 hours, sessionTypeRegular, true, thuOpen_, _earlyEnd(thuOpen_));
        _assertSession(thuOpen_ + 4 hours, sessionTypeExtended, true, thuOpen_, _earlyEnd(thuOpen_));
        _assertSession(holStart_ + 1 hours, sessionTypeHoliday, true, thuOpen_, _earlyEnd(thuOpen_));
        _assertSession(friOpen_ - 2 hours, sessionTypeHoliday, true, thuOpen_, _earlyEnd(thuOpen_));

        // Friday full holiday + weekend bridge
        _assertSession(friOpen_ + 2 hours, sessionTypeHoliday, true, thuOpen_, _earlyEnd(thuOpen_));
        _assertSession(friOpen_ + 30 hours, sessionTypeHoliday, true, thuOpen_, _earlyEnd(thuOpen_));

        // Monday pre via holiday extended; Mon Jul 7 REGULAR is outside this week's schedule.
        _assertSession(monJul7_ - 2 hours, sessionTypeExtended, true, thuOpen_, _earlyEnd(thuOpen_));
        _assertSession(monJul7_ + 1 hours, sessionTypeUnknown, false, 0, 0);
        _assertLatestRegular(monJul7_ + 1 hours, thuOpen_, _earlyEnd(thuOpen_));
    }

    function test_MlkDayMonday2025() public {
        uint32 mon_ = Cal.marketOpen(2025, 1, 20); // MLK holiday — Saturday rewrite required
        _writeSaturdayRewrite(mon_);

        uint32 tueOpen_ = Cal.marketOpen(2025, 1, 21);
        uint32 friJan17_ = Cal.marketOpen(2025, 1, 17);

        _assertSession(mon_ + 2 hours, sessionTypeHoliday, true, friJan17_, _regularEnd(friJan17_));
        _assertSession(tueOpen_ - 2 hours, sessionTypeExtended, true, friJan17_, _regularEnd(friJan17_));
        _assertSession(tueOpen_ + 2 hours, sessionTypeRegular, true, tueOpen_, _regularEnd(tueOpen_));
    }

    function test_GoodFriday2025() public {
        uint32 mon_ = Cal.marketOpen(2025, 4, 14);
        _writeWeek(mon_);

        uint32 gf_ = Cal.marketOpen(2025, 4, 18);
        uint32 thuOpen_ = Cal.marketOpen(2025, 4, 17);
        uint32 holStart_ = _regularEnd(thuOpen_) + uint32(Cal.POST_MINUTES) * 60;

        // Thu post then HOLIDAY overnight — not EXTENDED into Fri 09:30.
        _assertSession(holStart_ + 1 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(gf_ - 2 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(gf_ + 3 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(gf_ + 30 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
    }

    function test_ThanksgivingAndBlackFriday2025() public {
        uint32 mon_ = Cal.marketOpen(2025, 11, 24);
        _writeWeek(mon_);

        uint32 thu_ = Cal.marketOpen(2025, 11, 27);
        uint32 fri_ = Cal.marketOpen(2025, 11, 28);
        uint32 wed_ = Cal.marketOpen(2025, 11, 26);
        uint32 holStart_ = _regularEnd(wed_) + uint32(Cal.POST_MINUTES) * 60;

        _assertSession(holStart_ + 1 hours, sessionTypeHoliday, true, wed_, _regularEnd(wed_));
        _assertSession(thu_ - 2 hours, sessionTypeHoliday, true, wed_, _regularEnd(wed_));
        _assertSession(thu_ + 2 hours, sessionTypeHoliday, true, wed_, _regularEnd(wed_));
        _assertSession(fri_ + 1 hours, sessionTypeRegular, true, fri_, _earlyEnd(fri_));
        _assertSession(fri_ + 4 hours, sessionTypeExtended, true, fri_, _earlyEnd(fri_));
    }

    function test_ChristmasEve2025() public {
        uint32 mon_ = Cal.marketOpen(2025, 12, 22);
        _writeWeek(mon_);

        uint32 wed_ = Cal.marketOpen(2025, 12, 24);
        _assertSession(wed_ + 2 hours, sessionTypeRegular, true, wed_, _earlyEnd(wed_));
        _assertSession(wed_ + 5 hours, sessionTypeExtended, true, wed_, _earlyEnd(wed_));
    }

    function test_ObservedIndependenceDay2026() public {
        uint32 mon_ = Cal.marketOpen(2026, 6, 29);
        _writeWeek(mon_);

        // Jul 2 2026 is a normal full session; Jul 3 is Independence Day observed (full holiday).
        // NYSE has no early close ahead of that observed holiday.
        uint32 thuOpen_ = Cal.marketOpen(2026, 7, 2);
        uint32 friHol_ = Cal.marketOpen(2026, 7, 3);
        uint32 monJul6_ = Cal.marketOpen(2026, 7, 6);

        _assertSession(thuOpen_ + 2 hours, sessionTypeRegular, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(thuOpen_ + 7 hours, sessionTypeExtended, true, thuOpen_, _regularEnd(thuOpen_));
        // After Thu post → HOLIDAY (covers overnight into Fri observed holiday).
        _assertSession(
            _regularEnd(thuOpen_) + uint32(Cal.POST_MINUTES) * 60 + 1 hours,
            sessionTypeHoliday,
            true,
            thuOpen_,
            _regularEnd(thuOpen_)
        );
        _assertSession(friHol_ - 2 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(friHol_ + 2 hours, sessionTypeHoliday, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(monJul6_ - 2 hours, sessionTypeExtended, true, thuOpen_, _regularEnd(thuOpen_));
        _assertSession(monJul6_ + 2 hours, sessionTypeUnknown, false, 0, 0);
        _assertLatestRegular(monJul6_ + 2 hours, thuOpen_, _regularEnd(thuOpen_));
    }

    // -------- edge cases --------

    function test_BeforeScheduleUnknown() public {
        uint32 mon_ = Cal.marketOpen(2025, 8, 4);
        _writeWeek(mon_);

        vm.warp(mon_ + 2 days);
        marketHours.getCurrentSession();

        _assertSession(mon_ - 1 hours, sessionTypeUnknown, false, 0, 0);
        (uint32 regStart_, uint32 regEnd_) = marketHours.getLatestRegularHoursWindow(mon_ - 1 hours);
        assertEq(regStart_, 0);
        assertEq(regEnd_, 0);
        ++assertionCount_;
    }

    function test_AfterScheduleUnknownWithLastRegularWindow() public {
        uint32 mon_ = Cal.marketOpen(2025, 8, 4);
        _writeWeek(mon_);

        uint32 nextMon_ = Cal.weekdayOpenFromMonday(mon_, 7);
        uint32 fri_ = Cal.weekdayOpenFromMonday(mon_, 4);

        // Past last entry (weekend ext ends next Mon 09:30)
        _assertSession(nextMon_ + 2 hours, sessionTypeUnknown, false, 0, 0);
        _assertLatestRegular(nextMon_ + 2 hours, fri_, _regularEnd(fri_));
    }

    function test_GetCurrentSessionAdvancesCursor() public {
        uint32 mon_ = Cal.marketOpen(2025, 9, 8);
        _writeWeek(mon_);

        vm.warp(mon_ + 1 days + 2 hours);
        marketHours.getCurrentSession();
        uint8 idx1_ = uint8(marketHours.readFromStorage(bytes32(uint256(1))) & 0xff);

        vm.warp(mon_ + 4 days + 11 hours);
        marketHours.getCurrentSession();
        uint8 idx2_ = uint8(marketHours.readFromStorage(bytes32(uint256(1))) & 0xff);

        assertTrue(idx2_ > idx1_);
    }

    function test_BidirectionalResolveAfterCursorAdvance() public {
        uint32 mon_ = Cal.marketOpen(2025, 10, 6);
        _writeWeek(mon_);

        vm.warp(mon_ + 4 days + 11 hours);
        marketHours.getCurrentSession();

        // Jump back to Monday regular — view must still resolve correctly.
        _assertSession(mon_ + 2 hours, sessionTypeRegular, true, mon_, _regularEnd(mon_));
    }

    function test_SaturdayRewritePreservesFridayRegularWindow() public {
        uint32 mon_ = Cal.marketOpen(2025, 8, 11);
        _writeWeek(mon_);

        uint32 nextMon_ = Cal.weekdayOpenFromMonday(mon_, 7);
        uint32 fri_ = Cal.weekdayOpenFromMonday(mon_, 4);
        _writeSaturdayRewrite(nextMon_);

        vm.warp(nextMon_ - 2 days + 12 hours);
        _assertLatestRegular(uint32(block.timestamp), fri_, _regularEnd(fri_));
        _assertSession(uint32(block.timestamp), sessionTypeHoliday, true, fri_, _regularEnd(fri_));
    }

    function test_SaturdayRewriteIndependenceDayWeek2025() public {
        uint32 monJun30_ = Cal.marketOpen(2025, 6, 30);
        _writeWeek(monJun30_);

        uint32 monJul7_ = Cal.marketOpen(2025, 7, 7);
        _writeSaturdayRewrite(monJul7_);

        uint32 thu_ = Cal.marketOpen(2025, 7, 3);
        vm.warp(Cal.etToUnix(2025, 7, 5, 12, 0));
        _assertLatestRegular(uint32(block.timestamp), thu_, _earlyEnd(thu_));
        _assertSession(uint32(block.timestamp), sessionTypeHoliday, true, thu_, _earlyEnd(thu_));
    }

    function test_SaturdayRewriteChristmasWeek2025() public {
        uint32 monDec15_ = Cal.marketOpen(2025, 12, 15);
        _writeWeek(monDec15_);
        uint32 monDec22_ = Cal.marketOpen(2025, 12, 22);
        _writeSaturdayRewrite(monDec22_);

        uint32 wed_ = Cal.marketOpen(2025, 12, 24);
        _assertSession(wed_ + 1 hours, sessionTypeRegular, true, wed_, _earlyEnd(wed_));
        _assertSession(wed_ + 4 hours, sessionTypeExtended, true, wed_, _earlyEnd(wed_));
    }

    // -------- year walk (Saturday rewrites Jul 2025 – Jul 2026) --------

    function test_CalendarYearSaturdayWalk() public {
        scheduleWriter = WRITER; // a year of weekly rewrites must never need the override class

        uint32 firstMon_ = Cal.marketOpen(2025, 7, 7);
        _writeWeek(firstMon_);

        uint32 monOpen_ = firstMon_;
        uint32 endMon_ = Cal.marketOpen(2026, 7, 13);

        while (monOpen_ <= endMon_) {
            uint32 nextMon_ = Cal.weekdayOpenFromMonday(monOpen_, 7);
            _writeSaturdayRewrite(nextMon_);
            _sampleNormalWeek(nextMon_);
            monOpen_ = nextMon_;
        }

        // Sanity: exercised many assertions
        assertGt(assertionCount_, 500);
    }

    function test_AllFullHolidaysInSpan() public {
        uint32[20] memory hols_ = Cal.fullHolidays();
        for (uint256 i_; i_ < hols_.length; ++i_) {
            uint32 packed_ = hols_[i_];
            uint16 y_ = uint16(packed_ / 10000);
            uint8 m_ = uint8((packed_ / 100) % 100);
            uint8 d_ = uint8(packed_ % 100);

            if (y_ == 2025 && m_ == 7 && d_ == 4) continue; // covered in dedicated test
            if (y_ == 2026 && m_ == 7 && d_ == 3) continue;

            Cal.Date memory dd_ = Cal.dateFromYmd(y_, m_, d_);
            uint32 mon_ = Cal.mondayOpenOfWeek(y_, m_, d_);
            if (dd_.weekday == 0) {
                _writeSaturdayRewrite(mon_);
            } else {
                _writeWeek(mon_);
            }

            _assertSession(Cal.marketOpen(y_, m_, d_) + 2 hours, sessionTypeHoliday, false, 0, 0);
        }
        assertGe(assertionCount_, 18);
    }

    function test_AllEarlyClosesInSpan() public {
        uint32[5] memory earlys_ = Cal.earlyCloses();
        for (uint256 i_; i_ < earlys_.length; ++i_) {
            uint32 packed_ = earlys_[i_];
            uint16 y_ = uint16(packed_ / 10000);
            uint8 m_ = uint8((packed_ / 100) % 100);
            uint8 d_ = uint8(packed_ % 100);
            uint32 open_ = Cal.marketOpen(y_, m_, d_);
            uint32 mon_ = Cal.mondayOpenOfWeek(y_, m_, d_);
            _writeWeek(mon_);
            _assertSession(open_ + 1 hours, sessionTypeRegular, true, open_, _earlyEnd(open_));
            _assertSession(open_ + 4 hours, sessionTypeExtended, true, open_, _earlyEnd(open_));
        }
        assertGe(assertionCount_, 10);
    }

    function test_GetSessionTypeMatchesGetCurrentSession() public {
        uint32 mon_ = Cal.marketOpen(2026, 3, 9);
        _writeWeek(mon_);

        uint32[] memory samples_ = new uint32[](5);
        samples_[0] = mon_ + 2 hours;
        samples_[1] = mon_ + 1 days + 3 hours;
        samples_[2] = mon_ + 2 days + 8 hours;
        samples_[3] = mon_ + 4 days + 6 hours;
        samples_[4] = mon_ + 4 days + 11 hours;

        for (uint256 i_; i_ < samples_.length; ++i_) {
            vm.warp(samples_[i_]);
            (uint256 curType_, uint32 curStart_, uint32 curEnd_) = marketHours.getCurrentSession();
            (uint256 viewType_, uint32 viewStart_, uint32 viewEnd_) = marketHours.getSessionInfo(samples_[i_]);
            assertEq(curType_, viewType_);
            assertEq(curStart_, viewStart_);
            assertEq(curEnd_, viewEnd_);
            ++assertionCount_;
        }
    }

    // -------- random timestamp fuzz over the calendar span --------

    /// @dev Classify `ts_` against a packed week the same way the contract does (type + latest REGULAR).
    function _classifyFromSessions(
        Structs.Session[] memory sessions_,
        uint32 ts_
    ) internal pure returns (uint256 sessionType_, uint32 regStart_, uint32 regEnd_) {
        uint256 len_ = sessions_.length;
        for (uint256 i_; i_ < len_; ++i_) {
            Structs.Session memory s_ = sessions_[i_];
            if (s_.sessionStart == 0 || s_.sessionStart > ts_) break;
            if (s_.sessionType == sessionTypeRegular) {
                regStart_ = s_.sessionStart;
                regEnd_ = uint32(uint256(s_.sessionStart) + uint256(s_.durationMinutes) * 1 minutes);
            }
        }

        for (uint256 i_; i_ < len_; ++i_) {
            Structs.Session memory s_ = sessions_[i_];
            if (s_.sessionStart == 0) break;
            if (ts_ < s_.sessionStart) {
                return (sessionTypeUnknown, regStart_, regEnd_);
            }
            uint256 sessionEnd_ = uint256(s_.sessionStart) + uint256(s_.durationMinutes) * 1 minutes;
            uint256 entryEnd_ = sessionEnd_ + uint256(s_.extendedDurationMinutes) * 1 minutes;
            if (ts_ >= entryEnd_) continue;
            if (ts_ < sessionEnd_) {
                sessionType_ = s_.sessionType == sessionTypeRegular ? sessionTypeRegular : sessionTypeHoliday;
            } else {
                sessionType_ = sessionTypeExtended;
            }
            return (sessionType_, regStart_, regEnd_);
        }
        return (sessionTypeUnknown, regStart_, regEnd_);
    }

    function _coverageRange(Structs.Session[] memory sessions_) internal pure returns (uint32 start_, uint32 end_) {
        for (uint256 i_; i_ < sessions_.length; ++i_) {
            Structs.Session memory s_ = sessions_[i_];
            if (s_.sessionStart == 0) break;
            if (start_ == 0) start_ = s_.sessionStart;
            end_ = uint32(
                uint256(s_.sessionStart) +
                    (uint256(s_.durationMinutes) + uint256(s_.extendedDurationMinutes)) *
                    1 minutes
            );
        }
    }

    function _countRewriteWeeks(uint32 firstMon_, uint32 endMon_) internal pure returns (uint256 n_) {
        uint32 monOpen_ = firstMon_;
        while (monOpen_ <= endMon_) {
            ++n_;
            monOpen_ = Cal.weekdayOpenFromMonday(monOpen_, 7);
        }
    }

    // Contiguity of Saturday-rewrite builders is covered by the year walk + random suite.

    function _assertMatchesSessions(Structs.Session[] memory sessions_, uint32 ts_) internal view {
        (uint256 expType_, uint32 expStart_, uint32 expEnd_) = _classifyFromSessions(sessions_, ts_);
        (uint256 gotType_, uint32 gotStart_, uint32 gotEnd_) = marketHours.getSessionInfo(ts_);
        // Keep asserts label-free in the hot path — string labels OOM at 100k samples.
        assertEq(gotType_, expType_);
        assertEq(gotStart_, expStart_);
        assertEq(gotEnd_, expEnd_);
    }

    /// @dev 100_000 deterministic pseudo-random timestamps across Jul 2025 – Jul 2026.
    ///      Each sample is checked against classification of the week schedule that was written.
    function test_RandomTimestampsMatchSchedule() public {
        uint256 totalSamples_ = 100_000;
        uint32 firstMon_ = Cal.marketOpen(2025, 7, 7);
        uint32 endMon_ = Cal.marketOpen(2026, 7, 13);

        _writeWeek(firstMon_);

        uint256 weeks_ = _countRewriteWeeks(firstMon_, endMon_);
        uint256 perWeek_ = totalSamples_ / weeks_;
        uint256 remainder_ = totalSamples_ % weeks_;
        uint256 checked_ = 0;

        uint32 monOpen_ = firstMon_;
        for (uint256 weekIdx_ = 0; weekIdx_ < weeks_; ++weekIdx_) {
            uint32 nextMon_ = Cal.weekdayOpenFromMonday(monOpen_, 7);
            _writeSaturdayRewrite(nextMon_);

            Structs.Session[] memory sessions_ = marketHours.getSessions();
            (uint32 rangeStart_, uint32 rangeEnd_) = _coverageRange(sessions_);
            assertTrue(rangeEnd_ > rangeStart_ + 1);

            uint256 n_ = perWeek_ + (weekIdx_ < remainder_ ? 1 : 0);
            uint256 span_ = rangeEnd_ - rangeStart_;
            for (uint256 i_; i_ < n_; ++i_) {
                uint32 ts_ = rangeStart_ +
                    uint32(uint256(keccak256(abi.encode(uint256(0xca1e11da), weekIdx_, i_))) % span_);
                _assertMatchesSessions(sessions_, ts_);
                ++checked_;
            }

            monOpen_ = nextMon_;
        }

        assertEq(checked_, totalSamples_);
    }
}
