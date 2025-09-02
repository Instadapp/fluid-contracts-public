// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IFTokenAdmin, IFToken } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { IFluidLendingFactoryAdmin } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

// To test run: forge test --match-path test/foundry/lending/lendingRewardsRateModel.t.sol -vvv
contract FluidLendingRewardsRateModelTest is Test {
    FluidLendingRewardsRateModel public model;
    IFTokenAdmin public fToken = IFTokenAdmin(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33);
    IFluidLendingFactoryAdmin public lendingFactory =
        IFluidLendingFactoryAdmin(0x54B91A0D94cb471F37f949c60F7Fa7935b551D03);

    address public configurator;

    uint256 constant START_TVL = 1000e6;
    uint256 constant REWARD_AMOUNT = 796533872098; // = 20% rate according to current total tvl
    uint256 constant DURATION = 7 days;
    uint256 constant RATE_PRECISION = 1e12;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21680552);

        configurator = address(this);

        model = new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            REWARD_AMOUNT,
            DURATION,
            block.timestamp // start immediately
        );

        vm.prank(GOVERNANCE);
        fToken.updateRewards((model));

        vm.prank(GOVERNANCE);
        lendingFactory.setAuth(address(model), true);
    }

    function testConstructorRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        new FluidLendingRewardsRateModel(
            address(0),
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            REWARD_AMOUNT,
            DURATION,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        new FluidLendingRewardsRateModel(
            configurator,
            address(0),
            address(0),
            address(0),
            START_TVL,
            REWARD_AMOUNT,
            DURATION,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            0,
            REWARD_AMOUNT,
            DURATION,
            0
        );
    }

    function testGetConfig() public {
        (
            uint256 duration,
            uint256 startTime,
            uint256 endTime,
            uint256 startTvl,
            uint256 maxRate,
            uint256 rewardAmount,
            address initiator
        ) = model.getConfig();

        uint256 yearlyReward = (REWARD_AMOUNT * 365 days) / DURATION;

        assertEq(duration, DURATION);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + DURATION);
        assertEq(startTvl, START_TVL);
        assertEq(maxRate, 50 * RATE_PRECISION);
        assertEq(rewardAmount, (yearlyReward * DURATION) / 365 days);
        assertEq(initiator, configurator);
    }

    function testGetRate() public {
        // Test when TVL is below START_TVL
        (uint256 rate, bool ended, uint256 startTime) = model.getRate(START_TVL - 1);
        assertEq(rate, 0);
        assertEq(ended, false);
        assertEq(startTime, block.timestamp);

        // Test with valid TVL
        (rate, ended, startTime) = model.getRate(START_TVL * 2);
        assert(rate > 0);
        assertEq(ended, false);
        assertEq(startTime, block.timestamp);

        // Test after duration
        vm.warp(block.timestamp + DURATION + 1);
        (rate, ended, startTime) = model.getRate(START_TVL * 2);
        assertEq(rate, 0);
        assertEq(ended, true);
    }

    function testStopRewards() public {
        // Verify new rewards configuration
        (uint256 duration, uint256 startTime, uint256 endTime, , , uint256 rewardAmount, ) = model.getConfig();

        uint256 yearlyReward = (rewardAmount * 365 days) / duration;

        vm.warp(block.timestamp + 1 days);

        model.stopRewards();

        (uint256 duration_, , , , , uint256 rewardAmount_, ) = model.getConfig();

        uint256 yearlyReward_ = (rewardAmount_ * 365 days) / duration_;

        assertGt(yearlyReward, yearlyReward_);

        // Verify rewards are stopped
        (uint256 rate, , ) = model.getRate(START_TVL * 2);
        assertEq(rate, 0);

        // Cannot stop again
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__AlreadyStopped)
        );
        model.stopRewards();
    }

    function testQueueAndTransitionRewards() public {
        uint256 newRewardAmount = 200e6;
        uint256 newDuration = 14 days;

        model.queueNextRewards(newRewardAmount, newDuration);

        // Cannot queue again without canceling
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.LendingRewardsRateModel__NextRewardsQueued
            )
        );
        model.queueNextRewards(newRewardAmount, newDuration);

        // Cannot transition before current rewards end
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__NotEnded)
        );
        model.transitionToNextRewards();

        // Warp to end of current rewards
        vm.warp(block.timestamp + DURATION + 1);

        // expect getRate to still return not ended
        (uint256 rate, bool ended, ) = model.getRate(START_TVL + 1);
        assertGt(rate, 0);
        assertEq(ended, false);

        model.transitionToNextRewards();

        // Verify new rewards are active
        (uint256 duration, uint256 startTime, uint256 endTime, , , uint256 rewardAmount, ) = model.getConfig();

        assertEq(duration, newDuration);
        assertEq(startTime + 1, block.timestamp);
        assertEq(endTime + 1, block.timestamp + newDuration);
    }

    function testCancelQueuedRewards() public {
        model.queueNextRewards(200e6, 14 days);

        model.cancelQueuedRewards();

        // Cannot cancel when no rewards are queued
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.LendingRewardsRateModel__NoQueuedRewards
            )
        );
        model.cancelQueuedRewards();
    }

    function testStartRewards() public {
        vm.warp(block.timestamp + 1 days);

        // Stop current rewards
        model.stopRewards();

        uint256 newStartTime = block.timestamp + 1 days;
        uint256 newRewardAmount = 300e6;
        uint256 newDuration = 30 days;

        vm.prank(GOVERNANCE);
        lendingFactory.setAuth(address(model), false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        model.startRewards(newRewardAmount, newDuration, newStartTime);

        vm.prank(GOVERNANCE);
        lendingFactory.setAuth(address(model), true);

        model.startRewards(newRewardAmount, newDuration, newStartTime);

        // Verify new rewards configuration
        (uint256 duration, uint256 startTime, uint256 endTime, , , uint256 rewardAmount, ) = model.getConfig();

        assertEq(duration, newDuration);
        assertEq(startTime, newStartTime);
        assertEq(endTime, newStartTime + newDuration);
        assertEq(rewardAmount, newRewardAmount);
    }

    function testStartStopFToken() public {
        // Get initial fToken state
        (
            ,
            ,
            IFluidLendingRewardsRateModel rewardsModel,
            ,
            ,
            bool rewardsActive,
            ,
            uint256 liquidityExchangePriceBefore,
            uint256 tokenExchangePriceBefore
        ) = IFToken(address(fToken)).getData();

        // rewards should accrue at expected rate
        assertTrue(rewardsActive);
        // Fetch rewards rate from the rewards model
        (uint256 currentRate, , ) = rewardsModel.getRate(IFToken(address(fToken)).totalAssets());
        assertApproxEqAbs(currentRate, 20e12, 10);

        // Warp ahead and check rewards accrued
        vm.warp(block.timestamp + 1 days);

        // Get new fToken state after rewards have accrued
        uint256 liquidityExchangePriceAfter;
        uint256 tokenExchangePriceAfter;
        (, , rewardsModel, , , rewardsActive, , liquidityExchangePriceAfter, tokenExchangePriceAfter) = IFToken(
            address(fToken)
        ).getData();

        {
            // Calculate the increase in liquidityExchangePrice
            uint256 liquidityExchangePriceAPR = (((liquidityExchangePriceAfter - liquidityExchangePriceBefore) * 1e14) /
                liquidityExchangePriceBefore) * 365;

            uint256 tokenExchangePriceAPR = (((tokenExchangePriceAfter - tokenExchangePriceBefore) * 1e14) /
                tokenExchangePriceBefore) * 365;

            assertEq(liquidityExchangePriceBefore, 1086367831752);
            assertEq(liquidityExchangePriceAfter, 1086608496682);
            assertEq(liquidityExchangePriceAPR, 8085907634730);
            // Confirm the token exchange price has increased as expected
            assertApproxEqAbs(tokenExchangePriceAPR - liquidityExchangePriceAPR, currentRate, 1e6);
        }

        // Stop rewards
        model.stopRewards();

        // Confirm rewards stopped
        (, , rewardsModel, , , rewardsActive, , , ) = IFToken(address(fToken)).getData();
        assertFalse(rewardsActive);

        // Warp ahead and verify no additional rewards accrued
        (, , , , , , , liquidityExchangePriceBefore, tokenExchangePriceBefore) = IFToken(address(fToken)).getData();
        vm.warp(block.timestamp + 30 days);
        (, , , , , , , liquidityExchangePriceAfter, tokenExchangePriceAfter) = IFToken(address(fToken)).getData();
        {
            // Calculate the increase in liquidityExchangePrice
            uint256 liquidityExchangePriceAPR = (((liquidityExchangePriceAfter - liquidityExchangePriceBefore) * 1e14) /
                liquidityExchangePriceBefore) * 365;

            uint256 tokenExchangePriceAPR = (((tokenExchangePriceAfter - tokenExchangePriceBefore) * 1e14) /
                tokenExchangePriceBefore) * 365;

            assertApproxEqAbs(liquidityExchangePriceAPR, tokenExchangePriceAPR, 1e6);
        }

        // Start new rewards
        uint256 newStartTime = block.timestamp + 1 days;
        // Warp to start time
        vm.warp(newStartTime);

        uint256 newRewardAmount = (((IFToken(address(fToken)).totalAssets() / 20) * 7) / 365); // 5% rate
        uint256 newDuration = 7 days;

        model.startRewards(newRewardAmount, newDuration, newStartTime);

        // Get price before new rewards
        (, , rewardsModel, , , rewardsActive, , liquidityExchangePriceBefore, tokenExchangePriceBefore) = IFToken(
            address(fToken)
        ).getData();
        assertTrue(rewardsActive);
        (currentRate, , ) = rewardsModel.getRate(IFToken(address(fToken)).totalAssets());
        assertApproxEqAbs(currentRate, 5e12, 10);

        // Warp ahead half duration and check new rewards rate
        vm.warp(block.timestamp + 3.5 days);

        // Get new fToken state after new rewards have accrued
        (, , rewardsModel, , , rewardsActive, , liquidityExchangePriceAfter, tokenExchangePriceAfter) = IFToken(
            address(fToken)
        ).getData();

        // New rewards should accrue at expected rate
        assertTrue(rewardsActive);

        {
            // Calculate the increase in liquidityExchangePrice
            uint256 liquidityExchangePriceAPR = (((((liquidityExchangePriceAfter - liquidityExchangePriceBefore) *
                1e14) / liquidityExchangePriceBefore) * 10) / 35) * 365;

            uint256 tokenExchangePriceAPR = (((((tokenExchangePriceAfter - tokenExchangePriceBefore) * 1e14) /
                tokenExchangePriceBefore) * 10) / 35) * 365;

            // Confirm the token exchange price has increased as expected
            assertApproxEqAbs(tokenExchangePriceAPR - liquidityExchangePriceAPR, currentRate, 1e6);
        }
    }

    function testOnlyConfiguratorModifier() public {
        address nonConfigurator = address(0x123);
        vm.startPrank(nonConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__Unauthorized)
        );
        model.stopRewards();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__Unauthorized)
        );
        model.startRewards(100e6, 7 days, 0);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__Unauthorized)
        );
        model.queueNextRewards(100e6, 7 days);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__Unauthorized)
        );
        model.cancelQueuedRewards();

        vm.stopPrank();
    }
}
