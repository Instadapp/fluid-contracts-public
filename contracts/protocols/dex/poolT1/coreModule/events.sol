// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice Emitted on token swaps
    /// @param swap0to1 Indicates whether the swap is from token0 to token1 or vice-versa.
    /// @param amountIn The amount of tokens to be sent to the vault to swap.
    /// @param amountOut The amount of tokens user got from the swap.
    /// @param to Recepient of swapped tokens.
    event Swap(bool swap0to1, uint256 amountIn, uint256 amountOut, address to);

    /// @notice Emitted when liquidity is added with shares specified.
    /// @param shares Expected exact shares to be received.
    /// @param token0Amt Amount of token0 deposited.
    /// @param token0Amt Amount of token1 deposited.
    event LogDepositPerfectColLiquidity(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when liquidity is withdrawn with shares specified.
    /// @param shares shares burned
    /// @param token0Amt Amount of token0 withdrawn.
    /// @param token1Amt Amount of token1 withdrawn.
    event LogWithdrawPerfectColLiquidity(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when liquidity is borrowed with shares specified.
    /// @param shares shares minted
    /// @param token0Amt Amount of token0 borrowed.
    /// @param token1Amt Amount of token1 borrowed.
    event LogBorrowPerfectDebtLiquidity(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when liquidity is paid back with shares specified.
    /// @param shares shares burned
    /// @param token0Amt Amount of token0 paid back.
    /// @param token1Amt Amount of token1 paid back.
    event LogPaybackPerfectDebtLiquidity(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when liquidity is deposited with specified token0 & token1 amount
    /// @param amount0 Amount of token0 deposited.
    /// @param amount1 Amount of token1 deposited.
    /// @param shares Amount of shares minted.
    event LogDepositColLiquidity(uint amount0, uint amount1, uint shares);

    /// @notice Emitted when liquidity is withdrawn with specified token0 & token1 amount
    /// @param amount0 Amount of token0 withdrawn.
    /// @param amount1 Amount of token1 withdrawn.
    /// @param shares Amount of shares burned.
    event LogWithdrawColLiquidity(uint amount0, uint amount1, uint shares);

    /// @notice Emitted when liquidity is borrowed with specified token0 & token1 amount
    /// @param amount0 Amount of token0 borrowed.
    /// @param amount1 Amount of token1 borrowed.
    /// @param shares Amount of shares minted.
    event LogBorrowDebtLiquidity(uint amount0, uint amount1, uint shares);

    /// @notice Emitted when liquidity is paid back with specified token0 & token1 amount
    /// @param amount0 Amount of token0 paid back.
    /// @param amount1 Amount of token1 paid back.
    /// @param shares Amount of shares burned.
    event LogPaybackDebtLiquidity(uint amount0, uint amount1, uint shares);

    /// @notice Emitted when liquidity is withdrawn with shares specified into one token only.
    /// @param shares shares burned
    /// @param token0Amt Amount of token0 withdrawn.
    /// @param token1Amt Amount of token1 withdrawn.
    event LogWithdrawColInOneToken(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when liquidity is paid back with shares specified from one token only.
    /// @param shares shares burned
    /// @param token0Amt Amount of token0 paid back.
    /// @param token1Amt Amount of token1 paid back.
    event LogPaybackDebtInOneToken(uint shares, uint token0Amt, uint token1Amt);

    /// @notice Emitted when internal arbitrage between 2 pools happen
    /// @param routing if positive then routing is amtIn of token0 in deposit & borrow else token0 withdraw & payback
    /// @param amtOut if routing is positive then token1 withdraw & payback amount else token1 deposit & borrow
    event LogArbitrage(int routing, uint amtOut);
}
