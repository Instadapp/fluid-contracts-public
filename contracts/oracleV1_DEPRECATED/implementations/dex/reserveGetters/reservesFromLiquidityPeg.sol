// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { DexReservesFromLiquidity } from "./reservesFromLiquidity.sol";
import { ErrorTypes } from "../../../errorTypes.sol";

/// @notice reads the dex reserves directly from Liquidity (user supply / user debt) and adds a certain % buffer.
abstract contract DexReservesFromLiquidityPeg is DexReservesFromLiquidity {
    /// @dev if Dex is e.g. USDC / USDT a peg can be assumed instead of fetching the price
    /// at the Dex Oracle (which might not even be active in such a case). If so, this var
    /// defines the peg buffer to reduce collateral value (and increase debt value) by some
    /// defined percentage for safety handling of price ranges.
    /// in 1e4: 10000 = 1%, 1000000 = 100%
    uint256 public immutable RESERVES_PEG_BUFFER_PERCENT;

    constructor(
        address dexPool_,
        bool quoteInToken0_,
        uint256 reservesPegBufferPercent_
    ) DexReservesFromLiquidity(dexPool_, quoteInToken0_) {
        if (reservesPegBufferPercent_ == 0) {
            revert FluidOracleError(ErrorTypes.DexOracle__InvalidParams);
        }
        RESERVES_PEG_BUFFER_PERCENT = reservesPegBufferPercent_;
    }

    /// @inheritdoc DexReservesFromLiquidity
    function _getDexCollateralReserves()
        internal
        view
        override
        returns (uint256 token0Reserves_, uint256 token1Reserves_)
    {
        (token0Reserves_, token1Reserves_) = super._getDexCollateralReserves();

        // reduce col value by peg buffer percent
        token0Reserves_ = (token0Reserves_ * (1e6 - RESERVES_PEG_BUFFER_PERCENT)) / 1e6;
        token1Reserves_ = (token1Reserves_ * (1e6 - RESERVES_PEG_BUFFER_PERCENT)) / 1e6;
    }

    /// @inheritdoc DexReservesFromLiquidity
    function _getDexDebtReserves() internal view override returns (uint256 token0Reserves_, uint256 token1Reserves_) {
        (token0Reserves_, token1Reserves_) = super._getDexDebtReserves();

        // increase debt value by peg buffer percent
        token0Reserves_ = (token0Reserves_ * (1e6 + RESERVES_PEG_BUFFER_PERCENT)) / 1e6;
        token1Reserves_ = (token1Reserves_ * (1e6 + RESERVES_PEG_BUFFER_PERCENT)) / 1e6;
    }
}
