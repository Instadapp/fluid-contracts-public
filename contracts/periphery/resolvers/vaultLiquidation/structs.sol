// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Structs {
    struct VaultData{
        ///
        /// @param vault vault address at which the token pair is available
        address vault;
        ///
        /// @param tokenIn input token, borrow token at the vault
        address tokenIn;
        ///
        /// @param tokenOut output token, collateral token at the vault
        address tokenOut;
    }

    struct SwapData {
        ///
        /// @param vault vault address at which the token pair is available
        address vault;
        ///
        /// @param inAmt total input token available amount (without absorb)
        uint256 inAmt;
        ///
        /// @param outAmt total output token amount received for `inAmt` (without absorb)
        uint256 outAmt;
        ///
        /// @param inAmtWithAbsorb total input token available amount (with absorb)
        uint256 inAmtWithAbsorb;
        ///
        /// @param outAmtWithAbsorb total output token amount received for `inAmtWithAbsorb` (with absorb)
        uint256 outAmtWithAbsorb;
    }
}
