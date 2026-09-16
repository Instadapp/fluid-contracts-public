// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";

abstract contract Helpers is Structs, Variables {
    uint256 private constant SESSION_BITS = 60;
    uint256 private constant CURRENT_INDEX_BITS = 8;
    uint256 private constant SESSIONS_PER_WORD = 4;

    uint256 private constant BITS_DURATION_MINUTES = 32;
    uint256 private constant BITS_EXTENDED_DURATION_MINUTES = 45;
    uint256 private constant BITS_SESSION_TYPE = 58;

    uint256 private constant MASK_CURRENT_INDEX = (1 << CURRENT_INDEX_BITS) - 1;
    uint256 private constant MASK_DURATION = (1 << DURATION_BITS) - 1;
    uint256 private constant MASK_SESSION = (1 << SESSION_BITS) - 1;

    /// @dev Packs a session into 60 bits.
    function _packSession(Session calldata s_) internal pure returns (uint256 packed_) {
        packed_ = uint256(s_.sessionStart);
        packed_ |= uint256(s_.durationMinutes) << BITS_DURATION_MINUTES;
        packed_ |= uint256(s_.extendedDurationMinutes) << BITS_EXTENDED_DURATION_MINUTES;
        packed_ |= uint256(s_.sessionType) << BITS_SESSION_TYPE;
    }

    /// @dev Unpacks a 60-bit session word.
    function _unpackSession(uint256 packed_) internal pure returns (Session memory s_) {
        s_.sessionStart = uint32(packed_);
        s_.durationMinutes = uint16((packed_ >> BITS_DURATION_MINUTES) & MASK_DURATION);
        s_.extendedDurationMinutes = uint16((packed_ >> BITS_EXTENDED_DURATION_MINUTES) & MASK_DURATION);
        s_.sessionType = uint8(packed_ >> BITS_SESSION_TYPE);
    }

    /// @dev Reads `currentIndex` from `_sessionData0`.
    function _currentIndex(uint256 data0_) internal pure returns (uint256) {
        return data0_ & MASK_CURRENT_INDEX;
    }

    /// @dev Writes `currentIndex` into `_sessionData0`.
    function _setCurrentIndex(uint256 data0_, uint256 index_) internal pure returns (uint256) {
        return (data0_ & ~MASK_CURRENT_INDEX) | (index_ & MASK_CURRENT_INDEX);
    }

    /// @dev Loads session at `index_` from the two packed words.
    function _loadSession(uint256 data0_, uint256 data1_, uint256 index_) internal pure returns (Session memory) {
        uint256 packed_;
        unchecked {
            // Callers only pass `index_ < MAX_SESSIONS` (8); bit offsets fit uint256.
            if (index_ < SESSIONS_PER_WORD) {
                packed_ = (data0_ >> (CURRENT_INDEX_BITS + index_ * SESSION_BITS)) & MASK_SESSION;
            } else {
                packed_ = (data1_ >> ((index_ - SESSIONS_PER_WORD) * SESSION_BITS)) & MASK_SESSION;
            }
        }
        return _unpackSession(packed_);
    }

    /// @dev Whether `s_` is identical to a stored session (unused zero slots never match a validated entry).
    function _isStoredSession(uint256 data0_, uint256 data1_, Session calldata s_) internal pure returns (bool) {
        for (uint256 i_; i_ < MAX_SESSIONS; ++i_) {
            Session memory stored_ = _loadSession(data0_, data1_, i_);
            if (
                stored_.sessionStart == s_.sessionStart &&
                stored_.durationMinutes == s_.durationMinutes &&
                stored_.extendedDurationMinutes == s_.extendedDurationMinutes &&
                stored_.sessionType == s_.sessionType
            ) return true;
        }
        return false;
    }

    /// @dev Like `_loadSession`, but sloads `_sessionData1` only when `index_ >= 4`.
    function _getSession(
        uint256 data0_,
        uint256 data1_,
        bool data1Loaded_,
        uint256 index_
    ) internal view returns (uint256, bool, Session memory) {
        if (index_ >= SESSIONS_PER_WORD && !data1Loaded_) {
            data1_ = _sessionData1;
            data1Loaded_ = true;
        }
        return (data1_, data1Loaded_, _loadSession(data0_, data1_, index_));
    }

    /// @dev Packs sessions into `_sessionData0` / `_sessionData1` (index bits cleared).
    function _storeSessions(Session[] calldata sessions_) internal pure returns (uint256 data0_, uint256 data1_) {
        uint256 len_ = sessions_.length;
        for (uint256 i_; i_ < len_; ++i_) {
            uint256 packed_ = _packSession(sessions_[i_]);
            if (i_ < SESSIONS_PER_WORD) {
                data0_ |= packed_ << (CURRENT_INDEX_BITS + i_ * SESSION_BITS);
            } else {
                data1_ |= packed_ << ((i_ - SESSIONS_PER_WORD) * SESSION_BITS);
            }
        }
    }
}
