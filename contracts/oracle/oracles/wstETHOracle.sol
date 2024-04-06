// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { WstETHOracleImpl } from "../implementations/wstETHOracleImpl.sol";
import { IWstETH } from "../interfaces/external/IWstETH.sol";

/// @title   WstETHOracle
/// @notice  Gets the exchange rate between wstETH and stETH directly from the wstETH contract.
contract WstETHOracle is FluidOracle, WstETHOracleImpl {
    /// @notice constructor sets the wstETH `wstETH_` token address.
    constructor(IWstETH wstETH_) WstETHOracleImpl(wstETH_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return _getWstETHExchangeRate();
    }
}
