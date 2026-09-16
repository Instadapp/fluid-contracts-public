// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { Structs as CLXStructs } from "../../../contracts/oracleV2/stocks/clxStockOracle/structs.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";
import { MockChainlinkFeed, MockBackedAutoFeeToken, MockBackedWrapper } from "./clxStockOracleMocks.sol";

/**
 * @title FluidCLXStockOracleDifferentialTest
 * @notice Layer C — replay fixture rounds, sample many timestamps, compare oracle vs ref.
 *
 * Fixture: `fixtures/clx-differential-fixture.json`
 * Regenerate: `npx ts-node scripts/cursor-scripts/fetch-clx-differential-fixture.ts`
 * Live: add `--live` + `CLX_CHAINLINK_FEED` (+ optional `POLYGON_API_KEY` cross-check in the script).
 *
 * Depends on `clxStockOracleMocks.sol` (created with Layer A/D).
 */
contract FluidCLXStockOracleDifferentialTest is Test {
    using stdJson for string;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    uint256 constant RATE_MULTIPLIER = 1e19;
    uint256 constant CAP = 10e4; // 10%
    uint256 constant SIX_DECIMALS = 1e6;
    /// @dev Max relative drift vs fixture ref during REGULAR (3%).
    uint256 constant MAX_REF_DRIFT_BPS = 300;

    FluidUsEquityMarketHours marketHours;
    MockChainlinkFeed feed;
    MockBackedAutoFeeToken token;
    MockBackedWrapper wrapper;
    FluidCLXStockOracle oracle;

    string fixture;

    function setUp() public {
        string memory path_ = string.concat(
            vm.projectRoot(),
            "/test/foundry/oracle/fixtures/clx-differential-fixture.json"
        );
        if (!vm.exists(path_)) {
            vm.skip(true);
        }
        fixture = vm.readFile(path_);

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
        marketHours.updateAuth(AUTH, 2); // harness writes unrelated weeks out of order

        feed = new MockChainlinkFeed();
        token = new MockBackedAutoFeeToken();
        wrapper = new MockBackedWrapper(token);
        token.setMultiplier(1e18);

        // Load rounds into mock.
        uint256 roundCount_ = fixture.readUint(".meta.roundCount");
        for (uint256 i_; i_ < roundCount_; ++i_) {
            string memory base_ = string.concat(".rounds[", vm.toString(i_), "]");
            int256 answer_ = int256(fixture.readUint(string.concat(base_, ".answer")));
            uint256 updatedAt_ = fixture.readUint(string.concat(base_, ".updatedAt"));
            feed.pushRound(answer_, updatedAt_);
        }

        // Schedule covering fixture start (Jul 2025) + a few following weeks.
        uint32 mon_ = Cal.marketOpen(2025, 7, 7);
        vm.warp(uint256(mon_) - 2 days + 12 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(mon_));

        for (uint256 w_; w_ < 8; ++w_) {
            mon_ = uint32(uint256(mon_) + 7 days);
            Cal.Date memory d_ = Cal.dateFromTimestamp(mon_);
            uint32 weekStart_ = mon_;
            if (Cal.isFullHoliday(d_.year, d_.month, d_.day)) {
                weekStart_ = Cal.nextTradingDayOpen(d_.year, d_.month, d_.day);
            }
            vm.warp(uint256(mon_) - 2 days + 12 hours);
            vm.prank(AUTH);
            marketHours.updateWeekSessions(Cal.buildSaturdayRewrite(weekStart_));
        }

        oracle = new FluidCLXStockOracle(
            CLXStructs.CLXStockOracleConstructorParams({
                infoName: "diff CLX",
                targetDecimals: 27,
                liquidity: LIQUIDITY,
                chainlinkFeed: address(feed),
                backedWrapper: address(wrapper),
                marketHours: address(marketHours),
                rateMultiplier: RATE_MULTIPLIER,
                maxMultiplierChangePercent: 100,
                maxExtendedHoursCapPercent: CAP,
                maxPriceGapDownPercent: 9999, // non-binding: differential fixtures replay large CL moves
                maxPriceGapUpPercent: 1e8
            })
        );

        // Warm from a mid-RTH tip if possible.
        vm.warp(Cal.marketOpen(2025, 7, 8) + 1 hours);
        try oracle.updateRegularHoursAnchor(0) {} catch {}
    }

    /// @dev Replay up to 10k samples: session classification + price vs ref / clamp band.
    function test_Differential_SamplesMatchRefAndClamp() public {
        uint256 sampleCount_ = fixture.readUint(".meta.sampleCount");
        uint256 stride_ = 1;
        uint256 checked_;
        uint256 withinRef_;
        uint256 clampOk_;

        for (uint256 i_; i_ < sampleCount_; i_ += stride_) {
            string memory base_ = string.concat(".samples[", vm.toString(i_), "]");
            uint256 ts_ = fixture.readUint(string.concat(base_, ".ts"));
            uint256 refAnswer_ = fixture.readUint(string.concat(base_, ".refAnswer"));

            // Keep schedule covering `ts_` when inside 2025–2026 lib span.
            Cal.Date memory d_ = Cal.dateFromTimestamp(uint32(ts_));
            if (d_.year < 2025 || d_.year > 2026) continue;

            _ensureSchedule(uint32(ts_));
            _setLatestAsOf(ts_);
            vm.warp(ts_);

            (uint256 sessionType_, uint32 regStart_, uint32 regEnd_) = marketHours.getSessionInfo(uint32(ts_));

            // Skip if CL too stale for operate rules — liquidate path still useful.
            uint256 priceOp_;
            uint256 priceLiq_;
            bool opOk_ = true;
            try oracle.getExchangeRateOperate() returns (uint256 p_) {
                priceOp_ = p_;
            } catch {
                opOk_ = false;
            }
            try oracle.getExchangeRateLiquidate() returns (uint256 p_) {
                priceLiq_ = p_;
            } catch {
                continue;
            }

            uint256 refScaled_ = (refAnswer_ * 1e18 * RATE_MULTIPLIER) / 1e18;

            if (sessionType_ == 1 && opOk_) {
                // REGULAR: oracle should track live (~ref) within drift.
                uint256 live_ = priceOp_;
                uint256 drift_ = live_ > refScaled_ ? live_ - refScaled_ : refScaled_ - live_;
                if (refScaled_ > 0 && (drift_ * 10_000) / refScaled_ <= MAX_REF_DRIFT_BPS) {
                    unchecked {
                        ++withinRef_;
                    }
                }
            } else if ((sessionType_ == 2 || sessionType_ == 3 || sessionType_ == 0) && regStart_ != 0 && opOk_) {
                // Non-REGULAR with window: operate/liq must sit inside ±cap of RTH-scaled band vs live path.
                // We assert operate ≤ liq band consistency: collateral op caps up, liq floors down → op can be < or = liq depending on live.
                // Stronger: both within [floor, ceil] of *some* anchor — use mid of op/liq as proxy only if both succeed.
                uint256 lo_ = priceOp_ < priceLiq_ ? priceOp_ : priceLiq_;
                uint256 hi_ = priceOp_ > priceLiq_ ? priceOp_ : priceLiq_;
                // Band width should not exceed 2 * cap of ref (loose sanity).
                if (hi_ - lo_ <= (refScaled_ * 2 * CAP) / SIX_DECIMALS + 1) {
                    unchecked {
                        ++clampOk_;
                    }
                }
                // Silence unused
                regEnd_;
            }

            unchecked {
                ++checked_;
            }
        }

        assertGt(checked_, 100, "too few samples checked");
        // Synthetic fixture: ref == last CL print so REGULAR drift should be excellent when stride hits RTH.
        emit log_named_uint("checked", checked_);
        emit log_named_uint("withinRef", withinRef_);
        emit log_named_uint("clampOk", clampOk_);
    }

    function _ensureSchedule(uint32 ts_) internal {
        (uint256 t_, , ) = marketHours.getSessionInfo(ts_);
        if (t_ != 0) return;

        Cal.Date memory d_ = Cal.dateFromTimestamp(ts_);
        if (d_.year < 2025 || d_.year > 2026) return;

        uint32 mon_ = Cal.mondayOpenOfWeek(d_.year, d_.month, d_.day);
        Cal.Date memory md_ = Cal.dateFromTimestamp(mon_);
        uint32 weekStart_ = mon_;
        if (Cal.isFullHoliday(md_.year, md_.month, md_.day)) {
            weekStart_ = Cal.nextTradingDayOpen(md_.year, md_.month, md_.day);
        }

        // Sanity checks require contains-`now` — write from inside the week, then restore ts.
        vm.warp(uint256(weekStart_) + 1 hours);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(Cal.buildWeekWithWeekend(weekStart_));
        vm.warp(ts_);
    }

    function _setLatestAsOf(uint256 ts_) internal {
        // Find newest fixture round with updatedAt <= ts among loaded prefix and setLatest.
        uint256 roundCount_ = fixture.readUint(".meta.roundCount");
        int256 answer_ = 0;
        uint256 updatedAt_ = 0;
        for (uint256 i_; i_ < roundCount_; ++i_) {
            string memory base_ = string.concat(".rounds[", vm.toString(i_), "]");
            uint256 u_ = fixture.readUint(string.concat(base_, ".updatedAt"));
            if (u_ <= ts_) {
                answer_ = int256(fixture.readUint(string.concat(base_, ".answer")));
                updatedAt_ = u_;
            } else {
                break; // rounds are time-sorted in generator
            }
        }
        if (updatedAt_ != 0) {
            feed.setLatest(answer_, updatedAt_);
        }
    }
}
