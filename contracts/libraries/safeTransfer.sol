// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import { LibsErrorTypes as ErrorTypes } from "./errorTypes.sol";

/// @notice provides minimalistic methods for safe transfers, e.g. ERC20 safeTransferFrom
library SafeTransfer {
    uint256 internal constant MAX_NATIVE_TRANSFER_GAS = 20000; // pass max. 20k gas for native transfers

    error FluidSafeTransferError(uint256 errorId_);

    /// @dev Transfer `amount_` of `token_` from `from_` to `to_`, spending the approval given by `from_` to the
    /// calling contract. If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// Minimally modified from Solmate SafeTransferLib (address as input param for token, Custom Error):
    /// https://github.com/transmissions11/solmate/blob/50e15bb566f98b7174da9b0066126a4c3e75e0fd/src/utils/SafeTransferLib.sol#L31-L63
    function safeTransferFrom(address token_, address from_, address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), and(from_, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "from_" argument.
            mstore(add(freeMemoryPointer, 36), and(to_, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to_" argument.
            mstore(add(freeMemoryPointer, 68), amount_) // Append the "amount_" argument. Masking not required as it's a full 32 byte type.

            success_ := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 100 because the length of our calldata totals up like so: 4 + 32 * 3.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token_, 0, freeMemoryPointer, 100, 0, 32)
            )
        }

        if (!success_) {
            revert FluidSafeTransferError(ErrorTypes.SafeTransfer__TransferFromFailed);
        }
    }

    /// @dev Transfer `amount_` of `token_` to `to_`.
    /// If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// Minimally modified from Solmate SafeTransferLib (address as input param for token, Custom Error):
    /// https://github.com/transmissions11/solmate/blob/50e15bb566f98b7174da9b0066126a4c3e75e0fd/src/utils/SafeTransferLib.sol#L65-L95
    function safeTransfer(address token_, address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), and(to_, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to_" argument.
            mstore(add(freeMemoryPointer, 36), amount_) // Append the "amount_" argument. Masking not required as it's a full 32 byte type.

            success_ := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token_, 0, freeMemoryPointer, 68, 0, 32)
            )
        }

        if (!success_) {
            revert FluidSafeTransferError(ErrorTypes.SafeTransfer__TransferFailed);
        }
    }

    /// @dev Transfer `amount_` of ` native token to `to_`.
    /// Minimally modified from Solmate SafeTransferLib (Custom Error):
    /// https://github.com/transmissions11/solmate/blob/50e15bb566f98b7174da9b0066126a4c3e75e0fd/src/utils/SafeTransferLib.sol#L15-L25
    function safeTransferNative(address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the ETH and store if it succeeded or not. Pass limited gas
            success_ := call(MAX_NATIVE_TRANSFER_GAS, to_, amount_, 0, 0, 0, 0)
        }

        if (!success_) {
            revert FluidSafeTransferError(ErrorTypes.SafeTransfer__TransferFailed);
        }
    }
}
