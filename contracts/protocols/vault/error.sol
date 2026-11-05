// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Error {
    error FluidVaultError(uint256 errorId_);

    /// @notice used to simulate liquidation to find the maximum liquidatable amounts
    error FluidLiquidateResult(uint256 colLiquidated, uint256 debtLiquidated);
}
