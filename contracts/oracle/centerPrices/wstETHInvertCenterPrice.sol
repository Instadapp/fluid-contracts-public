// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPrice } from "../fluidCenterPrice.sol";
import { WstETHInvertOracleImpl } from "../implementations/wstETHInvertOracleImpl.sol";
import { IWstETH } from "../interfaces/external/IWstETH.sol";

/// @title   WstETHInvertCenterPrice
/// @notice  Gets the exchange rate between wstETH and stETH directly from the wstETH contract: wstETH per stETH.
contract WstETHInvertCenterPrice is FluidCenterPrice, WstETHInvertOracleImpl {
    /// @notice constructor sets the wstETH `wstETH_` token address.
    constructor(string memory infoName_, IWstETH wstETH_) WstETHInvertOracleImpl(wstETH_) FluidCenterPrice(infoName_) {}

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external view override returns (uint256 price_) {
        return _getWstETHExchangeRate();
    }
}
