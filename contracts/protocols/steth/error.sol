// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Error {
    /// @notice general Custom error used for all contract specific errors with the `errorId_` param as error code.
    /// Look up the specific error code in the source code to find a better explanation of what went wrong (errors.sol).
    error StETHQueueError(uint256 errorId_);
}
