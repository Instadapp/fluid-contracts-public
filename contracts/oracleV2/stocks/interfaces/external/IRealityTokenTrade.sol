// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Reality's `RWATokenTrade` primary-market contract; flags an rtoken while a corporate action is processed.
interface IRealityTokenTrade {
    function tradePaused(address token_) external view returns (bool);
}
