// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel } from "../interfaces/iLendingRewardsRateModel.sol";
import { IFTokenAdmin } from "../interfaces/iFToken.sol";

import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

abstract contract Constants {
    /// @dev precision decimals for rewards rate
    uint256 internal constant RATE_PRECISION = 1e12;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @dev maximum rewards rate is 50%. no config higher than this should be possible.
    uint256 internal constant MAX_RATE = 50 * RATE_PRECISION; // 1e12 = 1%, this is 50%.

    /// @dev tvl below which rewards rate is 0
    uint256 internal immutable START_TVL;

    /// @dev address which has access to manage rewards amounts, start time etc.
    address internal immutable CONFIGURATOR;

    /// @notice address of the fTokens where these rewards are supposed to be set
    address public immutable FTOKEN;
    address public immutable FTOKEN2;
    address public immutable FTOKEN3;
}

abstract contract Variables is Constants {
    // ----------------------- slot 0 ---------------------------

    /// @dev for how long current rewards should run
    uint40 internal _duration;

    /// @dev when current rewards got started
    uint40 internal _startTime;

    /// @dev current annualized reward based on input params (duration, rewardAmount)
    uint176 internal _yearlyReward;

    // ----------------------- slot 1 ---------------------------
    /// @dev Duration for the next rewards phase.
    uint40 internal _nextDuration;

    /// @dev Amount of rewards for the next phase.
    uint176 internal _nextRewardAmount;

    // 40 bytes empty
}

abstract contract Events {
    /// @notice Emitted when rewards are stopped.
    event LogStopRewards();

    /// @notice Emitted when queued rewards are cancelled.
    event LogCancelQueuedRewards();

    /// @notice Emitted when the rewards transition to the next phase.
    event LogTransitionedToNextRewards(uint256 startTime, uint256 endTime);

    /// @notice Emitted when rewards are started.
    /// @param rewardAmount The amount of rewards to be distributed.
    /// @param duration The duration for which the rewards will run.
    /// @param startTime The timestamp when the rewards start.
    event LogStartRewards(uint256 rewardAmount, uint256 duration, uint256 startTime);

    /// @notice Emitted when the next rewards are queued.
    /// @param rewardAmount The amount of rewards to be distributed in the next phase.
    /// @param duration The duration for which the next rewards will run.
    event LogQueueNextRewards(uint256 rewardAmount, uint256 duration);
}

/// @title LendingRewardsRateModel
/// @notice Calculates rewards rate used for an fToken based on a rewardAmount over a given duration.
/// Rewards start according to the configurator triggers and only accrue above a certain startTVL.
/// Max rate cap is at 50%.
contract FluidLendingRewardsRateModel is Variables, IFluidLendingRewardsRateModel, Events, Error {
    /// @dev Validates that an address is the configurator (team multisig)
    modifier onlyConfigurator() {
        if (msg.sender != CONFIGURATOR) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__Unauthorized);
        }
        _;
    }

    /// @notice Sets variables for rewards rate configuration based on input parameters.
    /// @param configurator_ The address with authority to configure rewards.
    /// @param fToken_ The address of the associated fToken contract.
    /// @param fToken2_ The address of the associated fToken contract 2, optional.
    /// @param fToken3_ The address of the associated fToken contract 3, optional.
    /// @param startTvl_ The TVL threshold below which the reward rate is 0.
    /// @param rewardAmount_ The total amount of underlying assets to be distributed as rewards.
    /// @param duration_ The duration (in seconds) for which the rewards will run.
    /// @param startTime_ The timestamp when rewards are scheduled to start; must be 0 or a future time.
    constructor(
        address configurator_,
        address fToken_,
        address fToken2_,
        address fToken3_,
        uint256 startTvl_,
        uint256 rewardAmount_,
        uint256 duration_,
        uint256 startTime_
    ) {
        if (
            configurator_ == address(0) ||
            fToken_ == address(0) ||
            rewardAmount_ == 0 ||
            startTvl_ == 0 ||
            duration_ == 0 ||
            (startTime_ > 0 && startTime_ < block.timestamp)
        ) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        CONFIGURATOR = configurator_;
        FTOKEN = fToken_;
        FTOKEN2 = fToken2_;
        FTOKEN3 = fToken3_;
        START_TVL = startTvl_;
        _duration = uint40(duration_);
        _startTime = uint40(startTime_);

        _yearlyReward = uint176((rewardAmount_ * SECONDS_PER_YEAR) / duration_);
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    /// @dev initiator_ is actually the configurator who has access to manage the rewards. named as is for backwards-compatibility reasons.
    function getConfig()
        external
        view
        returns (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            uint256 maxRate_,
            uint256 rewardAmount_,
            address initiator_
        )
    {
        rewardAmount_ = (_yearlyReward * _duration) / SECONDS_PER_YEAR;
        endTime_ = _startTime + _duration;
        return (_duration, _startTime, endTime_, START_TVL, MAX_RATE, rewardAmount_, CONFIGURATOR);
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    function getRate(uint256 totalAssets_) public view returns (uint256 rate_, bool ended_, uint256 startTime_) {
        startTime_ = _startTime;
        uint256 endTime_;
        uint256 duration_ = uint256(_duration);
        unchecked {
            endTime_ = startTime_ + duration_;
        }
        if (startTime_ == 0 || block.timestamp < startTime_) {
            return (0, false, startTime_);
        }
        if (block.timestamp > endTime_) {
            uint256 nextRewardAmount_ = uint256(_nextRewardAmount);
            if (nextRewardAmount_ == 0) {
                return (0, true, startTime_);
            }

            // use next queued rewards amounts. transition should be triggered via `transitionToNextRewards()` separately.
            // can not do this here because it modifies state and this method _must_ stay a view method to be compatible with
            // existing fTokens and all the view methods there that call this.

            uint256 nextDuration_ = uint256(_nextDuration);
            startTime_ = endTime_;
            endTime_ = startTime_ + nextDuration_;

            if (block.timestamp > endTime_) {
                // even next rewards ended
                return (0, true, startTime_);
            }
            if (totalAssets_ < START_TVL) {
                return (0, false, startTime_);
            }

            rate_ = (nextRewardAmount_ * SECONDS_PER_YEAR) / nextDuration_; // yearly reward
            rate_ = (rate_ * 1e14) / totalAssets_;
        } else {
            if (totalAssets_ < START_TVL) {
                return (0, false, startTime_);
            }

            rate_ = (uint256(_yearlyReward) * 1e14) / totalAssets_;
        }

        // Note when rewards just got started, fToken handles applying rewards only from _startTime onwards

        return (rate_ > MAX_RATE ? MAX_RATE : rate_, false, startTime_);
    }

    /// @notice stops current ongoing rewards instantly.
    function stopRewards() external onlyConfigurator {
        if (_startTime == 0 || block.timestamp > _startTime + _duration) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__AlreadyStopped);
        }
        if (_nextRewardAmount > 0) {
            // must cancel first with `cancelQueuedRewards()`
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NextRewardsQueued);
        }

        // update exchange price on fToken until now. Note there is no gas or otherwise benefit in calling `updateRewards()`
        // and setting address to zero at the fToken instead. still leaving the rewards address linked gives more clarity
        // when fetching data through resolvers.
        IFTokenAdmin(FTOKEN).updateRates();
        if (FTOKEN2 != address(0)) IFTokenAdmin(FTOKEN2).updateRates();
        if (FTOKEN3 != address(0)) IFTokenAdmin(FTOKEN3).updateRates();

        _duration = (block.timestamp - 1) > _startTime ? uint40(block.timestamp - _startTime - 1) : 0;
        // _yearlyReward stays the same

        emit LogStopRewards();
    }

    /// @notice start new rewards. LendingRewards must be an auth at the LendingFactory!
    /// set startTime set to 0 for using block.timestamp
    function startRewards(uint256 rewardAmount_, uint256 duration_, uint256 startTime_) public onlyConfigurator {
        if (block.timestamp <= _startTime + _duration) {
            // for instant switching must stop first with `stopRewards()`
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NotEnded);
        }
        if (startTime_ == 0) {
            startTime_ = block.timestamp;
        }
        if (duration_ == 0 || rewardAmount_ == 0 || startTime_ < block.timestamp) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        _startTime = uint40(startTime_);
        _duration = uint40(duration_);

        _yearlyReward = uint176((rewardAmount_ * SECONDS_PER_YEAR) / duration_);

        // make sure fTokens do not have set rewardsActive_ as false (locked in state if previous rewards ended)
        IFTokenAdmin(FTOKEN).updateRewards(IFluidLendingRewardsRateModel(address(this)));
        if (FTOKEN2 != address(0)) IFTokenAdmin(FTOKEN2).updateRewards(IFluidLendingRewardsRateModel(address(this)));
        if (FTOKEN3 != address(0)) IFTokenAdmin(FTOKEN3).updateRewards(IFluidLendingRewardsRateModel(address(this)));

        emit LogStartRewards(rewardAmount_, duration_, startTime_);
    }

    /// @notice cancels currently queued rewards
    function cancelQueuedRewards() external onlyConfigurator {
        if (_nextRewardAmount == 0) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NoQueuedRewards);
        }
        if (block.timestamp > _startTime + _duration) {
            // can not be cancelled if switch from current queued that already became active to making them current ones
            // has not been written to storage yet but time has passed for it. in this case, queued rewards must be
            // activated with `transitionToNextRewards()` and then call `stopRewards()`.
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__MustTransitionToNext);
        }

        _nextDuration = 0;
        _nextRewardAmount = 0;

        emit LogCancelQueuedRewards();
    }

    /// @notice queues next rewards which can be come active after current ongoing rewards.
    function queueNextRewards(uint256 rewardAmount_, uint256 duration_) external onlyConfigurator {
        if (duration_ == 0 || rewardAmount_ == 0) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }
        if (_nextRewardAmount > 0) {
            // must cancel already queued first with `cancelQueuedRewards()`
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NextRewardsQueued);
        }
        if (_startTime == 0) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NoRewardsStarted);
        }
        if (block.timestamp > _startTime + _duration) {
            // if current rewards are ended, immediately start the new queued ones
            return startRewards(rewardAmount_, duration_, block.timestamp);
        }

        _nextRewardAmount = uint176(rewardAmount_);
        _nextDuration = uint40(duration_);

        emit LogQueueNextRewards(rewardAmount_, duration_);
    }

    /// @notice transitions to next queued rewards after current ongoing rewards ended. Callable by anyone.
    /// @dev    Note triggering this is not required for queued rewards to start accruing as that happens anyway in the `getRate`
    ///         view method, but it cleans up the status here in storage and gas optimizes the `getRate()` call.
    function transitionToNextRewards() public {
        // there is no way to read lastUpdateTimestamp from fToken so we apply the new rewards rate
        // for _startTime to until now. Rewards are only applied from _startTime to now at fToken code,
        // so rewards between lastUpdateTimestamp and new _startTime (= old endTime) are lost.

        uint256 startTime_ = uint256(_startTime);
        uint256 endTime_ = startTime_ + _duration;
        if (block.timestamp <= endTime_) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NotEnded);
        }

        uint256 nextRewardAmount_ = uint256(_nextRewardAmount);
        if (nextRewardAmount_ == 0) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NoQueuedRewards);
        }

        uint256 nextDuration_ = uint256(_nextDuration);

        startTime_ = endTime_;
        _startTime = uint40(startTime_);
        _duration = uint40(nextDuration_);
        _yearlyReward = uint176((nextRewardAmount_ * SECONDS_PER_YEAR) / nextDuration_);

        endTime_ = startTime_ + nextDuration_; // update for emit event

        _nextDuration = 0;
        _nextRewardAmount = 0;

        emit LogTransitionedToNextRewards(startTime_, endTime_);
    }
}
