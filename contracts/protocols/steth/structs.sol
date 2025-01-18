// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
    /// @notice Claim data struct for storage link to owner address
    struct Claim {
        /// @param borrowAmountRaw raw borrow amount at Liquidity. Multiply with borrowExchangePrice to get normal borrow amount
        uint128 borrowAmountRaw;
        /// @param checkpoint checkpoint at time of queue. optimizes finding checkpoint hints range at claim time.
        uint48 checkpoint;
        /// @param requestIdTo last request Id linked to the claim
        uint40 requestIdTo;
        // 5 bytes empty
    }
}
