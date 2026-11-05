// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Reality rtoken (ERC-8056) surface used for pricing and halts.
interface IRealityToken {
    /// @return 1e18 = 1x
    function uiMultiplier() external view returns (uint256);

    function paused() external view returns (bool);
}
