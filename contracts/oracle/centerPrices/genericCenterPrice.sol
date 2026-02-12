// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPrice } from "../fluidCenterPrice.sol";
import { FluidGenericOracleBase } from "../oracles/genericOracleBase.sol";
import { IFluidOracle } from "../interfaces/iFluidOracle.sol";

/// @title   FluidGenericCenterPrice
/// @notice  Gets the exchange rate between 2 tokens via GenericOracle feeds for a Dex center price
/// @dev     Also implements IFluidOracle interface
contract FluidGenericCenterPrice is FluidCenterPrice, IFluidOracle, FluidGenericOracleBase {
    constructor(
        string memory infoName_,
        OracleHopSource[] memory sources_
    ) FluidCenterPrice(infoName_) FluidGenericOracleBase(sources_) {}

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external view override returns (uint256 price_) {
        price_ = _getHopsExchangeRate(true);
    }

    /// @inheritdoc FluidCenterPrice
    function infoName() public view override(IFluidOracle, FluidCenterPrice) returns (string memory) {
        return super.infoName();
    }

    /// @inheritdoc FluidCenterPrice
    function targetDecimals() public pure override(IFluidOracle, FluidCenterPrice) returns (uint8) {
        return super.targetDecimals();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(true);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }
}
