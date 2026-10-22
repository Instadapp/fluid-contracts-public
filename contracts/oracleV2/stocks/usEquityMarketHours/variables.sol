// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { BasicUpgradeable } from "../../../libraries/access/basicUpgradeable.sol";
import { StorageRead } from "../../../libraries/storageRead.sol";
import { SessionTypes } from "./sessionTypes.sol";

abstract contract Constants is SessionTypes {
    /// @dev Eight 60-bit sessions + index fit in two words with spare bits in word1. See SPEC.
    uint256 internal constant MAX_SESSIONS = 8;

    /// @dev Bits per duration field in the packed session word.
    uint256 internal constant DURATION_BITS = 13;

    /// @dev Max value for each duration field in packed storage. ≈ 5.69 days.
    uint256 internal constant MAX_DURATION_MINUTES = (1 << DURATION_BITS) - 1; // 8191
    /// @dev REGULAR duration cap; CLX anchor lookback relies on regular hours never exceeding 24h.
    uint256 internal constant MAX_REGULAR_DURATION_MINUTES = 1 days / 1 minutes; // 1440

    /// @dev Minimum sum of (durationMinutes + extendedDurationMinutes) across a non-empty update.
    uint256 internal constant MIN_SCHEDULE_DURATION_MINUTES = 7 days / 1 minutes; // 10080

    /// @dev Schedule writers use auth class `1` (`onlyAuthClassAbove`).
    uint256 internal constant AUTH_CLASS_SCHEDULE = 1;
    /// @dev Auth class `2` (or governance) may also rewrite pinned sessions.
    uint256 internal constant AUTH_CLASS_SCHEDULE_OVERRIDE = 2;

    /// @dev Sessions starting before `now + this` are pinned (immutable) for plain schedule writers.
    uint256 internal constant PINNED_SESSION_LOOKAHEAD = 5 hours;
}

abstract contract Variables is Constants, BasicUpgradeable, StorageRead {
    /// @param liquidity_ Liquidity proxy whose EIP-1967 admin is governance for this schedule contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address liquidity_) BasicUpgradeable(liquidity_) {}

    // ------------ storage from BasicUpgradeable / Initializable comes before vars here --------
    // - slot 0: `_initialized` / `_initializing`

    // ----------------------- slot 1 ---------------------------
    /// @dev Layout: `currentIndex:8 | session0:60 | session1:60 | session2:60 | session3:60` (8 bits spare).
    ///      Session: `sessionStart:32 | durationMinutes:13 | extendedDurationMinutes:13 | sessionType:2`.
    ///      Unused sessions have `sessionStart == 0`.
    uint256 internal _sessionData0;

    // ----------------------- slot 2 ---------------------------
    /// @dev Same session packing as slot 1 for `session4..7`, but **no** `currentIndex`
    ///      (sessions start at bit 0). 16 bits spare at the high end (reserved).
    uint256 internal _sessionData1;

    // ----------------------- slot 3 ---------------------------
    /// @dev Auth class for `BasicAuth` hooks (`0` = none, `1` = schedule writer).
    mapping(address => uint256) internal _auths;
}
