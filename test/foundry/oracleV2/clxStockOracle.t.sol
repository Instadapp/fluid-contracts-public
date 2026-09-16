// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { IFluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/interfaces/iFluidUsEquityMarketHours.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { Structs as CLXStructs } from "../../../contracts/oracleV2/stocks/clxStockOracle/structs.sol";
import { ErrorTypes } from "../../../contracts/oracleV2/stocks/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/stocks/error.sol";
import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";
import { StringBytes32Utils } from "../../../contracts/libraries/StringBytes32Utils.sol";

contract MockChainlinkFeed {
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint80 public latestRoundId;
    mapping(uint80 => Round) internal _rounds;
    mapping(uint80 => bool) public revertRound;
    /// @dev When set, `getRoundData` returns success with answer=0 / updatedAt=0 (mainnet CL post-tip quirk).
    mapping(uint80 => bool) public phantomRound;
    uint8 public decimals_ = 8;
    bool public revertLatest;

    function pushRound(int256 answer_, uint256 updatedAt_) external {
        ++latestRoundId;
        _rounds[latestRoundId] = Round({ answer: answer_, updatedAt: updatedAt_ });
    }

    function setLatest(int256 answer_, uint256 updatedAt_) external {
        if (latestRoundId == 0) {
            latestRoundId = 1;
        }
        _rounds[latestRoundId] = Round({ answer: answer_, updatedAt: updatedAt_ });
    }

    function setRevertLatest(bool revert_) external {
        revertLatest = revert_;
    }

    function setRevertRound(uint80 roundId_, bool revert_) external {
        revertRound[roundId_] = revert_;
    }

    function setPhantomRound(uint80 roundId_, bool phantom_) external {
        phantomRound[roundId_] = phantom_;
    }

    /// @dev Mark `count_` ids after `latestRoundId` as successful empty rounds (no tip advance).
    function setPhantomRoundsAfterLatest(uint256 count_) external {
        for (uint256 i_ = 1; i_ <= count_; ++i_) {
            phantomRound[latestRoundId + uint80(i_)] = true;
        }
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (revertLatest) revert("latest revert");
        Round memory r_ = _rounds[latestRoundId];
        return (latestRoundId, r_.answer, 0, r_.updatedAt, latestRoundId);
    }

    function getRoundData(uint80 roundId_) external view returns (uint80, int256, uint256, uint256, uint80) {
        if (revertRound[roundId_]) revert("round revert");
        if (phantomRound[roundId_]) return (roundId_, 0, 0, 0, roundId_);
        Round memory r_ = _rounds[roundId_];
        require(r_.updatedAt != 0 || r_.answer != 0, "no round");
        return (roundId_, r_.answer, 0, r_.updatedAt, roundId_);
    }
}

contract MockBackedAutoFeeToken {
    uint256 public lastMultiplier = 1e18;
    uint256 public newMultiplier = 1e18;
    uint256 public newMultiplierActivationTime;

    function setMultiplier(uint256 multiplier_) external {
        lastMultiplier = multiplier_;
        newMultiplier = multiplier_;
        newMultiplierActivationTime = 0;
    }

    /// @dev Future activation; overrides any pending entry in place.
    function scheduleMultiplier(uint256 multiplier_, uint256 activationTime_) external {
        lastMultiplier = block.timestamp < newMultiplierActivationTime ? lastMultiplier : newMultiplier;
        newMultiplier = multiplier_;
        newMultiplierActivationTime = activationTime_;
    }

    function getCurrentMultiplier() external view returns (uint256, uint256, uint256) {
        if (block.timestamp < newMultiplierActivationTime) return (lastMultiplier, 0, 0);
        return (newMultiplier, 0, 0);
    }
}

contract MockBackedWrapper {
    MockBackedAutoFeeToken public immutable token;
    uint256 public passthroughSkew;

    constructor(MockBackedAutoFeeToken token_) {
        token = token_;
    }

    function setPassthroughSkew(uint256 skew_) external {
        passthroughSkew = skew_;
    }

    function convertToAssets(uint256 shares_) external view returns (uint256) {
        (uint256 multiplier_, , ) = token.getCurrentMultiplier();
        return (shares_ * (multiplier_ + passthroughSkew)) / 1e18;
    }

    function asset() external view returns (address) {
        return address(token);
    }
}

contract FluidUsEquityMarketHoursTest is Test {
    FluidUsEquityMarketHours marketHours;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    uint16 constant REGULAR_MINUTES = 390; // 6.5h
    uint16 constant POST_MINUTES = 240; // 4h
    uint16 constant PRE_MINUTES = 330; // 5.5h
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050; // 17.5h until next regular open

    // Session type return values (contract `SESSION_TYPE_*`).
    uint8 constant sessionTypeUnknown = 0;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

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

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 1);
    }

    /// @dev Mon–Thu: regular + extended through next open. Fri: regular + post. Weekend: HOLIDAY + Mon pre.
    ///      Total duration minutes = 10080 (exactly 7 days).
    function _weekWithWeekend(uint32 monStart_) internal view returns (Structs.Session[] memory s_) {
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
        // Fri post end → Mon pre start as HOLIDAY; extended = Monday pre-market.
        uint32 weekendStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        // Fri 20:00 → Mon 04:00 = 56 hours
        s_[5] = Structs.Session({
            sessionStart: weekendStart_,
            durationMinutes: 56 * 60,
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: sessionTypeHoliday
        });
    }

    /// @dev Warp into Monday regular and write the week (active entry + started REGULAR).
    function _setWeek(uint32 monStart_) internal {
        vm.warp(uint256(monStart_) + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(monStart_));
    }

    /// @dev Saturday rewrite: last Friday REGULAR + ongoing weekend HOLIDAY + next Mon–Fri + next weekend (8 total).
    function _weekRewriteFromNow(uint32 nextMon_) internal view returns (Structs.Session[] memory s_) {
        uint32 fri_ = uint32(uint256(nextMon_) - 3 days);
        uint32 weekendStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        uint256 preStart_ = uint256(nextMon_) - uint256(PRE_MINUTES) * 1 minutes;
        uint256 holDurMin_ = (preStart_ - weekendStart_) / 1 minutes;

        Structs.Session[] memory rest_ = _weekWithWeekend(nextMon_);
        s_ = new Structs.Session[](2 + rest_.length);
        s_[0] = Structs.Session({
            sessionStart: fri_,
            durationMinutes: REGULAR_MINUTES,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: sessionTypeRegular
        });
        s_[1] = Structs.Session({
            sessionStart: weekendStart_,
            durationMinutes: uint16(holDurMin_),
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: sessionTypeHoliday
        });
        for (uint256 i_; i_ < rest_.length; i_++) {
            s_[2 + i_] = rest_[i_];
        }
    }

    function test_EmptyScheduleIsUnknown() public view {
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
    }

    function test_RegularAndPostAndPre() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        assertEq(marketHours.getSessionType(mon_ + 1 hours), sessionTypeRegular);
        assertEq(marketHours.getSessionType(mon_ + 7 hours), sessionTypeExtended);
        uint32 tue_ = uint32(uint256(mon_) + 1 days);
        assertEq(marketHours.getSessionType(tue_ - 2 hours), sessionTypeExtended);
        assertEq(marketHours.getSessionType(mon_ + 12 hours), sessionTypeExtended);
    }

    function test_GetSessionInfoReturnsBoth() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) = marketHours
            .getSessionInfo(mon_ + 7 hours);

        assertEq(sessionType_, sessionTypeExtended);
        assertTrue(latestRegularHoursStart_ != 0);
        assertEq(latestRegularHoursStart_, mon_);
        assertEq(latestRegularHoursEnd_, mon_ + 6.5 hours);
    }

    function test_HolidaySkipsRegular() public {
        uint32 mon_ = uint32(1_700_000_000);
        Structs.Session[] memory week_ = _weekWithWeekend(mon_);
        // Tuesday is a holiday; Monday REGULAR already started so started-REGULAR check passes.
        week_[1].sessionType = sessionTypeHoliday;

        vm.warp(uint256(mon_) + 1 days + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(week_);

        assertEq(marketHours.getSessionType(mon_ + 1 days + 1 hours), sessionTypeHoliday);
    }

    function test_FridayThenHoliday() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        uint32 fri_ = uint32(uint256(mon_) + 4 days);
        assertEq(marketHours.getSessionType(fri_ + 11 hours), sessionTypeHoliday);
    }

    function test_MondayPreIsExtendedViaWeekendEntry() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        uint32 nextMon_ = uint32(uint256(mon_) + 7 days);
        // Weekend extended covers next Monday pre (04:00–09:30).
        assertEq(marketHours.getSessionType(nextMon_ - 2 hours), sessionTypeExtended);
        // Past last entry → UNKNOWN (no coverage).
        assertEq(marketHours.getSessionType(nextMon_ + 1 hours), sessionTypeUnknown);
    }

    /// @dev Cursor = low 8 bits of `_sessionData0` (storage slot 1).
    function _currentIndexFromStorage() internal view returns (uint8) {
        return uint8(marketHours.readFromStorage(bytes32(uint256(1))) & 0xff);
    }

    function test_WriteAdvancesIndex() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);
        assertEq(_currentIndexFromStorage(), 0);

        vm.warp(mon_ + 1 days + 1 hours); // Tuesday regular
        marketHours.getCurrentSession();
        assertEq(_currentIndexFromStorage(), 1);

        vm.warp(mon_ + 4 days + 11 hours); // weekend HOLIDAY
        marketHours.getCurrentSession();
        assertEq(_currentIndexFromStorage(), 5);
    }

    function test_CursorOnHolidayStillReturnsFridayRegularWindow() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        uint32 fri_ = uint32(uint256(mon_) + 4 days);
        vm.warp(fri_ + 11 hours);
        (, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) = marketHours.getCurrentSession();
        assertEq(_currentIndexFromStorage(), 5);
        assertTrue(latestRegularHoursStart_ != 0);
        assertEq(latestRegularHoursStart_, fri_);
        assertEq(latestRegularHoursEnd_, fri_ + 6.5 hours);

        // View path with cursor already on weekend must not drop Friday's window.
        (, latestRegularHoursStart_, latestRegularHoursEnd_) = marketHours.getSessionInfo(block.timestamp);
        assertTrue(latestRegularHoursStart_ != 0);
        assertEq(latestRegularHoursStart_, fri_);
        assertEq(latestRegularHoursEnd_, fri_ + 6.5 hours);
    }

    function test_BeforeScheduleCoverageReturnsUnknown() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        // Advance cursor mid-week, then read a timestamp before any stored entry.
        vm.warp(mon_ + 2 days + 1 hours);
        marketHours.getCurrentSession();
        assertTrue(_currentIndexFromStorage() > 0);

        (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) = marketHours
            .getSessionInfo(uint256(mon_) - 1 hours);
        assertEq(sessionType_, sessionTypeUnknown);
        assertEq(latestRegularHoursStart_, 0);
        assertEq(latestRegularHoursEnd_, 0);
    }

    function test_SaturdayRewritePreservesLastRegularHoursWindow() public {
        uint32 mon_ = uint32(1_700_000_000);
        _setWeek(mon_);

        uint32 nextMon_ = uint32(uint256(mon_) + 7 days);
        vm.warp(mon_ + 5 days); // Saturday — inside weekend HOLIDAY of current week
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekRewriteFromNow(nextMon_));

        (uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) = marketHours.getLatestRegularHoursWindow(
            block.timestamp
        );
        assertTrue(latestRegularHoursStart_ != 0);
        uint32 fri_ = uint32(uint256(mon_) + 4 days);
        assertEq(latestRegularHoursStart_, fri_);
        assertEq(latestRegularHoursEnd_, fri_ + 6.5 hours);
    }

    function test_UnauthorizedCannotUpdate() public {
        Structs.Session[] memory week_ = _weekWithWeekend(uint32(1_700_000_000));
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        marketHours.updateWeekSessions(week_);
    }

    function test_OnlyGovernanceCanSetAuth() public {
        address other_ = address(0xB0B);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        marketHours.updateAuth(other_, 1);

        vm.prank(GOVERNANCE);
        marketHours.updateAuth(other_, 1);
        assertTrue(marketHours.isAuth(other_));

        uint32 mon_ = uint32(1_700_000_000);
        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(other_);
        marketHours.updateWeekSessions(_weekWithWeekend(mon_));
    }

    function test_GovernanceCanUpdateWeekSessions() public {
        uint32 mon_ = uint32(1_700_000_000);
        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(GOVERNANCE);
        marketHours.updateWeekSessions(_weekWithWeekend(mon_));
        assertEq(marketHours.getSessionType(mon_ + 1 hours), sessionTypeRegular);
    }

    function test_OverlappingSessionsRevert() public {
        uint32 mon_ = uint32(1_700_000_000);
        Structs.Session[] memory week_ = new Structs.Session[](2);
        // Long enough to pass the 7-day sum check; second starts before first ends.
        week_[0] = Structs.Session({
            sessionStart: mon_,
            durationMinutes: uint16(1 days / 1 minutes),
            extendedDurationMinutes: uint16(3 days / 1 minutes),
            sessionType: sessionTypeRegular
        });
        week_[1] = Structs.Session({
            sessionStart: uint32(uint256(mon_) + 1 days),
            durationMinutes: uint16(1 days / 1 minutes),
            extendedDurationMinutes: uint16(3 days / 1 minutes),
            sessionType: sessionTypeRegular
        });

        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(week_);
    }

    function test_RegularDurationAbove24hReverts() public {
        uint32 mon_ = uint32(1_700_000_000);
        Structs.Session[] memory week_ = new Structs.Session[](2);
        week_[0] = Structs.Session({
            sessionStart: mon_,
            durationMinutes: 1440, // exactly 24h regular is ok
            extendedDurationMinutes: 8191,
            sessionType: sessionTypeRegular
        });
        week_[1] = Structs.Session({
            sessionStart: uint32(uint256(mon_) + 9631 minutes),
            durationMinutes: 449,
            extendedDurationMinutes: 0,
            sessionType: sessionTypeHoliday
        });
        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(week_);

        week_[0].durationMinutes = 1441; // 24h + 1min regular reverts
        week_[1].sessionStart = uint32(uint256(mon_) + 9632 minutes);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(week_);
    }

    function test_GapBetweenSessionsRevert() public {
        uint32 mon_ = uint32(1_700_000_000);
        Structs.Session[] memory week_ = new Structs.Session[](2);
        week_[0] = Structs.Session({
            sessionStart: mon_,
            durationMinutes: uint16(1 days / 1 minutes),
            extendedDurationMinutes: uint16(2 days / 1 minutes),
            sessionType: sessionTypeRegular
        });
        // 1 day gap before second session.
        week_[1] = Structs.Session({
            sessionStart: uint32(uint256(mon_) + 4 days),
            durationMinutes: uint16(1 days / 1 minutes),
            extendedDurationMinutes: uint16(3 days / 1 minutes),
            sessionType: sessionTypeRegular
        });

        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(week_);
    }

    function test_ActiveEntryMustContainNow() public {
        uint32 mon_ = uint32(1_700_000_000);
        vm.warp(uint256(mon_) - 1 days); // before first entry
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(_weekWithWeekend(mon_));
    }

    function test_MustIncludeStartedRegular() public {
        uint32 mon_ = uint32(1_700_000_000);
        // Weekend HOLIDAY only covering `now` — no REGULAR with start <= now.
        uint32 fri_ = uint32(uint256(mon_) + 4 days);
        uint32 weekendStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        Structs.Session[] memory week_ = new Structs.Session[](1);
        week_[0] = Structs.Session({
            sessionStart: weekendStart_,
            durationMinutes: 56 * 60,
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: sessionTypeHoliday
        });

        vm.warp(uint256(weekendStart_) + 1 hours);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(week_);
    }

    function test_ScheduleShorterThan7DaysReverts() public {
        uint32 mon_ = uint32(1_700_000_000);
        Structs.Session[] memory week_ = new Structs.Session[](1);
        week_[0] = Structs.Session({
            sessionStart: mon_,
            durationMinutes: REGULAR_MINUTES,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: sessionTypeRegular
        });
        vm.warp(uint256(mon_) + 1 hours);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.UsEquityMarketHours__InvalidParams)
        );
        marketHours.updateWeekSessions(week_);
    }

    // -------- pinned sessions --------

    /// @dev `_weekWithWeekend` with Monday relabeled HOLIDAY — an elapsed-session rewrite.
    function _weekWithMondayRelabeled(uint32 monStart_) internal view returns (Structs.Session[] memory s_) {
        s_ = _weekWithWeekend(monStart_);
        s_[0].sessionType = sessionTypeHoliday;
    }

    function test_PinnedSessionRewriteRevertsForScheduleWriter() public {
        uint32 mon_ = 1_700_000_000;
        _setWeek(mon_);

        vm.warp(uint256(mon_) + 2 days + 1 hours); // Wednesday regular
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.UsEquityMarketHours__PinnedSessionMutated
            )
        );
        marketHours.updateWeekSessions(_weekWithMondayRelabeled(mon_));

        // anchor unmoved
        (uint32 regStart_, ) = marketHours.getLatestRegularHoursWindow(block.timestamp);
        assertEq(regStart_, uint32(uint256(mon_) + 2 days));
    }

    function test_PinnedSessionRewriteAllowedForOverrideClassAndGovernance() public {
        uint32 mon_ = 1_700_000_000;
        _setWeek(mon_);
        vm.warp(uint256(mon_) + 2 days + 1 hours);

        vm.prank(GOVERNANCE);
        marketHours.updateWeekSessions(_weekWithMondayRelabeled(mon_));
        assertEq(marketHours.getSessionType(uint256(mon_) + 1 hours), sessionTypeHoliday);

        address override_ = address(0xC1A55);
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(override_, 2);
        vm.prank(override_);
        marketHours.updateWeekSessions(_weekWithWeekend(mon_));
        assertEq(marketHours.getSessionType(uint256(mon_) + 1 hours), sessionTypeRegular);
    }

    function test_FutureSessionsStayEditableForScheduleWriter() public {
        uint32 mon_ = 1_700_000_000;
        _setWeek(mon_);
        vm.warp(uint256(mon_) + 2 days + 1 hours);

        // Thursday (still ahead) turned into a holiday closure; Mon–Wed re-posted unchanged.
        Structs.Session[] memory week_ = _weekWithWeekend(mon_);
        week_[3].sessionType = sessionTypeHoliday;
        vm.prank(AUTH);
        marketHours.updateWeekSessions(week_);
        assertEq(marketHours.getSessionType(uint256(mon_) + 3 days + 1 hours), sessionTypeHoliday);
    }

    function test_NextSessionPinnedOnlyWithinLookahead() public {
        uint32 mon_ = 1_700_000_000;
        _setWeek(mon_);

        // Monday's entry ends at Tuesday's open, so Tuesday pins once it is within the lookahead.
        uint32 tue_ = uint32(uint256(mon_) + 1 days);
        Structs.Session[] memory week_ = _weekWithWeekend(mon_);
        week_[1].sessionType = sessionTypeHoliday;

        vm.warp(uint256(tue_) - 6 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(week_);

        vm.warp(uint256(tue_) - 4 hours);
        vm.prank(AUTH);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.UsEquityMarketHours__PinnedSessionMutated
            )
        );
        marketHours.updateWeekSessions(_weekWithWeekend(mon_));
    }

    function test_UpgradeOnlyGovernance() public {
        FluidUsEquityMarketHours newImpl_ = new FluidUsEquityMarketHours(LIQUIDITY);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        marketHours.upgradeTo(address(newImpl_));

        vm.prank(GOVERNANCE);
        marketHours.upgradeTo(address(newImpl_));

        // Schedule still works after upgrade (storage preserved on proxy).
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
    }
}

contract FluidCLXStockOracleTest is Test {
    event LogUpdateAcceptedMultiplier(uint256 oldMultiplier, uint256 newMultiplier);
    event LogUpdateRegularHoursAnchor(uint80 roundId);
    event LogExtendedHoursFallback(uint256 sessionType);
    event LogPause();
    event LogUnpause();

    FluidUsEquityMarketHours marketHours;
    FluidCLXStockOracle oracle;
    MockChainlinkFeed feed;
    MockBackedAutoFeeToken token;
    MockBackedWrapper wrapper;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    uint16 constant REGULAR_MINUTES = 390;
    uint16 constant POST_MINUTES = 240;
    uint16 constant PRE_MINUTES = 330;
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050;
    uint32 constant MON = 1_700_000_000;

    uint8 constant sessionTypeUnknown = 0;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

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

    function _weekWithWeekend(uint32 monStart_) internal view returns (Structs.Session[] memory s_) {
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

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 1);

        feed = new MockChainlinkFeed();
        token = new MockBackedAutoFeeToken();
        wrapper = new MockBackedWrapper(token);

        feed.pushRound(int256(1e10), MON + 1 hours);

        vm.warp(MON + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(MON));

        oracle = new FluidCLXStockOracle(
            CLXStructs.CLXStockOracleConstructorParams({
                infoName: "wSPYx / USD",
                targetDecimals: 27,
                liquidity: LIQUIDITY,
                chainlinkFeed: address(feed),
                backedWrapper: address(wrapper),
                marketHours: address(marketHours),
                rateMultiplier: 1e19,
                maxMultiplierChangePercent: 100, // 1% over 30 days, then capped
                maxExtendedHoursCapPercent: 10e4,
                maxPriceGapDownPercent: 9999, // non-binding for mechanics tests; gap tests use _deployGapOracle
                maxPriceGapUpPercent: 1e8
            })
        );

        oracle.updateRegularHoursAnchor(0);
    }

    function test_OperatePriceDuringRegularHours() public view {
        assertEq(oracle.getExchangeRateOperate(), 1e29);
        assertEq(oracle.getExchangeRateLiquidate(), 1e29);

        CLXStructs.CLXStockOracleConfig memory cfg_ = oracle.getConfig();
        assertEq(oracle.LIQUIDITY(), LIQUIDITY);
        assertEq(cfg_.chainlinkFeed, address(feed));
        assertEq(cfg_.backedWrapper, address(wrapper));
        assertEq(cfg_.marketHours, address(marketHours));
        assertEq(cfg_.rateMultiplier, 1e19);
        assertEq(cfg_.maxMultiplierChangePercent, 100);
        assertEq(cfg_.maxExtendedHoursCapPercent, 10e4);
    }

    function test_OperateWriteStoresRegularHoursAnchor() public {
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        feed.pushRound(int256(12e9), block.timestamp);
        uint80 roundId_ = feed.latestRoundId();

        assertEq(oracle.getExchangeRateOperateWrite(), 12e28);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, roundId_);
        // REGULAR warm stores `block.timestamp` — not `regularEnd` — so later discovery still walks,
        // but from this tip (forward) rather than discarding a "stale" CL `updatedAt`.
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(block.timestamp));
        assertTrue(oracle.getConfig().lastVerifiedRegularHoursEnd != MON + 6.5 hours);
    }

    function test_RegularWriteKeepsQuietHintForForwardWalk() public {
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        // Quiet tip: CL `updatedAt` is older than a fresh print would be, but still within operate
        // staleness. REGULAR write refreshes sync via `block.timestamp` (not CL `updatedAt`).
        uint256 oldPrint_ = block.timestamp - 12 hours;
        feed.pushRound(int256(12e9), oldPrint_);
        uint80 quietRoundId_ = feed.latestRoundId();

        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, quietRoundId_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(block.timestamp));

        // After close + buffer: tip advances. Hint sync is fresh → walk forward from quiet tip.
        // (If freshness used CL `updatedAt` alone and it were >5d old, we'd discard and walk back.)
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(13e9), MON + 6 hours); // late RTH / buffer print
        uint80 lateRthRoundId_ = feed.latestRoundId();
        feed.pushRound(int256(3e10), block.timestamp); // extended spike

        assertEq(oracle.getExchangeRateOperate(), (13e28 * 110) / 100);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, lateRthRoundId_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, MON + 6.5 hours);
    }

    function test_ExtendedHoursCapsUseStoredRegularHoursAnchor() public {
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1);

        // Past official close + 15m buffer so the spike is not itself an RTH print.
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
        // Debt side inverts clamp direction.
        assertEq(oracle.getExchangeRateOperateDebt(), 2e29);
        assertEq(oracle.getExchangeRateLiquidateDebt(), (1e29 * 110) / 100);
    }

    function test_ExtendedHoursClampWalksBackWhenStoredAnchorIsStale() public {
        // Leave Monday's round stored, then move into Tuesday extended with a fresh RTH print.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(15e9), tue_ + 1 hours); // Tuesday RTH → 1.5e29 after scaling
        uint80 tueRthRoundId_ = feed.latestRoundId();

        // Past official close + 15m buffer so the spike is not itself treated as RTH.
        vm.warp(uint256(tue_) + 7 hours);
        feed.pushRound(int256(3e10), block.timestamp); // extended spike

        // Stored hint is still Monday round 1 (outside Tuesday's regular window) → walk finds Tuesday RTH.
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1);
        assertEq(oracle.getExchangeRateOperate(), (15e28 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 3e29);

        // Write warms storage to the resolved Tuesday RTH round.
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, tueRthRoundId_);
    }

    function test_UpdateRegularHoursAnchorWalksBackToLastRegularHoursRound() public {
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 rthRoundId_ = feed.latestRoundId();

        // Past official close + 15m buffer: later prints must be skipped by the walk.
        // Regular ends MON+6.5h; buffer accepts until MON+6.5h+15m (= MON+6h45m).
        vm.warp(MON + 6 hours + 50 minutes);
        feed.pushRound(int256(2e10), block.timestamp);
        feed.pushRound(int256(3e10), block.timestamp + 1);

        oracle.updateRegularHoursAnchor(0);

        assertEq(oracle.getConfig().lastRegularHoursRoundId, rthRoundId_);
        assertEq(oracle.getExchangeRateOperate(), (11e28 * 110) / 100);
    }

    function test_UpdateRegularHoursAnchorHintWalksForwardToLatestInWindow() public {
        feed.pushRound(int256(10e9), MON + 1 hours);
        uint80 earlyRthRoundId_ = feed.latestRoundId();

        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 lateRthRoundId_ = feed.latestRoundId();

        // After buffer: extended prints must not become the anchor.
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        // Early-in-window hint → walk forward to the last in-window round (near close).
        oracle.updateRegularHoursAnchor(earlyRthRoundId_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, lateRthRoundId_);

        // Same result starting from latest (walk back past extended, then settle on late RTH).
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, lateRthRoundId_);
    }

    /// @dev Mainnet SPY/GOOGL quirk: post-tip `getRoundData` can succeed with updatedAt=0. Walk must stop
    ///      immediately (not burn MAX_REGULAR_HOURS_ROUND_LOOKBACK) and keep the last real in-window round.
    function test_UpdateRegularHoursAnchorStopsForwardWalkOnZeroUpdatedAtPhantoms() public {
        feed.pushRound(int256(10e9), MON + 1 hours);
        uint80 earlyRthRoundId_ = feed.latestRoundId();
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 lateRthRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        // No extended print — tip is still the late RTH round. Mark 300 post-tip phantoms like mainnet CL.
        feed.setPhantomRoundsAfterLatest(300);

        uint256 gasBefore_ = gasleft();
        oracle.updateRegularHoursAnchor(earlyRthRoundId_);
        uint256 gasUsed_ = gasBefore_ - gasleft();

        assertEq(oracle.getConfig().lastRegularHoursRoundId, lateRthRoundId_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, MON + 6.5 hours);
        // Must stop at the first phantom, not walk 300 (~1.9M on mainnet). Slack bound: the figure
        // tracks how much state the runner has already warmed (60k on forge 1.7.1, 94k on 1.8.1).
        assertLt(gasUsed_, 150_000);
    }

    /// @dev A phantom hit while walking back counts as a gap: the walk stops instead of reading through it
    ///      to the older real RTH round. Clearing the phantom resolves the same call to that round.
    function test_UpdateRegularHoursAnchorStopsBackWalkOnZeroUpdatedAtPhantom() public {
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 rthRoundId_ = feed.latestRoundId();

        // Past close + 15m buffer: both prints are extended, so the cursor starts after the window.
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);
        uint80 phantomRoundId_ = feed.latestRoundId();
        feed.pushRound(int256(3e10), block.timestamp + 1);
        uint80 tipRoundId_ = feed.latestRoundId();

        feed.setPhantomRound(phantomRoundId_, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound
            )
        );
        oracle.updateRegularHoursAnchor(tipRoundId_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1); // anchor untouched

        // Same call, phantom cleared → back walk reaches the real RTH round.
        feed.setPhantomRound(phantomRoundId_, false);
        oracle.updateRegularHoursAnchor(tipRoundId_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, rthRoundId_);
    }

    function test_ExtendedHoursFloorsLiquidateDownside() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(5e9), block.timestamp);

        assertEq(oracle.getExchangeRateOperate(), 5e28);
        assertEq(oracle.getExchangeRateLiquidate(), (1e29 * 90) / 100);
        // Debt side inverts clamp direction.
        assertEq(oracle.getExchangeRateOperateDebt(), (1e29 * 90) / 100);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 5e28);
    }

    function test_StaleDuringRegularHoursRevertsOperateButLiquidateOk() public {
        feed.setLatest(int256(1e10), MON + 1 hours);
        vm.warp(MON + 1 hours + 24 hours + 20 minutes + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();

        // Liquidate allows up to 5 days (extended).
        assertEq(oracle.getExchangeRateLiquidate(), 1e29);
    }

    function test_StaleAfterFiveDaysRevertsLiquidate() public {
        feed.setLatest(int256(1e10), MON + 1 hours);
        vm.warp(MON + 1 hours + 5 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateLiquidate();
    }

    function test_RawSkipsStalenessAndMultiplierBandReverts() public {
        // Shortly after Monday close (EXTENDED, still in 15 min tight buffer): operate uses 25h staleness.
        vm.warp(MON + 6 hours + 35 minutes);
        feed.setLatest(int256(1e10), MON + 6 hours + 35 minutes - 26 hours);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();

        // Raw still returns operate-side price with extended-hours caps (live == anchor → 1e29).
        assertEq(oracle.getExchangeRateOperateRaw(), 1e29);
        assertEq(oracle.getExchangeRateRaw(), 1e29);

        token.setMultiplier(2e18);
        // Refresh updatedAt so only the multiplier band reverts on the guarded path.
        feed.setLatest(int256(1e10), block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        // Raw skips band revert. Extended-hours caps scale RTH round with the same live multiplier,
        // so a pure multiplier jump (same CL answer) does not hit the CL-side cap.
        assertEq(oracle.getExchangeRateOperateRaw(), 2e29);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 2e29);
    }

    function test_HolidayAllowsOperateWithExtendedStaleness() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        // Saturday (holiday): operate uses 5d extended window (24/5 may not print on weekends).
        feed.setLatest(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 days + 2 hours);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeHoliday);
        assertEq(oracle.getExchangeRateOperate(), 1e29);
    }

    function test_HolidayUsesLiveWithDeviationCaps() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        vm.warp(fri_ + 11 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeHoliday);
        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
    }

    function test_UnknownUsesPreservedRegularHoursWindowWithCaps() public {
        // Seed a Friday RTH print so UNKNOWN can still resolve the preserved regular window.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        // Past last entry → UNKNOWN (no clear-via-empty write).
        uint32 nextMon_ = uint32(uint256(MON) + 7 days);
        vm.warp(nextMon_ + 1 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
    }

    function test_AnchorBufferAcceptsPrintJustAfterRegularClose() public {
        // Official regular end is MON + 6.5h; buffer allows prints up to +15 min.
        feed.pushRound(int256(11e9), MON + 6 hours + 40 minutes);
        uint80 bufferedRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, bufferedRoundId_);
    }

    function test_MultiplierJumpRevertsUntilConfirm() public {
        token.setMultiplier(2e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        uint256 acceptedBefore_ = oracle.getConfig().acceptedMultiplier;
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().acceptedMultiplier, acceptedBefore_);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(2e18);
        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);
        feed.setLatest(int256(1e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), 2e29);
    }

    function test_ConfirmMultiplierChangeRejectsIfLiveFarFromExpected() public {
        token.setMultiplier(2e18);

        // Expected 1.5e18 but live is 2e18 → >1% off → reject.
        vm.prank(GOVERNANCE);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidParams)
        );
        oracle.confirmMultiplierChange(15e17);

        // Within 1% of live is accepted; stored value is live.
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(199e16); // 1.99e18, live 2e18 → 0.5%
        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);
    }

    function test_DownwardMultiplierAlsoNeedsConfirmation() public {
        token.setMultiplier(5e17);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        uint256 acceptedBefore_ = oracle.getConfig().acceptedMultiplier;
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().acceptedMultiplier, acceptedBefore_);
    }

    function test_InBandDownwardMultiplierSyncsOnWrite() public {
        // Seed Friday RTH so UNKNOWN-after-warp clamp can still resolve the preserved window.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        // Full 1% band after 30 days; -0.5% should sync accepted downward and emit.
        vm.warp(block.timestamp + 30 days);
        token.setMultiplier(995e15); // 0.995e18
        feed.pushRound(int256(1e10), block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit LogUpdateAcceptedMultiplier(1e18, 995e15);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().acceptedMultiplier, 995e15);
    }

    function test_OnlyGovernanceOrClass3CanConfirmMultiplierChange() public {
        token.setMultiplier(2e18);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.confirmMultiplierChange(2e18);

        address class2_ = address(0xC0C);
        vm.prank(GOVERNANCE);
        oracle.updateAuth(class2_, 2);
        vm.prank(class2_);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.confirmMultiplierChange(2e18);

        address class3_ = address(0xD0D);
        vm.prank(GOVERNANCE);
        oracle.updateAuth(class3_, 3);
        vm.prank(class3_);
        oracle.confirmMultiplierChange(2e18);
        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);

        token.setMultiplier(3e18);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(3e18);
        assertEq(oracle.getConfig().acceptedMultiplier, 3e18);
    }

    function test_ConstructorRevertsOnZeroLiquidity() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.liquidity = address(0);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        _deployOracle(p_);
    }

    function test_MultiplierBandCapsAtOneMonthEvenIfLonger() public {
        // Seed Friday RTH so UNKNOWN-after-warp clamp can still resolve the preserved window.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        // After >> 30 days, band is still only ±1% — a 2% jump still needs confirmMultiplierChange.
        // Schedule is stale → UNKNOWN + stale MH window → REGULAR-like fallback (5d staleness).
        vm.warp(block.timestamp + 365 days);
        token.setMultiplier(102e16); // +2%
        feed.pushRound(int256(1e10), block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        // +1% at full period is allowed (dividend-sized).
        token.setMultiplier(101e16);
        // 1e10 * 1.01e18 * 1e19 / 1e18 = 1.01e29; live equals RTH×mult so no clamp change.
        assertEq(oracle.getExchangeRateOperate(), 101e27);
    }

    // -------- scheduled multiplier freeze --------

    function _expectScheduledPending() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__ScheduledMultiplierPending
            )
        );
    }

    function test_ScheduledMultiplierJumpFreezesAllGuardedPaths() public {
        token.scheduleMultiplier(2e18, block.timestamp + 2 hours);

        _expectScheduledPending();
        oracle.getExchangeRateOperate();
        _expectScheduledPending();
        oracle.getExchangeRateLiquidate();
        _expectScheduledPending();
        oracle.getExchangeRateOperateDebt();
        _expectScheduledPending();
        oracle.getExchangeRateLiquidateDebt();
        _expectScheduledPending();
        oracle.getExchangeRateOperateWrite();

        // raw + anchor stay usable; confirm cannot lift a pre-activation freeze
        assertEq(oracle.getExchangeRateOperateRaw(), 1e29);
        oracle.updateRegularHoursAnchor(0);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(1e18);
        _expectScheduledPending();
        oracle.getExchangeRateOperate();
    }

    function test_ScheduledMultiplierInBandDoesNotFreeze() public {
        token.scheduleMultiplier(1005e15, block.timestamp + 2 hours); // +0.5% vs live
        assertEq(oracle.getExchangeRateOperate(), 1e29);
    }

    function test_ScheduledMultiplierFreezesOnlyWithinBuffer() public {
        token.scheduleMultiplier(2e18, block.timestamp + 24 hours + 1);
        assertEq(oracle.getExchangeRateOperate(), 1e29);

        // buffer edge is inclusive
        vm.warp(block.timestamp + 1);
        _expectScheduledPending();
        oracle.getExchangeRateOperate();
    }

    function test_ScheduledMultiplierFreezeHandsOverToBandAtActivation() public {
        uint256 activation_ = block.timestamp + 1 hours;
        token.scheduleMultiplier(2e18, activation_);

        _expectScheduledPending();
        oracle.getExchangeRateOperate();

        vm.warp(activation_);
        feed.setLatest(int256(1e10), block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();

        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(2e18);
        assertEq(oracle.getExchangeRateOperate(), 2e29);
    }

    function test_ScheduledMultiplierOverrideToBenignUnfreezes() public {
        token.scheduleMultiplier(2e18, block.timestamp + 2 hours);
        _expectScheduledPending();
        oracle.getExchangeRateOperate();

        token.scheduleMultiplier(1e18, block.timestamp + 2 hours);
        assertEq(oracle.getExchangeRateOperate(), 1e29);
    }

    function test_ScheduledMultiplierFreezeModeAnyDeviationFreezes() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxMultiplierChangePercent = 0;
        FluidCLXStockOracle frozen_ = _deployOracle(p_);

        token.scheduleMultiplier(1e18 + 1, block.timestamp + 2 hours);
        _expectScheduledPending();
        frozen_.getExchangeRateOperate();

        token.scheduleMultiplier(1e18, block.timestamp + 2 hours);
        assertEq(frozen_.getExchangeRateOperate(), 1e29);
    }

    function test_BackedUnderlyingGetterResolvesFromWrapperAsset() public view {
        assertEq(oracle.getConfig().backedWrapper, address(wrapper));
        assertEq(oracle.backedUnderlying(), address(token));
    }

    /// @dev A reverting wrapper must not brick pricing.
    function test_WrapperNotReadOnPricingPaths() public {
        vm.mockCallRevert(
            address(wrapper),
            abi.encodeWithSelector(MockBackedWrapper.convertToAssets.selector),
            "wrapper down"
        );

        assertEq(oracle.getExchangeRateOperate(), 1e29);
        assertEq(oracle.getExchangeRateLiquidate(), 1e29);
        assertEq(oracle.getExchangeRateOperateDebt(), 1e29);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 1e29);
        assertEq(oracle.getExchangeRateOperateRaw(), 1e29);
        oracle.getExchangeRateOperateWrite();
        oracle.updateRegularHoursAnchor(0);

        token.setMultiplier(2e18);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(2e18);
        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);
    }

    // -------- price gap guard --------

    function _expectPriceGapBreak() internal {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__PriceGapBreak)
        );
    }

    /// @dev Production bounds (>42% down / >68% up); reference seeded from the current round via the anchor.
    function _deployGapOracle() internal returns (FluidCLXStockOracle o_) {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxPriceGapDownPercent = 4200;
        p_.maxPriceGapUpPercent = 6800;
        o_ = _deployOracle(p_);
        o_.updateRegularHoursAnchor(0);
    }

    function test_PriceGapDownFreezesGuardedPathsAndSelfHealsOnRecovery() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        feed.pushRound(int256(4e9), block.timestamp); // -60%, new round: reference round keeps 1e10
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();
        _expectPriceGapBreak();
        o_.getExchangeRateLiquidate();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateDebt();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateWrite();
        assertEq(o_.getExchangeRateOperateRaw(), 4e28);

        // stateless: live back in-band resumes with no action
        feed.setLatest(int256(1e10), block.timestamp);
        assertEq(o_.getExchangeRateOperate(), 1e29);
    }

    /// @dev Kills the "gap check only during REGULAR" mutant: without the guard, EXTENDED would pass a
    ///      CL-first split through the clamp (operate takes -50% live, liquidate floors at the cap).
    function test_PriceGapFreezesGuardedPathsInExtendedSession() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        // past close + 15m buffer: CL applies a 2:1 split, nothing scheduled, multiplier unchanged
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(5e9), block.timestamp);

        _expectPriceGapBreak();
        o_.getExchangeRateOperate();
        _expectPriceGapBreak();
        o_.getExchangeRateLiquidate();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateDebt();
        _expectPriceGapBreak();
        o_.getExchangeRateLiquidateDebt();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateWrite();
        assertEq(o_.getExchangeRateOperateRaw(), 5e28);
    }

    /// @dev Weekend HOLIDAY: the clamp finds no Friday anchor (fallback), but the gap reference is
    ///      MH-independent and still freezes while inside its 5d max age.
    function test_PriceGapFreezesGuardedPathsOnWeekendHoliday() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        vm.warp(uint256(MON) + 4 days + 11 hours);
        feed.pushRound(int256(5e9), block.timestamp);

        _expectPriceGapBreak();
        o_.getExchangeRateOperate();
        _expectPriceGapBreak();
        o_.getExchangeRateLiquidate();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateDebt();
        _expectPriceGapBreak();
        o_.getExchangeRateLiquidateDebt();
        _expectPriceGapBreak();
        o_.getExchangeRateOperateWrite();
        assertEq(o_.getExchangeRateOperateRaw(), 5e28);
    }

    /// @dev A 2:1 split printed as two quick rounds must not be walkable by re-anchoring onto the
    ///      intermediate print: rolls are blocked in the first 20m of REGULAR, and afterwards the walk
    ///      resolves the (out-of-band) latest print, so the pre-split reference holds until class ≥ 3.
    function test_PriceGapSplitPrintWalkBlockedAtSessionOpen() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        // Tuesday 9:35: intermediate print -30%, in-band vs Monday reference; write may not roll onto it
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        vm.warp(uint256(tue_) + 5 minutes);
        feed.pushRound(int256(7e9), block.timestamp);
        o_.getExchangeRateOperateWrite();
        assertEq(o_.getConfig().lastRegularHoursRoundId, 1);

        // final post-split print: -50% vs the still-held reference
        feed.pushRound(int256(5e9), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // past the session-open delay the resolver finds the latest (post-split) print — still out-of-band
        vm.warp(uint256(tue_) + 25 minutes);
        _expectPriceGapBreak();
        o_.updateRegularHoursAnchor(0);
        assertEq(o_.getConfig().lastRegularHoursRoundId, 1);
    }

    /// @dev Worst case for the post-close warm bot: a hint stored in the session's final second delays
    ///      the verified close store until close + 20m at most — hint rounds never print after the close.
    function test_PriceGapCloseStoreAllowedTwentyMinutesAfterFinalHint() public {
        uint32 regularEnd_ = uint32(MON + 6.5 hours);
        vm.warp(uint256(regularEnd_) - 1);
        feed.pushRound(int256(11e9), block.timestamp);
        uint80 finalHint_ = feed.latestRoundId();
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, finalHint_);

        feed.pushRound(int256(112e8), uint256(regularEnd_) + 5 minutes); // close print in the buffer

        vm.warp(uint256(regularEnd_) + 15 minutes);
        oracle.updateRegularHoursAnchor(0); // hint only 16m old: silent skip
        assertEq(oracle.getConfig().lastRegularHoursRoundId, finalHint_);

        vm.warp(uint256(regularEnd_) + 21 minutes);
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, feed.latestRoundId());
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, regularEnd_);
    }

    function test_PriceGapReferenceRollsRateLimitedBetweenRounds() public {
        vm.warp(block.timestamp + 20 minutes);
        feed.pushRound(int256(12e9), block.timestamp);
        uint80 second_ = feed.latestRoundId();
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, second_);

        // stored round younger than 20m: the write prices but does not roll
        feed.pushRound(int256(13e9), block.timestamp);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, second_);

        vm.warp(block.timestamp + 20 minutes);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, feed.latestRoundId());
    }

    function test_PriceGapExactBoundariesPass() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        feed.pushRound(int256(58e8), block.timestamp); // exactly -42%, new round: reference round keeps 1e10
        assertEq(o_.getExchangeRateOperate(), 58e27);
        feed.setLatest(int256(58e8 - 1), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        feed.setLatest(int256(168e8), block.timestamp); // exactly +68%
        assertEq(o_.getExchangeRateOperate(), 168e27);
        feed.setLatest(int256(168e8 + 1), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();
    }

    function test_PriceGapAnchorRollBlockedMidGap() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        feed.pushRound(int256(4e9), block.timestamp);

        _expectPriceGapBreak();
        o_.updateRegularHoursAnchor(0);
    }

    function test_PriceGapAuthedAnchorRollUnfreezes() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        feed.pushRound(int256(4e9), block.timestamp);
        uint80 postGapRound_ = feed.latestRoundId();

        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // class 2 is not enough for an out-of-band roll
        address class2_ = address(0xC0C);
        vm.prank(GOVERNANCE);
        o_.updateAuth(class2_, 2);
        vm.prank(class2_);
        _expectPriceGapBreak();
        o_.updateRegularHoursAnchor(0);

        address class3_ = address(0xD0D);
        vm.prank(GOVERNANCE);
        o_.updateAuth(class3_, 3);
        vm.prank(class3_);
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRegularHoursAnchor(postGapRound_);
        o_.updateRegularHoursAnchor(0);
        assertEq(o_.getExchangeRateOperate(), 4e28);
    }

    function test_PriceGapInBandAnchorRollStaysPermissionless() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        feed.pushRound(int256(13e9), block.timestamp); // +30%

        vm.prank(address(0xBEEF));
        o_.updateRegularHoursAnchor(0);
        assertEq(o_.getConfig().lastRegularHoursRoundId, feed.latestRoundId());
    }

    function test_PriceGapAgeOutUnfreezesWithoutIntervention() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        feed.pushRound(int256(4e9), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // reference round ages past 5d: check disarms, pricing resumes with no action
        vm.warp(uint256(MON) + 5 days + 2 hours);
        feed.pushRound(int256(4e9), block.timestamp);
        assertEq(o_.getExchangeRateLiquidate(), 4e28);
    }

    function test_PriceGapUnreadableReferenceRoundSkipsCheck() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        feed.setRevertRound(1, true); // stored reference round
        feed.pushRound(int256(1e9), block.timestamp); // -90%
        assertEq(o_.getExchangeRateOperate(), 1e28); // fail-open
    }

    function test_PriceGapUnaffectedByMultiplierMoves() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        token.setMultiplier(2e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        o_.getExchangeRateOperate();

        // the reference scales with the live multiplier: a confirmed multiplier move is no CL gap
        vm.prank(GOVERNANCE);
        o_.confirmMultiplierChange(2e18);
        assertEq(o_.getExchangeRateOperate(), 2e29);
    }

    function test_PriceGapFullSplitTimeline() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        // 1. Backed schedules the 10:1 multiplier hours ahead
        token.scheduleMultiplier(1e19, block.timestamp + 2 hours);
        _expectScheduledPending();
        o_.getExchangeRateOperate();

        // 2. CL reprices ahead of activation; scheduled freeze is first in check order
        feed.pushRound(int256(1e9), block.timestamp);
        _expectScheduledPending();
        o_.getExchangeRateOperate();

        // 3. activation: multiplier flips, band takes over
        vm.warp(block.timestamp + 2 hours);
        feed.pushRound(int256(1e9), block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        o_.getExchangeRateOperate();

        // 4. confirm alone does not clear the CL-leg gap vs the pre-split reference
        vm.prank(GOVERNANCE);
        o_.confirmMultiplierChange(1e19);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // 5. auth'd re-anchor onto a post-split round resumes continuous pricing
        vm.prank(GOVERNANCE);
        o_.updateRegularHoursAnchor(0);
        assertEq(o_.getExchangeRateOperate(), 1e29);
    }

    function test_PriceGapWriteRollsReference() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        vm.warp(block.timestamp + 20 minutes); // reference roll delay

        // +40% is in-band; the write stores the new round as reference.
        feed.pushRound(int256(14e9), block.timestamp);
        o_.getExchangeRateOperateWrite();

        // +96% cumulative vs the original reference, but only +40% vs the rolled one.
        feed.pushRound(int256(196e8), block.timestamp);
        assertEq(o_.getExchangeRateOperate(), 196e27);
    }

    function test_PriceGapStaleReferenceSkipsCheck() public {
        FluidCLXStockOracle o_ = _deployGapOracle();
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        // +200% vs the 7d-old reference would break; age > 5d skips the check (fail-open).
        vm.warp(uint256(MON) + 7 days + 1 hours);
        feed.pushRound(int256(3e10), block.timestamp);
        assertEq(o_.getExchangeRateOperate(), (1e29 * 110) / 100);
    }

    function test_PriceGapNoReferenceSkipsCheck() public {
        FluidCLXStockOracle o_ = _deployOracle(_defaultParams()); // no anchor stored yet

        feed.setLatest(int256(1e9), block.timestamp); // -90%
        assertEq(o_.getExchangeRateOperate(), 1e28);
    }

    function test_ConstructorRevertsOnZeroPriceGapPercents() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxPriceGapDownPercent = 0;
        _expectInvalidParams();
        _deployOracle(p_);

        p_ = _defaultParams();
        p_.maxPriceGapUpPercent = 0;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnPriceGapDownAtHundredPercent() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxPriceGapDownPercent = 1e4;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_GetConfigExposesPriceGapPercents() public {
        CLXStructs.CLXStockOracleConfig memory cfg_ = _deployGapOracle().getConfig();
        assertEq(cfg_.maxPriceGapDownPercent, 4200);
        assertEq(cfg_.maxPriceGapUpPercent, 6800);
    }

    /// @dev 2:1 is the smallest split large caps still do (PANW 2024, MNST/APH 2026) — bounds must clear it
    ///      even when genuine drift pushes the net move toward the bound.
    function test_PriceGapCatchesTwoForOneSplitWithAdverseDrift() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        // clean 2:1 vs the 1e10 reference: -50%
        feed.pushRound(int256(5e9), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // +5% drift before the split shrinks the net move to -47.5%; still caught at 42%
        feed.setLatest(int256(525e7), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // only a >16% same-window rally would hide it (net -42%): documented margin
        feed.setLatest(int256(58e8), block.timestamp);
        assertEq(o_.getExchangeRateOperate(), 58e27);
    }

    function test_PriceGapCatchesOneForTwoReverseSplitWithAdverseDrift() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        // clean 1:2 reverse vs the 1e10 reference: +100%
        feed.pushRound(int256(2e10), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // -5% drift before the reverse split leaves +90%; still caught at 68%
        feed.setLatest(int256(19e9), block.timestamp);
        _expectPriceGapBreak();
        o_.getExchangeRateOperate();

        // mirrored margin: only a >16% same-window selloff would hide it (net +68%)
        feed.setLatest(int256(168e8), block.timestamp);
        assertEq(o_.getExchangeRateOperate(), 168e27);
    }

    /// @dev Documented limitation: a 3:2 split is only -33%, inside any bound that avoids false freezes
    ///      (worst legit overnight gap on these names ~-26%). Mid-cap-only ratio; not in the xStock roster.
    function test_PriceGapDoesNotCatchThreeForTwoSplit() public {
        FluidCLXStockOracle o_ = _deployGapOracle();

        feed.pushRound(int256(6667e6), block.timestamp); // 1e10 / 1.5
        assertEq(o_.getExchangeRateOperate(), 6667e25);
    }

    // -------- helpers for constructor / deploy --------

    function _defaultParams() internal view returns (CLXStructs.CLXStockOracleConstructorParams memory p_) {
        p_ = CLXStructs.CLXStockOracleConstructorParams({
            infoName: "wSPYx / USD",
            targetDecimals: 27,
            liquidity: LIQUIDITY,
            chainlinkFeed: address(feed),
            backedWrapper: address(wrapper),
            marketHours: address(marketHours),
            rateMultiplier: 1e19,
            maxMultiplierChangePercent: 100,
            maxExtendedHoursCapPercent: 10e4,
            maxPriceGapDownPercent: 9999,
            maxPriceGapUpPercent: 1e8
        });
    }

    function _deployOracle(
        CLXStructs.CLXStockOracleConstructorParams memory p_
    ) internal returns (FluidCLXStockOracle) {
        return new FluidCLXStockOracle(p_);
    }

    function _expectInvalidParams() internal {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidParams)
        );
    }

    function _expectNotFound() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound
            )
        );
    }

    function _regularEnd() internal pure returns (uint32) {
        return MON + 6.5 hours;
    }

    function _windowEnd() internal pure returns (uint256) {
        return uint256(_regularEnd()) + 15 minutes;
    }

    // -------- constructor / InvalidParams --------

    function test_ConstructorRevertsOnNon27TargetDecimals() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.targetDecimals = 15;
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.FluidOracle__InvalidTargetDecimals
            )
        );
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnEmptyInfoName() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.infoName = "";
        vm.expectRevert(StringBytes32Utils.StringBytes32Utils__InvalidStringLength.selector);
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnOversizedInfoName() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.infoName = "this info name is definitely longer than thirty two bytes";
        vm.expectRevert(StringBytes32Utils.StringBytes32Utils__InvalidStringLength.selector);
        _deployOracle(p_);
    }

    function test_InfoNameRoundTrips() public view {
        assertEq(oracle.infoName(), "wSPYx / USD");
        assertEq(oracle.targetDecimals(), 27);
    }

    function test_ConstructorRevertsOnZeroChainlinkFeed() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.chainlinkFeed = address(0);
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnZeroBackedWrapper() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.backedWrapper = address(0);
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnZeroMarketHours() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.marketHours = address(0);
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnZeroRateMultiplier() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.rateMultiplier = 0;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnRateMultiplierTooHigh() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.rateMultiplier = 1e27 + 1;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorAllowsRateMultiplierAtMax() public {
        // Retarget CL answer so CL × mult × 1e27 / 1e18 stays in a sane vault price band for the smoke read.
        feed.setLatest(int256(1e8), block.timestamp); // $1 at 8 decimals
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.rateMultiplier = 1e27;
        FluidCLXStockOracle o_ = _deployOracle(p_);
        assertEq(o_.getConfig().rateMultiplier, 1e27);
        // 1e8 * 1e18 * 1e27 / 1e18 = 1e35
        assertEq(o_.getExchangeRateOperate(), 1e35);
    }

    function test_ConstructorAllowsZeroMaxMultiplierChangePercentFreezeMode() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxMultiplierChangePercent = 0;
        FluidCLXStockOracle frozen_ = _deployOracle(p_);
        assertEq(frozen_.getConfig().maxMultiplierChangePercent, 0);
        // Unchanged live must still price (not a silent permanent brick).
        assertEq(frozen_.getExchangeRateOperate(), 1e29);

        token.setMultiplier(1e18 + 1);
        feed.setLatest(int256(1e10), block.timestamp);
        bytes memory needsConfirm_ = abi.encodeWithSelector(
            Error.FluidStockOracleError.selector,
            ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
        );
        vm.expectRevert(needsConfirm_);
        frozen_.getExchangeRateOperate();

        // Confirm escape hatch still works with exact live.
        vm.prank(GOVERNANCE);
        frozen_.confirmMultiplierChange(1e18 + 1);
        assertEq(frozen_.getConfig().acceptedMultiplier, 1e18 + 1);
        assertEq(frozen_.getExchangeRateOperate(), (1e18 + 1) * 1e11);
    }

    function test_ConstructorRevertsOnMaxMultiplierChangePercentTooHigh() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxMultiplierChangePercent = 1001;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnZeroMaxExtendedHoursCapPercent() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxExtendedHoursCapPercent = 0;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnMaxExtendedHoursCapPercentTooHigh() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxExtendedHoursCapPercent = 1e6 + 1;
        _expectInvalidParams();
        _deployOracle(p_);
    }

    function test_ConstructorRevertsOnZeroChainlinkPrice() public {
        feed.setLatest(0, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidPrice)
        );
        _deployOracle(_defaultParams());
    }

    function test_ConstructorRevertsOnZeroWrapperMultiplier() public {
        token.setMultiplier(0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidPrice)
        );
        _deployOracle(_defaultParams());
    }

    function test_ConstructorRevertsOnWrapperPassthroughMismatch() public {
        wrapper.setPassthroughSkew(1);
        _expectInvalidParams();
        _deployOracle(_defaultParams());
    }

    function test_ConstructorRevertsWhileDiscontinuousSchedulePending() public {
        token.scheduleMultiplier(2e18, block.timestamp + 2 hours);
        _expectScheduledPending();
        _deployOracle(_defaultParams());

        token.scheduleMultiplier(1005e15, block.timestamp + 2 hours);
        _deployOracle(_defaultParams());
    }

    function test_ConstructorSeedsAcceptedMultiplierAndUpdateTime() public {
        uint256 ts_ = block.timestamp;
        FluidCLXStockOracle o_ = _deployOracle(_defaultParams());
        CLXStructs.CLXStockOracleConfig memory cfg_ = o_.getConfig();
        assertEq(cfg_.acceptedMultiplier, 1e18);
        assertEq(cfg_.lastMultiplierUpdateTime, uint32(ts_));
    }

    // -------- API surface --------

    function test_GetExchangeRateEqualsOperate() public view {
        assertEq(oracle.getExchangeRate(), oracle.getExchangeRateOperate());
    }

    function test_LiquidateWriteStoresVerifiedRegularHoursAnchor() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        uint256 tsBefore_ = oracle.getConfig().lastMultiplierUpdateTime;
        oracle.getExchangeRateLiquidateWrite();

        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, _regularEnd());
        assertTrue(oracle.getConfig().lastVerifiedRegularHoursEnd != uint32(block.timestamp));
        assertEq(oracle.getConfig().lastMultiplierUpdateTime, tsBefore_);
    }

    function test_OperateDebtWriteMatchesDebtViewAndStoresAnchor() public {
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        feed.pushRound(int256(12e9), block.timestamp);
        uint80 roundId_ = feed.latestRoundId();

        uint256 viewDebtRate_ = oracle.getExchangeRateOperateDebt();
        assertEq(oracle.getExchangeRateOperateDebtWrite(), viewDebtRate_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, roundId_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(block.timestamp));
    }

    function test_LiquidateDebtWriteMatchesDebtViewAndStoresAnchor() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        uint256 tsBefore_ = oracle.getConfig().lastMultiplierUpdateTime;
        uint256 viewDebtRate_ = oracle.getExchangeRateLiquidateDebt();
        assertEq(oracle.getExchangeRateLiquidateDebtWrite(), viewDebtRate_);

        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, _regularEnd());
        assertEq(oracle.getConfig().lastMultiplierUpdateTime, tsBefore_);
    }

    function test_OperateRawLiquidateRawAndRawParityDuringRegular() public view {
        assertEq(oracle.getExchangeRateOperateRaw(), oracle.getExchangeRateLiquidateRaw());
        assertEq(oracle.getExchangeRateOperateRaw(), oracle.getExchangeRateRaw());
        assertEq(oracle.getExchangeRateOperateRaw(), 1e29);
    }

    function test_DebtCollateralParityDuringRegularHoursWithinBand() public view {
        assertEq(oracle.getExchangeRateOperateDebt(), oracle.getExchangeRateOperate());
        assertEq(oracle.getExchangeRateLiquidateDebt(), oracle.getExchangeRateLiquidate());
    }

    function test_InBandMultiplierDoesNotRevertOnOperate() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        vm.warp(block.timestamp + 15 days);
        token.setMultiplier(1005e15); // +0.5% after half band period
        feed.pushRound(int256(1e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), 1005e26);
    }

    // -------- staleness matrix --------

    function test_UpdatedAtZeroRevertsStalePrice() public {
        feed.setLatest(int256(1e10), 0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
    }

    /// @dev The `updatedAt == 0` rule for CL round walks (phantom = gap) must not leak into the live price
    ///      path: a zero-`updatedAt` latest round stays `StalePrice` on every priced read, and raw stays
    ///      deliberately staleness-agnostic (non-zero price, no revert).
    function test_UpdatedAtZeroLatestRoundStalePriceOnEveryPricedRead() public {
        feed.setLatest(int256(1e10), 0);
        bytes memory stale_ = abi.encodeWithSelector(
            Error.FluidStockOracleError.selector,
            ErrorTypes.CLXStockOracle__StalePrice
        );

        vm.expectRevert(stale_);
        oracle.getExchangeRate();
        vm.expectRevert(stale_);
        oracle.getExchangeRateLiquidate();
        vm.expectRevert(stale_);
        oracle.getExchangeRateOperateDebt();
        vm.expectRevert(stale_);
        oracle.getExchangeRateLiquidateDebt();
        vm.expectRevert(stale_);
        oracle.getExchangeRateOperateWrite();
        vm.expectRevert(stale_);
        oracle.getExchangeRateLiquidateWrite();

        assertEq(oracle.getExchangeRateRaw(), 1e29);
        assertEq(oracle.getExchangeRateOperateRaw(), 1e29);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 1e29);
    }

    function test_OperateExtendedUsesHeartbeatStaleness() public {
        vm.warp(MON + 7 hours);
        uint256 staleAt_ = block.timestamp - (24 hours + 20 minutes);
        feed.setLatest(int256(1e10), staleAt_);
        assertEq(oracle.getExchangeRateOperate(), 1e29);

        feed.setLatest(int256(1e10), staleAt_ - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_OperateRegularStalenessBoundaryExactlyAtMaxAgeOk() public {
        uint256 printAt_ = MON + 1 hours;
        feed.setLatest(int256(1e10), printAt_);
        vm.warp(printAt_ + 24 hours + 20 minutes);
        assertEq(oracle.getExchangeRateOperate(), 1e29);
    }

    function test_OperateRegularStalenessBoundaryOneSecondOverReverts() public {
        uint256 printAt_ = MON + 1 hours;
        feed.setLatest(int256(1e10), printAt_);
        vm.warp(printAt_ + 24 hours + 20 minutes + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_LiquidateStalenessBoundaryExactlyAtMaxAgeOk() public {
        // Same-day extended: MH window still fresh → clamp path → liquidate allows 5d.
        vm.warp(MON + 7 hours);
        uint256 printAt_ = block.timestamp - 5 days;
        feed.pushRound(int256(1e10), printAt_);
        assertEq(oracle.getExchangeRateLiquidate(), 1e29);
    }

    function test_LiquidateStalenessBoundaryOneSecondOverReverts() public {
        vm.warp(MON + 7 hours);
        uint256 printAt_ = block.timestamp - 5 days - 1;
        feed.pushRound(int256(1e10), printAt_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateLiquidate();
    }

    // -------- multiplier band --------

    /// @dev Regression: floored percent accrued to 0 for ~7.2h at MAX%=1%; absolute maxDiff must not.
    function test_EarlyBandWindowAllowsTinyDriftBelowOnePercentUnit() public {
        // At 1h: maxDiff ≈ 1e18 * 100 * 1h / (30d * 1e4) ≈ 1.388e13.
        vm.warp(block.timestamp + 1 hours);
        uint256 live_ = 1e18 + 1e13; // < maxDiff at 1h, >> 0
        token.setMultiplier(live_);
        feed.pushRound(int256(1e10), block.timestamp);

        // 1e10 * live * 1e19 / 1e18 = live * 1e11
        assertEq(oracle.getExchangeRateOperate(), live_ * 1e11);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().acceptedMultiplier, live_);
    }

    function test_EarlyBandWindowSameSecondStillRejectsAnyDrift() public {
        // elapsed = 0 → maxDiff = 0; nonzero drift must still need confirm.
        token.setMultiplier(1e18 + 1);
        feed.setLatest(int256(1e10), block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        oracle.getExchangeRateOperate();
    }

    function test_EarlyBandWindowStillRejectsOutOfBandJump() public {
        vm.warp(block.timestamp + 1 hours);
        // +1% absolute while accrued band at 1h is ≪ 1% → NeedsConfirmation.
        token.setMultiplier(101e16);
        feed.pushRound(int256(1e10), block.timestamp);
        bytes memory needsConfirm_ = abi.encodeWithSelector(
            Error.FluidStockOracleError.selector,
            ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
        );
        vm.expectRevert(needsConfirm_);
        oracle.getExchangeRateOperate();
        vm.expectRevert(needsConfirm_);
        oracle.getExchangeRateLiquidate();
    }

    function test_FreezeModeRejectsLiquidateDriftToo() public {
        CLXStructs.CLXStockOracleConstructorParams memory p_ = _defaultParams();
        p_.maxMultiplierChangePercent = 0;
        FluidCLXStockOracle frozen_ = _deployOracle(p_);
        assertEq(frozen_.getExchangeRateLiquidate(), 1e29);

        token.setMultiplier(1e18 + 1);
        feed.setLatest(int256(1e10), block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
        frozen_.getExchangeRateLiquidate();
    }

    function test_InBandUpwardMultiplierSyncsOnWrite() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);

        vm.warp(block.timestamp + 30 days);
        token.setMultiplier(1005e15); // +0.5%
        feed.pushRound(int256(1e10), block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit LogUpdateAcceptedMultiplier(1e18, 1005e15);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().acceptedMultiplier, 1005e15);
    }

    function test_NoMultiplierSyncWhenLiveEqualsAccepted() public {
        uint256 tsBefore_ = oracle.getConfig().lastMultiplierUpdateTime;
        uint256 acceptedBefore_ = oracle.getConfig().acceptedMultiplier;

        oracle.getExchangeRateOperateWrite();

        assertEq(oracle.getConfig().acceptedMultiplier, acceptedBefore_);
        assertEq(oracle.getConfig().lastMultiplierUpdateTime, tsBefore_);
    }

    function test_ConfirmMultiplierChangeRevertsOnZeroExpected() public {
        token.setMultiplier(2e18);
        vm.prank(GOVERNANCE);
        _expectInvalidParams();
        oracle.confirmMultiplierChange(0);
    }

    function test_ConfirmMultiplierChangeRevertsOnZeroLiveMultiplier() public {
        token.setMultiplier(0);
        vm.prank(GOVERNANCE);
        _expectInvalidParams();
        oracle.confirmMultiplierChange(1e18);
    }

    function test_ConfirmMultiplierChangeRevertsOnLiveAboveUint104Max() public {
        token.setMultiplier(uint256(type(uint104).max) + 1);
        vm.prank(GOVERNANCE);
        _expectInvalidParams();
        oracle.confirmMultiplierChange(type(uint104).max);
    }

    function test_ConfirmMultiplierChangeUpdatesTimeAndEmits() public {
        token.setMultiplier(2e18);
        uint256 tsBefore_ = oracle.getConfig().lastMultiplierUpdateTime;

        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, true, true, true);
        emit LogUpdateAcceptedMultiplier(1e18, 2e18);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(2e18);

        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);
        assertEq(oracle.getConfig().lastMultiplierUpdateTime, uint32(block.timestamp));
        assertTrue(oracle.getConfig().lastMultiplierUpdateTime > tsBefore_);
    }

    // -------- RTH resolve / cache --------

    /// @dev A mid-session anchor call must not stamp the verified-for-close marker: the close may still print,
    ///      and a cache hit on that marker would clamp the whole extended period to an intraday price.
    function test_MidSessionAnchorDoesNotPinPostCloseReference() public {
        vm.warp(MON + 2 hours);
        feed.pushRound(int256(11e9), block.timestamp);
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(block.timestamp), "mid-session = hint only");
        assertTrue(oracle.getConfig().lastVerifiedRegularHoursEnd != _regularEnd(), "must not claim the close");

        // the real close prints lower than the pinned intraday round
        vm.warp(uint256(_regularEnd()) - 5 minutes);
        feed.pushRound(int256(8e9), block.timestamp);
        uint80 closeRoundId_ = feed.latestRoundId();

        // extended hours must clamp against the close, not the pin
        vm.warp(uint256(_regularEnd()) + 1 hours);
        feed.pushRound(int256(2e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), (8e28 * 110) / 100, "clamped to close +10%");
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, closeRoundId_, "anchor is the close round");
    }

    /// @dev Forward-walk lookback exhaustion must fail open (like the back walk) instead of certifying a
    ///      non-latest in-window round as the regular-hours close.
    function test_ForwardWalkExhaustionDoesNotCertifyNonLatestRound() public {
        uint80 earlyRoundId_ = feed.latestRoundId(); // setUp round at MON + 1 hours (in window)

        // more in-window rounds after it than the lookback can traverse
        for (uint256 i_; i_ < 301; ++i_) {
            feed.pushRound(int256(9e9), MON + 2 hours + i_);
        }

        vm.warp(uint256(_regularEnd()) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound
            )
        );
        oracle.updateRegularHoursAnchor(earlyRoundId_);
    }

    function test_CacheHitUsesStoredRoundWithoutRediscovery() public {
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 rthRoundId_ = feed.latestRoundId();
        // anchor after the close: during REGULAR the marker is only a hint (the close may still print)
        vm.warp(uint256(_regularEnd()) + 1);
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, _regularEnd());

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(99e9), block.timestamp); // would skew discovery if re-walked

        assertEq(oracle.getExchangeRateOperate(), (11e28 * 110) / 100);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, rthRoundId_);
    }

    function test_RegularWriteSyncNotEqualToRegularEnd() public {
        uint32 regularEnd_ = _regularEnd();
        feed.pushRound(int256(12e9), block.timestamp);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(block.timestamp));
        assertTrue(oracle.getConfig().lastVerifiedRegularHoursEnd != regularEnd_);
    }

    function test_UpdateRegularHoursAnchorRevertsOutsideRegularWhenNotFound() public {
        vm.warp(MON + 7 hours); // EXTENDED — clamp needs the anchor
        feed.setLatest(int256(2e10), _windowEnd() + 1);
        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_UpdateRegularHoursAnchorNoOpEarlyRegularBeforeFirstPrint() public {
        // This morning's WSPY case: in REGULAR, CL tip still pre-open — quiet no-op (no invent / no alert).
        uint80 roundBefore_ = oracle.getConfig().lastRegularHoursRoundId;
        uint32 endBefore_ = oracle.getConfig().lastVerifiedRegularHoursEnd;

        feed.setLatest(int256(1e10), MON - 2 hours);
        vm.warp(MON + 10 minutes);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeRegular);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, roundBefore_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, endBefore_);
        // Live REGULAR pricing still works without the warm cache.
        assertEq(oracle.getExchangeRateOperate(), 1e29);
    }

    function test_UpdateRegularHoursAnchorExplicitRoundAgesByUpdatedAt() public {
        feed.pushRound(int256(10e9), MON + 1 hours);
        uint80 earlyRoundId_ = feed.latestRoundId();
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 lateRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        // Explicit hint: freshness from round `updatedAt`, not storage sync marker.
        oracle.updateRegularHoursAnchor(earlyRoundId_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, lateRoundId_);
    }

    function test_StaleHintOlderThanFiveDaysDiscardsAndWalksBack() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        feed.pushRound(int256(11e9), fri_ + 6 hours);
        uint80 friLateRound_ = feed.latestRoundId();

        vm.warp(fri_ + 1 hours);
        oracle.getExchangeRateOperateWrite();
        uint80 friHintRound_ = oracle.getConfig().lastRegularHoursRoundId;
        uint32 friHintSync_ = oracle.getConfig().lastVerifiedRegularHoursEnd;

        vm.warp(fri_ + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.updateRegularHoursAnchor(friHintRound_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, friLateRound_);

        vm.warp(uint256(friHintSync_) + 5 days + 1);
        feed.setLatest(int256(2e10), fri_ + 7 hours);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, friLateRound_);
    }

    function test_FutureUpdatedAtOnHintFallsBackToLatest() public {
        uint256 futureAt_ = block.timestamp + 1 hours;
        feed.pushRound(int256(5e9), futureAt_);
        uint80 futureRoundId_ = feed.latestRoundId();
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 validRthRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.updateRegularHoursAnchor(futureRoundId_);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, validRthRoundId_);
    }

    function test_RegularStartZeroFallsBackToLiveUnclamped() public {
        vm.warp(MON - 1 hours);
        feed.setLatest(int256(2e10), block.timestamp);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);

        assertEq(oracle.getExchangeRateOperate(), 2e29);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
        assertEq(oracle.getExchangeRateOperateDebt(), 2e29);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 2e29);
    }

    function test_RegularStartZeroRawReturnsUnclamped() public {
        vm.warp(MON - 1 hours);
        feed.setLatest(int256(2e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperateRaw(), 2e29);
    }

    function test_WriteEmitsFallbackOnNoWindow() public {
        uint80 roundBefore_ = oracle.getConfig().lastRegularHoursRoundId;
        uint32 endBefore_ = oracle.getConfig().lastVerifiedRegularHoursEnd;

        vm.warp(MON - 1 hours);
        feed.setLatest(int256(2e10), block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit LogExtendedHoursFallback(sessionTypeUnknown);
        oracle.getExchangeRateOperateWrite();

        // Fallback must not persist a fake RTH round.
        assertEq(oracle.getConfig().lastRegularHoursRoundId, roundBefore_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, endBefore_);
    }

    function test_StaleMhWindowFallsBackToLiveUnclamped() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        uint32 friEnd_ = fri_ + 6.5 hours;
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(uint256(friEnd_) + 1); // anchor post-close so the marker is the verified close
        oracle.updateRegularHoursAnchor(0);

        // Exactly 5d after regular end → window untrusted; live spike must not be capped to +10%.
        vm.warp(uint256(friEnd_) + 5 days);
        feed.pushRound(int256(2e10), block.timestamp);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
        assertEq(oracle.getExchangeRateOperate(), 2e29);

        vm.expectEmit(true, true, true, true);
        emit LogExtendedHoursFallback(sessionTypeUnknown);
        oracle.getExchangeRateOperateWrite();
        // Successful write still must not refresh verified end from an untrusted window.
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, friEnd_);
    }

    function test_SilentRthFallsBackToLiveAndEmitsOnWrite() public {
        // Monday cache from setUp does not match Tuesday's regularEnd → must rediscover; no Tue RTH print.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        uint32 monEnd_ = oracle.getConfig().lastVerifiedRegularHoursEnd;
        vm.warp(tue_ + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        assertEq(oracle.getExchangeRateOperate(), 2e29);

        vm.expectEmit(true, true, true, true);
        emit LogExtendedHoursFallback(sessionTypeExtended);
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, monEnd_);
    }

    function test_FallbackUses5DayStalenessForOperateAndLiquidate() public {
        vm.warp(MON - 1 hours);
        uint256 printAt_ = block.timestamp;
        feed.setLatest(int256(2e10), printAt_);
        assertEq(oracle.getExchangeRateOperate(), 2e29);

        vm.warp(printAt_ + 5 days);
        assertEq(oracle.getExchangeRateOperate(), 2e29);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);

        vm.warp(printAt_ + 5 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateLiquidate();
    }

    function test_UpdateRegularHoursAnchorRevertsOnStaleWindow() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        uint32 friEnd_ = fri_ + 6.5 hours;
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        vm.warp(uint256(friEnd_) + 5 days);
        feed.pushRound(int256(2e10), block.timestamp);
        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_TrustedWindowBoundaryOneSecondUnderFiveDaysStillClamps() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        uint32 friEnd_ = fri_ + 6.5 hours;
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        // Age = 5d - 1s → window still trusted; live spike must clamp to +10%.
        vm.warp(uint256(friEnd_) + 5 days - 1);
        feed.pushRound(int256(2e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
    }

    function test_SilentRthFallbackOperateRevertsBeyondHeartbeat() public {
        // Fully silent Tuesday (no print since Monday RTH, 36h old): operate requires heartbeat freshness
        // even in fallback; liquidate stays on the 5d rule.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        vm.warp(uint256(tue_) + 13 hours);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 1e29);
    }

    function test_LookbackExhaustionOnPricingFallsBackToLive() public {
        // Monday verified cache must not match Tuesday's regularEnd, or we never walk.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        vm.warp(tue_ + 7 hours);
        for (uint256 i_; i_ < 301; ++i_) {
            feed.pushRound(int256(2e10), block.timestamp);
        }
        // Walk from tip exhausts lookback without an in-window round → pricing fail-opens to live.
        assertEq(oracle.getExchangeRateOperate(), 2e29);
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
    }

    function test_LiquidateWriteEmitsFallbackOnNoWindow() public {
        vm.warp(MON - 1 hours);
        feed.setLatest(int256(2e10), block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit LogExtendedHoursFallback(sessionTypeUnknown);
        oracle.getExchangeRateLiquidateWrite();
    }

    // -------- walk back / forward edge cases --------
    function test_WindowEndBoundaryIsInWindow() public {
        feed.pushRound(int256(11e9), _windowEnd());
        uint80 boundaryRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, boundaryRoundId_);
    }

    function test_WindowEndPlusOneIsOutside() public {
        vm.warp(MON + 7 hours);
        feed.setLatest(int256(2e10), _windowEnd() + 1);
        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_QuietSessionAnchorsPreWindowPrintWithinHeartbeatLookback() public {
        // wSPYx 2026-08-10 case: heartbeat print pre-open, zero prints through the whole RTH session.
        // Once the window is fully past, the pre-window print is certified by CL deviation semantics.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(2e10), uint256(tue_) - 1 hours);
        vm.warp(uint256(tue_) + 7 hours); // EXTENDED, Tuesday window fully past

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(uint256(tue_) + 6.5 hours));

        // Clamp anchors to the pre-window print: live 2x anchor → operate capped to anchor +10%.
        feed.pushRound(int256(4e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), (2e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 4e29); // floor at anchor -10% does not bite
    }

    function test_QuietSessionViewClampWalksToPreWindowAnchor() public {
        // View path (Monday cache mismatches Tuesday regularEnd) rediscovers the pre-window anchor.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(12e9), uint256(tue_) - 1 hours); // heartbeat print pre-open, then silent RTH
        vm.warp(uint256(tue_) + 7 hours);
        feed.pushRound(int256(24e9), block.timestamp); // live extended print

        assertEq(oracle.getExchangeRateOperate(), (12e28 * 110) / 100); // capped to anchor +10%
        assertEq(oracle.getExchangeRateLiquidate(), 24e28); // floor does not bite
    }

    function test_WalkBackAcceptsPreWindowPrintWithinLookback() public {
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(12e9), uint256(tue_) - 1 hours); // round 2: Tuesday pre-open heartbeat
        vm.warp(uint256(tue_) + 7 hours);
        feed.pushRound(int256(3e10), block.timestamp); // round 3: tip beyond Tuesday windowEnd

        oracle.updateRegularHoursAnchor(feed.latestRoundId()); // walk back from tip
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(uint256(tue_) + 6.5 hours));
    }

    function test_InWindowPrintWinsOverPreWindowPrint() public {
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(12e9), uint256(tue_) - 1 hours); // round 2: pre-open
        feed.pushRound(int256(14e9), uint256(tue_) + 3 hours); // round 3: in-window
        vm.warp(uint256(tue_) + 7 hours);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 3);
    }

    function test_QuietFridayDeadlineBoundaryInWeekendAccepted() public {
        // Deadline (print + heartbeat) lands exactly at weekend HOLIDAY start → missing print proves
        // nothing (feed expectedly silent) → anchor trusted.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        uint256 weekendStart_ = uint256(fri_) + 6.5 hours + 4 hours; // Friday post-market ends
        feed.pushRound(int256(2e10), weekendStart_ - (24 hours + 20 minutes)); // round 2: pre-Friday-open
        vm.warp(uint256(fri_) + 1 days + 2 hours); // Saturday
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeHoliday);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(uint256(fri_) + 6.5 hours));
    }

    function test_QuietFridayDeadlineBeforeWeekendRejected() public {
        // Deadline falls 1s before weekend start — Friday post-market EXTENDED, feed owed a print while
        // its market was trading → provable miss → anchor rejected even queried on Saturday.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        uint256 weekendStart_ = uint256(fri_) + 6.5 hours + 4 hours;
        feed.pushRound(int256(2e10), weekendStart_ - (24 hours + 20 minutes) - 1);
        vm.warp(uint256(fri_) + 1 days + 2 hours); // Saturday

        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_QuietFridayAnchorStaysTrustedThroughMondayPreMarket() public {
        // Quiet Friday: last print before Friday open, deadline lands inside the weekend → the anchor
        // stays trusted through Monday pre-market (EXTENDED), keeping the clamp active.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(2e10), uint256(fri_) - 1 hours); // round 2: last print before Friday open
        uint256 preMarket_ = uint256(fri_) + 6.5 hours + 4 hours + 56 hours + 1 hours; // Monday pre-market
        vm.warp(preMarket_);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeExtended);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);

        // Clamp active vs the Friday-certified anchor once a fresh Monday print lands.
        feed.pushRound(int256(4e10), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), (2e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), 4e29);
    }

    function test_QuietSessionAnchorRejectedAfterHeartbeatGap() public {
        // Last print Tuesday pre-open, quiet Tuesday, feed silent past its heartbeat ("Wed 1am" case):
        // liveness unproven → anchor rejected (alert) and operate reverts stale; liquidate stays on 5d.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(2e10), uint256(tue_) - 13 hours); // round 2: last print
        vm.warp(uint256(tue_) - 13 hours + 24 hours + 20 minutes + 1);

        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
    }

    function test_QuietSessionAnchorTrustedByNextHeartbeatPrint() public {
        // Anchor older than heartbeat vs now, but the next print came within heartbeat of it → feed was
        // provably live across the quiet session → certification holds, clamp active.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(2e10), uint256(tue_) - 13 hours); // round 2: pre-open print
        feed.pushRound(int256(4e10), uint256(tue_) + 11 hours); // round 3: next heartbeat print, 24h later
        vm.warp(uint256(tue_) + 12 hours); // round 2 now 25h old

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);

        assertEq(oracle.getExchangeRateOperate(), (2e29 * 110) / 100); // capped to anchor +10%
        assertEq(oracle.getExchangeRateLiquidate(), 4e29);
    }

    function test_QuietSessionAnchorRejectedWhenNextPrintBeyondHeartbeat() public {
        // Feed recovers only after violating its heartbeat across the session → certification void →
        // no clamp: live is served unclamped instead of being capped against an untrustworthy anchor.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(2e10), uint256(tue_) - 13 hours); // round 2: pre-open print
        feed.pushRound(int256(4e10), uint256(tue_) + 12 hours); // round 3: 25h gap > heartbeat
        vm.warp(uint256(tue_) + 12 hours + 30 minutes);

        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getExchangeRateOperate(), 4e29); // unclamped fallback, live is fresh
    }

    function test_QuietSessionCachedAnchorInvalidatedAfterHeartbeatGap() public {
        // Anchor stored while trusted; feed then goes silent past heartbeat → cache hit must re-reject.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(2e10), uint256(tue_) - 13 hours); // round 2: last print ever
        vm.warp(uint256(tue_) + 7 hours);
        oracle.updateRegularHoursAnchor(0); // trusted: only 20h old
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 2);

        vm.warp(uint256(tue_) - 13 hours + 24 hours + 20 minutes + 1); // heartbeat now violated
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
        assertEq(oracle.getExchangeRateLiquidate(), 2e29);
    }

    function test_QuietSessionRejectsPreWindowPrintBeyondHeartbeatLookback() public {
        // Print older than heartbeat + grace vs the close = the feed skipped a heartbeat → alert.
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        uint256 windowStart_ = uint256(tue_) + 6.5 hours + 15 minutes - (24 hours + 20 minutes);
        feed.pushRound(int256(2e10), windowStart_ - 1);
        vm.warp(uint256(tue_) + 7 hours);

        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_WalkForwardNeverFindsInWindowReturnsNotFound() public {
        vm.warp(MON + 7 hours);
        feed.setLatest(int256(0), MON + 1 hours);
        feed.pushRound(int256(2e10), block.timestamp);
        _expectNotFound();
        oracle.updateRegularHoursAnchor(1);
    }

    function test_GetRoundDataRevertDuringWalkReturnsNotFound() public {
        uint32 tue_ = uint32(uint256(MON) + 1 days);
        feed.pushRound(int256(15e9), tue_ + 1 hours);
        feed.pushRound(int256(16e9), tue_ + 6 hours);
        feed.setRevertRound(2, true);
        feed.setRevertRound(3, true);

        vm.warp(tue_ + 7 hours);
        feed.pushRound(int256(3e10), block.timestamp);

        _expectNotFound();
        oracle.updateRegularHoursAnchor(0);
    }

    function test_ZeroOrNegativeAnswerNotSelectedAsValidRTH() public {
        feed.pushRound(int256(-1), MON + 1 hours);
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 validRoundId_ = feed.latestRoundId();

        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, validRoundId_);
    }

    // -------- clamp math --------

    function test_LiveExactlyAtCapNoClampChange() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(11e9), block.timestamp); // exactly +10% vs 1e29 anchor
        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
        assertEq(oracle.getExchangeRateLiquidate(), (1e29 * 110) / 100);
    }

    function test_LiveJustInsideCapNoClamp() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(1099e7), block.timestamp);
        assertEq(oracle.getExchangeRateOperate(), 1099e26);
    }

    function test_LiveJustOutsideCapClamps() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(1101e7), block.timestamp); // 11.01% above anchor
        assertEq(oracle.getExchangeRateOperate(), (1e29 * 110) / 100);
    }

    function test_RawReturnsUnclampedWhenReferenceNotFound() public {
        vm.warp(MON - 1 hours);
        feed.setLatest(int256(25e9), block.timestamp);
        assertEq(oracle.getExchangeRateOperateRaw(), 25e28);
    }

    // -------- InvalidPrice --------

    function test_GuardedRevertsInvalidPriceOnZeroAnswer() public {
        feed.setLatest(0, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidPrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_GuardedRevertsInvalidPriceOnLatestRevert() public {
        feed.setRevertLatest(true);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidPrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_RawReturnsZeroOnInvalidPrice() public {
        feed.setLatest(0, block.timestamp);
        assertEq(oracle.getExchangeRateOperateRaw(), 0);
        assertEq(oracle.getExchangeRateRaw(), 0);
    }

    function test_GuardedRevertsInvalidPriceWhenScalingTruncatesToZero() public {
        // Extreme parameterization: all factors non-zero yet the product scales below 1e18.
        FluidCLXStockOracle oracle_ = new FluidCLXStockOracle(
            CLXStructs.CLXStockOracleConstructorParams({
                infoName: "wSPYx / USD",
                targetDecimals: 27,
                liquidity: LIQUIDITY,
                chainlinkFeed: address(feed),
                backedWrapper: address(wrapper),
                marketHours: address(marketHours),
                rateMultiplier: 1,
                maxMultiplierChangePercent: 100,
                maxExtendedHoursCapPercent: 10e4,
                maxPriceGapDownPercent: 9999,
                maxPriceGapUpPercent: 1e8
            })
        );

        feed.setLatest(1, block.timestamp);
        token.setMultiplier(1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__InvalidPrice)
        );
        oracle_.getExchangeRateOperate();
        assertEq(oracle_.getExchangeRateOperateRaw(), 0);
    }

    // -------- write path --------

    function test_NonRegularWriteStoresRoundIdAndRegularEnd() public {
        vm.warp(MON + 7 hours);
        feed.pushRound(int256(2e10), block.timestamp);

        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, 1);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, _regularEnd());
    }

    function test_RegularWriteStoresRoundIdAndBlockTimestamp() public {
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        feed.pushRound(int256(12e9), block.timestamp);
        uint80 roundId_ = feed.latestRoundId();
        uint256 ts_ = block.timestamp;

        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getConfig().lastRegularHoursRoundId, roundId_);
        assertEq(oracle.getConfig().lastVerifiedRegularHoursEnd, uint32(ts_));
    }

    // -------- Fable coverage gaps --------

    function test_ConstructorRevertsOnMultiplierAboveUint104Max() public {
        // Only live branch of the post-`_readLatestPrice` InvalidParams check (zeros never reach it).
        token.setMultiplier(uint256(type(uint104).max) + 1);
        _expectInvalidParams();
        _deployOracle(_defaultParams());
    }

    function test_HolidayOperateRevertsWhenOlderThanFiveDays() public {
        // Holiday window itself is <5d, so use a CL stamp older than 5d while still in holiday.
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        vm.warp(fri_ + 1 days + 2 hours); // Saturday holiday
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeHoliday);
        feed.setLatest(int256(1e10), block.timestamp - 5 days - 1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_UnknownOperateRevertsWhenOlderThanFiveDays() public {
        uint32 fri_ = uint32(uint256(MON) + 4 days);
        feed.pushRound(int256(1e10), fri_ + 1 hours);
        vm.warp(fri_ + 1 hours);
        oracle.updateRegularHoursAnchor(0);

        uint32 nextMon_ = uint32(uint256(MON) + 7 days);
        vm.warp(nextMon_ + 1 hours);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeUnknown);
        feed.setLatest(int256(1e10), block.timestamp - 5 days - 1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StalePrice)
        );
        oracle.getExchangeRateOperate();
    }

    function test_RawReturnsZeroOnZeroWrapperMultiplier() public {
        token.setMultiplier(0);
        assertEq(oracle.getExchangeRateOperateRaw(), 0);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 0);
        assertEq(oracle.getExchangeRateRaw(), 0);
    }

    function test_UpdateRegularHoursAnchorEmitsEvent() public {
        vm.warp(block.timestamp + 20 minutes); // reference roll delay
        feed.pushRound(int256(11e9), MON + 6 hours);
        uint80 expectedRoundId_ = feed.latestRoundId();

        vm.expectEmit(true, true, true, true);
        emit LogUpdateRegularHoursAnchor(expectedRoundId_);
        oracle.updateRegularHoursAnchor(0);
        assertEq(oracle.getConfig().lastRegularHoursRoundId, expectedRoundId_);
    }

    function test_WalkBackLookbackExhaustionReturnsNotFound() public {
        // Explicit tip hint (not stored RTH round) so we walk back through 301 post-window prints.
        vm.warp(MON + 7 hours);
        for (uint256 i_; i_ < 301; ++i_) {
            feed.pushRound(int256(2e10), block.timestamp);
        }
        uint80 tip_ = feed.latestRoundId();
        _expectNotFound();
        oracle.updateRegularHoursAnchor(tip_);
    }

    function test_SyncAcceptedMultiplierStorageOverflowOnWrite() public {
        // accepted = uint104.max; live = max+1 still in-band after a short accrual → sync cast overflows.
        // Stay in REGULAR so write does not hit RTH discovery first.
        token.setMultiplier(type(uint104).max);
        feed.setLatest(int256(1e10), block.timestamp);
        vm.prank(GOVERNANCE);
        oracle.confirmMultiplierChange(type(uint104).max);
        assertEq(oracle.getConfig().acceptedMultiplier, type(uint104).max);

        token.setMultiplier(uint256(type(uint104).max) + 1);
        vm.warp(block.timestamp + 1 days); // still Tuesday REGULAR of the same week schedule
        feed.setLatest(int256(1e10), block.timestamp);
        assertEq(marketHours.getSessionType(block.timestamp), sessionTypeRegular);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__StorageOverflow)
        );
        oracle.getExchangeRateOperateWrite();
    }

    // -------- Pause --------

    function test_PauseBlocksPricingAndUnpauseRestores() public {
        uint256 before_ = oracle.getExchangeRateOperate();
        assertFalse(oracle.getConfig().paused);

        vm.expectEmit(true, true, true, true);
        emit LogPause();
        vm.prank(GOVERNANCE);
        oracle.pause();
        assertTrue(oracle.getConfig().paused);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__Paused)
        );
        oracle.getExchangeRateOperate();
        // Raw stays readable while paused (skip pause / band / staleness).
        assertEq(oracle.getExchangeRateOperateRaw(), before_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidStockOracleError.selector, ErrorTypes.CLXStockOracle__Paused)
        );
        oracle.getExchangeRateOperateWrite();

        // Anchor warm still allowed while paused.
        oracle.updateRegularHoursAnchor(0);

        vm.expectEmit(true, true, true, true);
        emit LogUnpause();
        vm.prank(GOVERNANCE);
        oracle.unpause();
        assertFalse(oracle.getConfig().paused);
        assertEq(oracle.getExchangeRateOperate(), before_);
    }

    function test_AuthClass1CanPauseButNotUnpause() public {
        address pauseAuth_ = address(0xB0B);
        vm.prank(GOVERNANCE);
        oracle.updateAuth(pauseAuth_, 1);
        assertEq(oracle.authClass(pauseAuth_), 1);

        vm.prank(pauseAuth_);
        oracle.pause();
        assertTrue(oracle.getConfig().paused);

        vm.prank(pauseAuth_);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.unpause();

        vm.prank(GOVERNANCE);
        oracle.unpause();
        assertFalse(oracle.getConfig().paused);
    }

    function test_AuthClass2CanPauseAndUnpause() public {
        address pauseUnpauseAuth_ = address(0xC0C);
        vm.prank(GOVERNANCE);
        oracle.updateAuth(pauseUnpauseAuth_, 2);

        vm.prank(pauseUnpauseAuth_);
        oracle.pause();
        assertTrue(oracle.getConfig().paused);

        vm.prank(pauseUnpauseAuth_);
        oracle.unpause();
        assertFalse(oracle.getConfig().paused);
    }

    function test_PauseUnauthorizedReverts() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.pause();

        // Team is not privileged unless governance sets it as an auth class.
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.pause();

        vm.prank(GOVERNANCE);
        oracle.pause();

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.unpause();
    }

    function test_AuthClass3CanPauseUnpauseAndConfirm() public {
        address class3_ = address(0xD0D);
        vm.prank(GOVERNANCE);
        oracle.updateAuth(class3_, 3);

        vm.prank(class3_);
        oracle.pause();
        assertTrue(oracle.getConfig().paused);
        vm.prank(class3_);
        oracle.unpause();
        assertFalse(oracle.getConfig().paused);

        token.setMultiplier(2e18);
        vm.prank(class3_);
        oracle.confirmMultiplierChange(2e18);
        assertEq(oracle.getConfig().acceptedMultiplier, 2e18);
    }

    function test_UpdateAuthOnlyGovernance() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.updateAuth(address(0xB0B), 1);

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.updateAuth(address(0xB0B), 1);

        vm.prank(GOVERNANCE);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        oracle.updateAuth(address(0), 1);

        vm.prank(GOVERNANCE);
        _expectInvalidParams();
        oracle.updateAuth(address(0xB0B), 4);
    }
}
