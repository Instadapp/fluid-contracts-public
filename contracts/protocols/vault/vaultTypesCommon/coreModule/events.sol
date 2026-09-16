// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice emitted when an operate() method is executed that changes collateral (`colAmt_`) / debt (debtAmt_`)
    /// amount for a `user_` position with `nftId_`. Receiver of any funds is the address `to_`.
    event LogOperate(address user_, uint256 nftId_, int256 colAmt_, int256 debtAmt_, address to_);

    /// @notice emitted when the exchange prices are updated in storage.
    event LogUpdateExchangePrice(uint256 supplyExPrice_, uint256 borrowExPrice_);

    /// @notice emitted when a liquidation has been executed.
    event LogLiquidate(address liquidator_, uint256 colAmt_, uint256 debtAmt_, address to_);

    /// @notice emitted when `absorb()` was executed to absorb bad debt.
    event LogAbsorb(uint colAbsorbedRaw_, uint debtAbsorbedRaw_);

    /// @notice emitted when a `rebalance()` has been executed, balancing out total supply / borrow between Vault
    /// and Fluid Liquidity pools.
    /// if `colAmt_` is positive then loss, meaning transfer from rebalancer address to vault and deposit.
    /// if `colAmt_` is negative then profit, meaning withdrawn from vault and sent to rebalancer address.
    /// if `debtAmt_` is positive then profit, meaning borrow from vault and sent to rebalancer address.
    /// if `debtAmt_` is negative then loss, meaning transfer from rebalancer address to vault and payback.
    event LogRebalance(int colAmt_, int debtAmt_);
}
