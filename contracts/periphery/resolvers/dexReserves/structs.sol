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
        IFluidDexT1.CollateralReserves collateralReserves;
        IFluidDexT1.DebtReserves debtReserves;
    }
}
