// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice Emitted when magnifier is updated
    event LogUpdateMagnifier(address indexed vault, uint256 newMagnifier);

    /// @notice Emitted when rewards are started
    event LogRewardsStarted(uint256 startTime, uint256 endTime);

    /// @notice Emitted when next rewards are set
    event LogNextRewardsQueued(uint256 rewardsAmount, uint256 duration);
}
