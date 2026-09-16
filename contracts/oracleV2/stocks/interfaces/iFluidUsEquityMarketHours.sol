// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Structs } from "../usEquityMarketHours/structs.sol";

/// @notice Shared US equity market-hours schedule for Chainlink 24/5 stock oracles.
/// @dev Week-ahead session list; lookup never reverts — UNKNOWN if missing/undefined (fail-open).
///      Off-chain writer is complementary only.
///
///      Session type return values (`SESSION_TYPE_*` in implementation Constants):
///      - UNKNOWN  (0) — empty schedule, or time outside any stored entry
///      - REGULAR  (1) — regular trading hours (also valid stored entry type)
///      - EXTENDED (2) — after `durationMinutes`, for `extendedDurationMinutes`
///      - HOLIDAY  (3) — inside a HOLIDAY entry’s main window (also valid stored entry type)
///
///      Regular-hours window: `latestRegularHoursStart_ == 0` means none found (no separate found flag).
interface IFluidUsEquityMarketHours {
    /// @notice Session type at `timestamp_`.
    function getSessionType(uint256 timestamp_) external view returns (uint256 sessionType_);

    /// @notice Session type at `block.timestamp`.
    function getCurrentSessionType() external view returns (uint256 sessionType_);

    /// @notice Full week-ahead session schedule currently stored.
    function getSessions() external view returns (Structs.Session[] memory sessions_);

    /// @notice Most recent REGULAR session window at or before `timestamp_`.
    /// @dev `latestRegularHoursStart_ == 0` if none found.
    function getLatestRegularHoursWindow(
        uint256 timestamp_
    ) external view returns (uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_);

    /// @notice Session type at `timestamp_`, plus the latest REGULAR-hours window at or before that time.
    /// @dev `latestRegularHoursStart_ == 0` if no REGULAR window found.
    function getSessionInfo(
        uint256 timestamp_
    ) external view returns (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_);

    /// @notice Like `getSessionInfo(block.timestamp)`, advancing the schedule cursor.
    /// @dev `latestRegularHoursStart_ == 0` if no REGULAR window found.
    function getCurrentSession()
        external
        returns (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_);
}
