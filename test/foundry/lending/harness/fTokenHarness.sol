//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

contract fTokenHarness is fToken {
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) fToken(liquidity_, lendingFactory_, asset_) {}

    function exposed_updateRates(uint256 liquidityExchangePrice_) external returns (uint256 tokenExchangePrice_) {
        return _updateRates(liquidityExchangePrice_, true);
    }

    function exposed_tokenExchangePrice() external view returns (uint64) {
        return _tokenExchangePrice;
    }

    function exposed_liquidityExchangePrice() external view returns (uint64) {
        return _liquidityExchangePrice;
    }

    function exposed_lastUpdateTimestamp() external view returns (uint40) {
        return _lastUpdateTimestamp;
    }

    function exposed_rewardsActive() external view returns (bool) {
        return _rewardsActive;
    }

    function liquidityCallback(
        address /* token_ */,
        uint256 /* amount_ */,
        bytes calldata /* data_ */
    ) external pure override {
        revert("Not implemented");
    }
}
