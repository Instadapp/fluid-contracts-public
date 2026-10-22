// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFToken } from "../../../protocols/lending/interfaces/iFToken.sol";
import { IFluidLendingStakingRewards } from "../../../protocols/lending/interfaces/iStakingRewards.sol";

/// @notice Fluid Lending protocol Merkle Staking Rewards resolver
contract FluidStakingMerkleResolver {
    IFToken public constant FUSDC = IFToken(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33);
    IFToken public constant FUSDT = IFToken(0x5C20B550819128074FD538Edf79791733ccEdd18);

    IFluidLendingStakingRewards public constant FUSDC_STAKING =
        IFluidLendingStakingRewards(0x2fA6c95B69c10f9F52b8990b6C03171F13C46225);
    IFluidLendingStakingRewards public constant FUSDT_STAKING =
        IFluidLendingStakingRewards(0x490681095ed277B45377d28cA15Ac41d64583048);

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
