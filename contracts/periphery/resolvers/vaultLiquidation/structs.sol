// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Structs {
    struct SwapPath {
        ///
        /// @param protocol vault address at which the token pair is available
        address protocol;
        ///
        /// @param tokenIn input token, borrow token at the vault
        address tokenIn;
        ///
        /// @param tokenOut output token, collateral token at the vault
        address tokenOut;
    }

    struct SwapData {
        ///
        /// @param inAmt total input token amount
        uint256 inAmt;
        ///
        /// @param outAmt total output token amount received
        uint256 outAmt;
        ///
        /// @param withAbsorb flag for using mode "withAbsorb" when calling liquidate() on the Vault.
        ///                   Is set to true if a) liquidity without absorb would not
        ///                   cover the desired `inAmt_` or if b) the rate of with absorb is better than without absorb.
        bool withAbsorb;
        ///
        /// @param ratio ratio of outAmt / inAmt scaled by 1e27
        uint256 ratio;
    }

    struct Swap {
        ///
        /// @param path swap path struct info such as protocol where the swap is available
        SwapPath path;
        ///
        /// @param data swap data struct info such as amounts
        SwapData data;
    }
}
