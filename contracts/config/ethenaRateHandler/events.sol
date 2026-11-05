// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice emitted when borrow magnifier is updated at vault
    event LogUpdateBorrowRateMagnifier(uint256 oldMagnifier, uint256 newMagnifier);
}
