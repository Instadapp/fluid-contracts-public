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
import { Error } from "../../../contracts/oracleV2/stocks/error.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";

import { MockChronicle, MockRealityToken, MockRealityTokenTrade, MockAuthGate, SequencerUptimeFeedMock } from "./chrStockOracleMocks.sol";

contract CHRStockOracleTest is Test {
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
    address constant STRANGER = address(0xBAD);

    uint16 constant REGULAR_MINUTES = 390;
    uint16 constant POST_MINUTES = 240;
    uint16 constant PRE_MINUTES = 330;
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

    uint256 constant MON = 1_700_000_000;
    /// @dev Monday regular window: [MON, REG_END).
    uint256 constant REG_END = MON + 390 minutes;
    uint256 constant FRI = MON + 4 days;

    uint256 constant ANCHOR = 700e27;
    uint256 constant CAP_FLOOR = 595e27;
    uint256 constant CAP_CEIL = 805e27;

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

    function _deploy(CHRStructs.CHRStockOracleConstructorParams memory p_) internal returns (FluidCHRStockOracle) {
        return new FluidCHRStockOracleL2(p_, address(feed));
    }

    function _expectErr(uint256 id_) internal {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidStockOracleError.selector, id_));
    }

    function _expectUnauthorized() internal {
        vm.expectRevert(abi.encodeWithSelector(MockAuthGate.Access__Unauthorized.selector));
    }

    function _setPrice(uint256 price18_) internal {
        chronicle.set(true, price18_, block.timestamp);
    }

    function _setPriceAt(uint256 price18_, uint256 age_) internal {
        chronicle.set(true, price18_, age_);
    }

    function _setSequencerUp() internal {
        feed.setRound(1, 0, MON - 1 days);
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

        oracle = _deploy(_params());
        _setPrice(700e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
    }

    // ------------------------------------------------------------------ constructor

    function test_constructor_RevertIfChronicleNoCode() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.chronicle = makeAddr("noCode");
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfRtokenNoCode() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.rtoken = makeAddr("noCode");
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfRealityTokenTradeNoCode() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.realityTokenTrade = makeAddr("noCode");
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfMarketHoursNoCode() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.marketHours = makeAddr("noCode");
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfAuthGateNoCode() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.authGate = makeAddr("noCode");
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfSequencerFeedNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.SequencerL2__InvalidFeed)
        );
        new FluidCHRStockOracleL2(_params(), makeAddr("noCode"));
    }

    function test_constructor_RevertIfLiquidityZero() public {
        authGate.setLiquidity(address(0));
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(_params());
    }

    function test_constructor_RevertIfMultiplierZero() public {
        rtoken.setUIMultiplier(0);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(_params());
    }

    function test_constructor_RevertIfMultiplierAboveUint104() public {
        rtoken.setUIMultiplier(uint256(type(uint104).max) + 1);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(_params());
    }

    function test_constructor_RevertIfCapZero() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxCapPercent = 0;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfCapNotBelowBreak() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxCapPercent = 3000;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfBreakAtOrAbove100Percent() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxBreakPercent = 10_000;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfOperateAgeZero() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxOperateAge = 0;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfOperateAgeAboveLiquidateAge() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxOperateAge = 2 hours;
        p_.maxLiquidateAge = 1 hours;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfLiquidateAgeAboveFiveDays() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxLiquidateAge = 5 days + 1;
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        _deploy(p_);
    }

    function test_constructor_RevertIfTargetDecimals26() public {
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.targetDecimals = 26;
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.FluidOracle__InvalidTargetDecimals
            )
        );
        _deploy(p_);
    }

    function test_constructor_SetsAcceptedMultiplier() public {
        rtoken.setUIMultiplier(2e18);
        FluidCHRStockOracle fresh_ = _deploy(_params());
        assertEq(fresh_.getConfig().acceptedMultiplier, 2e18);
    }

    // ------------------------------------------------------------------ read path

    function test_guardedGetters_ReturnLiveValueInsideCap() public view {
        assertEq(oracle.getExchangeRateOperate(), 700e27);
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);
        assertEq(oracle.getExchangeRateOperateDebt(), 700e27);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 700e27);
    }

    function test_getExchangeRateOperate_RevertIfSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.SequencerL2__SequencerDown
            )
        );
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfSequencerGracePeriod() public {
        uint256 t1_ = block.timestamp - 10 minutes;
        feed.setRound(1, 1, t1_ - 30 minutes);
        feed.setRound(2, 0, t1_);
        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.SequencerL2__GracePeriod)
        );
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfPaused() public {
        vm.prank(MID);
        oracle.pause();
        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfRtokenPaused() public {
        rtoken.setPaused(true);
        _expectErr(ErrorTypes.CHRStockOracle__RtokenPaused);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfTradePaused() public {
        trade.setTradePaused(address(rtoken), true);
        _expectErr(ErrorTypes.CHRStockOracle__TradePaused);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfMultiplierZero() public {
        rtoken.setUIMultiplier(0);
        _expectErr(ErrorTypes.CHRStockOracle__MultiplierChanged);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfMultiplierChanged() public {
        rtoken.setUIMultiplier(2e18);
        _expectErr(ErrorTypes.CHRStockOracle__MultiplierChanged);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChronicleNotOk() public {
        chronicle.set(false, 700e18, block.timestamp);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChroniclePriceZero() public {
        chronicle.set(true, 0, block.timestamp);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChroniclePriceAboveUint128() public {
        chronicle.set(true, uint256(type(uint128).max) + 1, block.timestamp);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChronicleAgeZero() public {
        chronicle.set(true, 700e18, 0);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChronicleAgeInFuture() public {
        chronicle.set(true, 700e18, block.timestamp + 1);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfChronicleReverts() public {
        chronicle.setRevert(true);
        vm.expectRevert();
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_LivePriceBeforeFirstAnchor() public {
        FluidCHRStockOracle fresh_ = _deploy(_params());
        _setPrice(1400e18);
        assertEq(fresh_.getExchangeRateOperate(), 1400e27);
        assertEq(fresh_.getExchangeRateLiquidate(), 1400e27);
        assertEq(fresh_.getExchangeRateLiquidateDebt(), 1400e27);
    }

    function test_getExchangeRateOperate_RevertIfPriceBreakDown() public {
        _setPrice(490e18 - 1);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfPriceBreakUp() public {
        _setPrice(910e18 + 1);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateLiquidate_BreakBoundIsInclusive() public {
        _setPrice(490e18);
        assertEq(oracle.getExchangeRateLiquidate(), CAP_FLOOR);
        _setPrice(910e18);
        assertEq(oracle.getExchangeRateLiquidate(), 910e27);
    }

    function test_getExchangeRateLiquidate_RevertIfPriceBreakDown() public {
        _setPrice(490e18 - 1);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateLiquidate();
    }

    function test_getExchangeRateLiquidate_RevertIfPriceBreakUp() public {
        _setPrice(910e18 + 1);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateLiquidate();
    }

    function test_getExchangeRateOperate_AcceptsPriceAtOperateAgeBound() public {
        _setPriceAt(700e18, block.timestamp - 1 hours);
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    function test_getExchangeRateOperate_RevertIfStale() public {
        _setPriceAt(700e18, block.timestamp - 1 hours - 1);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateLiquidate_AcceptsPriceAtLiquidateAgeBound() public {
        _setPriceAt(700e18, block.timestamp - 1 days);
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);
    }

    function test_getExchangeRateLiquidate_RevertIfStale() public {
        _setPriceAt(700e18, block.timestamp - 1 days - 1);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.getExchangeRateLiquidate();
    }

    function test_getExchangeRateOperate_RevertIfOutsideCapBelow() public {
        _setPrice(595e18 - 1);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_RevertIfOutsideCapAbove() public {
        _setPrice(805e18 + 1);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperateDebt_RevertIfOutsideCap() public {
        _setPrice(590e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperateDebt();
    }

    function test_getExchangeRateOperate_CapBoundIsInclusive() public {
        _setPrice(595e18);
        assertEq(oracle.getExchangeRateOperate(), CAP_FLOOR);
        _setPrice(805e18);
        assertEq(oracle.getExchangeRateOperate(), CAP_CEIL);
    }

    function test_getExchangeRateOperate_PriceBreakBeforeStale() public {
        _setPriceAt(480e18, block.timestamp - 2 hours);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_StaleBeforeOutsideCap() public {
        _setPriceAt(590e18, block.timestamp - 2 hours);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateOperate_TradePausedBeforeMultiplierChanged() public {
        rtoken.setUIMultiplier(2e18);
        trade.setTradePaused(address(rtoken), true);
        _expectErr(ErrorTypes.CHRStockOracle__TradePaused);
        oracle.getExchangeRateOperate();
    }

    // ------------------------------------------------------------------ clamp

    function test_getExchangeRateLiquidate_ClampsCollateralToFloor() public {
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidate(), CAP_FLOOR);
    }

    function test_getExchangeRateLiquidate_ReturnsLiveAboveCeiling() public {
        _setPrice(810e18);
        assertEq(oracle.getExchangeRateLiquidate(), 810e27);
    }

    function test_getExchangeRateLiquidateDebt_ClampsDebtToCeiling() public {
        _setPrice(810e18);
        assertEq(oracle.getExchangeRateLiquidateDebt(), CAP_CEIL);
    }

    function test_getExchangeRateLiquidateDebt_ReturnsLiveBelowFloor() public {
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidateDebt(), 590e27);
    }

    // ------------------------------------------------------------------ raw and getExchangeRate

    function test_getExchangeRateRaw_ReturnsLiveWhilePaused() public {
        vm.prank(MID);
        oracle.pause();
        assertEq(oracle.getExchangeRateRaw(), 700e27);
    }

    function test_getExchangeRateRaw_ReturnsLiveWhenFlaggedOrBeyondBreak() public {
        rtoken.setPaused(true);
        _setPrice(480e18);
        assertEq(oracle.getExchangeRateRaw(), 480e27);
    }

    function test_getExchangeRateOperateRaw_CapsAtCeiling() public {
        _setPrice(810e18);
        assertEq(oracle.getExchangeRateOperateRaw(), CAP_CEIL);
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateOperateRaw(), 590e27);
    }

    function test_getExchangeRateLiquidateRaw_FloorsAtCap() public {
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidateRaw(), CAP_FLOOR);
        _setPrice(810e18);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 810e27);
    }

    function test_getExchangeRateRaw_ReturnsZeroIfChronicleInvalid() public {
        chronicle.set(false, 700e18, block.timestamp);
        assertEq(oracle.getExchangeRateRaw(), 0);
        assertEq(oracle.getExchangeRateOperateRaw(), 0);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 0);
    }

    function test_getExchangeRateRaw_NoClampWithoutAnchor() public {
        FluidCHRStockOracle fresh_ = _deploy(_params());
        _setPrice(810e18);
        assertEq(fresh_.getExchangeRateOperateRaw(), 810e27);
        _setPrice(590e18);
        assertEq(fresh_.getExchangeRateLiquidateRaw(), 590e27);
    }

    function test_getExchangeRate_RevertIfSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.SequencerL2__SequencerDown
            )
        );
        oracle.getExchangeRate();
    }

    function test_getExchangeRate_ReturnsLiveWhilePaused() public {
        vm.prank(MID);
        oracle.pause();
        assertEq(oracle.getExchangeRate(), 700e27);
    }

    // ------------------------------------------------------------------ anchor upkeep (SPEC §7)

    function test_updateRegularHoursAnchor_RecordsHintInRegularSession() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.hintValue, 705e27);
        assertEq(s_.hintAge, MON + 2 hours);
        assertEq(s_.hintRegularEnd, REG_END);
    }

    function test_updateRegularHoursAnchor_RecordsHintAtRegularEnd() public {
        vm.warp(REG_END);
        _setPriceAt(705e18, REG_END);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, REG_END, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, REG_END);
    }

    function test_updateRegularHoursAnchor_RecordsHintAtRegularEndPlusBuffer() public {
        vm.warp(REG_END + 120);
        _setPriceAt(705e18, REG_END + 120);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, REG_END + 120, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, REG_END + 120);
    }

    function test_updateRegularHoursAnchor_NoHintAfterRegularEndPlusBuffer() public {
        vm.warp(REG_END + 121);
        _setPriceAt(705e18, REG_END + 121);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_getExchangeRateLiquidate_HintIsAnchorAfterRegularEndBeforeWrite() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        // the hint sets the floor (705 * 85% = 599.25), not the 700 anchor's 595
        vm.warp(MON + 7 hours);
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidate(), 599.25e27);
        assertEq(oracle.getConfig().anchorValue, ANCHOR);
        assertEq(oracle.getConfig().anchorTime, MON + 1 hours);
    }

    function test_updateRegularHoursAnchor_SealsHintAfterRegularEnd() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        vm.warp(MON + 7 hours);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 2 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 2 hours);
        assertEq(s_.hintAge, 0);
    }

    function test_updateRegularHoursAnchor_RecordsAndSealsAfterRegularEndBuffer() public {
        vm.warp(MON + 6 hours);
        _setPriceAt(705e18, MON + 6 hours);
        vm.warp(REG_END + 2 minutes + 1);

        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 6 hours, REG_END);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 6 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 6 hours);
        assertEq(s_.hintAge, 0);
    }

    function test_updateRegularHoursAnchor_DoesNotSealInsideBuffer() public {
        vm.warp(MON + 6 hours);
        _setPriceAt(705e18, MON + 6 hours);
        vm.warp(REG_END + 10);

        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 6 hours, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.hintAge, MON + 6 hours);
        assertEq(s_.anchorTime, MON + 1 hours);
    }

    function test_updateRegularHoursAnchor_CloseInsideBufferReplacesHint() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        vm.warp(REG_END + 60);
        _setPriceAt(710e18, REG_END + 60);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(710e27, REG_END + 60, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintValue, 710e27);
        assertEq(oracle.getConfig().hintAge, REG_END + 60);

        vm.warp(REG_END + 2 minutes + 1);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(710e27, REG_END + 60);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 710e27);
        assertEq(s_.anchorTime, REG_END + 60);
        assertEq(s_.hintAge, 0);
    }

    function test_getExchangeRateOperateWrite_RecordsHint() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertEq(oracle.getExchangeRateOperateWrite(), 705e27);
    }

    function test_updateRegularHoursAnchor_NoHintWhenPaused() public {
        vm.prank(MID);
        oracle.pause();
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenTradePaused() public {
        trade.setTradePaused(address(rtoken), true);
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenMultiplierChanged() public {
        rtoken.setUIMultiplier(2e18);
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintBeyondBreak() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(480e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_RevertIfMarketHoursReverts() public {
        vm.mockCallRevert(address(marketHours), abi.encodeCall(IFluidUsEquityMarketHours.getCurrentSession, ()), "");
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        vm.expectRevert();
        oracle.updateRegularHoursAnchor();
        vm.expectRevert();
        oracle.getExchangeRateOperateWrite();
        assertEq(oracle.getExchangeRateOperate(), 705e27);
    }

    function test_updateRegularHoursAnchor_AgedOutPricesLiveAndRecordsWithoutBreak() public {
        // anchor set at MON + 1h is 5 days + 13 hours old here: break and cap disarmed, price live
        vm.warp(MON + 5 days + 14 hours);
        _setPrice(480e18);
        assertEq(oracle.getExchangeRateOperate(), 480e27);
        assertEq(oracle.getExchangeRateLiquidate(), 480e27);

        // Friday's regular print (Saturday now): recorded without the break check, then sealed (session over)
        _setPriceAt(480e18, FRI + 1 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(480e27, FRI + 1 hours, FRI + 390 minutes);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(480e27, FRI + 1 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        // the seal re-arms the break: 700 is beyond +30% of the sealed 480 anchor
        _setPrice(700e18);
        _expectErr(ErrorTypes.CHRStockOracle__PriceBreak);
        oracle.getExchangeRateOperate();
    }

    function test_updateRegularHoursAnchor_RecordsHintBeforeFirstAnchorWithoutBreak() public {
        FluidCHRStockOracle fresh_ = _deploy(_params());
        vm.warp(MON + 2 hours);
        _setPriceAt(1400e18, MON + 2 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(1400e27, MON + 2 hours, REG_END);
        assertTrue(fresh_.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = fresh_.getConfig();
        assertEq(s_.hintValue, 1400e27);
        assertEq(s_.hintAge, MON + 2 hours);
        assertEq(s_.anchorTime, 0);
    }

    function test_getExchangeRateOperate_AgedOutSkipsCap() public {
        vm.warp(MON + 1 hours + 5 days + 12 hours + 1);
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateOperate(), 590e27);
        assertEq(oracle.getExchangeRateLiquidate(), 590e27);
    }

    // ------------------------------------------------------------------ setAnchor (SPEC §7)

    function test_setAnchor_RevertIfNotHigh() public {
        vm.prank(MID);
        _expectUnauthorized();
        oracle.setAnchor(1e18);
    }

    function test_setAnchor_RevertIfExpectedMultiplierMismatch() public {
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        oracle.setAnchor(2e18);
    }

    function test_setAnchor_RevertIfExpectedMultiplierZero() public {
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        oracle.setAnchor(0);
    }

    function test_setAnchor_RevertIfRtokenPaused() public {
        rtoken.setPaused(true);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__RtokenPaused);
        oracle.setAnchor(1e18);
    }

    function test_setAnchor_RevertIfTradePaused() public {
        trade.setTradePaused(address(rtoken), true);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__TradePaused);
        oracle.setAnchor(1e18);
    }

    function test_setAnchor_RevertIfStale() public {
        _setPriceAt(705e18, block.timestamp - 1 hours - 1);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__StalePrice);
        oracle.setAnchor(1e18);
    }

    function test_setAnchor_RevertIfChronicleInvalid() public {
        chronicle.set(false, 705e18, block.timestamp);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.setAnchor(1e18);
    }

    function test_setAnchor_UpdatesAnchorAndEmits() public {
        vm.warp(MON + 2 hours);
        _setPrice(705e18);
        vm.expectEmit(true, true, true, true);
        emit LogSetAnchor(ANCHOR, 705e27, 1e18, 1e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 2 hours);
        assertEq(s_.acceptedMultiplier, 1e18);
    }

    function test_setAnchor_ClearsHint() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(702e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();
        assertEq(oracle.getConfig().hintAge, MON + 2 hours);

        _setPrice(705e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_setAnchor_AllowedWhilePaused() public {
        vm.prank(MID);
        oracle.pause();
        _setPrice(705e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
        assertEq(oracle.getConfig().anchorValue, 705e27);
        assertTrue(oracle.getConfig().paused);
    }

    function test_setAnchor_AcceptsMultiplierChange() public {
        rtoken.setUIMultiplier(2e18);
        _setPrice(705e18);
        vm.expectEmit(true, true, true, true);
        emit LogSetAnchor(ANCHOR, 1410e27, 1e18, 2e18);
        vm.prank(HIGH);
        oracle.setAnchor(2e18);
        assertEq(oracle.getExchangeRateOperate(), 1410e27);
    }

    // ------------------------------------------------------------------ pause / unpause / latch (SPEC §8)

    function test_pause_RevertIfNotMid() public {
        vm.prank(STRANGER);
        _expectUnauthorized();
        oracle.pause();
    }

    function test_pause_EmitsOnceAndIsIdempotent() public {
        vm.expectEmit(true, true, true, true);
        emit LogPause(MID);
        vm.prank(MID);
        oracle.pause();

        vm.recordLogs();
        vm.prank(MID);
        oracle.pause();
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_unpause_ClearsPauseWhenNoCause() public {
        vm.prank(MID);
        oracle.pause();
        vm.expectEmit(true, true, true, true);
        emit LogUnpause(MID);
        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    function test_unpause_RevertIfLatchCauseActive_TradePaused() public {
        vm.prank(MID);
        oracle.pause();
        trade.setTradePaused(address(rtoken), true);
        vm.prank(MID);
        _expectErr(ErrorTypes.CHRStockOracle__LatchCauseActive);
        oracle.unpause();
    }

    function test_unpause_RevertIfLatchCauseActive_RtokenPaused() public {
        vm.prank(MID);
        oracle.pause();
        rtoken.setPaused(true);
        vm.prank(MID);
        _expectErr(ErrorTypes.CHRStockOracle__LatchCauseActive);
        oracle.unpause();
    }

    function test_unpause_RevertIfLatchCauseActive_MultiplierChanged() public {
        vm.prank(MID);
        oracle.pause();
        rtoken.setUIMultiplier(2e18);
        vm.prank(MID);
        _expectErr(ErrorTypes.CHRStockOracle__LatchCauseActive);
        oracle.unpause();
    }

    function test_unpause_RevertIfCauseReadReverts() public {
        vm.prank(MID);
        oracle.pause();
        rtoken.setRevertAll(true);
        vm.prank(MID);
        vm.expectRevert();
        oracle.unpause();
    }

    function test_unpause_RevertIfNotMid() public {
        vm.prank(MID);
        oracle.pause();
        vm.prank(STRANGER);
        _expectUnauthorized();
        oracle.unpause();
    }

    function test_latchPause_ReturnsTradePausedBit() public {
        trade.setTradePaused(address(rtoken), true);
        assertEq(oracle.latchPause(), 1);
        assertTrue(oracle.getConfig().paused);
    }

    function test_latchPause_ReturnsRtokenPausedBit() public {
        rtoken.setPaused(true);
        assertEq(oracle.latchPause(), 2);
    }

    function test_latchPause_IgnoresDelistedFlag() public {
        rtoken.setDelisted(true);
        assertEq(oracle.latchPause(), 0);
        assertFalse(oracle.getConfig().paused);
        assertEq(oracle.getExchangeRateOperate(), 700e27);
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);
    }

    function test_latchPause_ReturnsMultiplierBit() public {
        rtoken.setUIMultiplier(2e18);
        assertEq(oracle.latchPause(), 4);
    }

    function test_latchPause_ReturnsCombinedBits() public {
        rtoken.setPaused(true);
        rtoken.setUIMultiplier(2e18);
        assertEq(oracle.latchPause(), 6);
    }

    function test_latchPause_NoCauseNoPause() public {
        assertEq(oracle.latchPause(), 0);
        assertFalse(oracle.getConfig().paused);
    }

    function test_latchPause_EmitsOnlyOnTransition() public {
        rtoken.setPaused(true);
        vm.expectEmit(true, true, true, true);
        emit LogPauseLatched(2);
        assertEq(oracle.latchPause(), 2);

        vm.recordLogs();
        assertEq(oracle.latchPause(), 2);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_latchPause_NoEventWhenAlreadyPaused() public {
        vm.prank(MID);
        oracle.pause();
        trade.setTradePaused(address(rtoken), true);
        vm.recordLogs();
        assertEq(oracle.latchPause(), 1);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_latchPause_DoesNotRevertWhenRtokenReverts() public {
        rtoken.setRevertAll(true);
        assertEq(oracle.latchPause(), 0);
    }

    /// @dev Accepted residual: try/catch does not catch a failed decode of malformed return data.
    function test_latchPause_RevertIfRtokenReturnsShortData() public {
        rtoken.setShortReturn(true);
        vm.expectRevert();
        oracle.latchPause();
    }

    function test_latchPause_DoesNotRevertWhenTradeReverts() public {
        trade.setRevert(true);
        assertEq(oracle.latchPause(), 0);
    }

    function test_latchPause_NotGatedBySequencer() public {
        feed.setRound(2, 1, block.timestamp);
        trade.setTradePaused(address(rtoken), true);
        assertEq(oracle.latchPause(), 1);
    }

    function test_latchPause_PersistsAfterMultiplierRestored() public {
        rtoken.setUIMultiplier(2e18);
        assertEq(oracle.latchPause(), 4);
        rtoken.setUIMultiplier(1e18);

        _expectErr(ErrorTypes.CHRStockOracle__Paused);
        oracle.getExchangeRateOperate();

        vm.prank(MID);
        oracle.unpause();
        assertEq(oracle.getExchangeRateOperate(), 700e27);
    }

    // ------------------------------------------------------------------ sequencer gate on every guarded entry point

    function _expectAllGuardedRevert(uint256 id_) internal {
        bytes memory err_ = abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, id_);
        vm.expectRevert(err_);
        oracle.getExchangeRateOperate();
        vm.expectRevert(err_);
        oracle.getExchangeRateLiquidate();
        vm.expectRevert(err_);
        oracle.getExchangeRateOperateDebt();
        vm.expectRevert(err_);
        oracle.getExchangeRateLiquidateDebt();
        vm.expectRevert(err_);
        oracle.getExchangeRateOperateWrite();
        vm.expectRevert(err_);
        oracle.getExchangeRateLiquidateWrite();
        vm.expectRevert(err_);
        oracle.getExchangeRateOperateDebtWrite();
        vm.expectRevert(err_);
        oracle.getExchangeRateLiquidateDebtWrite();
        vm.expectRevert(err_);
        oracle.getExchangeRate();
        vm.expectRevert(err_);
        oracle.updateRegularHoursAnchor();
    }

    function test_guardedGetters_RevertIfSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        _expectAllGuardedRevert(CommonErrorTypes.SequencerL2__SequencerDown);
    }

    function test_guardedGetters_RevertIfSequencerGracePeriod() public {
        uint256 t1_ = block.timestamp - 10 minutes;
        feed.setRound(1, 1, t1_ - 30 minutes);
        feed.setRound(2, 0, t1_);
        _expectAllGuardedRevert(CommonErrorTypes.SequencerL2__GracePeriod);
    }

    function test_rawGetters_AnswerWhileSequencerDown() public {
        feed.setRound(2, 1, block.timestamp);
        _setPrice(705e18);
        assertEq(oracle.getExchangeRateRaw(), 705e27);
        assertEq(oracle.getExchangeRateOperateRaw(), 705e27);
        assertEq(oracle.getExchangeRateLiquidateRaw(), 705e27);
    }

    function test_setAnchorAndPause_NotGatedBySequencer() public {
        feed.setRound(2, 1, block.timestamp);
        _setPrice(705e18);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
        assertEq(oracle.getConfig().anchorValue, 705e27);

        vm.prank(MID);
        oracle.pause();
        assertTrue(oracle.getConfig().paused);
        vm.prank(MID);
        oracle.unpause();
        assertFalse(oracle.getConfig().paused);
    }

    function test_sequencerL2Data_ReportsUpAndDown() public {
        FluidCHRStockOracleL2 l2_ = FluidCHRStockOracleL2(address(oracle));
        (address feed_, , bool up_, , , , , bool valid_) = l2_.sequencerL2Data();
        assertEq(feed_, address(feed));
        assertTrue(up_);
        assertTrue(valid_);

        feed.setRound(2, 1, block.timestamp);
        (, , up_, , , , , valid_) = l2_.sequencerL2Data();
        assertFalse(up_);
        assertFalse(valid_);
    }

    // ------------------------------------------------------------------ write getters (SPEC §7)

    function test_getExchangeRateLiquidateDebtWrite_SealsHintAndReturnsClamped() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        // past the buffer the hint is the effective anchor (ceiling 810.75) and seals; live 824 is clamped down
        vm.warp(REG_END + 121);
        _setPrice(824e18);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 2 hours);
        assertEq(oracle.getExchangeRateLiquidateDebtWrite(), 810.75e27);

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 2 hours);
        assertEq(s_.hintAge, 0);
    }

    function test_getExchangeRateLiquidateWrite_SealsHintAndReturnsFloorClamped() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        vm.warp(REG_END + 121);
        _setPrice(590e18);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 2 hours);
        assertEq(oracle.getExchangeRateLiquidateWrite(), 599.25e27);

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.hintAge, 0);
    }

    function test_getExchangeRateOperateDebtWrite_RevertIfOutsideCap() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        vm.warp(REG_END + 121);
        _setPrice(824e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperateDebtWrite();
    }

    // ------------------------------------------------------------------ constructor and dependency probes

    function test_constructor_AcceptsInclusiveBounds() public {
        rtoken.setUIMultiplier(type(uint104).max);
        CHRStructs.CHRStockOracleConstructorParams memory p_ = _params();
        p_.maxOperateAge = 5 days;
        p_.maxLiquidateAge = 5 days;
        p_.maxBreakPercent = 9999;
        p_.maxCapPercent = 9998;

        CHRStructs.CHRStockOracleConfig memory s_ = _deploy(p_).getConfig();
        assertEq(s_.maxOperateAge, 5 days);
        assertEq(s_.maxLiquidateAge, 5 days);
        assertEq(s_.maxBreakPercent, 9999);
        assertEq(s_.maxCapPercent, 9998);
        assertEq(s_.acceptedMultiplier, type(uint104).max);
    }

    function test_constructor_RevertIfTradeProbeReverts() public {
        trade.setRevert(true);
        vm.expectRevert(bytes("trade: revert"));
        _deploy(_params());
    }

    function test_constructor_RevertIfMarketHoursProbeReverts() public {
        vm.mockCallRevert(
            address(marketHours),
            abi.encodeCall(IFluidUsEquityMarketHours.getSessionInfo, (block.timestamp)),
            ""
        );
        vm.expectRevert();
        _deploy(_params());
    }

    function test_getConfig_ReturnsImmutables() public view {
        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.chronicle, address(chronicle));
        assertEq(s_.rtoken, address(rtoken));
        assertEq(s_.realityTokenTrade, address(trade));
        assertEq(s_.marketHours, address(marketHours));
        assertEq(s_.authGate, address(authGate));
        assertEq(s_.maxCapPercent, 1500);
        assertEq(s_.maxBreakPercent, 3000);
        assertEq(s_.maxOperateAge, 1 hours);
        assertEq(s_.maxLiquidateAge, 1 days);
    }

    // ------------------------------------------------------------------ invalid value, cap edges, and setAnchor bounds

    function test_getExchangeRateOperate_RevertIfLiveValueRoundsToZero() public {
        rtoken.setUIMultiplier(1);
        FluidCHRStockOracle fresh_ = _deploy(_params());
        _setPrice(1e8); // 1e8 * 1 / 1e9 rounds to 0
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        fresh_.getExchangeRateOperate();
        assertEq(fresh_.getExchangeRateRaw(), 0);
    }

    function test_getExchangeRateOperate_ArmedAtExactlyMaxAge() public {
        vm.warp(MON + 1 hours + 5 days + 12 hours);
        _setPrice(590e18);
        _expectErr(ErrorTypes.CHRStockOracle__OutsideCap);
        oracle.getExchangeRateOperate();
    }

    function test_getExchangeRateLiquidate_HintNotEffectiveAtExactBufferEnd() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        oracle.updateRegularHoursAnchor();

        // at regularEnd + 2 min the hint is not yet the anchor: floor is 700's 595
        vm.warp(REG_END + 120);
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidate(), CAP_FLOOR);

        // one second later the hint is the anchor: floor is 705's 599.25
        vm.warp(REG_END + 121);
        _setPrice(590e18);
        assertEq(oracle.getExchangeRateLiquidate(), 599.25e27);
    }

    function test_setAnchor_RevertIfExpectedMultiplierAboveUint104() public {
        uint256 over_ = uint256(type(uint104).max) + 1;
        rtoken.setUIMultiplier(over_);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidParams);
        oracle.setAnchor(over_);
    }

    function test_setAnchor_RevertIfLiveValueAboveUint128() public {
        rtoken.setUIMultiplier(type(uint104).max);
        chronicle.set(true, type(uint128).max, block.timestamp);
        vm.prank(HIGH);
        _expectErr(ErrorTypes.CHRStockOracle__InvalidPrice);
        oracle.setAnchor(type(uint104).max);
    }

    function test_setAnchor_AcceptsPriceAtOperateAgeBound() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 1 hours);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.anchorValue, 705e27);
        assertEq(s_.anchorTime, MON + 1 hours);
    }

    // ------------------------------------------------------------------ hint recording skips (SPEC §7)

    function test_updateRegularHoursAnchor_NoHintForPreMarketPrint() public {
        // Tuesday's regular window has started, so a print from before it is pre-market
        vm.warp(MON + 1 days + 1 hours);
        _setPriceAt(705e18, MON + 1 days - 1 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintForSameAgePrint() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        vm.recordLogs();
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(oracle.getConfig().hintAge, MON + 2 hours);
    }

    function test_updateRegularHoursAnchor_NoHintAtAnchorTime() public {
        // the print is aged MON + 1h, the same as the anchor set in setUp
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 1 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenNoRegularWindow() public {
        vm.mockCall(
            address(marketHours),
            abi.encodeCall(IFluidUsEquityMarketHours.getCurrentSession, ()),
            abi.encode(uint256(sessionTypeRegular), uint32(0), uint32(MON + 3 hours))
        );
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenRegularWindowInverted() public {
        vm.mockCall(
            address(marketHours),
            abi.encodeCall(IFluidUsEquityMarketHours.getCurrentSession, ()),
            abi.encode(uint256(sessionTypeRegular), uint32(MON + 2 hours), uint32(MON + 2 hours - 1))
        );
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenLiveValueAboveUint128() public {
        // aged-out anchor disarms the break, so only the uint128 bound stops the record
        uint256 now_ = MON + 5 days + 14 hours;
        vm.warp(now_);
        vm.mockCall(
            address(marketHours),
            abi.encodeCall(IFluidUsEquityMarketHours.getCurrentSession, ()),
            abi.encode(uint256(sessionTypeRegular), uint32(now_ - 1 hours), uint32(now_ + 5 hours))
        );
        _setPriceAt(type(uint128).max, now_);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintWhenRtokenPaused() public {
        rtoken.setPaused(true);
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_NoHintForInvalidPrint() public {
        vm.warp(MON + 2 hours);
        chronicle.set(false, 705e18, MON + 2 hours);
        assertFalse(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_updateRegularHoursAnchor_SealsHintWhilePaused() public {
        vm.warp(MON + 2 hours);
        _setPriceAt(705e18, MON + 2 hours);
        assertTrue(oracle.updateRegularHoursAnchor());

        vm.prank(MID);
        oracle.pause();
        vm.warp(REG_END + 121);
        vm.expectEmit(true, true, true, true);
        emit LogSealAnchor(705e27, MON + 2 hours);
        assertTrue(oracle.updateRegularHoursAnchor());
        assertEq(oracle.getConfig().anchorValue, 705e27);
    }

    // ------------------------------------------------------------------ unpause no-op

    function test_unpause_NoOpWhenNotPaused() public {
        trade.setTradePaused(address(rtoken), true);
        vm.recordLogs();
        vm.prank(MID);
        oracle.unpause();
        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(oracle.getConfig().paused);
    }

    // ------------------------------------------------------------------ fuzz

    function test_fuzz_ReadLive_NoPanic(uint256 price_, uint256 multiplier_) public {
        price_ = bound(price_, 1, type(uint128).max);
        multiplier_ = bound(multiplier_, 1, type(uint104).max);
        rtoken.setUIMultiplier(multiplier_);
        chronicle.set(true, price_, block.timestamp);

        oracle.getConfig();
        uint256 raw_ = oracle.getExchangeRateRaw();
        assertEq(raw_, (price_ * multiplier_) / 1e9);
        oracle.getExchangeRateOperateRaw();
        oracle.getExchangeRateLiquidateRaw();
        oracle.getExchangeRate();
    }
}
