//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";

import "../testERC20.sol";
import "../bytesLib.sol";
import { TestHelpers } from "../liquidity/liquidityTestHelpers.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";

import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

contract LendingRewardsRateModelTestBase is Test, TestHelpers {
    FluidLendingRewardsRateModel rateModel;

    uint256 constant RATE_PRECISION = 1e12;
    uint256 constant MAX_RATE = 50 * RATE_PRECISION; // 25%

    uint256 duration = 73 days;

    // define start time in 10 days
    uint256 startTime = block.timestamp + 10 days;
    // define end time 1 year
    uint256 endTime = startTime + duration;

    uint256 startTvl = 1e8;

    uint256 rewardAmount = 1 ether;

    address payable internal admin = payable(makeAddr("admin"));
    address payable internal alice = payable(makeAddr("alice"));

    function setUp() public virtual {
        // create rewards contract
        rateModel = new FluidLendingRewardsRateModel(
            duration,
            startTvl,
            rewardAmount,
            alice,
            IFluidLendingRewardsRateModel(address(0))
        );
    }
}

contract LendingRewardsRateModelTestsBeforeStarted is LendingRewardsRateModelTestBase {
    function test_getConfig() public {
        (
            uint256 actualDuration_,
            uint256 actualStartTime_,
            uint256 actualEndTime_,
            uint256 actualStartTvl_,
            uint256 actualMaxRate_,
            uint256 actualRewardAmount_,
            address actualInitiator_
        ) = rateModel.getConfig();

        assertEq(actualDuration_, duration);
        assertEq(actualStartTime_, 0);
        assertEq(actualEndTime_, 0);
        assertEq(actualStartTvl_, startTvl);
        assertEq(actualRewardAmount_, rewardAmount);
        assertEq(actualMaxRate_, MAX_RATE);
        assertEq(actualInitiator_, alice);
    }

    function test_Constructor_RevertIfDurationEqualsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        rateModel = new FluidLendingRewardsRateModel(
            0,
            startTvl,
            rewardAmount,
            alice,
            IFluidLendingRewardsRateModel(address(0))
        );
    }

    function test_Constructor_RevertIfStartTvlEqualsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        rateModel = new FluidLendingRewardsRateModel(
            duration,
            0,
            rewardAmount,
            alice,
            IFluidLendingRewardsRateModel(address(0))
        );
    }

    function test_Constructor_RevertIfRewardAmountEqualsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        rateModel = new FluidLendingRewardsRateModel(
            duration,
            startTvl,
            0,
            alice,
            IFluidLendingRewardsRateModel(address(0))
        );
    }

    function test_Constructor_RevertIfInitiatorAndPreviousModelEqualsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        rateModel = new FluidLendingRewardsRateModel(
            duration,
            startTvl,
            rewardAmount,
            address(0),
            IFluidLendingRewardsRateModel(address(0))
        );
    }

    function test_Constructor_WithPreviousRewardsModel() public {
        vm.warp(startTime);
        vm.prank(alice);
        rateModel.start();
        FluidLendingRewardsRateModel newRateModel = new FluidLendingRewardsRateModel(
            duration,
            startTvl,
            rewardAmount,
            address(0),
            IFluidLendingRewardsRateModel(address(rateModel))
        );
    }

    function test_getRate_BeforeStarted() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(10 ether);
        assertEq(rate, 0);
        assertFalse(ended);
        assertEq(returnStartTime, 0);
    }

    function test_start_RevertUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.LendingRewardsRateModel__NotTheInitiator
            )
        );
        vm.prank(admin);
        rateModel.start();
    }
}

contract LendingRewardsRateModelTestsWhenStarted is LendingRewardsRateModelTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(startTime);
        vm.prank(alice);
        rateModel.start();
    }

    function test_getConfig() public {
        (
            uint256 actualDuration_,
            uint256 actualStartTime_,
            uint256 actualEndTime_,
            uint256 actualStartTvl_,
            uint256 actualMaxRate_,
            uint256 actualRewardAmount_,
            address actualInitiator_
        ) = rateModel.getConfig();

        assertEq(actualDuration_, duration);
        assertEq(actualStartTime_, startTime);
        assertEq(actualEndTime_, endTime);
        assertEq(actualStartTvl_, startTvl);
        assertEq(actualRewardAmount_, rewardAmount);
        assertEq(actualMaxRate_, MAX_RATE);
        assertEq(actualInitiator_, alice);
    }

    function test_start_RevertAlreadyStarted() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__AlreadyStarted)
        );
        vm.prank(alice);
        rateModel.start();
    }

    function test_getRate_AfterEndTime() public {
        // Simulate the passage of time beyond the END_TIME
        vm.warp(endTime + 1);
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(10 ether);
        assertEq(rate, 0);
        assertTrue(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_WithinTime() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(10 ether);
        assertFalse(rate == 0);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_AssetAmountBelowStartTvl() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(startTvl - 1);
        assertEq(rate, 0);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_AboveStartTvl() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(25 ether);
        // should be 20% (1 ether rewards in 20% of a year so 5 ether yearly. so at 25 ether it is 20%)
        assertEq(rate, 20e12);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_At10Percent() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(50 ether);
        // should be 10% (1 ether rewards in 20% of a year so 5 ether yearly. so at 50 ether it is 10%)
        assertEq(rate, 10e12);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_At0Point6Percent() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(833333333333333333333);
        // should be 0.6% (1 ether rewards in 20% of a year so 5 ether yearly. so at 833.333333333333333333 ether it is 0.6%)
        assertEq(rate, 6e11);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_AboveMaxRate() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(5 ether);
        assertEq(rate, MAX_RATE); // would be 100% -> should be capped at 50%
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }
}

contract LendingRewardsRateModelTestsWithPreviousModel is LendingRewardsRateModelTestBase {
    address previousModel;

    function setUp() public virtual override {
        super.setUp();

        vm.warp(startTime);
        vm.prank(alice);
        rateModel.start();

        vm.warp(endTime - 1);

        previousModel = address(rateModel);

        rateModel = new FluidLendingRewardsRateModel(
            duration,
            startTvl,
            rewardAmount * 2,
            address(alice),
            IFluidLendingRewardsRateModel(address(rateModel))
        );
    }

    function test_PREVIOUS_MODEL() public {
        assertEq(previousModel, address(rateModel.PREVIOUS_MODEL()));
    }

    function test_getConfig() public {
        (
            uint256 actualDuration_,
            uint256 actualStartTime_,
            uint256 actualEndTime_,
            uint256 actualStartTvl_,
            uint256 actualMaxRate_,
            uint256 actualRewardAmount_,
            address actualInitiator_
        ) = rateModel.getConfig();

        assertEq(actualDuration_, duration);
        assertEq(actualStartTime_, endTime); // start time of new model is end time of previous model
        assertEq(actualEndTime_, endTime + duration);
        assertEq(actualStartTvl_, startTvl);
        assertEq(actualRewardAmount_, rewardAmount * 2);
        assertEq(actualMaxRate_, MAX_RATE);
        assertEq(actualInitiator_, alice);
    }

    function test_getRate_BeforePreviousModelEnd() public {
        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(25 ether);
        // should be 20% (1 ether rewards in 20% of a year so 5 ether yearly. so at 25 ether it is 20%)
        assertEq(rate, 20e12);
        assertFalse(ended);
        assertEq(startTime, returnStartTime);
    }

    function test_getRate_AfterPreviousModelEnd() public {
        vm.warp(endTime + 1);

        (uint256 rate, bool ended, uint256 returnStartTime) = rateModel.getRate(25 ether);
        // should be 40% (2 ether rewards in 20% of a year so 10 ether yearly. so at 25 ether it is 10/25 = 2/5 = 40%)
        assertEq(rate, 20e12 * 2); // rate should be 5x, as reward amount is 5x
        assertFalse(ended);
        uint256 expectedStartTime = endTime; // previous model end time is new model start time
        assertEq(expectedStartTime, returnStartTime);
    }

    function test_start_shouldRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__AlreadyStarted)
        );
        vm.prank(alice);
        rateModel.start();
    }
}
