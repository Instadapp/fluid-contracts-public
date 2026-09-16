// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

/**
 * @title UsEquityMarketHoursScheduleForTipTest
 * @notice Guards `Cal.scheduleForTip`, which `clxStockOracleFork.t.sol` derives its whole `setUp`
 *         schedule from. That suite is fork-only and excluded from CI, so this is the only gate.
 *         Two tips used to land under the contract's seven-day `MIN_SCHEDULE_DURATION_MINUTES` and
 *         revert `310301` in `setUp`: a holiday Monday (six days) and a spring-forward week
 *         (167 hours). The day sweeps are what catch the next one.
 */
contract UsEquityMarketHoursScheduleForTipTest is Test {
    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = address(0xA07);

    FluidUsEquityMarketHours marketHours;

    function setUp() public {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(GOVERNANCE)))
        );

        FluidUsEquityMarketHours impl_ = new FluidUsEquityMarketHours(LIQUIDITY);
        marketHours = FluidUsEquityMarketHours(
            address(new FluidUsEquityMarketHoursProxy(address(impl_), abi.encodeCall(BasicUpgradeable.initialize, ())))
        );
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 2); // SCHEDULE_OVERRIDE: sweeps write unrelated weeks out of order
    }

    /// @dev Writes the schedule `tip_` derives, then returns the tip to where it was.
    function _writeForTip(uint32 tip_) internal returns (Structs.Session[] memory sessions_) {
        uint32 writeAt_;
        (sessions_, writeAt_) = Cal.scheduleForTip(tip_);

        vm.warp(writeAt_);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(sessions_);
        vm.warp(tip_);
    }

    function _totalMinutes(Structs.Session[] memory sessions_) internal pure returns (uint256 total_) {
        for (uint256 i_; i_ < sessions_.length; ++i_) {
            total_ += uint256(sessions_[i_].durationMinutes) + sessions_[i_].extendedDurationMinutes;
        }
    }

    /// @dev `(year, month, day)` of the packed `YYYYMMDD` holidays the calendar lib carries.
    function _unpack(uint32 packed_) internal pure returns (uint16 y_, uint8 m_, uint8 d_) {
        y_ = uint16(packed_ / 10_000);
        m_ = uint8((packed_ / 100) % 100);
        d_ = uint8(packed_ % 100);
    }

    function test_scheduleForTip_HolidayMondayCoversSevenDays() public {
        uint32[20] memory holidays_ = Cal.fullHolidays();
        uint256 checked_;

        for (uint256 i_; i_ < holidays_.length; ++i_) {
            (uint16 y_, uint8 m_, uint8 d_) = _unpack(holidays_[i_]);
            if (Cal.dateFromYmd(y_, m_, d_).weekday != 0) continue;

            Structs.Session[] memory sessions_ = _writeForTip(Cal.etToUnix(y_, m_, d_, 3, 50));
            assertGe(
                _totalMinutes(sessions_),
                Cal.MIN_SCHEDULE_DURATION_MINUTES,
                "holiday Monday schedule shorter than the contract minimum"
            );
            ++checked_;
        }

        assertGt(checked_, 0, "no Monday holidays in the calendar span");
    }

    /// @dev The weekend rewrite derives the prior Friday from the Monday open it is handed, so a
    ///      holiday Monday must not be skipped past on the way in.
    function test_scheduleForTip_WeekendBeforeHolidayMondayWrites() public {
        uint32[20] memory holidays_ = Cal.fullHolidays();

        for (uint256 i_; i_ < holidays_.length; ++i_) {
            (uint16 y_, uint8 m_, uint8 d_) = _unpack(holidays_[i_]);
            if (Cal.dateFromYmd(y_, m_, d_).weekday != 0) continue;

            uint32 mondayOpen_ = Cal.marketOpen(y_, m_, d_);
            _writeForTip(mondayOpen_ - 2 days); // Saturday
            _writeForTip(mondayOpen_ - 1 days); // Sunday
        }
    }

    function test_scheduleForTip_WritesForEveryDayIn2025And2026() public {
        uint32 tip_ = Cal.etToUnix(2025, 1, 1, 3, 50);

        for (uint256 i_; i_ < 730; ++i_) {
            _writeForTip(tip_);
            tip_ += 1 days;
        }
    }

    function test_scheduleForTip_WritesLateInTheDay() public {
        uint32 tip_ = Cal.etToUnix(2025, 1, 1, 22, 30);

        for (uint256 i_; i_ < 730; ++i_) {
            _writeForTip(tip_);
            tip_ += 1 days;
        }
    }
}
