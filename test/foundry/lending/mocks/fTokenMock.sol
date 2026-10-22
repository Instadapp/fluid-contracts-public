//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

contract fTokenEIP2612Mock is fToken {
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) fToken(liquidity_, lendingFactory_, asset_) {}

    function updateRates(uint256 liquidityExchangePrice_) external returns (uint256 tokenExchangePrice_) {
        return _updateRates(liquidityExchangePrice_, false);
    }

    function getTokenExchangePrice() public view returns (uint256) {
        return _tokenExchangePrice;
    }
}
