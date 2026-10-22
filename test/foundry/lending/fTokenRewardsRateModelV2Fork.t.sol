// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { IFToken, IFTokenAdmin } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFluidLendingStaticRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingStaticRateModel.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { FluidLendingStaticRateModel } from "../../../contracts/protocols/lending/lendingStaticRateModel/main.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { fTokenStaticRateTestBase } from "./fTokenStaticRate.t.sol";

// ---------------------------------------------------------------------------
// Part A — mainnet fork: backward compatibility with deployed (old-bytecode) fTokens
// ---------------------------------------------------------------------------

contract fTokenRewardsRateModelV2ForkPartATest is Test {
    IFluidLendingFactory internal constant LENDING_FACTORY =
        IFluidLendingFactory(0x54B91A0D94cb471F37f949c60F7Fa7935b551D03);
    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant FUSDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
    address internal constant FUSDT = 0x5C20B550819128074FD538Edf79791733ccEdd18;
    address internal constant FWETH = 0x90551c1795392094FE6D29B758EcCD233cFAa260;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant RATE_PRECISION = 1e12;
    uint256 internal constant START_TVL = 1000e6;
    uint256 internal constant REWARD_DURATION = 7 days;
    uint256 internal constant DEPOSIT_AMOUNT = 10_000e6;

    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_680_552);
    }

    function _deployAndWireStreamingModel(
        address fToken_,
        uint256 rewardAmount_
    ) internal returns (FluidLendingRewardsRateModel model_) {
        model_ = new FluidLendingRewardsRateModel(
            address(this),
            fToken_,
            address(0),
            address(0),
            START_TVL,
            rewardAmount_,
            REWARD_DURATION,
            block.timestamp
        );

        vm.prank(GOVERNANCE);
        LENDING_FACTORY.setAuth(address(model_), true);

        vm.prank(GOVERNANCE);
        IFTokenAdmin(fToken_).updateRewards(IFluidLendingRewardsRateModel(address(model_)));
    }

    function _rewardAmountForApproxRate(address fToken_, uint256 targetRateBps_) internal view returns (uint256) {
        uint256 totalAssets_ = IFToken(fToken_).totalAssets();
        if (totalAssets_ < START_TVL) {
            totalAssets_ = START_TVL;
        }
        // targetRateBps_ is in 1e12 scale (e.g. 5e12 = 5%)
        return (totalAssets_ * targetRateBps_ * REWARD_DURATION) / (1e14 * 365 days);
    }

    function test_fork_lendingFactory_allTokensIncludesDeployedFTokens() public view {
        address[] memory tokens_ = LENDING_FACTORY.allTokens();
        assertGt(tokens_.length, 0);

        bool foundUsdc_;
        bool foundUsdt_;
        bool foundWeth_;
        for (uint256 i_; i_ < tokens_.length; i_++) {
            if (tokens_[i_] == FUSDC) foundUsdc_ = true;
            if (tokens_[i_] == FUSDT) foundUsdt_ = true;
            if (tokens_[i_] == FWETH) foundWeth_ = true;
        }
        assertTrue(foundUsdc_, "fUSDC missing from allTokens");
        assertTrue(foundUsdt_, "fUSDT missing from allTokens");
        assertTrue(foundWeth_, "fWETH missing from allTokens");
    }

    function test_fork_oldFToken_fUSDC_newModel_rewardsAccrueWhileActive() public {
        FluidLendingRewardsRateModel model_ = _deployAndWireStreamingModel(
            FUSDC,
            _rewardAmountForApproxRate(FUSDC, 5 * RATE_PRECISION)
        );

        (, , , , , bool rewardsActiveBefore_, , uint256 liquidityBefore_, uint256 tokenBefore_) = IFToken(FUSDC)
            .getData();
        assertTrue(rewardsActiveBefore_);

        vm.warp(block.timestamp + 1 days);

        (, , , , , bool rewardsActiveAfter_, , uint256 liquidityAfter_, uint256 tokenAfter_) = IFToken(FUSDC).getData();
        assertTrue(rewardsActiveAfter_);
        assertGt(tokenAfter_, tokenBefore_, "token exchange price should grow with rewards");
        assertGe(liquidityAfter_, liquidityBefore_, "liquidity exchange price should not decrease");

        uint256 liquidityApr_ = (((liquidityAfter_ - liquidityBefore_) * 1e14) / liquidityBefore_) * 365;
        uint256 tokenApr_ = (((tokenAfter_ - tokenBefore_) * 1e14) / tokenBefore_) * 365;
        assertGt(tokenApr_, liquidityApr_, "rewards should outpace liquidity yield alone");

        (uint256 legacyRate_, bool legacyEnded_, ) = model_.getRate(IFToken(FUSDC).totalAssets());
        assertGt(legacyRate_, 0);
        assertFalse(legacyEnded_);
    }

    function test_fork_oldFToken_fUSDC_afterRewardsEnd_legacyRateZero_noRevert() public {
        FluidLendingRewardsRateModel model_ = _deployAndWireStreamingModel(
            FUSDC,
            _rewardAmountForApproxRate(FUSDC, 5 * RATE_PRECISION)
        );

        // stored state right after wiring (updateRewards settled storage at this timestamp)
        (, , , , , , , uint256 liquidityStart_, uint256 tokenStart_) = IFToken(FUSDC).getData();

        vm.warp(block.timestamp + 1 days);
        (, , , , , , , , uint256 tokenMid_) = IFToken(FUSDC).getData();
        assertGt(tokenMid_, tokenStart_, "rewards accrue in view while mid-program");

        // warp far beyond program end and settle via updateRates
        vm.warp(block.timestamp + REWARD_DURATION + 30 days);
        IFTokenAdmin(FUSDC).updateRates();

        (uint256 legacyRate_, bool legacyEnded_, ) = model_.getRate(IFToken(FUSDC).totalAssets());
        assertEq(legacyRate_, 0, "legacy getRate returns 0 once ended");
        assertTrue(legacyEnded_);

        // KNOWN LEGACY LIMITATION (this is what getRateV2 fixes for NEW fTokens): the old fToken applies the
        // legacy rate (0 once ended) to the ENTIRE window since its last storage update. Since no poke happened
        // between wiring and program end, ALL rewards since wiring are lost — only liquidity yield compounds.
        (, , , , , , , uint256 liquidityEnd_, uint256 tokenEnd_) = IFToken(FUSDC).getData();
        uint256 expectedToken_ = tokenStart_ +
            (tokenStart_ * (((liquidityEnd_ - liquidityStart_) * 1e14) / liquidityStart_)) /
            1e14;
        assertEq(tokenEnd_, expectedToken_, "old fToken loses the whole unpoked rewards window (legacy behavior)");
    }

    function test_fork_oldFToken_fUSDC_depositWithdrawAfterRewardsEnd() public {
        _deployAndWireStreamingModel(FUSDC, _rewardAmountForApproxRate(FUSDC, 5 * RATE_PRECISION));

        vm.warp(block.timestamp + REWARD_DURATION + 1 days);
        IFTokenAdmin(FUSDC).updateRates();

        deal(USDC, alice, DEPOSIT_AMOUNT);
        vm.prank(alice);
        IERC20(USDC).approve(FUSDC, type(uint256).max);

        uint256 sharesBefore_ = IERC4626(FUSDC).balanceOf(alice);
        vm.prank(alice);
        uint256 shares_ = IERC4626(FUSDC).deposit(DEPOSIT_AMOUNT, alice);
        assertGt(shares_, 0);
        assertEq(IERC4626(FUSDC).balanceOf(alice), sharesBefore_ + shares_);

        vm.warp(block.timestamp + 7 days);

        uint256 withdrawable_ = IERC4626(FUSDC).maxWithdraw(alice);
        assertGt(withdrawable_, 0);
        vm.prank(alice);
        uint256 withdrawn_ = IERC4626(FUSDC).withdraw(withdrawable_, alice, alice);
        assertGt(withdrawn_, 0);
        assertEq(IERC4626(FUSDC).balanceOf(alice), 0);
    }

    function test_fork_oldFToken_fWETH_newModel_safeAfterEnd() public {
        FluidLendingRewardsRateModel model_ = _deployAndWireStreamingModel(
            FWETH,
            _rewardAmountForApproxRate(FWETH, 3 * RATE_PRECISION)
        );

        vm.warp(block.timestamp + REWARD_DURATION + 14 days);
        IFTokenAdmin(FWETH).updateRates();

        (uint256 legacyRate_, bool legacyEnded_, ) = model_.getRate(IFToken(FWETH).totalAssets());
        assertEq(legacyRate_, 0);
        assertTrue(legacyEnded_);

        (, , , , , , , , uint256 tokenAfter_) = IFToken(FWETH).getData();
        assertGt(tokenAfter_, 0, "sane exchange price after legacy end");
    }
}

// ---------------------------------------------------------------------------
// Part B — new fToken bytecode + new models (local harness, same file)
// ---------------------------------------------------------------------------

contract RevertingRewardsRateModel is IFluidLendingRewardsRateModel {
    function getRate(uint256) external pure returns (uint256, bool, uint256) {
        revert("broken getRate");
    }

    function getRateV2(uint256) external pure returns (int256, bool, uint256, uint256) {
        revert("broken getRateV2");
    }

    function getConfig() external pure returns (uint256, uint256, uint256, uint256, uint256, uint256, address) {
        revert("broken getConfig");
    }
}

contract fTokenRewardsRateModelV2PartBTest is fTokenStaticRateTestBase {
    function _wireStreamingModel(
        uint256 startTvl_,
        uint256 rewardAmount_,
        uint256 duration_,
        uint256 startTime_
    ) internal returns (FluidLendingRewardsRateModel model_) {
        model_ = new FluidLendingRewardsRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            startTvl_,
            rewardAmount_,
            duration_,
            startTime_
        );
        vm.prank(admin);
        factory.setAuth(address(model_), true);
        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(model_)));
    }

    function _wireStaticModel(uint256 rate_, uint256 duration_) internal returns (FluidLendingStaticRateModel model_) {
        model_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(rate_),
            duration_
        );
        vm.prank(admin);
        factory.setAuth(address(model_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(model_)));
    }

    // 1. before startTime: no rewards accrual (streaming)
    function test_partB_streaming_beforeStartTime_noAccrual() public {
        uint256 futureStart_ = block.timestamp + 3 days;
        _wireStreamingModel(1, DEFAULT_AMOUNT / 100, SHORT_DURATION, futureStart_);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        vm.warp(block.timestamp + 1 days);
        uint256 tokenMid_;
        (, , , , , , , , tokenMid_) = lendingFToken.getData();
        assertEq(tokenMid_, tokenBefore_, "no accrual before startTime");

        vm.warp(futureStart_ + 7 days);
        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();
        assertGt(tokenAfter_, tokenMid_, "accrual begins after startTime");
    }

    // 2. mid-program: accrual at expected rate (streaming)
    function test_partB_streaming_midProgram_exactAccrual() public {
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(
            1,
            DEFAULT_AMOUNT / 100,
            SHORT_DURATION,
            block.timestamp
        );

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        uint256 elapsed_ = 7 days;
        vm.warp(block.timestamp + elapsed_);

        (int256 rate_, , , ) = model_.getRateV2((tokenBefore_ * lendingFToken.totalSupply()) / 1e12);
        assertGt(rate_, int256(0));

        lendingFToken.updateRates();
        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();

        uint256 expectedReturn_ = (uint256(rate_) * elapsed_) / 365 days;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * expectedReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "mid-program streaming accrual must match rate * elapsed / year");
        assertEq(lastUpdate_, block.timestamp - elapsed_);
    }

    // 3. warp past endTime without poke: exact tail to endTime (streaming)
    function test_partB_streaming_pastEndWithoutPoke_exactMathToEndTime() public {
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(
            1,
            DEFAULT_AMOUNT / 100,
            SHORT_DURATION,
            block.timestamp
        );

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        vm.warp(block.timestamp + SHORT_DURATION + 365 days);

        (int256 rate_, bool ended_, , uint256 endTime_) = model_.getRateV2(
            (tokenBefore_ * lendingFToken.totalSupply()) / 1e12
        );
        assertTrue(ended_);

        lendingFToken.updateRates();
        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();

        uint256 expectedReturn_ = (uint256(rate_) * (endTime_ - lastUpdate_)) / 365 days;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * expectedReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "streaming tail must accrue exactly until endTime");
    }

    // 4. after end + updateRates poke: rewardsActive cleared, liquidity only (streaming)
    function test_partB_streaming_afterEndPoke_rewardsActiveCleared_liquidityOnly() public {
        _wireStreamingModel(1, DEFAULT_AMOUNT / 100, SHORT_DURATION, block.timestamp);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + SHORT_DURATION + 1 days);
        lendingFToken.updateRates();

        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive_, "rewardsActive clears after tail settled");

        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();
        vm.warp(block.timestamp + 365 days);
        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();
        assertEq(tokenAfter_, tokenBefore_, "no further accrual without liquidity yield bootstrapped");
    }

    // 5. queued next phase: accrual stops exactly at second phase endTime (streaming)
    function test_partB_streaming_queuedNextPhase_twoPhaseEnd() public {
        uint256 phase1Duration_ = 7 days;
        uint256 phase2Duration_ = 14 days;
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(
            1,
            DEFAULT_AMOUNT / 100,
            phase1Duration_,
            block.timestamp
        );

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 phase2Reward_ = DEFAULT_AMOUNT / 50;
        vm.prank(admin);
        model_.queueNextRewards(phase2Reward_, phase2Duration_);

        // finish phase 1, transition, and settle through phase-1 end + phase-2 start
        vm.warp(block.timestamp + phase1Duration_ + 1);
        vm.prank(admin);
        model_.transitionToNextRewards();
        lendingFToken.updateRates();

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        // warp far beyond phase 2 end without further pokes
        vm.warp(block.timestamp + phase2Duration_ + 365 days);

        (int256 rate_, bool ended_, , uint256 endTime_) = model_.getRateV2(
            (tokenBefore_ * lendingFToken.totalSupply()) / 1e12
        );
        assertTrue(ended_);
        assertGt(rate_, int256(0));

        lendingFToken.updateRates();
        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();

        uint256 expectedReturn_ = (uint256(rate_) * (endTime_ - lastUpdate_)) / 365 days;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * expectedReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "second phase tail accrues exactly until endTime");
    }

    function test_partB_streaming_startRewardsSettlesExpiredTailBeforeOverwrite() public {
        uint256 oldDuration_ = 7 days;
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(
            1,
            DEFAULT_AMOUNT / 100,
            oldDuration_,
            block.timestamp
        );

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        // checkpoint so lastUpdate / exchange prices match block.timestamp
        lendingFToken.updateRates();

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        uint256 liqBefore_;
        (, , , , , , , liqBefore_, tokenBefore_) = lendingFToken.getData();
        (int256 oldRate_, , , uint256 oldEndTime_) = model_.getRateV2(
            (tokenBefore_ * lendingFToken.totalSupply()) / 1e12
        );

        // expire without an intermediate poke, then restart — startRewards must settle the old tail first
        vm.warp(oldEndTime_ + 1);
        vm.prank(admin);
        model_.startRewards(DEFAULT_AMOUNT / 50, 14 days, block.timestamp);

        uint256 tokenAfter_;
        uint256 liqAfter_;
        bool rewardsActive_;
        (, , , , , rewardsActive_, , liqAfter_, tokenAfter_) = lendingFToken.getData();
        uint256 expectedRewardsReturn_ = (uint256(oldRate_) * (oldEndTime_ - lastUpdate_)) / 365 days;
        uint256 expectedLiquidityReturn_ = ((liqAfter_ - liqBefore_) * 1e14) / liqBefore_;
        uint256 expectedTokenAfter_ = tokenBefore_ +
            ((tokenBefore_ * (expectedRewardsReturn_ + expectedLiquidityReturn_)) / 1e14);

        assertEq(tokenAfter_, expectedTokenAfter_, "expired schedule tail must settle before new schedule overwrite");
        assertTrue(rewardsActive_, "new schedule must reactivate rewards");
    }

    function test_partB_streaming_startRewardsRequiresQueuedPhaseTransition() public {
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(1, DEFAULT_AMOUNT / 100, 7 days, block.timestamp);
        vm.prank(admin);
        model_.queueNextRewards(DEFAULT_AMOUNT / 50, 14 days);

        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.LendingRewardsRateModel__MustTransitionToNext
            )
        );
        vm.prank(admin);
        model_.startRewards(DEFAULT_AMOUNT / 25, 30 days, block.timestamp);
    }

    // 6a. static active: Liquidity yield always compounds; offset adds on top
    function test_partB_static_active_liquidityPlusOffset() public {
        _bootstrapLiquidityYield();
        FluidLendingStaticRateModel model_ = _wireStaticModel(STATIC_TARGET_RATE, SHORT_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        uint256 liquidityBefore_;
        (, , , , , , , liquidityBefore_, tokenBefore_) = lendingFToken.getData();

        vm.warp(block.timestamp + 7 days);

        uint256 tokenAfter_;
        uint256 liquidityAfter_;
        (, , , , , , , liquidityAfter_, tokenAfter_) = lendingFToken.getData();

        assertGt(liquidityAfter_, liquidityBefore_, "liquidity layer accrues independently");
        uint256 offsetReturn_ = (STATIC_TARGET_RATE * 7 days) / 365 days;
        uint256 liquidityReturn_ = ((liquidityAfter_ - liquidityBefore_) * 1e14) / liquidityBefore_;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * (offsetReturn_ + liquidityReturn_)) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "Liquidity yield + static offset while program active");

        (int256 rate_, bool ended_, , ) = model_.getRateV2(0);
        assertEq(rate_, int256(STATIC_TARGET_RATE));
        assertFalse(ended_);
        assertEq(lastUpdate_, block.timestamp - 7 days);
    }

    // 6b. static after end: offset until endTime + full-window Liquidity (no mid-window pro-rate)
    function test_partB_static_afterEnd_fullLiquidityPlusOffsetUntilEndTime() public {
        _bootstrapLiquidityYield();
        FluidLendingStaticRateModel model_ = _wireStaticModel(STATIC_TARGET_RATE, SHORT_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        uint256 liquidityBefore_;
        (, , , , , , , liquidityBefore_, tokenBefore_) = lendingFToken.getData();

        (, , , uint256 endTime_) = model_.getRateV2(0);

        vm.warp(block.timestamp + SHORT_DURATION + 60 days);

        uint256 tokenAfter_;
        uint256 liquidityAfter_;
        (, , , , , , , liquidityAfter_, tokenAfter_) = lendingFToken.getData();

        uint256 offsetReturn_ = (STATIC_TARGET_RATE * (endTime_ - lastUpdate_)) / 365 days;
        uint256 liquidityReturn_ = ((liquidityAfter_ - liquidityBefore_) * 1e14) / liquidityBefore_;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * (offsetReturn_ + liquidityReturn_)) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "offset until endTime + full Liquidity yield for the window");
    }

    // 7. broken/reverting model: operations do not revert, only liquidity yield
    function test_partB_revertingModel_noBrick() public {
        _bootstrapLiquidityYield();
        RevertingRewardsRateModel broken_ = new RevertingRewardsRateModel();

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(broken_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 tokenBefore_;
        uint256 liquidityBefore_;
        (, , , , , , , liquidityBefore_, tokenBefore_) = lendingFToken.getData();

        vm.warp(block.timestamp + 30 days);

        lendingFToken.updateRates();
        uint256 tokenAfter_;
        uint256 liquidityAfter_;
        bool rewardsActive_;
        (, , , , , rewardsActive_, , liquidityAfter_, tokenAfter_) = lendingFToken.getData();
        assertFalse(rewardsActive_, "broken model treated as ended");

        uint256 liquidityReturn_ = ((liquidityAfter_ - liquidityBefore_) * 1e14) / liquidityBefore_;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * liquidityReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "only liquidity yield accrues with broken model");

        vm.prank(bob);
        lendingFToken.deposit(DEFAULT_AMOUNT, bob);
        vm.prank(alice);
        lendingFToken.withdraw(DEFAULT_AMOUNT / 2, alice, alice);
    }

    // 8a. getRateV2 vs legacy getRate semantics on streaming model
    function test_partB_streaming_getRateV2_vs_legacyGetRate_semantics() public {
        FluidLendingRewardsRateModel model_ = _wireStreamingModel(
            1,
            DEFAULT_AMOUNT / 100,
            SHORT_DURATION,
            block.timestamp
        );

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 totalAssets_ = lendingFToken.totalAssets();
        (int256 activeRate_, , , uint256 activeEnd_) = model_.getRateV2(totalAssets_);
        (uint256 legacyRate_, bool legacyEnded_, ) = model_.getRate(totalAssets_);
        assertGt(activeRate_, int256(0));
        assertEq(legacyRate_, uint256(activeRate_));
        assertFalse(legacyEnded_);
        assertEq(activeEnd_, block.timestamp + SHORT_DURATION);

        vm.warp(block.timestamp + SHORT_DURATION + 1);

        (int256 endedV2Rate_, bool endedV2_, , uint256 endedEnd_) = model_.getRateV2(totalAssets_);
        (uint256 endedLegacyRate_, bool endedLegacy_, ) = model_.getRate(totalAssets_);
        assertTrue(endedV2_);
        assertTrue(endedLegacy_);
        assertGt(endedV2Rate_, int256(0), "getRateV2 keeps actual rate when ended");
        assertEq(endedLegacyRate_, 0, "legacy getRate returns 0 when ended");
        assertEq(endedEnd_, block.timestamp - 1);
    }

    // 8b. getRateV2 semantics on static model
    function test_partB_static_getRateV2_semantics() public {
        FluidLendingStaticRateModel model_ = _wireStaticModel(STATIC_TARGET_RATE, SHORT_DURATION);

        (int256 rate_, bool ended_, uint256 startTime_, uint256 endTime_) = model_.getRateV2(0);
        assertEq(rate_, int256(STATIC_TARGET_RATE));
        assertFalse(ended_);
        assertEq(startTime_, block.timestamp);
        assertEq(endTime_, block.timestamp + SHORT_DURATION);

        vm.warp(block.timestamp + SHORT_DURATION + 1);

        (rate_, ended_, startTime_, endTime_) = model_.getRateV2(0);
        assertEq(rate_, int256(STATIC_TARGET_RATE), "static rate stays actual when ended");
        assertTrue(ended_);
        assertEq(endTime_, startTime_ + SHORT_DURATION);
    }
}
