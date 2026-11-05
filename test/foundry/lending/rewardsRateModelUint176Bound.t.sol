// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";

/// @dev Minimal fToken stand-in for reward-model callbacks.
contract MockFToken {
    function updateRates() external pure returns (uint256) {
        return 0;
    }

    function updateRewards(IFluidLendingRewardsRateModel /* rewardsRateModel_ */) external pure {}
}

/// @dev Regression tests for reward storage bounds.
contract FluidLendingRewardsRateModelUint176BoundTest is Test {
    MockFToken internal fToken;
    address internal configurator = address(this);

    uint256 internal constant START_TVL = 1000e6;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant UINT176_MAX = type(uint176).max;
    uint256 internal constant MAX_REWARD_AMOUNT = UINT176_MAX / SECONDS_PER_YEAR;

    function setUp() public {
        fToken = new MockFToken();
    }

    // --------------------------------------------------------------------
    // Constructor
    // --------------------------------------------------------------------

    function test_constructor_RevertsOnYearlyRewardOverflow() public {
        uint256 rewardAmount = UINT176_MAX + 1; // yearly == rewardAmount when duration == SECONDS_PER_YEAR
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            rewardAmount,
            SECONDS_PER_YEAR,
            0
        );
    }

    function test_constructor_RevertsOnShortDurationBlowup() public {
        uint256 rewardAmount = UINT176_MAX / 2;
        uint256 duration = 1; // yearly ≈ rewardAmount * SECONDS_PER_YEAR ≫ uint176.max
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            rewardAmount,
            duration,
            0
        );
    }

    function test_constructor_AcceptsMaxRewardAmountBoundary() public {
        FluidLendingRewardsRateModel model = new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            MAX_REWARD_AMOUNT,
            SECONDS_PER_YEAR,
            block.timestamp
        );
        assertEq(model.FTOKEN(), address(fToken));

        (uint256 rate, bool ended, ) = model.getRate(START_TVL * 10);
        assertFalse(ended);
        assertGt(rate, 0);
    }

    // --------------------------------------------------------------------
    // startRewards
    // --------------------------------------------------------------------

    function _freshModel() internal returns (FluidLendingRewardsRateModel model) {
        model = new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            1e18,
            7 days,
            block.timestamp
        );
    }

    function test_startRewards_RevertsOnOverflow() public {
        FluidLendingRewardsRateModel model = _freshModel();
        // Jump well past current rewards end so `startRewards` is allowed.
        skip(365 days);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        model.startRewards(UINT176_MAX, 1, block.timestamp); // yearly ≫ uint176.max
    }

    // --------------------------------------------------------------------
    // queueNextRewards
    // --------------------------------------------------------------------

    function test_queueNextRewards_RevertsOnRewardAmountOverflow() public {
        FluidLendingRewardsRateModel model = _freshModel();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        model.queueNextRewards(UINT176_MAX + 1, 7 days);
    }

    function test_queueNextRewards_RevertsOnYearlyOverflow() public {
        FluidLendingRewardsRateModel model = _freshModel();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingRewardsRateModel__InvalidParams)
        );
        model.queueNextRewards(UINT176_MAX, 1);
    }
}
