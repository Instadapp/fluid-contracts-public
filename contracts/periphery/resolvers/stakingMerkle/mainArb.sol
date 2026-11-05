// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFToken } from "../../../protocols/lending/interfaces/iFToken.sol";
import { IFluidLendingStakingRewards } from "../../../protocols/lending/interfaces/iStakingRewards.sol";

/// @notice Fluid Lending protocol Merkle Staking Rewards resolver for Arbitrum
contract FluidStakingMerkleResolver {
    IFToken public constant FUSDC = IFToken(0x1A996cb54bb95462040408C06122D45D6Cdb6096);
    IFToken public constant FUSDT = IFToken(0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03);

    IFluidLendingStakingRewards public constant FUSDC_STAKING =
        IFluidLendingStakingRewards(0x48f89d731C5e3b5BeE8235162FC2C639Ba62DB7d);
    IFluidLendingStakingRewards public constant FUSDT_STAKING =
        IFluidLendingStakingRewards(0x65241f6cacde58c03400Cb84542a2c197d6dE9C3);

    struct UserPosition {
        address user;
        uint256 shares; // normalShares + stakeShares
        uint256 normalShares;
        uint256 stakeShares;
    }

    function getUsersPosition(
        address[] calldata users_,
        IFToken fToken_,
        IFluidLendingStakingRewards stakingContract_
    ) public view returns (UserPosition[] memory positions_) {
        positions_ = new UserPosition[](users_.length);

        for (uint256 i; i < users_.length; ++i) {
            positions_[i].user = users_[i];
            positions_[i].normalShares = fToken_.balanceOf(users_[i]);
            positions_[i].stakeShares = stakingContract_.balanceOf(users_[i]);
            positions_[i].shares = positions_[i].normalShares + positions_[i].stakeShares;
        }
    }

    function getUsersPositionFUSDC(address[] calldata users_) public view returns (UserPosition[] memory positions_) {
        return getUsersPosition(users_, FUSDC, FUSDC_STAKING);
    }

    function getUsersPositionFUSDT(address[] calldata users_) public view returns (UserPosition[] memory positions_) {
        return getUsersPosition(users_, FUSDT, FUSDT_STAKING);
    }
}
