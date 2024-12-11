// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { WeETHOracleImpl } from "../implementations/weETHOracleImpl.sol";
import { IWeETH } from "../interfaces/external/IWeETH.sol";

/// @title   WeETHOracle
/// @notice  Gets the exchange rate between weETH and eETH directly from the weETH contract.
contract WeETHOracle is FluidOracle, WeETHOracleImpl {
    /// @notice constructor sets the weETH `weETH_` token address.
    constructor(string memory infoName_, IWeETH weETH_) WeETHOracleImpl(weETH_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        return _getWeETHExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        return _getWeETHExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
