// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { FluidCHRStockOracle } from "../../../contracts/oracleV2/stocks/chrStockOracle/main.sol";
import { Structs as CHRStructs } from "../../../contracts/oracleV2/stocks/chrStockOracle/structs.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";

import { MockChronicle, MockRealityToken, MockRealityTokenTrade, MockAuthGate } from "./chrStockOracleMocks.sol";

/// @dev Base `FluidCHRStockOracle` with no sequencer: the guarded-read hook is a no-op.
contract CHRStockOracleBaseTest is Test {
    FluidUsEquityMarketHours marketHours;
    MockChronicle chronicle;
    MockRealityToken rtoken;
    MockRealityTokenTrade trade;
    MockAuthGate authGate;
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
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

    uint256 constant MON = 1_700_000_000;
    uint256 constant REG_END = MON + 390 minutes;

    event LogRecordHint(uint256 value, uint256 age, uint256 regularEnd);

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

    function setUp() public {
        _mockGovernance(GOVERNANCE);
        marketHours = _deployMarketHours();
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 1);

        chronicle = new MockChronicle();
        rtoken = new MockRealityToken();
        trade = new MockRealityTokenTrade();
        authGate = new MockAuthGate();
        authGate.setLevel(MID, 1);
        authGate.setLevel(HIGH, 2);

        vm.warp(MON + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(uint32(MON)));

        oracle = new FluidCHRStockOracle(_params());
        chronicle.set(true, 700e18, block.timestamp);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
    }

    // ------------------------------------------------------------------ guarded reads without a sequencer

    function test_getExchangeRateOperate_PricesNormallyWithoutSequencer() public view {
        assertEq(oracle.getExchangeRateOperate(), 700e27);
        assertEq(oracle.getExchangeRateLiquidate(), 700e27);
    }

    function test_getExchangeRate_EqualsRawWithoutSequencer() public {
        chronicle.set(true, 810e18, block.timestamp);
        assertEq(oracle.getExchangeRate(), oracle.getExchangeRateRaw());
        assertEq(oracle.getExchangeRate(), 810e27);
    }

    function test_getExchangeRate_EqualsRawWhilePaused() public {
        vm.prank(MID);
        oracle.pause();
        assertEq(oracle.getExchangeRate(), oracle.getExchangeRateRaw());
        assertEq(oracle.getExchangeRate(), 700e27);
    }

    // ------------------------------------------------------------------ anchor upkeep without a sequencer

    function test_updateRegularHoursAnchor_RecordsHintWithoutSequencer() public {
        vm.warp(MON + 2 hours);
        chronicle.set(true, 705e18, MON + 2 hours);
        vm.expectEmit(true, true, true, true);
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertTrue(oracle.updateRegularHoursAnchor());

        CHRStructs.CHRStockOracleConfig memory s_ = oracle.getConfig();
        assertEq(s_.hintValue, 705e27);
        assertEq(s_.hintAge, MON + 2 hours);
        assertEq(s_.hintRegularEnd, REG_END);
    }
}
