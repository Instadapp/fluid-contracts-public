// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Structs } from "./poolT1/coreModule/structs.sol";

abstract contract Error {
    error FluidDexError(uint256 errorId_);

    error FluidDexFactoryError(uint256 errorId);

    /// @notice used to simulate swap to find the output amount
    error FluidDexSwapResult(uint256 amountOut);

    error FluidDexPerfectLiquidityOutput(uint256 token0Amt, uint token1Amt);

    error FluidDexSingleTokenOutput(uint256 tokenAmt);

    error FluidDexLiquidityOutput(uint256 shares_);

    error FluidDexPricesAndExchangeRates(Structs.PricesAndExchangePrice pex_);

    error FluidSmartLendingError(uint256 errorId_);

    error FluidSmartLendingFactoryError(uint256 errorId_);
}
