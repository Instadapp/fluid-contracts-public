// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.21 <=0.8.29;

import { LibsErrorTypes as ErrorTypes } from "./errorTypes.sol";

/// @notice provides minimalistic methods for safe approve, e.g. ERC20 safeApprove
library SafeApprove {
    error FluidSafeApproveError(uint256 errorId_);

    /// @dev Approve `amount_` of `token_` to `to_`.
    /// If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// Minimally modified from Solmate SafeTransferLib (address as input param for token, Custom Error):
    /// https://github.com/transmissions11/solmate/blob/50e15bb566f98b7174da9b0066126a4c3e75e0fd/src/utils/SafeTransferLib.sol#L97-L127
    function safeApprove(
        address token_,
        address to_,
        uint256 amount_
    ) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0x095ea7b300000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), and(to_, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to" argument.
            mstore(add(freeMemoryPointer, 36), amount_) // Append the "amount" argument. Masking not required as it's a full 32 byte type.

            // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
            // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
            success_ := call(gas(), token_, 0, freeMemoryPointer, 68, 0, 32)

            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data and token has code.
            if and(iszero(and(eq(mload(0), 1), gt(returndatasize(), 31))), success_) {
                success_ := iszero(or(iszero(extcodesize(token_)), returndatasize())) 
            }
        }

        if (!success_) {
            revert FluidSafeApproveError(ErrorTypes.SafeApprove__ApproveFailed);
        }
    }
}
