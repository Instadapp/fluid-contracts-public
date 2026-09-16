// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IFluidOracle } from "../../../contracts/oracleV2/interfaces/iFluidOracle.sol";
import { FluidChainlinkCappedRate } from "../../../contracts/oracleV2/cappedRates/implementations/chainlinkCappedRate.sol";
import { FluidChainlinkCappedRateL2 } from "../../../contracts/oracleV2/cappedRates/implementationsL2/chainlinkCappedRateL2.sol";
import { FluidCappedRateBase } from "../../../contracts/oracleV2/cappedRates/fluidCappedRate.sol";
import { CenterPriceError } from "../../../contracts/oracleV2/centerPrices/error.sol";
import { ErrorTypes as CenterPriceErrorTypes } from "../../../contracts/oracleV2/centerPrices/errorTypes.sol";

contract MockSequencerUptimeFeedCappedTest {
    struct RoundData {
        int256 answer;
        uint256 startedAt;
    }

    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRoundId;

    function setRound(uint80 roundId_, int256 answer_, uint256 startedAt_) external {
        rounds[roundId_] = RoundData(answer_, startedAt_);
        if (roundId_ > latestRoundId) {
            latestRoundId = roundId_;
        }
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[latestRoundId];
        return (latestRoundId, r.answer, r.startedAt, block.timestamp, latestRoundId);
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[roundId_];
        return (roundId_, r.answer, r.startedAt, r.startedAt, roundId_);
    }
}

contract MockChainlinkRateFeed {
    int256 public answer = 1e18;

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

library ResolverOraclePriceFetch {
    function fetch(address oracle_) internal view returns (uint256 operate_, uint256 liquidate_) {
        if (oracle_ == address(0)) {
            return (0, 0);
        }

        try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
            operate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 liquidateRate_) {
                liquidate_ = liquidateRate_;
            } catch {
                liquidate_ = exchangeRate_;
            }
            return (operate_, liquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRateOperateRaw() returns (uint256 exchangeRate_) {
            operate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidateRaw() returns (uint256 liquidateRate_) {
                liquidate_ = liquidateRate_;
            } catch {
                liquidate_ = exchangeRate_;
            }
            return (operate_, liquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRate() returns (uint256 exchangeRate_) {
            return (exchangeRate_, exchangeRate_);
        } catch {}

        return (0, 0);
    }
}

contract FluidChainlinkCappedRateL2ResolverRawTest is Test {
    FluidChainlinkCappedRateL2 internal cappedRateL2;
    MockSequencerUptimeFeedCappedTest internal sequencerFeed;
    MockChainlinkRateFeed internal rateFeed;

    uint256 internal constant MAX_APR_PERCENT = 10e4;

    function setUp() public {
        vm.warp(1_700_000_000);

        sequencerFeed = new MockSequencerUptimeFeedCappedTest();
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        rateFeed = new MockChainlinkRateFeed();

        FluidCappedRateBase.CappedRateConstructorParams memory params_ = FluidCappedRateBase
            .CappedRateConstructorParams({
                infoName: "TEST/RATE",
                liquidity: address(0xBEEF),
                rateSource: address(rateFeed),
                rateMultiplier: 1e9,
                invertCenterPrice: false,
                minUpdateDiffPercent: 100,
                minHeartbeat: 7 days,
                avoidForcedLiquidationsCol: false,
                avoidForcedLiquidationsDebt: false,
                maxAPRPercent: MAX_APR_PERCENT,
                maxDownFromMaxReachedPercentCol: 0,
                maxDownFromMaxReachedPercentDebt: 0,
                maxDebtUpCapPercent: 0
            });

        cappedRateL2 = new FluidChainlinkCappedRateL2(params_, address(sequencerFeed));
    }

    function _setupGracePeriodScenario() internal {
        sequencerFeed.setRound(1, 0, block.timestamp - 1 hours);
        sequencerFeed.setRound(2, 1, block.timestamp - 10 minutes);
        sequencerFeed.setRound(3, 0, block.timestamp - 1 minutes);
    }

    function test_cappedRateL2_guardedReverts_rawSucceeds_withinGracePeriod() public {
        _setupGracePeriodScenario();

        vm.expectRevert(
            abi.encodeWithSelector(
                CenterPriceError.FluidCenterPriceError.selector,
                CenterPriceErrorTypes.FluidOracleL2__SequencerOutage
            )
        );
        cappedRateL2.getExchangeRateOperate();

        uint256 rawOperate_ = cappedRateL2.getExchangeRateOperateRaw();
        uint256 rawLiquidate_ = cappedRateL2.getExchangeRateLiquidateRaw();
        assertGt(rawOperate_, 0);
        assertGt(rawLiquidate_, 0);
    }

    function test_resolverFetch_cappedRateL2_doesNotRevert_duringGracePeriod() public {
        _setupGracePeriodScenario();

        (uint256 operate_, uint256 liquidate_) = ResolverOraclePriceFetch.fetch(address(cappedRateL2));
        assertGt(operate_, 0, "resolver fetch must return operate price during L2 grace");
        assertGt(liquidate_, 0, "resolver fetch must return liquidate price during L2 grace");
    }

    function test_resolverFetch_cappedRateL2_doesNotRevert_whileSequencerDown() public {
        sequencerFeed.setRound(2, 1, block.timestamp);

        (uint256 operate_, uint256 liquidate_) = ResolverOraclePriceFetch.fetch(address(cappedRateL2));
        assertGt(operate_, 0);
        assertGt(liquidate_, 0);
    }
}

contract FluidChainlinkCappedRateL2InvertParityTest is Test {
    uint256 internal constant MAX_APR_PERCENT = 10e4;
    uint256 internal constant RAW_RATE = 12e26;

    FluidChainlinkCappedRate internal l1Invert;
    FluidChainlinkCappedRateL2 internal l2Invert;
    MockChainlinkRateFeed internal rateFeed;
    MockSequencerUptimeFeedCappedTest internal sequencerFeed;

    function setUp() public {
        vm.warp(1_700_000_000);

        rateFeed = new MockChainlinkRateFeed();
        rateFeed.setAnswer(int256(RAW_RATE));

        sequencerFeed = new MockSequencerUptimeFeedCappedTest();
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        FluidCappedRateBase.CappedRateConstructorParams memory params_ = FluidCappedRateBase
            .CappedRateConstructorParams({
                infoName: "QUOTE per BASE",
                liquidity: address(0xBEEF),
                rateSource: address(rateFeed),
                rateMultiplier: 1,
                invertCenterPrice: true,
                minUpdateDiffPercent: 100,
                minHeartbeat: 7 days,
                avoidForcedLiquidationsCol: false,
                avoidForcedLiquidationsDebt: false,
                maxAPRPercent: MAX_APR_PERCENT,
                maxDownFromMaxReachedPercentCol: 0,
                maxDownFromMaxReachedPercentDebt: 0,
                maxDebtUpCapPercent: 0
            });

        l1Invert = new FluidChainlinkCappedRate(params_);
        l2Invert = new FluidChainlinkCappedRateL2(params_, address(sequencerFeed));
    }

    function test_centerPrice_l1InvertsWhenConfigured() public {
        uint256 center_ = l1Invert.centerPrice();
        assertEq(center_, 1e54 / RAW_RATE, "L1 capped rate honors invertCenterPrice via _invertRateIfNeeded");
    }

    function test_centerPrice_l2InvertParity() public {
        uint256 center_ = l2Invert.centerPrice();

        assertEq(center_, 1e54 / RAW_RATE, "L2 centerPrice inverts, matching L1 invertCenterPrice parity");
        assertEq(center_, l1Invert.centerPrice(), "L1 and L2 centerPrice are in parity");
    }
}
