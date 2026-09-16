// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IMaticXChildPool {
    /// @notice Converts an amount of MaticX shares to POL tokens.
    /// @param _balance - Balance in MaticX shares
    /// @return Balance in POL tokens
    /// @return Total MaticX shares
    /// @return Total pooled POL tokens
    function convertMaticXToMatic(uint256 _balance) external view returns (uint256, uint256, uint256);
}
