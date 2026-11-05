// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

/// @dev Shared US equity session-type values (`FluidUsEquityMarketHours` return codes).
abstract contract SessionTypes {
    uint256 internal constant SESSION_TYPE_UNKNOWN = 0;
    uint256 internal constant SESSION_TYPE_REGULAR = 1;
    uint256 internal constant SESSION_TYPE_EXTENDED = 2;
    uint256 internal constant SESSION_TYPE_HOLIDAY = 3;
}
