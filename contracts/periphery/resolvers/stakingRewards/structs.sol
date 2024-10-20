// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Structs as FluidLendingResolverStructs } from "../lending/structs.sol";

abstract contract Structs {
    struct FTokenStakingRewardsDetails {
        uint rewardPerToken; // how much rewards have distributed per token since start
        uint getRewardForDuration; // total rewards being distributed
        uint totalSupply; // total fToken deposited
        uint periodFinish; // when rewards will get over
        uint rewardRate; // total rewards / duration
        uint rewardsDuration; // how long rewards are for since start to end
        address rewardsToken; // which token are we distributing as rewards
        address fToken; // which token are we distributing as rewards
    }

    struct UserRewardDetails {
        uint earned;
        uint fTokenShares; // user fToken balance deposited
        uint underlyingAssets; // user fToken balance converted into underlying token
        uint ftokenAllowance; // allowance of fToken to rewards contract
    }

    struct UserFTokenRewardsEntireData {
        FluidLendingResolverStructs.FTokenDetails fTokenDetails;
        FluidLendingResolverStructs.UserPosition userPosition;
        FTokenStakingRewardsDetails fTokenRewardsDetails;
        UserRewardDetails userRewardsDetails;
    }
}
