// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPriceL2 } from "../fluidCenterPriceL2.sol";
import { FluidGenericOracleBase } from "../oracles/genericOracleBase.sol";
import { IFluidOracle } from "../interfaces/iFluidOracle.sol";

/// @title   FluidGenericCenterPriceL2
/// @notice  Gets the exchange rate between 2 tokens via GenericOracle feeds for a Dex center price for Layer 2 (with sequencer uptime feed check)
/// @dev     Also implements IFluidOracle interface
contract FluidGenericCenterPriceL2 is FluidCenterPriceL2, IFluidOracle, FluidGenericOracleBase {
    constructor(
        string memory infoName_,
        OracleHopSource[] memory sources_,
        address sequencerUptimeFeed_
    ) FluidCenterPriceL2(infoName_, sequencerUptimeFeed_) FluidGenericOracleBase(sources_) {}

    /// @inheritdoc FluidCenterPriceL2
    function centerPrice() external view override returns (uint256 price_) {
        price_ = _getHopsExchangeRate(true);
    }

    /// @inheritdoc FluidCenterPriceL2
    function infoName() public view override(IFluidOracle, FluidCenterPriceL2) returns (string memory) {
        return super.infoName();
    }

    /// @inheritdoc FluidCenterPriceL2
    function targetDecimals() public pure override(IFluidOracle, FluidCenterPriceL2) returns (uint8) {
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
