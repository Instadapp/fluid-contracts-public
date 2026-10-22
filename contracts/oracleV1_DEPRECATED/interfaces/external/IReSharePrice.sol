// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/// @notice Interface for Re Protocol Share Price Calculator (e.g. 0xd1d104a7515989ac82f1afda15a23650411b05b8).
/// @dev Returns current share price scaled by 1e18.
interface IReSharePrice {
    /// @notice Returns the current share price
    /// @return Current share price scaled by 1e18
    function getSharePrice() external view returns (uint256);
}
