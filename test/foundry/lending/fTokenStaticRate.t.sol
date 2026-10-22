// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidLendingStaticRateModel } from "../../../contracts/protocols/lending/lendingStaticRateModel/main.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFluidLendingStaticRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingStaticRateModel.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { LendingRewardsRateMockModel } from "./mocks/rewardsMock.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { fTokenBaseSetUp } from "./fToken.t.sol";
import { Events as fTokenEvents } from "../../../contracts/protocols/lending/fToken/events.sol";
import { FluidLendingResolver } from "../../../contracts/periphery/resolvers/lending/main.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IFToken } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Structs as FluidLendingResolverStructs } from "../../../contracts/periphery/resolvers/lending/structs.sol";
import { Structs as FluidLiquidityResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";

// To test run: forge test --match-path test/foundry/lending/fTokenStaticRate.t.sol -vvv
abstract contract fTokenStaticRateTestBase is fTokenBaseSetUp, fTokenEvents {
    uint256 constant RATE_PRECISION = 1e12;
    uint256 constant STATIC_TARGET_RATE = 3 * RATE_PRECISION; // 3% on-chain model scale
    uint256 constant STATIC_TARGET_RATE_RESOLVER = STATIC_TARGET_RATE / 1e10; // 3% at Liquidity scale
    /// @dev long-lived test programs (fits uint32; ~100 years)
    uint256 constant OPEN_ENDED_DURATION = 100 * 365 days;
    uint256 constant SHORT_DURATION = 30 days;

    FluidLendingStaticRateModel staticModel;

    function _createToken(
        FluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) internal virtual override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(asset_), "fToken", false));
    }

    function setUp() public virtual override {
        super.setUp();

        staticModel = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            OPEN_ENDED_DURATION
        );

        vm.prank(admin);
        factory.setAuth(address(staticModel), true);

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));
    }

    /// @dev Creates utilization at Liquidity so supplier exchange price accrues over time.
    function _bootstrapLiquidityYield() internal {
        uint256 extraSupply_ = DEFAULT_AMOUNT * 9;
        underlying.mint(alice, extraSupply_);
        _supply(address(liquidity), mockProtocol, address(underlying), alice, extraSupply_);
        _borrow(mockProtocol, address(underlying), bob, DEFAULT_AMOUNT * 8);
    }

    function _aprOverYear(uint256 exchangePriceBefore, uint256 exchangePriceAfter) internal pure returns (uint256) {
        return (((exchangePriceAfter - exchangePriceBefore) * 1e14) / exchangePriceBefore);
    }
}

contract fTokenStaticRateTest is fTokenStaticRateTestBase {
    function test_staticOffsetIndependentOfTvl_addsOnTopOfLiquidity() public {
        _bootstrapLiquidityYield();

        uint256 smallDeposit = DEFAULT_AMOUNT;
        uint256 largeDeposit = DEFAULT_AMOUNT * 10;

        vm.prank(alice);
        lendingFToken.deposit(smallDeposit, alice);

        uint256 liquidityBeforeSmall;
        uint256 tokenBeforeSmall;
        (, , , , , , , liquidityBeforeSmall, tokenBeforeSmall) = lendingFToken.getData();

        vm.warp(block.timestamp + 365 days);

        uint256 liquidityAfterSmall;
        uint256 tokenAfterSmall;
        (, , , , , , , liquidityAfterSmall, tokenAfterSmall) = lendingFToken.getData();

        uint256 tokenAprSmall = _aprOverYear(tokenBeforeSmall, tokenAfterSmall);
        uint256 liquidityAprSmall = _aprOverYear(liquidityBeforeSmall, liquidityAfterSmall);

        vm.prank(bob);
        lendingFToken.deposit(largeDeposit, bob);

        liquidityBeforeSmall = liquidityAfterSmall;
        tokenBeforeSmall = tokenAfterSmall;

        vm.warp(block.timestamp + 365 days);

        (, , , , , , , liquidityAfterSmall, tokenAfterSmall) = lendingFToken.getData();

        uint256 tokenAprLarge = _aprOverYear(tokenBeforeSmall, tokenAfterSmall);
        uint256 liquidityAprLarge = _aprOverYear(liquidityBeforeSmall, liquidityAfterSmall);

        // offset is TVL-independent and additive on Liquidity yield
        assertApproxEqAbs(tokenAprSmall, liquidityAprSmall + STATIC_TARGET_RATE, 1e6);
        assertApproxEqAbs(tokenAprLarge, liquidityAprLarge + STATIC_TARGET_RATE, 1e6);
        assertApproxEqAbs(tokenAprSmall - liquidityAprSmall, tokenAprLarge - liquidityAprLarge, 1e6);
        assertGt(liquidityAprSmall, 0, "liquidity supply should accrue with utilization");
        assertGt(liquidityAprLarge, 0, "liquidity supply should accrue with utilization");
    }

    function test_rebalance_withdrawsFeesWhenNegativeOffsetBelowLiquidity() public {
        _bootstrapLiquidityYield();

        // negative offset so share EP grows slower than Liquidity EP → surplus at Liquidity
        vm.prank(admin);
        staticModel.setStaticRate(-int256(2 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + 365 days);

        uint256 totalAssetsBefore = lendingFToken.totalAssets();
        (, , , , , , uint256 liquidityBalanceBefore, , ) = lendingFToken.getData();
        assertGt(liquidityBalanceBefore, totalAssetsBefore, "fees should accrue at Liquidity");

        uint256 adminBalanceBefore = underlying.balanceOf(admin);
        uint256 expectedWithdraw_ = liquidityBalanceBefore - totalAssetsBefore;
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(-int256(expectedWithdraw_));
        vm.prank(admin);
        uint256 withdrawn_ = lendingFToken.rebalance();

        assertGt(withdrawn_, 0);
        assertEq(withdrawn_, expectedWithdraw_);
        assertEq(underlying.balanceOf(admin), adminBalanceBefore + withdrawn_);
        assertEq(lendingFToken.totalAssets(), totalAssetsBefore);
        (, , , , , , uint256 liquidityBalanceAfter, , ) = lendingFToken.getData();
        assertApproxEqAbs(liquidityBalanceAfter, totalAssetsBefore, 1e3);
    }

    function test_negativeOffset_slowsSharePriceVsLiquidity_floorsAtZero() public {
        _bootstrapLiquidityYield();

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 liquidityBefore;
        uint256 tokenBefore;
        (, , , , , , , liquidityBefore, tokenBefore) = lendingFToken.getData();

        // Mild negative offset: still some net positive return
        vm.prank(admin);
        staticModel.setStaticRate(-int256(1 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.warp(block.timestamp + 365 days);

        uint256 liquidityAfter;
        uint256 tokenAfter;
        (, , , , , , , liquidityAfter, tokenAfter) = lendingFToken.getData();

        uint256 tokenApr = _aprOverYear(tokenBefore, tokenAfter);
        uint256 liquidityApr = _aprOverYear(liquidityBefore, liquidityAfter);
        assertApproxEqAbs(tokenApr, liquidityApr - RATE_PRECISION, 1e6);
        assertGt(tokenAfter, tokenBefore, "mild negative offset still allows EP growth");

        // Extreme negative offset: net return floored at 0 → EP unchanged over the window
        tokenBefore = tokenAfter;
        liquidityBefore = liquidityAfter;
        vm.prank(admin);
        staticModel.setStaticRate(-int256(50 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.warp(block.timestamp + 365 days);
        (, , , , , , , liquidityAfter, tokenAfter) = lendingFToken.getData();

        assertEq(tokenAfter, tokenBefore, "net return floored at 0 when |offset| exceeds Liquidity yield");
        assertGt(liquidityAfter, liquidityBefore, "Liquidity EP still grows");
    }

    function test_rewardsRateOutsideMax_treatedAsZero() public {
        _bootstrapLiquidityYield();

        LendingRewardsRateMockModel mock_ = new LendingRewardsRateMockModel();
        mock_.setStartTime(block.timestamp);
        // just above ±MAX_REWARDS_RATE (50%) → fToken zeroes the rate (safety valve)
        mock_.setSignedRate(int256(50 * RATE_PRECISION) + 1);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(mock_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 liquidityBefore;
        uint256 tokenBefore;
        (, , , , , , , liquidityBefore, tokenBefore) = lendingFToken.getData();

        vm.warp(block.timestamp + 365 days);

        uint256 liquidityAfter;
        uint256 tokenAfter;
        (, , , , , , , liquidityAfter, tokenAfter) = lendingFToken.getData();

        uint256 liquidityReturn_ = ((liquidityAfter - liquidityBefore) * 1e14) / liquidityBefore;
        uint256 expectedToken_ = tokenBefore + ((tokenBefore * liquidityReturn_) / 1e14);
        assertEq(tokenAfter, expectedToken_, "rate > MAX_REWARDS_RATE must be ignored (Liquidity only)");

        // checkpoint storage so the next window uses the new signed rate only
        lendingFToken.updateRates();

        // same for below -MAX
        mock_.setSignedRate(-int256(50 * RATE_PRECISION) - 1);
        (, , , , , , , liquidityBefore, tokenBefore) = lendingFToken.getData();
        vm.warp(block.timestamp + 365 days);
        (, , , , , , , liquidityAfter, tokenAfter) = lendingFToken.getData();
        liquidityReturn_ = ((liquidityAfter - liquidityBefore) * 1e14) / liquidityBefore;
        expectedToken_ = tokenBefore + ((tokenBefore * liquidityReturn_) / 1e14);
        assertEq(tokenAfter, expectedToken_, "rate < -MAX_REWARDS_RATE must be ignored (Liquidity only)");
    }

    function test_rebalance_depositsRewardsWhenStaticAboveLiquidity() public {
        _bootstrapLiquidityYield();

        vm.prank(admin);
        staticModel.setStaticRate(int256(20 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + 365 days);

        uint256 totalAssetsBefore = lendingFToken.totalAssets();
        (, , , , , , uint256 liquidityBalanceBefore, , ) = lendingFToken.getData();
        assertGt(totalAssetsBefore, liquidityBalanceBefore, "rewards gap should open");

        uint256 adminBalanceBefore = underlying.balanceOf(admin);
        uint256 expectedDeposit_ = totalAssetsBefore - liquidityBalanceBefore;
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(int256(expectedDeposit_));
        vm.prank(admin);
        uint256 deposited_ = lendingFToken.rebalance();

        assertGt(deposited_, 0);
        assertEq(deposited_, expectedDeposit_);
        assertEq(underlying.balanceOf(admin), adminBalanceBefore - deposited_);
        assertEq(lendingFToken.totalAssets(), totalAssetsBefore);
        (, , , , , , uint256 liquidityBalanceAfter, , ) = lendingFToken.getData();
        assertApproxEqAbs(liquidityBalanceAfter, totalAssetsBefore, 1e3);
    }

    function test_staticOffsetZero_tracksLiquidityYield() public {
        _bootstrapLiquidityYield();

        vm.prank(admin);
        staticModel.setStaticRate(int256(0), OPEN_ENDED_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 liquidityBefore;
        uint256 tokenBefore;
        (, , , , , , , liquidityBefore, tokenBefore) = lendingFToken.getData();

        vm.warp(block.timestamp + 365 days);

        uint256 liquidityBalanceAfter;
        uint256 liquidityAfter;
        uint256 tokenAfter;
        uint256 totalAssetsAfter = lendingFToken.totalAssets();
        (, , , , , , liquidityBalanceAfter, liquidityAfter, tokenAfter) = lendingFToken.getData();

        // 0 offset → share EP compounds Liquidity yield only; inventory stays matched
        assertApproxEqAbs(
            _aprOverYear(tokenBefore, tokenAfter),
            _aprOverYear(liquidityBefore, liquidityAfter),
            1e6,
            "0 offset should track Liquidity APR"
        );
        assertApproxEqAbs(liquidityBalanceAfter, totalAssetsAfter, 1e3, "no rebalance gap at 0 offset");
    }

    function test_streamingRateFallsWhenTvlDoubles() public {
        uint256 startTvl = DEFAULT_AMOUNT;
        uint256 rewardAmount = (startTvl * 20) / 100; // ~20% APR at startTvl

        FluidLendingRewardsRateModel streamingModel = new FluidLendingRewardsRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            1,
            rewardAmount,
            365 days,
            block.timestamp
        );

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 totalAssetsBefore = lendingFToken.totalAssets();
        (uint256 rateBefore, , ) = streamingModel.getRate(totalAssetsBefore);
        assertGt(rateBefore, 0);

        vm.prank(bob);
        lendingFToken.deposit(DEFAULT_AMOUNT, bob);

        uint256 totalAssetsAfter = lendingFToken.totalAssets();
        (uint256 rateAfter, , ) = streamingModel.getRate(totalAssetsAfter);

        assertGt(rateBefore, rateAfter);
        assertApproxEqAbs(totalAssetsAfter, totalAssetsBefore * 2, 1e6);
    }

    function test_updateStaticRewards_zeroDisables() public {
        assertTrue(lendingFToken.isStaticRateModelActive());

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(0)));

        (, , , , , bool rewardsActive, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive);
        assertFalse(lendingFToken.isStaticRateModelActive());
    }

    function test_switchBetweenStaticAndStreaming() public {
        assertTrue(lendingFToken.isStaticRateModelActive());

        LendingRewardsRateMockModel streamingModel = new LendingRewardsRateMockModel();
        streamingModel.setRate(10 * RATE_PRECISION);
        streamingModel.setStartTime(block.timestamp);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel)));

        assertFalse(lendingFToken.isStaticRateModelActive());
        (, , IFluidLendingRewardsRateModel rewardsModel, , , bool rewardsActive, , , ) = lendingFToken.getData();
        assertTrue(rewardsActive);
        assertEq(address(rewardsModel), address(streamingModel));

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));

        assertTrue(lendingFToken.isStaticRateModelActive());
        (, , rewardsModel, , , rewardsActive, , , ) = lendingFToken.getData();
        assertTrue(rewardsActive);
        assertEq(address(rewardsModel), address(staticModel));
    }

    function test_updateStaticRewards_RevertUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));
    }

    function test_wiredModel_canUpdateStaticRewardsWithoutFactoryAuth() public {
        // revoke factory auth that setUp granted for the initial wire
        vm.prank(admin);
        factory.setAuth(address(staticModel), false);

        vm.prank(address(staticModel));
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));

        assertTrue(lendingFToken.isStaticRateModelActive());
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertTrue(rewardsActive_);
    }

    function test_wiredModel_setStaticRateWithoutFactoryAuth() public {
        vm.prank(admin);
        factory.setAuth(address(staticModel), false);

        vm.prank(admin);
        staticModel.setStaticRate(int256(5 * RATE_PRECISION), OPEN_ENDED_DURATION);

        (int256 rate_, , , ) = staticModel.getRateV2(0);
        assertEq(rate_, int256(5 * RATE_PRECISION));
        assertTrue(lendingFToken.isStaticRateModelActive());
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertTrue(rewardsActive_);
    }

    function test_wiredModel_canUpdateRewardsWithoutFactoryAuth() public {
        LendingRewardsRateMockModel streamingModel = new LendingRewardsRateMockModel();
        streamingModel.setRate(10 * RATE_PRECISION);
        streamingModel.setStartTime(block.timestamp);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel)));

        // streaming mock is not factory auth — self-call must still work once wired
        vm.prank(address(streamingModel));
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel)));

        assertFalse(lendingFToken.isStaticRateModelActive());
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertTrue(rewardsActive_);
    }

    function test_wiredModel_canUnwireSelfWithoutFactoryAuth() public {
        vm.prank(admin);
        factory.setAuth(address(staticModel), false);

        vm.prank(address(staticModel));
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(0)));

        assertFalse(lendingFToken.isStaticRateModelActive());
        (, , IFluidLendingRewardsRateModel model_, , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertEq(address(model_), address(0));
        assertFalse(rewardsActive_);
    }

    function test_wiredModel_cannotInstallDifferentModel() public {
        FluidLendingStaticRateModel otherModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            OPEN_ENDED_DURATION
        );

        vm.prank(admin);
        factory.setAuth(address(staticModel), false);

        vm.prank(address(staticModel));
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(otherModel_)));
    }

    function test_newModel_cannotSelfWireWithoutFactoryAuth() public {
        FluidLendingStaticRateModel otherModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            OPEN_ENDED_DURATION
        );

        vm.prank(address(otherModel_));
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(otherModel_)));
    }

    function test_miswiredRateModel_governanceCanUnsetViaUpdateRewards() public {
        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(staticModel)));

        assertFalse(lendingFToken.isStaticRateModelActive());

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(0)));

        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive_);
    }

    function test_miswiredRateModel_governanceCanUnsetViaUpdateStaticRewards() public {
        LendingRewardsRateMockModel streamingModel_ = new LendingRewardsRateMockModel();
        streamingModel_.setRate(10 * RATE_PRECISION);
        streamingModel_.setStartTime(block.timestamp);

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(streamingModel_)));

        assertTrue(lendingFToken.isStaticRateModelActive());

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(0)));

        assertFalse(lendingFToken.isStaticRateModelActive());
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive_);
    }

    function test_recoverMiswiredRateModel_viaUpdateStaticRewards() public {
        vm.store(address(lendingFToken), bytes32(uint256(7)), bytes32(uint256(uint160(address(staticModel)))));

        uint256 slot8_ = uint256(vm.load(address(lendingFToken), bytes32(uint256(8))));
        slot8_ = (slot8_ & ~(uint256(1) << 184)) | (uint256(1) << 176);
        vm.store(address(lendingFToken), bytes32(uint256(8)), bytes32(slot8_));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(staticModel)));

        vm.prank(bob);
        lendingFToken.deposit(DEFAULT_AMOUNT, bob);
        assertGt(lendingFToken.balanceOf(bob), 0);
    }

    function test_recoverMiswiredRateModel_viaUpdateRewardsZero() public {
        LendingRewardsRateMockModel streamingModel_ = new LendingRewardsRateMockModel();
        streamingModel_.setRate(10 * RATE_PRECISION);
        streamingModel_.setStartTime(block.timestamp);

        vm.store(address(lendingFToken), bytes32(uint256(7)), bytes32(uint256(uint160(address(streamingModel_)))));
        uint256 slot8_ = uint256(vm.load(address(lendingFToken), bytes32(uint256(8))));
        slot8_ = (slot8_ | (uint256(1) << 184)) | (uint256(1) << 176);
        vm.store(address(lendingFToken), bytes32(uint256(8)), bytes32(slot8_));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(0)));

        vm.prank(bob);
        lendingFToken.deposit(DEFAULT_AMOUNT, bob);
        assertGt(lendingFToken.balanceOf(bob), 0);
    }

    function test_staticModelRate_endsAndDisablesRewardsActive() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + SHORT_DURATION - 1);
        lendingFToken.updateRates();
        (, , , , , bool rewardsActiveBefore_, , , ) = lendingFToken.getData();
        assertTrue(rewardsActiveBefore_);

        vm.warp(block.timestamp + 2);
        lendingFToken.updateRates();
        (, , , , , bool rewardsActiveAfter_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActiveAfter_, "ended static rate should disable _rewardsActive like streaming");
        assertTrue(lendingFToken.isStaticRateModelActive(), "static flag stays until model is unwired");
    }

    function test_setStaticRateAfterEndReenablesRewards() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        vm.warp(block.timestamp + SHORT_DURATION + 1);
        lendingFToken.updateRates();
        (, , , , , bool rewardsActiveEnded_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActiveEnded_);

        vm.prank(admin);
        shortModel_.setStaticRate(int256(STATIC_TARGET_RATE), OPEN_ENDED_DURATION);
        (, , , , , bool rewardsActiveRestarted_, , , ) = lendingFToken.getData();
        assertTrue(rewardsActiveRestarted_, "setStaticRate -> updateStaticRewards should re-enable rewards");
    }

    function test_stopStaticRate_settlesViaUpdateRates() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();
        vm.warp(block.timestamp + 7 days);

        vm.prank(admin);
        shortModel_.stopStaticRate();

        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();
        assertGt(tokenAfter_, tokenBefore_, "stop should settle accrual via updateRates");
        (int256 rate_, bool ended_, , ) = shortModel_.getRateV2(0);
        assertEq(rate_, int256(STATIC_TARGET_RATE), "rate stays the actual rate when ended (for exact tail accrual)");
        assertTrue(ended_);
    }

    function test_rebalance_noOpWhenBalanced() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        (, , , , , , uint256 liquidityBalance_, , ) = lendingFToken.getData();
        assertEq(liquidityBalance_, lendingFToken.totalAssets());

        vm.prank(admin);
        uint256 moved_ = lendingFToken.rebalance();
        assertEq(moved_, 0);
    }

    function test_rebalance_revertNotRebalancer() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__NotRebalancer));
        vm.prank(alice);
        lendingFToken.rebalance();
    }

    function test_staticModelRateEnded_compoundsLiquidityYieldWithoutPoke() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        _bootstrapLiquidityYield();
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + SHORT_DURATION + 1);

        uint256 tokenAtEnd_;
        (, , , , , , , , tokenAtEnd_) = lendingFToken.getData();

        vm.warp(block.timestamp + 365 days);

        uint256 tokenAfterDeadWindow_;
        (, , , , , , , , tokenAfterDeadWindow_) = lendingFToken.getData();

        assertGt(
            tokenAfterDeadWindow_,
            tokenAtEnd_,
            "liquidity yield should accrue after static end even before updateRates poke"
        );
        assertGt(_aprOverYear(tokenAtEnd_, tokenAfterDeadWindow_), 0);
    }

    function test_staticModelRateEnded_accruesExactlyToEndTime() public {
        // no liquidity yield bootstrapped -> token exchange price should move only via the static rate.
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        (, , , uint256 endTime_) = shortModel_.getRateV2(0);

        // warp far beyond the program end without any interaction in between
        vm.warp(block.timestamp + SHORT_DURATION + 365 days);
        lendingFToken.updateRates();

        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();

        // static rate must have accrued exactly for [lastUpdate, endTime], not 0 and not until block.timestamp
        uint256 expectedReturn_ = (STATIC_TARGET_RATE * (endTime_ - lastUpdate_)) / 365 days; // 1e14 = 100% scale
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * expectedReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "static tail must accrue exactly until endTime");

        // after settlement, no further accrual (rewards cleared, no liquidity yield)
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive_, "rewardsActive should clear on first settle after end");
        vm.warp(block.timestamp + 365 days);
        uint256 tokenLater_;
        (, , , , , , , , tokenLater_) = lendingFToken.getData();
        assertEq(tokenLater_, tokenAfter_, "no accrual after tail settled");
    }

    function test_staticOffsetEnded_fullLiquidityPlusOffsetUntilEndTime() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        _bootstrapLiquidityYield();
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        uint256 liquidityBefore_;
        (, , , , , , , liquidityBefore_, tokenBefore_) = lendingFToken.getData();

        (, , , uint256 endTime_) = shortModel_.getRateV2(0);

        // warp beyond the program end: offset until endTime + full-window Liquidity yield (no pro-rate)
        vm.warp(block.timestamp + SHORT_DURATION + 60 days);

        uint256 tokenAfter_;
        uint256 liquidityAfter_;
        (, , , , , , , liquidityAfter_, tokenAfter_) = lendingFToken.getData();

        uint256 offsetReturn_ = (STATIC_TARGET_RATE * (endTime_ - lastUpdate_)) / 365 days; // 1e14 = 100% scale
        uint256 liquidityReturn_ = ((liquidityAfter_ - liquidityBefore_) * 1e14) / liquidityBefore_;
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * (offsetReturn_ + liquidityReturn_)) / 1e14);

        assertEq(tokenAfter_, expectedToken_, "offset until endTime + full Liquidity yield for the window");
        assertGt(liquidityReturn_, 0, "liquidity yield must be > 0");
        assertGt(offsetReturn_, 0, "static offset tail until endTime must be > 0");
    }

    function test_streamingRewardsEnded_accruesExactlyToEndTime() public {
        // switch to a real streaming rewards model with a short duration; no liquidity yield bootstrapped
        // -> token exchange price should move only via the rewards rate.
        FluidLendingRewardsRateModel streamingModel_ = new FluidLendingRewardsRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            1, // startTvl
            DEFAULT_AMOUNT / 100, // rewardAmount
            SHORT_DURATION,
            block.timestamp
        );
        vm.prank(admin);
        factory.setAuth(address(streamingModel_), true);
        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 lastUpdate_ = block.timestamp;
        uint256 tokenBefore_;
        (, , , , , , , , tokenBefore_) = lendingFToken.getData();

        // warp far beyond the program end without any interaction in between
        vm.warp(block.timestamp + SHORT_DURATION + 365 days);

        // sample the rate the fToken will use for settlement (computed with the old token exchange price)
        (int256 rate_, bool ended_, , uint256 endTime_) = streamingModel_.getRateV2(
            (tokenBefore_ * lendingFToken.totalSupply()) / 1e12
        );
        assertTrue(ended_);
        assertGt(rate_, int256(0), "getRateV2 must return the actual phase rate even when ended");

        lendingFToken.updateRates();

        uint256 tokenAfter_;
        (, , , , , , , , tokenAfter_) = lendingFToken.getData();

        // rewards must have accrued exactly for [lastUpdate, endTime], not 0 and not until block.timestamp
        uint256 expectedReturn_ = (uint256(rate_) * (endTime_ - lastUpdate_)) / 365 days; // 1e14 scale
        uint256 expectedToken_ = tokenBefore_ + ((tokenBefore_ * expectedReturn_) / 1e14);
        assertEq(tokenAfter_, expectedToken_, "streaming tail must accrue exactly until endTime");

        // legacy getRate keeps returning 0 when ended (old fToken behavior unchanged)
        (uint256 legacyRate_, bool legacyEnded_, ) = streamingModel_.getRate(DEFAULT_AMOUNT);
        assertEq(legacyRate_, 0, "legacy getRate returns 0 once ended");
        assertTrue(legacyEnded_);

        // after settlement, no further accrual (rewards cleared, no liquidity yield)
        (, , , , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertFalse(rewardsActive_, "rewardsActive should clear on first settle after end");
        vm.warp(block.timestamp + 365 days);
        uint256 tokenLater_;
        (, , , , , , , , tokenLater_) = lendingFToken.getData();
        assertEq(tokenLater_, tokenAfter_, "no accrual after tail settled");
    }

    function test_staticModelRateEnded_compoundsLiquidityYield() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        _bootstrapLiquidityYield();
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + SHORT_DURATION + 1);
        lendingFToken.updateRates();

        uint256 tokenBefore_;
        uint256 liquidityBefore_;
        (, , , , , , liquidityBefore_, , tokenBefore_) = lendingFToken.getData();

        vm.warp(block.timestamp + 365 days);
        lendingFToken.updateRates();

        uint256 tokenAfter_;
        uint256 liquidityAfter_;
        (, , , , , , liquidityAfter_, , tokenAfter_) = lendingFToken.getData();

        assertGt(tokenAfter_, tokenBefore_, "liquidity yield should compound after static program ends");
        assertGt(liquidityAfter_, liquidityBefore_);
        assertGt(_aprOverYear(tokenBefore_, tokenAfter_), 0);
    }
}

contract fTokenStaticRateResolverTest is fTokenStaticRateTestBase {
    FluidLendingResolver lendingResolver;

    function setUp() public override {
        super.setUp();
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(liquidityProxy);
        lendingResolver = new FluidLendingResolver(
            IFluidLendingFactory(address(factory)),
            IFluidLiquidityResolver(address(liquidityResolver))
        );
    }

    function test_resolver_staticModelRateCompatWithStreamingFormula() public {
        _bootstrapLiquidityYield();

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        (, FluidLiquidityResolverStructs.OverallTokenData memory overallTokenData_) = IFluidLiquidityResolver(
            address(lendingResolver.LIQUIDITY_RESOLVER())
        ).getUserSupplyData(address(lendingFToken), address(underlying));
        assertGt(overallTokenData_.supplyRate, 0, "liquidity layer should have non-zero supply rate");

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (
            ,
            uint256 relativeModelRate_,
            int256 staticModelRate_,
            bool isStaticRate_,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(isStaticRate_);
        assertTrue(rewardsActive_);
        assertEq(relativeModelRate_, 0);
        assertEq(staticModelRate_, int256(STATIC_TARGET_RATE_RESOLVER));
        assertEq(details.relativeModelRate, 0);
        assertEq(details.staticModelRate, int256(STATIC_TARGET_RATE_RESOLVER));
        assertTrue(details.isStaticRate);
        assertTrue(details.rewardsActive);
        assertEq(liquidityRate_, overallTokenData_.supplyRate);
        assertEq(details.liquidityRate, overallTokenData_.supplyRate);
        // totalRate = liquidity + signed static offset
        assertEq(totalRate_, liquidityRate_ + STATIC_TARGET_RATE_RESOLVER);
        assertEq(details.totalRate, details.liquidityRate + STATIC_TARGET_RATE_RESOLVER);
    }

    function test_resolver_staticOffsetStillAdditiveWhenBelowLiquidityRate() public {
        _bootstrapLiquidityYield();

        FluidLiquidityResolverStructs.OverallTokenData memory overallTokenData_ = IFluidLiquidityResolver(
            address(lendingResolver.LIQUIDITY_RESOLVER())
        ).getOverallTokenData(address(underlying));
        assertGt(overallTokenData_.supplyRate, 0, "need non-zero liquidity supply rate");

        uint256 lowStaticRate_ = (overallTokenData_.supplyRate * 1e10) / 2;
        FluidLendingStaticRateModel lowModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(lowStaticRate_),
            OPEN_ENDED_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(lowModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(lowModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        (, FluidLiquidityResolverStructs.OverallTokenData memory overallAfterDeposit_) = IFluidLiquidityResolver(
            address(lendingResolver.LIQUIDITY_RESOLVER())
        ).getUserSupplyData(address(lendingFToken), address(underlying));

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (
            ,
            uint256 relativeModelRate_,
            int256 staticModelRate_,
            ,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(rewardsActive_);
        assertEq(relativeModelRate_, 0);
        assertEq(staticModelRate_, int256(lowStaticRate_ / 1e10));
        assertEq(details.relativeModelRate, 0);
        assertEq(details.staticModelRate, int256(lowStaticRate_ / 1e10));
        assertTrue(details.rewardsActive);
        assertEq(liquidityRate_, overallAfterDeposit_.supplyRate);
        assertEq(details.liquidityRate, overallAfterDeposit_.supplyRate);
        // holder APR = liquidity + signed offset (offset here is positive but below liquidity rate)
        assertEq(totalRate_, liquidityRate_ + uint256(staticModelRate_));
        assertEq(details.totalRate, details.liquidityRate + uint256(details.staticModelRate));
        assertGt(details.liquidityRate, uint256(staticModelRate_), "liquidity APR exceeds configured offset");
    }

    function test_resolver_totalRateFloorsAtZeroWhenOffsetExceedsLiquidity() public {
        _bootstrapLiquidityYield();

        FluidLiquidityResolverStructs.OverallTokenData memory overallTokenData_ = IFluidLiquidityResolver(
            address(lendingResolver.LIQUIDITY_RESOLVER())
        ).getOverallTokenData(address(underlying));
        assertGt(overallTokenData_.supplyRate, 0, "need non-zero liquidity supply rate");

        // offset more negative than liquidity APR → totalRate floored at 0
        int256 bigNegOffset_ = -int256(overallTokenData_.supplyRate * 1e10) - int256(RATE_PRECISION);
        FluidLendingStaticRateModel negModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            bigNegOffset_,
            OPEN_ENDED_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(negModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(negModel_)));

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        (
            ,
            ,
            int256 staticModelRate_,
            ,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(rewardsActive_);
        assertLt(staticModelRate_, 0);
        assertLt(int256(liquidityRate_) + staticModelRate_, 0);
        assertEq(totalRate_, 0, "resolver totalRate must floor at 0");
    }

    function test_resolver_staticModelRateEndedRestoresLiquiditySupplyRate() public {
        FluidLendingStaticRateModel shortModel_ = new FluidLendingStaticRateModel(
            admin,
            address(lendingFToken),
            address(0),
            address(0),
            int256(STATIC_TARGET_RATE),
            SHORT_DURATION
        );
        vm.prank(admin);
        factory.setAuth(address(shortModel_), true);
        vm.prank(admin);
        lendingFToken.updateStaticRewards(IFluidLendingStaticRateModel(address(shortModel_)));

        _bootstrapLiquidityYield();
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + SHORT_DURATION + 1);
        lendingFToken.updateRates();

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (
            ,
            uint256 relativeModelRate_,
            int256 staticModelRate_,
            bool isStaticRate_,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(isStaticRate_, "static model flag stays until unwired");
        assertFalse(rewardsActive_, "program ended - not currently accruing");
        assertFalse(details.rewardsActive);
        assertEq(relativeModelRate_, 0);
        assertEq(staticModelRate_, int256(0));
        assertEq(liquidityRate_, details.liquidityRate);
        assertEq(totalRate_, details.totalRate);
        assertEq(details.totalRate, details.liquidityRate);
        assertGt(details.liquidityRate, 0, "liquidity supplyRate returns after static program ends");
    }

    function test_resolver_stopStaticRate_keepsWiredShowsInactive() public {
        _bootstrapLiquidityYield();
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        FluidLendingResolverStructs.FTokenDetails memory beforeStop = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        assertTrue(beforeStop.isStaticRate);
        assertTrue(beforeStop.rewardsActive);

        // stopStaticRate shortens duration to (now - start - 1); need now > start so ended_ becomes true
        vm.warp(block.timestamp + 7 days);

        vm.prank(admin);
        staticModel.stopStaticRate();

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (, , int256 staticModelRate_, bool isStaticRate_, , uint256 totalRate_, bool rewardsActive_) = lendingResolver
            .getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(isStaticRate_, "model stays wired after stop");
        assertTrue(details.isStaticRate);
        assertFalse(rewardsActive_, "stop clears currently-accruing flag");
        assertFalse(details.rewardsActive);
        assertEq(staticModelRate_, int256(0));
        assertEq(details.staticModelRate, int256(0));
        assertEq(totalRate_, details.liquidityRate);
        assertEq(details.totalRate, details.liquidityRate);
    }

    function test_resolver_staticModelRateModelConfig() public {
        (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            int256 maxRateOrStaticRate_,
            uint256 rewardAmount_,
            address configurator_
        ) = lendingResolver.getFTokenRewardsRateModelConfig(IFToken(address(lendingFToken)));

        assertEq(duration_, OPEN_ENDED_DURATION);
        assertEq(
            maxRateOrStaticRate_,
            int256(STATIC_TARGET_RATE),
            "static path returns signed offset in maxRateOrStaticRate_"
        );
        assertEq(configurator_, admin);
        assertEq(startTvl_, 0);
        assertEq(rewardAmount_, 0);
        assertEq(endTime_, startTime_ + OPEN_ENDED_DURATION);

        (, , , , uint256 staticMaxRate_) = staticModel.getStaticConfig();
        assertEq(staticMaxRate_, 50 * 1e12, "getStaticConfig.maxRate is the 50% ceiling");
    }

    function test_resolver_negativeStaticOffset() public {
        _bootstrapLiquidityYield();
        vm.prank(admin);
        staticModel.setStaticRate(-int256(2 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (
            ,
            ,
            int256 staticModelRate_,
            ,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertTrue(rewardsActive_);
        assertEq(staticModelRate_, -int256((2 * RATE_PRECISION) / 1e10));
        assertEq(details.staticModelRate, -int256(200)); // 2% at Liquidity scale

        int256 expectedTotal_ = int256(liquidityRate_) + staticModelRate_;
        assertEq(totalRate_, expectedTotal_ > 0 ? uint256(expectedTotal_) : 0);
        assertEq(details.totalRate, totalRate_);

        (, , , , int256 maxRateOrStaticRate_, , ) = lendingResolver.getFTokenRewardsRateModelConfig(
            IFToken(address(lendingFToken))
        );
        assertEq(maxRateOrStaticRate_, -int256(2 * RATE_PRECISION));
    }

    function test_resolver_staticRebalanceDifference() public {
        _bootstrapLiquidityYield();
        // negative offset → Liquidity inventory ahead of share liabilities
        vm.prank(admin);
        staticModel.setStaticRate(-int256(2 * RATE_PRECISION), OPEN_ENDED_DURATION);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        vm.warp(block.timestamp + 365 days);

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        assertGt(details.rebalanceDifference, 0, "liquidity balance should exceed totalAssets with negative offset");
    }

    function test_resolver_streamingFToken_unchangedShape() public {
        _bootstrapLiquidityYield();

        LendingRewardsRateMockModel streamingModel = new LendingRewardsRateMockModel();
        streamingModel.setRate(10 * RATE_PRECISION);
        streamingModel.setStartTime(block.timestamp);

        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(streamingModel)));

        FluidLendingResolverStructs.FTokenDetails memory details = lendingResolver.getFTokenDetails(
            IFToken(address(lendingFToken))
        );
        (
            ,
            uint256 relativeModelRate_,
            int256 staticModelRate_,
            bool isStaticRate_,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        ) = lendingResolver.getFTokenRewards(IFToken(address(lendingFToken)));

        assertFalse(isStaticRate_);
        assertTrue(rewardsActive_);
        assertTrue(details.rewardsActive);
        assertEq(staticModelRate_, int256(0));
        assertEq(relativeModelRate_, details.relativeModelRate);
        assertEq(liquidityRate_, details.liquidityRate);
        assertEq(totalRate_, details.totalRate);
        assertEq(details.totalRate, details.liquidityRate + details.relativeModelRate);
        assertGt(details.liquidityRate, 0, "liquidity leg in Liquidity resolver scale");
        assertGt(details.totalRate, details.liquidityRate, "total includes streaming bonus");
    }
}
