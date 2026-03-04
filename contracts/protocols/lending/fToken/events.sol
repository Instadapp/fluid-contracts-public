// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel  } from "../interfaces/iLendingRewardsRateModel.sol";

abstract contract Events {
    /// @notice emitted whenever admin updates rewards rate model
    event LogUpdateRewards(IFluidLendingRewardsRateModel  indexed rewardsRateModel);

    /// @notice emitted whenever rebalance is executed to fund difference between Liquidity deposit and totalAssets()
    ///         as rewards through the rebalancer.
    event LogRebalance(uint256 assets);

    /// @notice emitted whenever exchange rates are updated
    event LogUpdateRates(uint256 tokenExchangePrice, uint256 liquidityExchangePrice);

    /// @notice emitted whenever funds for a certain `token` are rescued to Liquidity
    event LogRescueFunds(address indexed token);

    /// @notice emitted whenever rebalancer address is updated
    event LogUpdateRebalancer(address indexed rebalancer);
}
