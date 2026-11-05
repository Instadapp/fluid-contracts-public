// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";

/// @dev Minimal fToken stand-in for reward-model callbacks.
contract MockFToken {
    function updateRates() external pure returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_) {
        return (0, 0);
    }

    function updateRewards(IFluidLendingRewardsRateModel /* rewardsRateModel_ */) external pure {}
}

/// @dev Regression tests for same-block reward-stop finality.
contract FluidLendingRewardsRateModelStopRewardsTest is Test {
    MockFToken internal fToken;
    address internal configurator = address(this);

    uint256 internal constant START_TVL = 1000e6;
    uint256 internal constant REWARD_AMOUNT = 1e18;
    uint256 internal constant DURATION = 30 days;

    function setUp() public {
        fToken = new MockFToken();
    }

    function _deploy() internal returns (FluidLendingRewardsRateModel model) {
        model = new FluidLendingRewardsRateModel(
            configurator,
            address(fToken),
            address(0),
            address(0),
            START_TVL,
            REWARD_AMOUNT,
            DURATION,
            block.timestamp
        );
    }

    // Exercises the already-started branch, unchanged by the fix; also passes pre-fix.
    function test_stopRewards_IsImmediateForSameBlockReaders() public {
        FluidLendingRewardsRateModel model = _deploy();

        // advance a tiny amount so we're solidly inside the rewards window
        skip(1 days);

        (uint256 preRate, bool preEnded, ) = model.getRate(START_TVL * 10);
        assertGt(preRate, 0, "pre-stop: rate must be non-zero");
        assertFalse(preEnded, "pre-stop: must not be ended");

        model.stopRewards();

        (uint256 postRate, bool postEnded, ) = model.getRate(START_TVL * 10);
        assertEq(postRate, 0, "post-stop: same-block rate must be 0");
        assertTrue(postEnded, "post-stop: same-block must report ended");
    }

    /// @dev The stop window may lose at most 1 second of accrual.
    // Also exercises the already-started branch, unchanged by the fix; passes pre-fix too.
    function test_stopRewards_DurationLossBoundedByOneSecond() public {
        FluidLendingRewardsRateModel model = _deploy();

        skip(5 days);

        uint256 startTimeBefore = block.timestamp - 5 days;
        model.stopRewards();

        (uint256 duration, uint256 startTime, uint256 endTime, , , , ) = model.getConfig();

        assertEq(startTime, startTimeBefore, "start time should not change");
        // endTime must be strictly less than block.timestamp (to give same-block finality)
        // AND at least `block.timestamp - 1` (not more than 1 second lost).
        assertLt(endTime, block.timestamp, "endTime must be strictly before now for same-block finality");
        assertGe(
            endTime,
            block.timestamp - 1,
            "endTime must be at least now-1 (no more than 1 second of accrual lost)"
        );
        // duration = endTime - startTime
        assertEq(duration, endTime - startTime);
    }

    /// @dev Zero-age / future-start stops cancel immediately.
    function test_stopRewards_ZeroAgeWindow_CancelsImmediately() public {
        skip(10);
        FluidLendingRewardsRateModel model = _deploy();

        // no time advance — start block == current block
        model.stopRewards();

        (uint256 duration, , uint256 endTime, , , , ) = model.getConfig();
        assertEq(duration, 0, "zero-age: duration must clamp to 0");
        assertLt(endTime, block.timestamp, "zero-age: endTime moves before now");

        (uint256 rate, bool ended, ) = model.getRate(START_TVL * 10);
        assertEq(rate, 0);
        assertTrue(ended);

        model.startRewards(REWARD_AMOUNT, DURATION, block.timestamp);
        (, uint256 replacementStartTime, , , , , ) = model.getConfig();
        assertEq(replacementStartTime, block.timestamp, "replacement can start immediately");
    }
}
