//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidStETHQueue } from "../../../contracts/protocols/steth/main.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { ILidoWithdrawalQueue } from "../../../contracts/protocols/steth/interfaces/external/iLidoWithdrawalQueue.sol";

contract FluidStETHQueueExposed is FluidStETHQueue {
    constructor(
        IFluidLiquidity liquidity_,
        ILidoWithdrawalQueue lidoWithdrawalQueue_,
        IERC20 stETH_
    ) FluidStETHQueue(liquidity_, lidoWithdrawalQueue_, stETH_) {}

    function exposed_status() external view returns (uint8) {
        return _status;
    }
}
