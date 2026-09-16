// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { CLXStockOracleTestBase, MockChainlinkFeed, MockBackedAutoFeeToken, MockBackedWrapper } from "./clxStockOracleMocks.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

/// @dev Multi-week calendar integration for FluidCLXStockOracle (Jul–Oct 2025).
contract FluidCLXStockOracleLifecycleTest is CLXStockOracleTestBase {
    int256 internal baseClAnswer = 1e10;
    int256 internal lastRthClAnswer = 1e10;
    uint256 internal lastClUpdatedAt;

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, AUTH_CLASS_SCHEDULE_OVERRIDE); // harness writes unrelated weeks out of order

        feed = new MockChainlinkFeed();
        token = new MockBackedAutoFeeToken();
        wrapper = new MockBackedWrapper(token);
        token.setMultiplier(1e18);

        uint32 mon_ = Cal.marketOpen(2025, 7, 7);
        vm.warp(uint256(mon_) - 2 days + 12 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(mon_));

        uint32 thuOpen_ = Cal.marketOpen(2025, 7, 3);
        _pushCl(baseClAnswer, thuOpen_ + 2 hours);
        vm.warp(thuOpen_ + 2 hours);
        oracle = _deployOracleDefault();
        oracle.updateRegularHoursAnchor(0);
    }

    function _pushCl(int256 answer_, uint256 updatedAt_) internal {
        if (updatedAt_ <= lastClUpdatedAt) updatedAt_ = lastClUpdatedAt + 1;
        lastClUpdatedAt = updatedAt_;
        feed.pushRound(answer_, updatedAt_);
    }

    function test_MultiWeekLifecycleInvariants() public {
        uint32 mon_ = Cal.marketOpen(2025, 7, 7);
        bool skipSaturday_;
        bool silentTuesday_;
        bool multiplierWeek_;

        for (uint256 week_; week_ < 12; ++week_) {
            if (week_ == 4) skipSaturday_ = true;
            if (week_ == 5) silentTuesday_ = true;
            if (week_ == 6) multiplierWeek_ = true;

            if (!skipSaturday_) {
                _saturdayRewrite(mon_);
            } else {
                skipSaturday_ = false;
            }

            if (week_ == 0) {
                assertEq(marketHours.getSessionType(Cal.marketOpen(2025, 7, 3) + 4 hours), sessionTypeExtended);
                assertEq(marketHours.getSessionType(Cal.marketOpen(2025, 7, 4) + 2 hours), sessionTypeHoliday);
            }

            _sampleWeek(mon_, week_, silentTuesday_);
            silentTuesday_ = false;

            if (multiplierWeek_) {
                _injectMultiplierJump(mon_);
                multiplierWeek_ = false;
            }

            mon_ = _nextWeekMonOpen(mon_);
        }

        vm.warp(Cal.marketOpen(2025, 10, 6) + 2 hours);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
        _pushCl(12e9, block.timestamp);
        assertGt(oracle.getExchangeRateOperate(), 0);
    }

    function test_CacheVsFreshDiscoveryParity() public {
        uint32 mon_ = Cal.marketOpen(2025, 8, 4);
        _saturdayRewrite(mon_);
        vm.warp(mon_ + 1 hours);
        _pushCl(11e9, mon_ + 3 hours);
        oracle.updateRegularHoursAnchor(0);

        uint32 extTs_ = Cal.weekdayOpenFromMonday(mon_, 1) - 2 hours;
        _pushCl(15e9, extTs_);
        vm.warp(extTs_);
        uint256 cached_ = oracle.getExchangeRateOperate();

        FluidCLXStockOracle twin_ = _deployOracleDefault();
        twin_.updateRegularHoursAnchor(0);
        assertEq(twin_.getExchangeRateOperate(), cached_);
    }

    function test_SilentRthSessionFallsBackOnPricing() public {
        uint32 mon_ = Cal.marketOpen(2025, 9, 8);
        _saturdayRewrite(mon_);
        _pushCl(10e9, mon_ + 2 hours);
        vm.warp(mon_ + 2 hours);
        oracle.updateRegularHoursAnchor(0);

        vm.warp(_sessionEnd(Cal.weekdayOpenFromMonday(mon_, 1)) + 2 hours);
        _pushCl(20e9, block.timestamp);
        _expectNotFound();
        oracle.updateRegularHoursAnchor(0); // silent Tue RTH outside REGULAR → alert

        vm.warp(Cal.weekdayOpenFromMonday(mon_, 2) - 2 hours);
        _pushCl(22e9, block.timestamp);
        uint256 live_ = _scaledPrice(uint256(22e9), _tokenMultiplier());
        assertEq(oracle.getExchangeRateOperate(), live_);
        assertEq(oracle.getExchangeRateLiquidate(), live_);
    }

    function test_DstWeekNoRevert() public {
        uint32 mon_ = Cal.marketOpen(2025, 11, 3);
        _saturdayRewrite(mon_);
        vm.warp(mon_ + 2 hours);
        _pushCl(11e9, block.timestamp);
        oracle.updateRegularHoursAnchor(0);
        vm.warp(Cal.weekdayOpenFromMonday(mon_, 1) - 1 hours);
        _pushCl(12e9, block.timestamp);
        assertGt(oracle.getExchangeRateOperate(), 0);
    }

    function _saturdayRewrite(uint32 nextMonOpen_) internal {
        vm.warp(uint256(nextMonOpen_) - 2 days + 12 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(nextMonOpen_));
    }

    function _nextWeekMonOpen(uint32 monOpen_) internal pure returns (uint32) {
        Cal.Date memory d_ = Cal.dateFromTimestamp(monOpen_);
        uint32 nextMon_ = Cal.weekdayOpenFromMonday(Cal.mondayOpenOfWeek(d_.year, d_.month, d_.day), 7);
        Cal.Date memory nd_ = Cal.dateFromTimestamp(nextMon_);
        if (Cal.isFullHoliday(nd_.year, nd_.month, nd_.day)) {
            return Cal.nextTradingDayOpen(nd_.year, nd_.month, nd_.day);
        }
        return nextMon_;
    }

    function _sampleWeek(uint32 monOpen_, uint256 walkSeed_, bool silentTuesday_) internal {
        for (uint8 offset_; offset_ < 5; ++offset_) {
            uint32 open_ = Cal.weekdayOpenFromMonday(monOpen_, offset_);
            Cal.Date memory d_ = Cal.dateFromTimestamp(open_);
            if (Cal.isFullHoliday(d_.year, d_.month, d_.day)) continue;

            bool silentDay_ = silentTuesday_ && offset_ == 1;
            if (!silentDay_) {
                int256 seed_ = baseClAnswer + int256(((walkSeed_ + offset_) % 50) + 1) * 1e7;
                lastRthClAnswer = seed_;
                _pushCl(seed_, open_ + 3 hours);
            }

            uint32 end_ = _sessionEnd(open_);
            uint32[4] memory stamps_ = [open_ + 2 hours, open_ + 4 hours, end_ + 30 minutes, end_ + 2 hours];
            for (uint256 i_; i_ < 4; ++i_) {
                if (silentDay_ && stamps_[i_] >= open_ && stamps_[i_] <= end_) continue;
                _sampleAt(stamps_[i_], walkSeed_ + offset_ * 4 + i_);
            }
        }

        uint32 nextMon_ = Cal.weekdayOpenFromMonday(monOpen_, 7);
        Cal.Date memory nextD_ = Cal.dateFromTimestamp(nextMon_);
        if (!Cal.isFullHoliday(nextD_.year, nextD_.month, nextD_.day)) {
            _sampleAt(nextMon_ - 2 hours, walkSeed_ + 40);
        }
    }

    function _sampleAt(uint32 ts_, uint256 walkSeed_) internal {
        (uint256 sessionType_, uint32 regStart_, uint32 regEnd_) = marketHours.getSessionInfo(ts_);

        if (sessionType_ == sessionTypeRegular) {
            int256 ans_ = baseClAnswer + int256((walkSeed_ % 50) + 1) * 1e7;
            lastRthClAnswer = ans_;
            _pushCl(ans_, ts_);
            vm.warp(ts_);
            uint256 live_ = _scaledPrice(uint256(ans_), _tokenMultiplier());
            assertEq(oracle.getExchangeRateOperate(), live_);
            assertEq(oracle.getExchangeRateLiquidate(), live_);
            if (walkSeed_ % 7 == 0) oracle.getExchangeRateOperateWrite();
            return;
        }

        if (regStart_ == 0) return;

        uint256 bps_ = walkSeed_ % 1501;
        int256 liveAns_;
        if (walkSeed_ % 2 == 0) {
            liveAns_ = int256((uint256(lastRthClAnswer) * (10000 + bps_)) / 10000);
        } else {
            liveAns_ = int256((uint256(lastRthClAnswer) * (10000 - bps_)) / 10000);
            if (liveAns_ <= 0) liveAns_ = lastRthClAnswer / 2;
        }
        _pushCl(liveAns_, ts_);
        vm.warp(ts_);

        int256 anchorAns_ = _findAnchorClAnswer(feed, regStart_, regEnd_);
        uint256 mult_ = _tokenMultiplier();
        uint256 liveScaled_ = _scaledPrice(uint256(liveAns_), mult_);

        // No in-window RTH print (or stale window handled by oracle) → REGULAR-like live fallback.
        if (anchorAns_ <= 0 || (regEnd_ < ts_ && ts_ - regEnd_ >= 5 days)) {
            assertEq(oracle.getExchangeRateOperate(), liveScaled_);
            assertEq(oracle.getExchangeRateLiquidate(), liveScaled_);
            assertEq(oracle.getExchangeRateOperateDebt(), liveScaled_);
            assertEq(oracle.getExchangeRateLiquidateDebt(), liveScaled_);
            return;
        }

        uint256 anchorScaled_ = _scaledPrice(uint256(anchorAns_), mult_);

        assertApproxEqAbs(
            oracle.getExchangeRateOperate(),
            _clampUp(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT),
            1
        );
        assertApproxEqAbs(
            oracle.getExchangeRateLiquidate(),
            _clampDown(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT),
            1
        );
        assertApproxEqAbs(
            oracle.getExchangeRateOperateDebt(),
            _clampDown(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT),
            1
        );
        assertApproxEqAbs(
            oracle.getExchangeRateLiquidateDebt(),
            _clampUp(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT),
            1
        );
    }

    function _injectMultiplierJump(uint32 mon_) internal {
        vm.warp(mon_ + 2 hours);
        _pushCl(lastRthClAnswer, block.timestamp);
        token.setMultiplier(102e16);
        _expectMultiplierNeedsConfirmation();
        oracle.getExchangeRateOperate();
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(102e16);
        assertGt(oracle.getExchangeRateOperate(), 0);
        token.setMultiplier(1e18);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(1e18);
    }

    function _tokenMultiplier() internal view returns (uint256 multiplier_) {
        (multiplier_, , ) = token.getCurrentMultiplier();
    }
}
