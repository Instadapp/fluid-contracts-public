// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Error {
    /// @dev Thrown by vault oracle contracts (`VaultOracleBase`, `VaultT1Oracle`, …) and `VaultOracleFactory`.
    error FluidVaultOracleError(uint256 errorId_);
}
