//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidLiquidityLogic } from "../../../liquidity/interfaces/iLiquidity.sol";
import { IFluidDexT1 } from "../../dex/interfaces/iDexT1.sol";

interface ILiquidityDexCommon is IFluidLiquidityLogic, IFluidDexT1 {
    /// @notice only importing IFluidLiquidityLogic as readFromStorage is also defined in iDexT1 as well so to avoid clashing
}
