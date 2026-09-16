// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { CLXStockOracleTestBase, MockChainlinkFeed, MockBackedAutoFeeToken, MockBackedWrapper } from "./clxStockOracleMocks.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

/// @dev Property / fuzz tests for FluidCLXStockOracle clamp, walk, and multiplier band.
contract FluidCLXStockOracleFuzzTest is CLXStockOracleTestBase {
    uint32 internal constant MON = 1751895000; // Jul 7 2025 09:30 ET

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, AUTH_CLASS_SCHEDULE_OVERRIDE); // harness writes unrelated weeks out of order

        feed = new MockChainlinkFeed();
        token = new MockBackedAutoFeeToken();
        wrapper = new MockBackedWrapper(token);
        token.setMultiplier(1e18);

        vm.warp(MON + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildWeekWithWeekend(MON));

        feed.pushRound(int256(1e10), MON + 1 hours);

        oracle = _deployOracleDefault();
        oracle.updateRegularHoursAnchor(0);
    }

    function testFuzz_ExtendedHoursClampCollateral(uint256 liveBps_) public {
        liveBps_ = bound(liveBps_, 1, 20000); // 0 would trip the mandatory price-gap guard

        int256 anchorAnswer_ = 1e10;
        feed.pushRound(anchorAnswer_, MON + 3 hours);
        oracle.updateRegularHoursAnchor(0);

        int256 liveAnswer_ = int256((uint256(anchorAnswer_) * liveBps_) / 10000);
        if (liveAnswer_ <= 0) liveAnswer_ = 1;

        vm.warp(MON + 7 hours);
        feed.pushRound(liveAnswer_, block.timestamp);

        (uint256 mult_, , ) = token.getCurrentMultiplier();
        uint256 anchorScaled_ = _scaledPrice(uint256(anchorAnswer_), mult_);
        uint256 liveScaled_ = _scaledPrice(uint256(liveAnswer_), mult_);

        assertEq(oracle.getExchangeRateOperate(), _clampUp(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT));
        assertEq(oracle.getExchangeRateLiquidate(), _clampDown(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT));
        assertEq(oracle.getExchangeRateOperateDebt(), _clampDown(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT));
        assertEq(oracle.getExchangeRateLiquidateDebt(), _clampUp(liveScaled_, anchorScaled_, MAX_EXTENDED_CAP_PERCENT));
    }

    function testFuzz_WalkDiscoversLatestInWindow(uint8 extraAfter_, uint8 inWindow_) public {
        inWindow_ = uint8(bound(inWindow_, 1, 20));
        extraAfter_ = uint8(bound(extraAfter_, 0, 10));

        uint32 regStart_ = MON;
        uint32 regEnd_ = regStart_ + uint32(Cal.REGULAR_MINUTES) * 60;
        uint256 windowEnd_ = _windowEnd(regEnd_);

        uint80 lastInWindowId_;
        for (uint256 i_; i_ < inWindow_; ++i_) {
            uint256 ts_ = regStart_ + ((windowEnd_ - regStart_) * i_) / inWindow_;
            feed.pushRound(int256(10e9 + i_), ts_);
            lastInWindowId_ = feed.latestRoundId();
        }

        for (uint256 j_; j_ < extraAfter_; ++j_) {
            feed.pushRound(int256(99e9), windowEnd_ + 1 hours + j_ * 60);
        }

        vm.warp(regEnd_ + 2 hours);
        oracle.updateRegularHoursAnchor(feed.latestRoundId());
        assertEq(oracle.getConfig().lastRegularHoursRoundId, lastInWindowId_);
    }

    function testFuzz_WalkBackLookbackCap(uint16 afterCount_) public {
        afterCount_ = uint16(bound(afterCount_, 301, 400));

        feed.pushRound(int256(1e10), MON + 1 hours);
        uint32 regEnd_ = MON + uint32(Cal.REGULAR_MINUTES) * 60;

        vm.warp(regEnd_ + 2 hours);
        for (uint256 i_; i_ < afterCount_; ++i_) {
            feed.pushRound(int256(2e10), block.timestamp + i_);
        }
        uint80 tip_ = feed.latestRoundId();

        // Lookback cap → no usable RTH ref outside REGULAR → revert (warm bot alert).
        _expectNotFound();
        oracle.updateRegularHoursAnchor(tip_);
    }

    function testFuzz_MultiplierBand(uint32 elapsed_, uint256 liveDeltaBps_) public {
        elapsed_ = uint32(bound(elapsed_, 0, 40 days));
        liveDeltaBps_ = bound(liveDeltaBps_, 0, 500);

        // Reset band clock during Monday RTH.
        vm.warp(MON + 2 hours);
        feed.pushRound(int256(1e10), block.timestamp);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(1e18);
        uint256 t0_ = block.timestamp;

        // Land on a REGULAR timestamp at/after t0+elapsed so pricing does not hit RTH discovery.
        uint256 target_ = t0_ + elapsed_;
        Cal.Date memory d_ = Cal.dateFromTimestamp(uint32(target_ > type(uint32).max ? type(uint32).max : target_));
        if (d_.year < 2025) d_ = Cal.dateFromYmd(2025, 7, 7);
        if (d_.year > 2026) {
            // Cap inside calendar lib span.
            target_ = Cal.marketOpen(2026, 6, 1) + 2 hours;
            d_ = Cal.dateFromTimestamp(uint32(target_));
            elapsed_ = uint32(target_ - t0_);
        }

        uint32 monOpen_ = Cal.mondayOpenOfWeek(d_.year, d_.month, d_.day);
        Cal.Date memory md_ = Cal.dateFromTimestamp(monOpen_);
        if (Cal.isFullHoliday(md_.year, md_.month, md_.day)) {
            monOpen_ = Cal.nextTradingDayOpen(md_.year, md_.month, md_.day);
        }
        vm.warp(uint256(monOpen_) - 2 days + 12 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(monOpen_));

        // Mid-RTH on that Monday (or first trading day).
        uint256 regularTs_ = uint256(monOpen_) + 2 hours;
        if (regularTs_ < t0_) regularTs_ = t0_ + (elapsed_ > 2 hours ? 2 hours : elapsed_);
        vm.warp(regularTs_);
        uint256 actualElapsed_ = block.timestamp - t0_;

        uint256 accepted_ = 1e18;
        uint256 live_ = (accepted_ * (10000 + liveDeltaBps_)) / 10000;
        token.setMultiplier(live_);
        feed.pushRound(int256(1e10), block.timestamp);

        // Absolute band (not floored percent): maxDiff = accepted * MAX% * elapsed / (PERIOD * 1e4).
        uint256 cappedElapsed_ = actualElapsed_ > 30 days ? 30 days : actualElapsed_;
        uint256 maxDiff_ = (accepted_ * 100 * cappedElapsed_) / (uint256(30 days) * 10000);
        uint256 diff_ = live_ > accepted_ ? live_ - accepted_ : accepted_ - live_;
        bool outside_ = diff_ > maxDiff_;

        if (outside_) {
            _expectMultiplierNeedsConfirmation();
            oracle.getExchangeRateOperate();
        } else {
            assertEq(oracle.getExchangeRateOperate(), _scaledPrice(1e10, live_));
            oracle.getExchangeRateOperateWrite();
            assertEq(oracle.getConfig().acceptedMultiplier, live_);
        }
    }

    function testFuzz_ClampMathNoOverflow(uint128 anchor_, uint128 live_, uint32 capPercent_) public {
        capPercent_ = uint32(bound(capPercent_, 0, 1e6));
        if (capPercent_ != 0 && uint256(anchor_) > type(uint128).max / capPercent_) {
            anchor_ = uint128(type(uint128).max / capPercent_);
        }
        // Keep product inside uint256 comfortably for the formula.
        anchor_ = uint128(bound(anchor_, 0, type(uint128).max / 1e6));

        uint256 up_ = _clampUp(live_, anchor_, capPercent_);
        uint256 down_ = _clampDown(live_, anchor_, capPercent_);

        uint256 delta_ = (uint256(anchor_) * capPercent_) / 1e6;
        uint256 expectedUp_ = uint256(live_) > uint256(anchor_) + delta_ ? uint256(anchor_) + delta_ : live_;
        uint256 expectedDown_;
        if (delta_ > anchor_) {
            expectedDown_ = live_;
        } else {
            uint256 floor_ = uint256(anchor_) - delta_;
            expectedDown_ = uint256(live_) < floor_ ? floor_ : live_;
        }

        assertEq(up_, expectedUp_);
        assertEq(down_, expectedDown_);
    }
}
