// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice emitted whenever `maxLTV` is updated
    event LogSetMaxLTV(uint256 maxLTV);

    /// @notice emitted when a queue() process is executed
    event LogQueue(
        address indexed claimTo,
        uint256 requestIdFrom,
        uint256 borrowETHAmount,
        uint256 queueStETHAmount,
        address borrowTo
    );

    /// @notice emitted when a claim() process is executed
    event LogClaim(address indexed claimTo, uint256 requestIdFrom, uint256 claimedAmount, uint256 repayAmount);

    /// @notice emitted when an auth is modified by owner
    event LogSetAuth(address indexed auth, bool allowed);

    /// @notice emitted when a guardian is modified by owner
    event LogSetGuardian(address indexed guardian, bool allowed);

    /// @notice emitted when an allowed user is modified by auths
    event LogSetAllowed(address indexed user, bool allowed);

    /// @notice emitted when `allowListActive` status is updated
    event LogSetAllowListActive(bool active);

    /// @notice emitted when protocol is paused by guardian
    event LogPaused();

    /// @notice emitted when protocol is unpaused by owner
    event LogUnpaused();
}
