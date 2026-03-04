// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidLendingResolver } from "../lending/iLendingResolver.sol";
import { Structs as FluidLendingResolverStructs } from "../lending/structs.sol";
import { IFluidLendingStakingRewards } from "../../../protocols/lending/interfaces/iStakingRewards.sol";
import { Structs } from "./structs.sol";


/// @notice Fluid Lending protocol Staking Rewards (for fTokens) resolver
/// Implements various view-only methods to give easy access to Lending protocol staked fToken rewards data.
contract FluidStakingRewardsResolver is Structs {
    IFluidLendingResolver immutable public LENDING_RESOLVER;

    /// @notice thrown if an input param address is zero
    error FluidStakingRewardsResolver__AddressZero();

    constructor(address lendingResolver_) {
        if(lendingResolver_ == address(0)){
            revert FluidStakingRewardsResolver__AddressZero();
        }
        LENDING_RESOLVER = IFluidLendingResolver(lendingResolver_);
    }

    function getFTokenStakingRewardsEntireData(address reward_) public view returns (FTokenStakingRewardsDetails memory r_) {
        // if address is 0 then data will be returned as 0
        if (reward_ != address(0)) {
            IFluidLendingStakingRewards rewardContract_ = IFluidLendingStakingRewards(reward_);
            
            r_.rewardPerToken = rewardContract_.rewardPerToken();
            r_.getRewardForDuration = rewardContract_.getRewardForDuration();
            r_.totalSupply = rewardContract_.totalSupply();
            r_.periodFinish = rewardContract_.periodFinish();
            r_.rewardRate = rewardContract_.rewardRate();
            r_.rewardsDuration = rewardContract_.rewardsDuration();
            r_.rewardsToken = address(rewardContract_.rewardsToken());
            r_.fToken = address(rewardContract_.stakingToken());
        }
    }

    function getFTokensStakingRewardsEntireData(address[] memory rewards_) public view returns (FTokenStakingRewardsDetails[] memory r_) {
        r_ = new FTokenStakingRewardsDetails[](rewards_.length);
        for (uint i = 0; i < rewards_.length; i++) {
            r_[i] = getFTokenStakingRewardsEntireData(rewards_[i]);
        }
    }

    function getUserRewardsData(
        address user_,
        address reward_,
        FluidLendingResolverStructs.FTokenDetails memory fTokenDetails_
    ) public view returns (UserRewardDetails memory u_) {
        if (reward_ != address(0)) {
            IFluidLendingStakingRewards rewardContract_ = IFluidLendingStakingRewards(reward_);
            
            u_.earned = rewardContract_.earned(user_);
            u_.fTokenShares = rewardContract_.balanceOf(user_);
            u_.underlyingAssets = (u_.fTokenShares * fTokenDetails_.convertToAssets) / (10**fTokenDetails_.decimals);
            u_.ftokenAllowance = IERC20(fTokenDetails_.tokenAddress).allowance(user_, reward_);
        }
    }

    function getUserAllRewardsData(
        address user_,
        address[] memory rewards_,
        FluidLendingResolverStructs.FTokenDetails[] memory fTokensDetails_
    ) public view returns (UserRewardDetails[] memory u_) {
        u_ = new UserRewardDetails[](rewards_.length);
        for (uint i = 0; i < rewards_.length; i++) {
            u_[i] = getUserRewardsData(user_, rewards_[i], fTokensDetails_[i]);
        }
    }

    struct underlyingTokenToRewardsMap {
        address underlyingToken;
        address rewardContract;
    }

    function getUserPositions(
        address user_,
        underlyingTokenToRewardsMap[] memory rewardsMap_
    ) public view returns (UserFTokenRewardsEntireData[] memory u_) {
        FluidLendingResolverStructs.FTokenDetailsUserPosition[] memory e_  = LENDING_RESOLVER.getUserPositions(user_);
        uint length_ = e_.length;
        u_ = new UserFTokenRewardsEntireData[](length_);

        address rewardToken_;
        for (uint i = 0; i < length_; i++) {
            u_[i].fTokenDetails = e_[i].fTokenDetails;
            u_[i].userPosition = e_[i].userPosition;
            for (uint j = 0; j < rewardsMap_.length; j++) {
                if (u_[i].fTokenDetails.asset == rewardsMap_[j].underlyingToken) {
                    rewardToken_ = rewardsMap_[j].rewardContract;
                    break;
                }
            }
            u_[i].fTokenRewardsDetails = getFTokenStakingRewardsEntireData(rewardToken_);
            u_[i].userRewardsDetails = getUserRewardsData(user_, rewardToken_, u_[i].fTokenDetails);
            rewardToken_ = address(0);
        }
    }


}
