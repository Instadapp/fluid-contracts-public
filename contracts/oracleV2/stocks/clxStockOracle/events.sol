// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Events {
    /// @dev Accepted wrapper multiplier synced (in-band write or team confirm).
    event LogUpdateAcceptedMultiplier(uint256 oldMultiplier, uint256 newMultiplier);
    /// @dev Permissionless RTH clamp anchor warm.
    event LogUpdateRegularHoursAnchor(uint80 roundId);
    /// @dev Write path skipped extended-hours clamp.
    event LogExtendedHoursFallback(uint256 sessionType);
    event LogPause();
    event LogUnpause();
}
