// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel } from "../interfaces/iLendingRewardsRateModel.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

/// @title LendingRewardsRateModel
/// @notice Calculates rewards rate used for an fToken based on a rewardAmount over a given duration.
/// Rewards start once the allowed initiator address triggers `start()` and only accrue above a certain startTVL.
/// Max rate cap is at 50%.
contract FluidLendingRewardsRateModel is IFluidLendingRewardsRateModel, Error {
    /// @notice Emitted when rewards are started
    event LogRewardsStarted(uint256 startTime, uint256 endTime);

    /// @dev precision decimals for rewards rate
    uint256 internal constant RATE_PRECISION = 1e12;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @dev maximum rewards rate is 50%. no config higher than this should be possible.
    uint256 internal constant MAX_RATE = 50 * RATE_PRECISION; // 1e12 = 1%, this is 50%.

    /// @dev tvl below which rewards rate is 0
    uint256 internal immutable START_TVL;

    /// @dev for how long rewards should run
    uint256 internal immutable DURATION;

    /// @dev annualized reward based on constructor input params (duration, rewardAmount)
    uint256 internal immutable YEARLY_REWARD;

    /// @dev total amounts to be distributed. not needed but stored for easier tracking via `getConfig`
    uint256 internal immutable REWARD_AMOUNT;

    /// @dev address which has access to call start() which kickstarts the rewards
    address internal immutable INITIATOR;

    /// @dev address of the previously active lending rewards rate model for smooth transition. Can be zero address if none.
    IFluidLendingRewardsRateModel public immutable PREVIOUS_MODEL;
    /// @dev end time of previous lending rewards rate model. 0 if there is no previous model.
    uint256 internal immutable PREVIOUS_MODEL_END_TIME;

    /// @dev when rewards got started
    uint96 internal startTime;
    /// @dev when rewards will get over
    uint96 internal endTime;

    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__ZeroAddress);
        }
        _;
    }

    /// @notice sets immutable vars for rewards rate config based on input params.
    /// @param duration_ for how long rewards should run
    /// @param startTvl_  tvl below which rate is 0
    /// @param rewardAmount_  total amount of underlying asset to be distributed as rewards
    /// @param initiator_  address which has access to kickstart the rewards, if previousModel is address zero
    /// @param previousModel_  address of previously active lendingRewardsRateModel. can be zero address if none.
    constructor(
        uint256 duration_,
        uint256 startTvl_,
        uint256 rewardAmount_,
        address initiator_,
        IFluidLendingRewardsRateModel previousModel_
    ) {
        // sanity checks
        if (
            duration_ == 0 ||
            rewardAmount_ == 0 ||
            startTvl_ == 0 ||
            (initiator_ == address(0) && address(previousModel_) == address(0))
        ) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
        }

        START_TVL = startTvl_;
        DURATION = duration_;
        REWARD_AMOUNT = rewardAmount_;
        INITIATOR = initiator_;

        YEARLY_REWARD = (rewardAmount_ * SECONDS_PER_YEAR) / DURATION;

        if (address(previousModel_) != address(0)) {
            PREVIOUS_MODEL = previousModel_;
            (, , PREVIOUS_MODEL_END_TIME, , , , ) = previousModel_.getConfig();
            if (PREVIOUS_MODEL_END_TIME == 0) {
                revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__InvalidParams);
            }

            // start current model exactly when previous model ends. no trigger via start() needed.
            startTime = uint96(PREVIOUS_MODEL_END_TIME);
            endTime = uint96(PREVIOUS_MODEL_END_TIME + DURATION);

            emit LogRewardsStarted(startTime, endTime);
        }
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
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
        return (DURATION, startTime, endTime, START_TVL, MAX_RATE, REWARD_AMOUNT, INITIATOR);
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    function getRate(uint256 totalAssets_) public view returns (uint256 rate_, bool ended_, uint256 startTime_) {
        if (block.timestamp <= PREVIOUS_MODEL_END_TIME) {
            // return previous model rate until previous model end time.
            return PREVIOUS_MODEL.getRate(totalAssets_);
        }

        startTime_ = startTime;
        uint endTime_ = endTime;
        if (startTime_ == 0 || endTime_ == 0) {
            return (0, false, startTime_);
        }
        if (block.timestamp > endTime_) {
            return (0, true, startTime_);
        }
        if (totalAssets_ < START_TVL) {
            return (0, false, startTime_);
        }

        rate_ = (YEARLY_REWARD * 1e14) / totalAssets_;

        return (rate_ > MAX_RATE ? MAX_RATE : rate_, false, startTime_);
    }

    function start() external {
        if (msg.sender != INITIATOR) {
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__NotTheInitiator);
        }
        if (startTime > 0 || endTime > 0) {
            // will fail if started in constructor for smooth transition from previous model
            revert FluidLendingError(ErrorTypes.LendingRewardsRateModel__AlreadyStarted);
        }
        startTime = uint96(block.timestamp);
        endTime = uint96(block.timestamp + DURATION);

        emit LogRewardsStarted(startTime, endTime);
    }
}
