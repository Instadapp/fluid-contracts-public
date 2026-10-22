// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Structs {
    /// @notice One scheduled window. Durations are always in minutes.
    /// @dev Timeline: `[sessionStart, sessionStart + durationMinutes)` → REGULAR or HOLIDAY from `sessionType`,
    ///      then extended for `extendedDurationMinutes` → EXTENDED. Times outside any entry → UNKNOWN.
    ///
    ///      On-chain storage packs each session into **60 bits**:
    ///      `sessionStart:32 | durationMinutes:13 | extendedDurationMinutes:13 | sessionType:2`
    ///      (calldata may use wider `uint16` durations; values must be ≤ 8191).
    struct Session {
        uint32 sessionStart;
        uint16 durationMinutes;
        uint16 extendedDurationMinutes;
        uint8 sessionType;
    }
}
