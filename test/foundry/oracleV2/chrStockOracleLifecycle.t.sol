// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { IFluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/interfaces/iFluidUsEquityMarketHours.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { FluidCHRStockOracle } from "../../../contracts/oracleV2/stocks/chrStockOracle/main.sol";
import { FluidCHRStockOracleL2 } from "../../../contracts/oracleV2/stocks/chrStockOracle/mainL2.sol";
import { Structs as CHRStructs } from "../../../contracts/oracleV2/stocks/chrStockOracle/structs.sol";
import { ErrorTypes } from "../../../contracts/oracleV2/stocks/errorTypes.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/stocks/error.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";

import { MockChronicle, MockRealityToken, MockRealityTokenTrade, MockAuthGate, SequencerUptimeFeedMock } from "./chrStockOracleMocks.sol";

/// @notice Walks the EDGE_CASES.md scenarios on the Chronicle × Reality stock oracle, asserting the first failing
///         check or the returned value at each step.
contract CHRStockOracleLifecycleTest is Test {
    FluidUsEquityMarketHours marketHours;
    MockChronicle chronicle;
    MockRealityToken rtoken;
    MockRealityTokenTrade trade;
    MockAuthGate authGate;
    SequencerUptimeFeedMock feed;
    FluidCHRStockOracle oracle;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address constant MID = address(0x1D1D);
    address constant HIGH = address(0x1E1E);

    uint16 constant REGULAR_MINUTES = 390;
    uint16 constant POST_MINUTES = 240;
    uint16 constant PRE_MINUTES = 330;
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeHoliday = 3;

    uint256 constant MON = 1_700_000_000;
    /// @dev Monday regular window: [MON, REG_END).
    uint256 constant REG_END = MON + 390 minutes;

    uint256 constant CAUSE_TRADE_PAUSED = 1;
    uint256 constant CAUSE_RTOKEN_PAUSED = 2;
    uint256 constant CAUSE_MULTIPLIER_CHANGED = 4;

    event LogPause(address indexed sender);
    event LogUnpause(address indexed sender);
    event LogPauseLatched(uint256 causes);
    event LogSetAnchor(uint256 oldValue, uint256 newValue, uint256 oldMultiplier, uint256 newMultiplier);
    event LogRecordHint(uint256 value, uint256 age, uint256 regularEnd);
    event LogSealAnchor(uint256 value, uint256 age);

    // ------------------------------------------------------------------ setup helpers

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    function _deployMarketHours() internal returns (FluidUsEquityMarketHours) {
        FluidUsEquityMarketHours impl_ = new FluidUsEquityMarketHours(LIQUIDITY);
        FluidUsEquityMarketHoursProxy proxy_ = new FluidUsEquityMarketHoursProxy(
            address(impl_),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        return FluidUsEquityMarketHours(address(proxy_));
    }

    /// @dev Mon–Thu: regular + extended. Fri: regular + post. Weekend: HOLIDAY + Mon pre.
    function _weekWithWeekend(uint32 monStart_) internal pure returns (Structs.Session[] memory s_) {
        s_ = new Structs.Session[](6);
        for (uint256 i_; i_ < 4; i_++) {
            s_[i_] = Structs.Session({
                sessionStart: uint32(uint256(monStart_) + i_ * 1 days),
                durationMinutes: REGULAR_MINUTES,
                extendedDurationMinutes: WEEKDAY_EXTENDED_MINUTES,
                sessionType: sessionTypeRegular
            });
        }
        uint32 fri_ = uint32(uint256(monStart_) + 4 days);
        s_[4] = Structs.Session({
            sessionStart: fri_,
            durationMinutes: REGULAR_MINUTES,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: sessionTypeRegular
        });
        uint32 weekendStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        s_[5] = Structs.Session({
            sessionStart: weekendStart_,
            durationMinutes: 56 * 60,
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: sessionTypeHoliday
        });
    }

    /// @dev Friday regular, a weekend holiday entry ending at next Monday's open, then next Monday to Thursday.
    ///      Spans exactly the 7-day minimum, which `updateWeekSessions` requires.
    function _bridgeToNextMonday() internal pure returns (Structs.Session[] memory s_) {
        uint32 fri_ = uint32(MON + 4 days);
        uint32 holidayStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        s_ = new Structs.Session[](6);
        s_[0] = Structs.Session({
            sessionStart: fri_,
            durationMinutes: REGULAR_MINUTES,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: sessionTypeRegular
        });
        s_[1] = Structs.Session({
            sessionStart: holidayStart_,
            durationMinutes: 56 * 60,
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: sessionTypeHoliday
        });
        for (uint256 i_; i_ < 4; i_++) {
            s_[2 + i_] = Structs.Session({
                sessionStart: uint32(MON + 7 days + i_ * 1 days),
                durationMinutes: REGULAR_MINUTES,
                extendedDurationMinutes: WEEKDAY_EXTENDED_MINUTES,
                sessionType: sessionTypeRegular
            });
        }
    }

    function _params() internal view returns (CHRStructs.CHRStockOracleConstructorParams memory p_) {
        p_ = CHRStructs.CHRStockOracleConstructorParams({
            infoName: "rSPY",
            targetDecimals: 27,
            chronicle: address(chronicle),
            rtoken: address(rtoken),
            realityTokenTrade: address(trade),
            marketHours: address(marketHours),
            authGate: address(authGate),
            maxCapPercent: 1500,
            maxBreakPercent: 3000,
            maxOperateAge: 1 hours,
            maxLiquidateAge: 1 days
        });
    }

    function _expectErr(uint256 id_) internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidStockOracleError.selector, id_));
    }

    function _expectCommonErr(uint256 id_) internal {
        vm.expectRevert(abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, id_));
    }

    function _setPrice(uint256 price18_) internal {
        chronicle.set(true, price18_, block.timestamp);
    }

    function _setSequencerUp() internal {
        feed.setRound(1, 0, MON - 1 days);
    }

    function _mockSchedule() internal {
        vm.mockCallRevert(address(marketHours), abi.encodeCall(IFluidUsEquityMarketHours.getCurrentSession, ()), "");
    }

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 1);

        chronicle = new MockChronicle();
        rtoken = new MockRealityToken();
        trade = new MockRealityTokenTrade();
        authGate = new MockAuthGate();
        feed = new SequencerUptimeFeedMock();
        _setSequencerUp();
        authGate.setLevel(MID, 1);
        authGate.setLevel(HIGH, 2);

        vm.warp(MON + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(uint32(MON)));

        oracle = new FluidCHRStockOracleL2(_params(), address(feed));
        _setPrice(700e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
    }

    // ------------------------------------------------------------------ §1 normal weekday

    function test_edgeCase1_NormalWeekdayRecordsSealsAndMeasuresFromClose() public {
        // Monday 10:30 AM: the write getter records the print as the hint
        vm.warp(MON + 2 hours);
        _setPrice(705e18);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertEq(oracle.getExchangeRateOperateWrite(), 705e27);
        assertEq(oracle.getConfig().hintAge, MON + 2 hours);

        // 3:59 PM: the keeper records the newest in-session print
        vm.warp(REG_END - 1 minutes);
        _setPrice(706e18);
        assertTrue(oracle.updateRegularHoursAnchor());
        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.hintValue, 706e27);
        assertEq(s_.hintAge, REG_END - 1 minutes);
        assertEq(s_.hintRegularEnd, REG_END);

        // past the 2-minute buffer after 4:00 PM: views already treat the sealable hint as the anchor, then the keeper seals it
        vm.warp(REG_END + 3 minutes);
        // the hint sets the floor (706 * 85% = 600.1), not the 700 anchor's 595, and the stored anchor is still 700
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidate(), 600.1e27);
        assertEq(oracle.getConfig().anchorValue, 700e27);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(706e27, REG_END - 1 minutes);
        assertTrue(oracle.updateRegularHoursAnchor());
        s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 706e27);
        assertEq(s_.anchorTime, REG_END - 1 minutes);
        assertEq(s_.hintAge, 0);

        // Tuesday 10:30 AM: measured from Monday's close (706, cap floor 600.1), not the 700 anchor (floor 595)
        vm.warp(MON + 1 days + 1 hours);
        _setPrice(600e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();

        _setPrice(610e18);
        assertEq(oracle.getExchangeRateOperate(), 610e27);
    }

    function test_freshDeployment_FirstCloseSealsAnchorWithoutAdmin() public {
        FluidCHRStockOracle fresh_ = new FluidCHRStockOracleL2(_params(), address(feed));

        // Monday 10:30 AM: the keeper records the print as the hint, no setAnchor involved
        vm.warp(MON + 2 hours);
        chronicle.set(true, 705e18, MON + 2 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertTrue(fresh_.updateRegularHoursAnchor());

        // after 4:00 PM the next keeper call seals that print as the first anchor
        vm.warp(REG_END + 3 minutes);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 2 hours);
        assertTrue(fresh_.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = fresh_.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 2 hours);
        assertEq(s_.hintAge, 0);

        // the sealed anchor arms the break (+30% of 705) and the cap (+15%)
        vm.warp(MON + 1 days + 1 hours);
        _setPrice(920e18);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        fresh_.getExchangeRateOperate();

        _setPrice(830e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        fresh_.getExchangeRateOperate();
    }

    // ------------------------------------------------------------------ §3 2:1 split, multiplier first

    function test_edgeCase3_SplitMultiplierFirstFreezesUntilSetAnchor() public {
        vm.warp(MON + 2 hours);
        trade.setTradePaused(address(rtoken), true);
        _expectErr(ErrorTypes.CHRStockOracle__TradePaused);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_TRADE_PAUSED);

        // Reality moves the multiplier while the latch holds
        rtoken.setUIMultiplier(2e18);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        // Chronicle reprices -50%: the live value is continuous again
        _setPrice(350e18);
        assertEq(oracle.getExchangeRateRaw(), 700e27);

        // Reality clears tradePaused: still Paused, underneath the multiplier freeze
        trade.setTradePaused(address(rtoken), false);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_MULTIPLIER_CHANGED);

        // operator checks Chronicle repriced, then HIGH accepts the doubled multiplier at the live value
        vm.expectEmit(true, true, true, true);
        emit LogSetAnchor(700e27, 700e27, 1e18, 2e18);
        vm.prank(HIGH);
        oracle.setAnchor(2e18);

        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);
    }

    // ------------------------------------------------------------------ §4 2:1 split, price first

    function test_edgeCase4_SplitPriceFirstBreaksThenLatchesThenResumes() public {
        vm.warp(MON + 2 hours);
        _setPrice(350e18);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);

        // Reality moves the multiplier: the freeze reverts, the keeper latches cause 4
        rtoken.setUIMultiplier(2e18);
        _expectErr(ErrorTypes.CHRStockOracle__MultiplierChanged);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_MULTIPLIER_CHANGED);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        vm.expectEmit(true, true, true, true);
        emit LogSetAnchor(700e27, 700e27, 1e18, 2e18);
        vm.prank(HIGH);
        oracle.setAnchor(2e18);

        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    // ------------------------------------------------------------------ §6 crash beyond cap and break

    function test_edgeCase6_CrashBeyondCapClampsLiquidateAndSealsAtClose() public {
        // -20% intraday: inside the break, outside the cap
        vm.warp(MON + 2 hours);
        _setPrice(560e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 595e27);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 560e27);

        // 3:59 PM: the keeper records the -20% print, then seals it after the bell
        vm.warp(REG_END - 1 minutes);
        _setPrice(560e18);
        assertTrue(oracle.updateRegularHoursAnchor());

        vm.warp(REG_END + 3 minutes);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(560e27, REG_END - 1 minutes);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().anchorValue, 560e27);

        // Tuesday: measured from the -20% close (cap floor 476)
        vm.warp(MON + 1 days + 1 hours);
        _setPrice(560e18);
        assertEq(oracle.getExchangeRateOperate(), 560e27);
    }

    function test_edgeCase6_CrashBeyondBreakNeedsSetAnchor() public {
        // -35%: beyond the -30% break
        vm.warp(MON + 2 hours);
        _setPrice(455e18);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateLiquidate();
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);

        // operator checks the market, then accepts the move
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
        assertEq(oracle.getExchangeRateOperate(), 455e27);
    }

    // ------------------------------------------------------------------ §9 market-hours schedule stops

    function test_edgeCase9_ScheduleStopsFreezeHintsThenFailOpenThenReseal() public {
        // Monday 10:30 AM: MH stops answering. Writes revert, reads keep working against the last anchor
        _mockSchedule();
        vm.warp(MON + 2 hours);
        _setPrice(705e18);
        assertEq(oracle.getExchangeRateOperate(), 705e27);
        vm.expectRevert();
        oracle.updateRegularHoursAnchor();
        vm.expectRevert();
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().hintAge, 0);

        // Saturday night, 5.5 days on: the anchor is aged out, so cap and break are off and reads price live
        vm.warp(MON + 5 days + 14 hours);
        _setPrice(480e18);
        assertEq(oracle.getExchangeRateOperate(), 480e27);
        assertEq(oracle.getExchangeRateLiquidate(), 480e27);

        // a schedule covering now is written as governance (bypasses the pin on stored entries); MH answers again
        vm.prank(GOVERNANCE);
        marketHours.updateWeekSessions(_bridgeToNextMonday());
        vm.clearMockedCalls();
        _mockGovernance(GOVERNANCE);

        // Next Monday, 10:30 AM: the in-session print is recorded without the break check, and sealed at the bell
        vm.warp(MON + 7 days + 1 hours);
        _setPrice(480e18);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(480e27, MON + 7 days + 1 hours, MON + 7 days + 390 minutes);
        assertTrue(oracle.updateRegularHoursAnchor());

        vm.warp(MON + 7 days + 390 minutes + 3 minutes);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(480e27, MON + 7 days + 1 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        // the seal re-arms the break: 700 is beyond +42.85% of the new 480 anchor
        _setPrice(700e18);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
    }

    // ------------------------------------------------------------------ §10 rtoken paused for an upgrade

    function test_edgeCase10_RtokenPausedLatchesAndUnpauseWaitsForIssuer() public {
        vm.warp(MON + 2 hours);
        rtoken.setPaused(true);
        _expectErr(ErrorTypes.CHRStockOracle__RtokenPaused);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_RTOKEN_PAUSED);

        _expectErr(ErrorTypes.CHRStockOracle__LatchCauseActive);
        vm.prank(MID);
        oracle.unpause();

        rtoken.setPaused(false);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        _setPrice(700e18);
        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    // ------------------------------------------------------------------ §13 multiplier changes and changes back

    function test_edgeCase13_MultiplierChangeAndRestoreNeedsOnlyUnpause() public {
        vm.warp(MON + 2 hours);
        _setPrice(700e18);
        rtoken.setUIMultiplier(2e18);
        _expectErr(ErrorTypes.CHRStockOracle__MultiplierChanged);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_MULTIPLIER_CHANGED);

        rtoken.setUIMultiplier(1e18);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
        assertEq(oracle.getConfig().acceptedMultiplier, 1e18);
    }

    // ------------------------------------------------------------------ §14 sequencer outage

    function test_edgeCase14_SequencerOutageThenGraceCappedAt45Minutes() public {
        // sequencer goes down at 10:00 AM; latchPause keeps working during the outage
        vm.warp(MON + 2 hours + 1 minutes);
        feed.setRound(2, 1, MON + 2 hours);
        _setPrice(700e18);
        _expectCommonErr(CommonErrorTypes.SequencerL2__SequencerDown);
        oracle.getExchangeRateOperate();
        _expectCommonErr(CommonErrorTypes.SequencerL2__SequencerDown);
        oracle.updateRegularHoursAnchor();
        assertEq(oracle.getExchangeRateOperateRaw(), 700e27);

        rtoken.setPaused(true);
        assertEq(oracle.latchPause(), CAUSE_RTOKEN_PAUSED);

        // back up at 12:00 PM: a two-hour outage gives a 45-minute grace period
        vm.warp(MON + 4 hours);
        feed.setRound(3, 0, MON + 4 hours);
        _setPrice(700e18);
        _expectCommonErr(CommonErrorTypes.SequencerL2__GracePeriod);
        oracle.getExchangeRateOperate();

        vm.warp(MON + 4 hours + 45 minutes);
        _setPrice(700e18);
        _expectCommonErr(CommonErrorTypes.SequencerL2__GracePeriod);
        oracle.getExchangeRateOperate();

        // grace passed, but the latch still holds
        vm.warp(MON + 4 hours + 46 minutes);
        _setPrice(700e18);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        rtoken.setPaused(false);
        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    // ------------------------------------------------------------------ §2 weekend

    function test_edgeCase2_WeekendPrintsNotRecordedFridayCloseStaysAnchor() public {
        uint256 fri_ = MON + 4 days;
        uint256 friRegEnd_ = fri_ + 390 minutes;

        // Friday 10:30 AM: the print is recorded as the hint
        vm.warp(fri_ + 2 hours);
        _setPrice(705e18);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, fri_ + 2 hours, friRegEnd_);
        assertTrue(oracle.updateRegularHoursAnchor());

        // after the bell and the buffer the keeper seals it
        vm.warp(friRegEnd_ + 3 minutes);
        _setPrice(705e18);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, fri_ + 2 hours);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().anchorValue, 705e27);
        assertEq(oracle.getConfig().anchorTime, fri_ + 2 hours);

        // Saturday noon: Chronicle keeps posting, nothing is recorded and Friday's close stays the anchor
        vm.warp(MON + 5 days + 12 hours);
        _setPrice(720e18);
        assertFalse(oracle.updateRegularHoursAnchor());
        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.hintAge, 0);
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, fri_ + 2 hours);

        // the Friday anchor still caps: 830 is beyond 705 + 15% (810.75), 760 is inside it
        _setPrice(830e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();

        _setPrice(760e18);
        assertEq(oracle.getExchangeRateOperate(), 760e27);
    }

    // ------------------------------------------------------------------ §5 5:4 split, price first

    function test_edgeCase5_FiveFourSplitPriceFirstSealsThenLatchesOnMultiplier() public {
        // Monday 10:00 AM: Chronicle -20% with the multiplier unchanged, inside the break
        vm.warp(MON + 2 hours);
        _setPrice(560e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 595e27);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 560e27);

        // 3:59 PM: the keeper records the -20% print
        vm.warp(REG_END - 1 minutes);
        _setPrice(560e18);
        assertTrue(oracle.updateRegularHoursAnchor());

        // after the bell the seal makes -20% the anchor, so the full move is priced
        vm.warp(REG_END + 3 minutes);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(560e27, REG_END - 1 minutes);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().anchorValue, 560e27);

        _setPrice(560e18);
        assertEq(oracle.getExchangeRateOperate(), 560e27);
        assertEq(oracle.getExchangeRateLiquidate(), 560e27);

        // the multiplier then moves by the 5:4 partner (x1.25): reads freeze and the keeper latches cause 4
        rtoken.setUIMultiplier(1.25e18);
        _expectErr(ErrorTypes.CHRStockOracle__MultiplierChanged);
        oracle.getExchangeRateOperate();
        assertEq(oracle.latchPause(), CAUSE_MULTIPLIER_CHANGED);
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateLiquidate();
    }

    // ------------------------------------------------------------------ §7 Chronicle stops posting

    function test_edgeCase7_StalePrintRevertsWithoutLatchAndResumesOnNextPrint() public {
        vm.warp(MON + 2 hours);
        _setPrice(700e18);
        assertEq(oracle.getExchangeRateOperate(), 700e27);

        // an hour without a print: operate ages out, liquidate still prices
        vm.warp(MON + 3 hours + 1);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);

        // a day without a print: liquidate ages out too
        vm.warp(MON + 2 hours + 1 days + 1);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.getExchangeRateLiquidate();

        // nothing latched
        assertEq(oracle.latchPause(), 0);
        assertFalse(oracle.getConfig().paused);

        // the next print resumes pricing
        _setPrice(702e18);
        assertEq(oracle.getExchangeRateOperate(), 702e27);
    }
}
