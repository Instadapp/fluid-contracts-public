// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";

abstract contract Structs {
    struct Pool {
        address pool;
        address token0;
        address token1;
        uint256 fee;
    }

    struct PoolWithReserves {
        address pool;
        address token0;
        address token1;
        uint256 fee;
        uint256 centerPrice;
        IFluidDexT1.CollateralReserves collateralReserves;
        IFluidDexT1.DebtReserves debtReserves;
        DexLimits limits;
    }

    struct TokenLimit {
        // both `available` and `expandsTo` limits consider:
        // - max utilization (at Liquidity layer and at Dex, for withdrawable only dex)
        // - withdraw limits / borrow limits
        // - balances at liquidity layer
        uint256 available; // maximum available swap amount
        uint256 expandsTo; // maximum amount the available swap amount expands to
        uint256 expandDuration; // duration for `available` to grow to `expandsTo`
    }

    struct DexLimits {
        TokenLimit withdrawableToken0;
        TokenLimit withdrawableToken1;
        TokenLimit borrowableToken0;
        TokenLimit borrowableToken1;
    }
}
