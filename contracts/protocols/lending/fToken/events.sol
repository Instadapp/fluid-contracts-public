// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel } from "../interfaces/iLendingRewardsRateModel.sol";
import { IFluidLendingStaticRateModel } from "../interfaces/iLendingStaticRateModel.sol";

abstract contract Events {
    /// @notice ERC4626 event emitted on deposits; reused by permissioned fTokens that inherit the shared fToken core.
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice ERC4626 event emitted on withdrawals; reused by permissioned fTokens that inherit the shared fToken core.
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /// @notice emitted whenever admin updates rewards rate model
    event LogUpdateRewards(IFluidLendingRewardsRateModel indexed rewardsRateModel);

    /// @notice emitted whenever admin updates static rewards rate model
    event LogUpdateStaticRewards(IFluidLendingStaticRateModel indexed staticRateModel);

    /// @notice emitted whenever rebalance closes the gap between Liquidity supply and totalAssets().
    ///         Positive = rewards / deposit into Liquidity from the rebalancer (same direction as the legacy
    ///         absolute `uint256` amount on the deposit-only path); negative = fees / withdraw to the rebalancer;
    ///         zero = no-op. Magnitude is the absolute amount moved.
    event LogRebalance(int256 assets);

    /// @notice emitted whenever exchange rates are updated
    event LogUpdateRates(uint256 tokenExchangePrice, uint256 liquidityExchangePrice);

    /// @notice emitted whenever funds for a certain `token` are rescued to Liquidity
    event LogRescueFunds(address indexed token);

    /// @notice emitted whenever rebalancer address is updated
    event LogUpdateRebalancer(address indexed rebalancer);
}
