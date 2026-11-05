// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.21 <=0.8.36;

import { LibsErrorTypes as ErrorTypes } from "./errorTypes.sol";

/// @notice Provides a minimalistic method for safe ERC20 approvals.
/// @author Instadapp
library SafeApprove {
    error FluidSafeApproveError(uint256 errorId_);

    /// @dev Approve `amount_` of `token_` to `to_`.
    /// If `token_` returns no value, non-reverting calls are assumed to be successful.
    /// @dev Assembly aligned with Solady SafeTransferLib.
    function safeApprove(address token_, address to_, uint256 amount_) internal {
        bool success_;

        /// @solidity memory-safe-assembly
        assembly {
            // 1:1 Solady SafeTransferLib.sol L393-L403, keeping the result at L398 instead of reverting at L399-L400:
            // https://github.com/Vectorized/solady/blob/acd959aa4bd04720d640bf4e6a5c71037510cc4b/src/utils/SafeTransferLib.sol#L393-L403
            mstore(0x14, to_)
            mstore(0x34, amount_)
            mstore(0x00, 0x095ea7b3000000000000000000000000)
            success_ := call(gas(), token_, 0, 0x10, 0x44, 0x00, 0x20)
            if iszero(and(eq(mload(0x00), 1), success_)) {
                success_ := lt(or(iszero(extcodesize(token_)), returndatasize()), success_)
            }
            mstore(0x34, 0)
        }

        if (!success_) {
            revert FluidSafeApproveError(ErrorTypes.SafeApprove__ApproveFailed);
        }
    }
}
