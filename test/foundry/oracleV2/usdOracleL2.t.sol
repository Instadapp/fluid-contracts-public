//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { FluidUSDOracleTest } from "./usdOracle.t.sol";
import { IChainlinkAggregatorV3, MockReadFromStorage, MockChainlinkFeed, OracleAdminMulticall } from "./usdOracleForkTestBase.sol";
import { FluidUsdOracleL2 } from "../../../contracts/oracleV2/usdOracle/mainL2.sol";
import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { ErrorTypes as UsdOracleErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/usdOracle/error.sol";

contract MockSequencerUptimeFeed {
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

/// @dev Same read helpers as `FluidUsdOracleHarness` in `usdOracle.t.sol`, for `FluidUsdOracleL2` instances.
contract FluidUsdOracleL2Harness is FluidUsdOracleL2, OracleAdminMulticall {
    constructor(address liquidity_, address sequencer_) FluidUsdOracleL2(liquidity_, sequencer_) {}

    receive() external payable {}

    function readSourceOrRevert(
        SourceConfig memory cfg_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 rate_) {
        rate_ = _readSource(
            cfg_.sourceType,
            cfg_.source,
            _deriveMultiplierForCfg(cfg_.sourceType, cfg_.source),
            isOperate_,
            isCollateral_,
            true
        );
    }

    function readComposedPriceOrRevert(
        SourceConfig memory s1_,
        SourceConfig memory s2_,
        SourceConfig memory s3_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_) {
        price_ = _readSource(
            s1_.sourceType,
            s1_.source,
            _deriveMultiplierForCfg(s1_.sourceType, s1_.source),
            isOperate_,
            isCollateral_,
            true
        );
        if (s2_.sourceType == SOURCE_NOT_SET) {
            return price_;
        }
        uint256 r2_ = _readSource(
            s2_.sourceType,
            s2_.source,
            _deriveMultiplierForCfg(s2_.sourceType, s2_.source),
            isOperate_,
            isCollateral_,
            true
        );
        price_ = (price_ * r2_) / ORACLE_PRECISION;
        if (s3_.sourceType == SOURCE_NOT_SET) {
            return price_;
        }
        uint256 r3_ = _readSource(
            s3_.sourceType,
            s3_.source,
            _deriveMultiplierForCfg(s3_.sourceType, s3_.source),
            isOperate_,
            isCollateral_,
            true
        );
        price_ = (price_ * r3_) / ORACLE_PRECISION;
        if (price_ == 0) {
            revert FluidUsdOracleError(UsdOracleErrorTypes.UsdOracle__RateZero);
        }
    }

    function _deriveMultiplierForCfg(uint8 sourceType_, address source_) internal view returns (int8) {
        if (
            sourceType_ == SOURCE_CAPPED_RATE ||
            sourceType_ == SOURCE_FLUID_ORACLE ||
            sourceType_ == SOURCE_STABLE ||
            sourceType_ == SOURCE_NOT_SET
        ) {
            return 0;
        }
        return int8(int256(uint256(27)) - int256(uint256(IChainlinkAggregatorV3(source_).decimals())));
    }
}

contract FluidUSDOracleL2Test is FluidUSDOracleTest {
    FluidUsdOracleL2 public usdOracleL2;
    MockSequencerUptimeFeed public sequencerFeed;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        admin = makeAddr("admin");

        liquidityMock = new MockReadFromStorage();

        liquidityMock.setStorage(
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103,
            uint256(uint160(admin))
        );

        sequencerFeed = new MockSequencerUptimeFeed();
        // Set up a healthy sequencer state: up since long ago
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        usdOracleL2 = new FluidUsdOracleL2Harness(address(liquidityMock), address(sequencerFeed));

        usdOracle = FluidUsdOracle(address(usdOracleL2));

        clOracle = new MockChainlinkFeed(IChainlinkAggregatorV3(address(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4)));

        vm.mockCall(address(0x123), abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        pegToken = makeAddr("pegToken");
        vm.mockCall(pegToken, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.startPrank(admin);
        usdOracle.setTokenType(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 2); // USDC STABLE
        usdOracle.setTokenType(0xdAC17F958D2ee523a2206206994597C13D831ec7, 2); // USDT STABLE
        usdOracle.setTokenType(0x6B175474E89094C44Da98b954EedeAC495271d0F, 2); // DAI STABLE
        usdOracle.setTokenType(address(0x123), 3); // DUMMY_TOKEN VOLATILE
        usdOracle.setTokenType(pegToken, 1); // PEG (inherited cap / vault-matrix tests)
        vm.stopPrank();
    }

    /// @dev Helper: set up a simple USDC config for both operate and liquidate
    function _setupUsdcConfig() internal {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());
    }

    /// @dev Helper: set up sequencer rounds for an outage scenario.
    ///      Round 1: up since `upSince_`, Round 2: down at `downAt_`, Round 3: back up at `backUpAt_`
    function _setupOutageScenario(uint256 upSince_, uint256 downAt_, uint256 backUpAt_) internal {
        sequencerFeed.setRound(1, 0, upSince_);
        sequencerFeed.setRound(2, 1, downAt_);
        sequencerFeed.setRound(3, 0, backUpAt_);
    }

    // ==================== Constructor Tests ====================

    function test_l2_constructor_revertsOnZeroSequencerFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        new FluidUsdOracleL2(address(liquidityMock), address(0));
    }

    // ==================== Sequencer Down Tests ====================

    function test_l2_sequencerDown_revertsOperate() public {
        _setupUsdcConfig();

        // Sequencer goes down
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_l2_sequencerDown_revertsLiquidate() public {
        _setupUsdcConfig();

        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPrice(USDC, 0, false, true);
    }

    // ==================== Grace Period Tests ====================

    function test_l2_gracePeriod_revertsWithinGracePeriod() public {
        _setupUsdcConfig();

        // Outage: was up since T-1h, went down at T-10min, came back at T-1min
        // Outage duration = 9 minutes -> grace period = 9 minutes
        // Uptime duration = 1 minute -> 1 min < 9 min -> grace period NOT passed
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 10 minutes, block.timestamp - 1 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, false, true);

        (uint256 rawPrice_, , ) = usdOracle.getPriceDetailedViewRaw(USDC, 0, true, true);
        assertGt(rawPrice_, 0, "Raw view should skip sequencer grace checks");
    }

    function test_l2_gracePeriod_allowsAfterElapsed() public {
        _setupUsdcConfig();

        // Outage: 5 min outage, back up 6 min ago -> grace period (5 min) has passed
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 11 minutes, block.timestamp - 6 minutes);

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Should succeed after grace period elapsed");
    }

    // ==================== Dynamic Grace Period ====================

    function test_l2_dynamicGracePeriod_shortOutageShortGrace() public {
        _setupUsdcConfig();

        // 2 min outage -> 2 min grace period. Currently 1 min into uptime -> should revert
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 3 minutes, block.timestamp - 1 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, true, true);

        // Warp past grace period (1 more minute + 1s)
        vm.warp(block.timestamp + 1 minutes + 1);
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Should succeed after short grace period");
    }

    function test_l2_dynamicGracePeriod_cappedAtMaxGracePeriod() public {
        _setupUsdcConfig();

        // Very long outage (2 hours) -> grace period capped at 45 min
        // Back up 30 min ago -> 30 min < 45 min -> should revert
        _setupOutageScenario(
            block.timestamp - 4 hours,
            block.timestamp - 2 hours - 30 minutes,
            block.timestamp - 30 minutes
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, true, true);

        // Warp past max grace period
        vm.warp(block.timestamp + 16 minutes);
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Should succeed after max grace period elapses");
    }

    // ==================== sequencerL2Data View ====================

    function test_l2_sequencerL2Data_sequencerUp() public view {
        (address feed, uint256 maxGrace, bool isUp, , , bool gracePassed, , bool isUpAndValid) = usdOracleL2
            .sequencerL2Data();

        assertEq(feed, address(sequencerFeed));
        assertEq(maxGrace, 45 minutes);
        assertTrue(isUp, "Sequencer should be up");
        assertTrue(gracePassed, "Grace period should have passed");
        assertTrue(isUpAndValid, "Should be up and valid");
    }

    function test_l2_sequencerL2Data_sequencerDown() public {
        sequencerFeed.setRound(2, 1, block.timestamp);

        (, , bool isUp, , uint256 gracePeriod, bool gracePassed, , bool isUpAndValid) = usdOracleL2.sequencerL2Data();

        assertFalse(isUp, "Sequencer should be down");
        assertEq(gracePeriod, 45 minutes, "Grace period should be max when down");
        assertFalse(gracePassed, "Grace period should not have passed");
        assertFalse(isUpAndValid, "Should not be up and valid");
    }

    function test_l2_sequencerL2Data_withinGracePeriod() public {
        // 5 min outage, back up 2 min ago
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 7 minutes, block.timestamp - 2 minutes);

        (
            ,
            ,
            bool isUp,
            uint256 uptimeStarted,
            uint256 gracePeriod,
            bool gracePassed,
            uint256 outageStarted,
            bool isUpAndValid
        ) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp, "Sequencer should be up");
        assertEq(uptimeStarted, block.timestamp - 2 minutes, "Uptime start mismatch");
        assertEq(gracePeriod, 5 minutes, "Grace period should equal outage duration");
        assertFalse(gracePassed, "Grace period should not have passed yet");
        assertEq(outageStarted, block.timestamp - 7 minutes, "Outage start mismatch");
        assertFalse(isUpAndValid, "Should not be up and valid during grace period");
    }

    function test_l2_sequencerL2Data_firstRoundWithStartedAtZeroIsTreatedAsValid() public {
        sequencerFeed.setRound(1, 0, 0);

        (
            ,
            uint256 maxGrace,
            bool isUp,
            uint256 uptimeStarted,
            uint256 gracePeriod,
            bool gracePassed,
            uint256 outageStarted,
            bool isUpAndValid
        ) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp, "Sequencer should be up");
        assertEq(uptimeStarted, 0, "First round should preserve zero start time");
        assertEq(gracePeriod, maxGrace, "First round should use max grace period");
        assertTrue(gracePassed, "Zero start time should be treated as already valid");
        assertEq(outageStarted, 0, "No outage should be recorded");
        assertTrue(isUpAndValid, "Sequencer should be considered valid");
    }

    function test_l2_sequencerL2Data_downTracksEarliestConsecutiveOutageStart() public {
        sequencerFeed.setRound(1, 0, block.timestamp - 4 hours);
        sequencerFeed.setRound(2, 1, block.timestamp - 90 minutes);
        sequencerFeed.setRound(3, 1, block.timestamp - 45 minutes);

        (, , bool isUp, , uint256 gracePeriod, bool gracePassed, uint256 outageStarted, bool isUpAndValid) = usdOracleL2
            .sequencerL2Data();

        assertFalse(isUp, "Sequencer should be down");
        assertEq(gracePeriod, 45 minutes, "Down sequencer should use max grace period");
        assertFalse(gracePassed, "Grace period should not pass while sequencer is down");
        assertEq(outageStarted, block.timestamp - 90 minutes, "Should find earliest consecutive outage round");
        assertFalse(isUpAndValid, "Down sequencer cannot be valid");
    }

    // ==================== Normal Operation (sequencer up, grace period elapsed) ====================

    function test_l2_normalOperation_operateSucceeds() public {
        _setupUsdcConfig();

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Operate should succeed when sequencer is up and grace period elapsed");
    }

    function test_l2_normalOperation_liquidateSucceeds() public {
        _setupUsdcConfig();

        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertGt(price, 0, "Liquidate should succeed when sequencer is up and grace period elapsed");
    }

    // ==================== Consecutive Rounds Edge Cases ====================

    function test_l2_consecutiveUptimeRounds_findsCorrectStart() public {
        _setupUsdcConfig();

        // Round 1: up since T-2h
        // Round 2: down at T-1h
        // Round 3: up at T-31min
        // Round 4: up at T-20min (consecutive up, status report repeat)
        // Round 5: up at T-10min (consecutive up, status report repeat)
        // True uptime start is round 3 (T-31min)
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);
        sequencerFeed.setRound(2, 1, block.timestamp - 1 hours);
        sequencerFeed.setRound(3, 0, block.timestamp - 31 minutes);
        sequencerFeed.setRound(4, 0, block.timestamp - 20 minutes);
        sequencerFeed.setRound(5, 0, block.timestamp - 10 minutes);

        (, , bool isUp, uint256 uptimeStarted, , bool gracePassed, , ) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp);
        assertEq(uptimeStarted, block.timestamp - 31 minutes, "Should find earliest consecutive up round");
        assertTrue(gracePassed, "31 min uptime > 30 min outage, grace passed");
    }

    // ==================== Grace Period Boundary Tests ====================

    function test_l2_gracePeriod_exactBoundary_notPassed() public {
        _setupUsdcConfig();

        // 5 min outage, back up exactly 5 min ago -> uptimeDuration (5min) > gracePeriod (5min) is false
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 10 minutes, block.timestamp - 5 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_l2_gracePeriod_oneSecondPastBoundary_passes() public {
        _setupUsdcConfig();

        // 5 min outage, back up 5min+1s ago -> uptimeDuration > gracePeriod -> passes
        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 10 minutes, block.timestamp - 5 minutes - 1);

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "1 second past grace period boundary should pass");
    }

    // ==================== Sequencer Blocks Liquidate Too ====================

    function test_l2_gracePeriod_blocksLiquidateToo() public {
        _setupUsdcConfig();

        _setupOutageScenario(block.timestamp - 1 hours, block.timestamp - 10 minutes, block.timestamp - 1 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPrice(USDC, 0, false, true);
    }

    function test_l2_sequencerDown_blocksLiquidateToo() public {
        _setupUsdcConfig();

        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPrice(USDC, 0, false, true);
    }

    // ==================== Complex Round Histories ====================

    function test_l2_multipleOutages_usesLastOutageDuration() public {
        _setupUsdcConfig();

        // Round 1: up T-3h
        // Round 2: down T-2h (first outage: 30min)
        // Round 3: up T-1h30m
        // Round 4: down T-10min (second outage: latest)
        // Round 5: up T-5min
        // Grace period should be based on last outage (5 min = T-10 to T-5)
        sequencerFeed.setRound(1, 0, block.timestamp - 3 hours);
        sequencerFeed.setRound(2, 1, block.timestamp - 2 hours);
        sequencerFeed.setRound(3, 0, block.timestamp - 90 minutes);
        sequencerFeed.setRound(4, 1, block.timestamp - 10 minutes);
        sequencerFeed.setRound(5, 0, block.timestamp - 5 minutes);

        (
            ,
            ,
            bool isUp,
            uint256 uptimeStarted,
            uint256 gracePeriod,
            bool gracePassed,
            uint256 outageStarted,

        ) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp, "Sequencer should be up");
        assertEq(uptimeStarted, block.timestamp - 5 minutes, "Uptime should start at last up round");
        assertEq(outageStarted, block.timestamp - 10 minutes, "Outage should be the last down round");
        assertEq(gracePeriod, 5 minutes, "Grace period = last outage duration");
        assertFalse(gracePassed, "5 min uptime == 5 min grace period -> not passed (> not >=)");
    }

    function test_l2_longUptimeAfterMaxGrace_alwaysPasses() public {
        _setupUsdcConfig();

        // Sequencer up for >45 min (max grace) -> always passes regardless of outage duration
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        (, , bool isUp, , uint256 gracePeriod, bool gracePassed, , bool isUpAndValid) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp);
        assertEq(gracePeriod, 45 minutes, "Should return max grace period for long uptime");
        assertTrue(gracePassed, "Long uptime should always pass");
        assertTrue(isUpAndValid);

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Price should work after long uptime");
    }

    // ==================== All Inherited Base Tests Still Pass ====================

    function test_l2_allBaseOracleTests_inheritCorrectly() public {
        // Verify the L2 oracle inherits base behavior: stable source works
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "L2 oracle should delegate to base oracle for stable source");
    }

    // ==================== sequencerL2Data After Grace Period Passes ====================

    function test_l2_sequencerL2Data_afterGracePasses() public {
        _setupOutageScenario(block.timestamp - 2 hours, block.timestamp - 20 minutes, block.timestamp - 15 minutes);

        (
            ,
            ,
            bool isUp,
            uint256 uptimeStarted,
            uint256 gracePeriod,
            bool gracePassed,
            uint256 outageStarted,
            bool isUpAndValid
        ) = usdOracleL2.sequencerL2Data();

        assertTrue(isUp, "Sequencer should be up");
        assertEq(uptimeStarted, block.timestamp - 15 minutes, "Uptime start");
        assertEq(outageStarted, block.timestamp - 20 minutes, "Outage start");
        assertEq(gracePeriod, 5 minutes, "Grace period = outage duration");
        assertTrue(gracePassed, "15 min uptime > 5 min grace -> passed");
        assertTrue(isUpAndValid, "Should be up and valid");
    }

    // ==================== Pause + Sequencer Interaction ====================

    function test_l2_pauseCheckedAfterSequencer() public {
        _setupUsdcConfig();

        // Pause operate
        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, false);

        // With sequencer up: should revert with TokenPaused (sequencer check passes, then pause check kicks in)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPrice(USDC, 0, true, true);

        // With sequencer down: should revert with SequencerDown (checked first)
        sequencerFeed.setRound(2, 1, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    // ==================== L2 getPriceView Override ====================

    function test_l2_getPriceView_revertsWhenSequencerDown() public {
        _setupUsdcConfig();
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPriceView(USDC, 0, true, true);
    }

    function test_l2_getPriceView_succeedsWhenSequencerUp() public {
        _setupUsdcConfig();
        uint256 price = usdOracle.getPriceView(USDC, 0, true, true);
        assertGt(price, 0);
    }

    // ==================== L2 getPriceDetailed Override ====================

    function test_l2_getPriceDetailed_revertsWhenSequencerDown() public {
        _setupUsdcConfig();
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPriceDetailed(USDC, 0, true, true);
    }

    function test_l2_getPriceDetailed_returnsMetadata() public {
        _setupUsdcConfig();
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceDetailed(USDC, 0, true, true);
        assertGt(price, 0);
        assertEq(decimals, 6);
        assertEq(tokenType, 2);
    }

    // ==================== L2 getPriceDetailedView Override ====================

    function test_l2_getPriceDetailedView_revertsWhenSequencerDown() public {
        _setupUsdcConfig();
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPriceDetailedView(USDC, 0, true, true);
    }

    function test_l2_getPriceDetailedView_succeeds() public {
        _setupUsdcConfig();
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceDetailedView(USDC, 0, true, true);
        assertGt(price, 0);
        assertEq(decimals, 6);
        assertEq(tokenType, 2);
    }

    // ==================== L2 getPriceRawForMode Override ====================

    function test_l2_getPriceRawForMode_revertsWhenSequencerDown() public {
        _setupUsdcConfig();
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        usdOracle.getPriceRawForMode(USDC, 1);
    }

    function test_l2_getPriceRawForMode_succeedsAndBypassesCaps() public {
        _setupUsdcConfig();

        // Set a max cap on the operate key
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(OracleKey(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1 — collateral STABLE
        vm.stopPrank();

        // getPriceRawForMode bypasses caps
        (uint256 priceRaw, uint8 decimals, ) = usdOracle.getPriceRawForMode(USDC, 1);
        assertGt(priceRaw, 0, "Raw price should be non-zero");
        assertEq(decimals, 6);
    }

    function test_l2_getPriceRawForMode_revertsInGracePeriod() public {
        _setupUsdcConfig();
        _setupOutageScenario(block.timestamp - 10 minutes, block.timestamp - 5 minutes, block.timestamp - 2 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        usdOracle.getPriceRawForMode(USDC, 1);
    }

    function test_getPriceDetailed_sequencerCheckedOnce() public {
        _setupUsdcConfig();
        vm.expectCall(
            address(sequencerFeed),
            abi.encodeWithSelector(IChainlinkAggregatorV3.latestRoundData.selector),
            1
        );
        usdOracle.getPriceDetailed(USDC, 0, true, true);
    }
}
