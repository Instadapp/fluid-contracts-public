// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { Owned } from "solmate/src/auth/Owned.sol";

// Adapted from https://github.com/Uniswap/liquidity-staker/blob/master/contracts/StakingRewards.sol
contract FluidLendingStakingRewards is Owned, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardsToken; // should be INST or any ERC20
    IERC20 public immutable stakingToken; // should be fToken

    /* ========== STATE VARIABLES ========== */

    // Owned and ReentranyGuard storage variables before

    uint40 internal _periodFinish;
    uint40 public lastUpdateTime;
    uint40 internal _rewardsDuration; // e.g. 60 days
    uint136 internal _rewardRate;

    // ------------------------------ next slot

    uint128 public rewardPerTokenStored;
    uint128 internal _totalSupply;

    // ------------------------------ next slot

    uint40 public nextRewardsDuration; // e.g. 60 days
    uint216 public nextRewards;

    // ------------------------------ next slot

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => uint256) internal _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address owner_, IERC20 rewardsToken_, IERC20 stakingToken_, uint40 rewardsDuration_) Owned(owner_) {
        require(address(rewardsToken_) != address(0), "Invalid params");
        require(address(stakingToken_) != address(0), "Invalid params");
        require(owner_ != address(0), "Invalid params"); // Owned does not have a zero check for owner_
        require(rewardsDuration_ > 0, "Invalid params");

        rewardsToken = rewardsToken_;
        stakingToken = stakingToken_;
        _rewardsDuration = rewardsDuration_;
    }

    /* ========== VIEWS ========== */

    function nextPeriodFinish() public view returns (uint256) {
        if (nextRewardsDuration == 0) {
            return 0;
        }
        return _periodFinish + nextRewardsDuration;
    }

    function nextRewardRate() public view returns (uint256) {
        if (nextRewards == 0) {
            return 0;
        }
        return nextRewards / nextRewardsDuration;
    }

    function periodFinish() public view returns (uint256) {
        if (block.timestamp <= _periodFinish || nextRewardsDuration == 0) {
            return _periodFinish;
        }
        return nextPeriodFinish();
    }

    function rewardRate() public view returns (uint256) {
        if (block.timestamp <= _periodFinish || nextRewardsDuration == 0) {
            return _rewardRate;
        }
        return nextRewardRate();
    }

    function rewardsDuration() public view returns (uint256) {
        if (block.timestamp <= _periodFinish || nextRewardsDuration == 0) {
            return _rewardsDuration;
        }
        return nextRewardsDuration;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /// @notice gets last time where rewards accrue, also considering already queued next rewards
    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp <= _periodFinish) {
            return block.timestamp;
        }

        if (nextRewardsDuration == 0) {
            return _periodFinish;
        }

        // check if block.timestamp is within next rewards duration
        uint256 nextPeriodFinish_ = nextPeriodFinish();
        if (block.timestamp <= nextPeriodFinish_) {
            return block.timestamp;
        }
        return nextPeriodFinish_;
    }

    /// @notice gets reward amount per token, also considering automatic transition to queued next rewards
    function rewardPerToken() public view returns (uint256 rewardPerToken_) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        // reward per token for current rewards
        // get lastTimeRewardApplicable for storage vars (without next queued rewards as returned by view methods)
        uint256 lastTimeRewardApplicable_ = block.timestamp < _periodFinish ? block.timestamp : _periodFinish;

        rewardPerToken_ = (((lastTimeRewardApplicable_ - lastUpdateTime) * _rewardRate * 1e18) / _totalSupply);

        if (block.timestamp > _periodFinish && nextRewardsDuration > 0) {
            // previous rewards ended and next rewards queued, take into account accrued rewards:

            // check if block.timestamp is within next rewards duration
            rewardPerToken_ += (((lastTimeRewardApplicable() - _periodFinish) * nextRewardRate() * 1e18) /
                _totalSupply);
        }

        rewardPerToken_ += rewardPerTokenStored;
    }

    /// @notice gets earned reward amount for an `account`, also considering automatic transition to queued next rewards
    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /// @notice gets reward amount for current duration, also considering automatic transition to queued next rewards
    function getRewardForDuration() public view returns (uint256) {
        return rewardRate() * rewardsDuration();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stakeWithPermit(
        uint256 amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        // permit
        IERC20Permit(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        _totalSupply = _totalSupply + uint128(amount);
        _balances[msg.sender] = _balances[msg.sender] + amount;

        emit Staked(msg.sender, amount);
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        _totalSupply = _totalSupply + uint128(amount);
        _balances[msg.sender] = _balances[msg.sender] + amount;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");

        _totalSupply = _totalSupply - uint128(amount);
        _balances[msg.sender] = _balances[msg.sender] - amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /// @notice updates rewards until current block.timestamp or `periodFinish`. Transitions to next rewards
    /// if previous rewards ended and next ones were queued.
    function updateRewards() public nonReentrant updateReward(address(0)) {}

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice queues next rewards that will be transitioned to automatically after current rewards reach `periodFinish`.
    function queueNextRewardAmount(uint216 nextReward_, uint40 nextDuration_) external onlyOwner {
        require(block.timestamp < _periodFinish, "Previous duration already ended");
        require(nextDuration_ > 0 && nextReward_ > 0, "Invalid params");
        // must not already be queued
        require(nextRewardsDuration == 0, "Already queued next rewards");

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + nextReward must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance_ = rewardsToken.balanceOf(address(this));
        uint256 remainingCurrentReward_ = (_periodFinish - block.timestamp) * _rewardRate;
        uint256 requiredBalance_ = remainingCurrentReward_ + nextReward_;
        require(requiredBalance_ <= balance_, "Provided reward too high");

        nextRewards = nextReward_;
        nextRewardsDuration = nextDuration_;

        emit NextRewardQueued(nextReward_, nextDuration_);
    }

    /// @notice add new rewards and update reward duration AFTER a reward period has ended.
    function notifyRewardAmountWithDuration(
        uint256 reward_,
        uint40 newDuration_
    ) external onlyOwner updateReward(address(0)) {
        require(block.timestamp > _periodFinish, "Previous duration not ended");
        // @dev nextRewardsDuration == 0 should not be needed because if there are next rewards queued and block.timestamp > periodFinish,
        // then updateReward(address(0)) would automatically transition to the queued rewards and set nextRewardsDuration == 0.
        // Adding the check here anyway to be safe as gas optimization on an Admin Method is not necessary.
        require(nextRewardsDuration == 0, "Already queued next rewards");
        require(newDuration_ > 0, "Invalid params");

        _rewardsDuration = newDuration_;
        notifyRewardAmount(reward_);
    }

    /// @notice add new rewards or top-up adding to current rewards, adjusting rewardRate going forward for leftover + newReward
    /// until block.timestamp + duration
    function notifyRewardAmount(uint256 reward_) public onlyOwner updateReward(address(0)) {
        require(nextRewardsDuration == 0, "Already queued next rewards");

        if (block.timestamp >= _periodFinish) {
            _rewardRate = uint136(reward_ / _rewardsDuration);
        } else {
            uint256 remaining_ = _periodFinish - block.timestamp;
            uint256 leftover_ = remaining_ * _rewardRate;
            _rewardRate = uint136((reward_ + leftover_) / _rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance_ = rewardsToken.balanceOf(address(this));
        require(_rewardRate <= balance_ / _rewardsDuration, "Provided reward too high");

        lastUpdateTime = uint40(block.timestamp);
        _periodFinish = uint40(block.timestamp + _rewardsDuration);
        emit RewardAdded(reward_);
    }

    /// @notice         Spell allows owner aka governance to do any arbitrary call
    /// @param target_  Address to which the call needs to be delegated
    /// @param data_    Data to execute at the delegated address
    function spell(address target_, bytes memory data_) external onlyOwner returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        // get lastTimeRewardApplicable for storage vars (without next queued rewards as returned by view methods)
        uint256 lastTimeRewardApplicable_ = block.timestamp < _periodFinish ? block.timestamp : _periodFinish;

        // get reward per Token for storage vars (without next queued rewards as returned by view methods)
        uint256 rewardPerToken_;
        if (_totalSupply > 0) {
            rewardPerToken_ =
                rewardPerTokenStored +
                (((lastTimeRewardApplicable_ - lastUpdateTime) * _rewardRate * 1e18) / _totalSupply);
        }

        rewardPerTokenStored = uint128(rewardPerToken_);
        lastUpdateTime = uint40(lastTimeRewardApplicable_);

        if (block.timestamp > _periodFinish && nextRewardsDuration > 0) {
            // previous rewards ended, and new rewards were queued -> start new rewards.

            // previous rewards fully distributed until `periodFinish` by updating `rewardPerTokenStored`
            // according to `rewardRate` that was valid until period finish, with calls above.

            // transition to new rewards
            _rewardRate = uint136(nextRewards / nextRewardsDuration);
            _rewardsDuration = nextRewardsDuration;

            // new rewards started right at periodFinish
            _periodFinish = uint40(_periodFinish + _rewardsDuration);

            emit RewardAdded(nextRewards);

            // reset next rewards storage vars
            nextRewards = 0;
            nextRewardsDuration = 0;

            // update rewardPerTokenStored again to go until current block.timestamp now
            // can use normal view methods here as next rewards storage vars have just been set to 0
            rewardPerTokenStored = uint128(rewardPerToken());
            lastUpdateTime = uint40(lastTimeRewardApplicable());
        }

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event NextRewardQueued(uint256 reward, uint256 duration);
}
