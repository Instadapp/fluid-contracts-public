// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";

/// @dev Minimal fToken stand-in for reward-model callbacks.
contract MockFToken {
    function updateRates() external pure returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_) {
        return (0, 0);
    }

    function updateRewards(IFluidLendingRewardsRateModel /* rewardsRateModel_ */) external pure {}
}

/// @title Regression tests for the `_startTime + _duration` uint40 sum bound, checked separately from the
///        individual `duration_`/`startTime_` uint40 bounds at every entry point that feeds it.
contract FluidLendingRewardsRateModelTimeBoundsTest is Test {
    MockFToken internal fToken;
    address internal configurator = address(this);

    uint256 internal constant START_TVL = 1000e6;
    uint256 internal constant REWARD_AMOUNT = 1e18;
    uint256 internal constant UINT40_MAX = type(uint40).max;

    function setUp() public {
        fToken = new MockFToken();
    }

    function _deployModel(uint256 duration_, uint256 startTime_) internal returns (FluidLendingRewardsRateModel) {
        return
            new FluidLendingRewardsRateModel(
                configurator,
                address(fToken),
                address(0),
                address(0),
                START_TVL,
                REWARD_AMOUNT,
                duration_,
                startTime_
            );
    }

    // --------------------------------------------------------------------
    // Constructor
    // --------------------------------------------------------------------

    function test_constructor_AcceptsStartTimePlusDurationAtUint40Max() public {
        uint256 startTime_ = block.timestamp;
        uint256 duration_ = UINT40_MAX - startTime_;

        FluidLendingRewardsRateModel model = _deployModel(duration_, startTime_);

        (, , uint256 endTime, , , , ) = model.getConfig();
        assertEq(endTime, UINT40_MAX);

        vm.warp(startTime_ + 1);
        model.stopRewards();
    }

    function test_constructor_RevertsWhenStartTimePlusDurationExceedsUint40Max() public {
        uint256 startTime_ = block.timestamp;
        uint256 duration_ = UINT40_MAX - startTime_ + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        _deployModel(duration_, startTime_);
    }

    // --------------------------------------------------------------------
    // startRewards
    // --------------------------------------------------------------------

    function test_startRewards_AcceptsStartTimePlusDurationAtUint40Max() public {
        FluidLendingRewardsRateModel model = _deployModel(7 days, block.timestamp);
        skip(365 days); // past the initial window, so `startRewards` is callable again

        uint256 startTime_ = block.timestamp;
        uint256 duration_ = UINT40_MAX - startTime_;
        model.startRewards(REWARD_AMOUNT, duration_, startTime_);

        (, , uint256 endTime, , , , ) = model.getConfig();
        assertEq(endTime, UINT40_MAX);

        vm.warp(startTime_ + 1);
        model.stopRewards();
    }

    function test_startRewards_RevertsWhenStartTimePlusDurationExceedsUint40Max() public {
        FluidLendingRewardsRateModel model = _deployModel(7 days, block.timestamp);
        skip(365 days);

        uint256 startTime_ = block.timestamp;
        uint256 duration_ = UINT40_MAX - startTime_ + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        model.startRewards(REWARD_AMOUNT, duration_, startTime_);
    }

    // --------------------------------------------------------------------
    // queueNextRewards — activation time is the *current* window's end, so the bound is checked against
    // that, not against `block.timestamp` (these calls happen while current rewards are still active).
    // --------------------------------------------------------------------

    function test_queueNextRewards_AcceptsActivationSumAtUint40Max() public {
        FluidLendingRewardsRateModel model = _deployModel(7 days, block.timestamp);

        (, , uint256 currentEnd_, , , , ) = model.getConfig();
        uint256 duration_ = UINT40_MAX - currentEnd_;
        model.queueNextRewards(REWARD_AMOUNT, duration_);

        vm.warp(currentEnd_ + 1);
        model.transitionToNextRewards();

        (, , uint256 endTime, , , , ) = model.getConfig();
        assertEq(endTime, UINT40_MAX);
        model.stopRewards();
    }

    function test_queueNextRewards_RevertsWhenActivationSumExceedsUint40Max() public {
        FluidLendingRewardsRateModel model = _deployModel(7 days, block.timestamp);

        (, , uint256 currentEnd_, , , , ) = model.getConfig();
        uint256 duration_ = UINT40_MAX - currentEnd_ + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        model.queueNextRewards(REWARD_AMOUNT, duration_);
    }
}
