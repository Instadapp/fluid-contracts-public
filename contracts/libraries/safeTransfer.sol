// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.21 <=0.8.36;

import { LibsErrorTypes as ErrorTypes } from "./errorTypes.sol";

/// @notice Provides minimalistic methods for safe ERC20 and native token transfers.
/// @author Instadapp
library SafeTransfer {
    // pass max. 50k gas for native transfers. This ensures support for some realistic
    // scenarios like WETH deposits in receive() but as restrictive as possible.
    uint256 internal constant MAX_NATIVE_TRANSFER_GAS = 50000;

    error FluidSafeTransferError(uint256 errorId_);

    /// @dev Transfer `amount_` of `token_` from `from_` to `to_`, spending the approval given by `from_` to the
    /// calling contract. If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// @dev Calldata assembly aligned with Solady SafeTransferLib while preserving Fluid's return-data semantics.
    function safeTransferFrom(address token_, address from_, address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // 1:1 Solady SafeTransferLib.sol L257-L262:
            // https://github.com/Vectorized/solady/blob/acd959aa4bd04720d640bf4e6a5c71037510cc4b/src/utils/SafeTransferLib.sol#L257-L262
            let m := mload(0x40)
            mstore(0x60, amount_)
            mstore(0x40, to_)
            mstore(0x2c, shl(96, from_))
            mstore(0x0c, 0x23b872dd000000000000000000000000)
            success_ := call(gas(), token_, 0, 0x1c, 0x64, 0x00, 0x20)
            // Fluid's rule instead of Solady L263-L268: 1 in at least 32 bytes, or no data, without a code check
            success_ := and(success_, or(and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)), iszero(returndatasize())))
            // 1:1 Solady L269-L270:
            // https://github.com/Vectorized/solady/blob/acd959aa4bd04720d640bf4e6a5c71037510cc4b/src/utils/SafeTransferLib.sol#L269-L270
            mstore(0x60, 0)
            mstore(0x40, m)
        }

        if (!success_) {
            revert FluidSafeTransferError(ErrorTypes.SafeTransfer__TransferFromFailed);
        }
    }

    /// @dev Transfer `amount_` of `token_` to `to_`.
    /// If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// @dev Calldata assembly aligned with Solady SafeTransferLib while preserving Fluid's return-data semantics.
    function safeTransfer(address token_, address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // 1:1 Solady SafeTransferLib.sol L341-L345:
            // https://github.com/Vectorized/solady/blob/acd959aa4bd04720d640bf4e6a5c71037510cc4b/src/utils/SafeTransferLib.sol#L341-L345
            mstore(0x14, to_)
            mstore(0x34, amount_)
            mstore(0x00, 0xa9059cbb000000000000000000000000)
            success_ := call(gas(), token_, 0, 0x10, 0x44, 0x00, 0x20)
            // Fluid's rule instead of Solady L346-L351: 1 in at least 32 bytes, or no data, without a code check
            success_ := and(success_, or(and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)), iszero(returndatasize())))
            // 1:1 Solady L352:
            // https://github.com/Vectorized/solady/blob/acd959aa4bd04720d640bf4e6a5c71037510cc4b/src/utils/SafeTransferLib.sol#L352
            mstore(0x34, 0)
        }

        if (!success_) {
            revert FluidSafeTransferError(ErrorTypes.SafeTransfer__TransferFailed);
        }
    }

    /// @dev Transfer `amount_` of native token to `to_` with a limited gas stipend.
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
