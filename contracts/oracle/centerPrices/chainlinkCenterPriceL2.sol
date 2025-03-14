// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPriceL2 } from "../fluidCenterPriceL2.sol";
import { ChainlinkOracleImpl } from "../implementations/chainlinkOracleImpl.sol";
import { IFluidOracle } from "../interfaces/iFluidOracle.sol";

/// @title   ChainlinkCenterPriceL2
/// @notice  Gets the exchange rate between 2 tokens via Chainlink feeds for Layer 2 (with sequencer uptime feed check)
/// @dev     Also implements IFluidOracle interface
contract ChainlinkCenterPriceL2 is FluidCenterPriceL2, IFluidOracle, ChainlinkOracleImpl {
    /// @notice constructor sets the chainlink feeds config & L2 sequencer uptime feed
    constructor(
        string memory infoName_,
        ChainlinkOracleImpl.ChainlinkConstructorParams memory clParams_,
        address sequencerUptimeFeed_
    ) ChainlinkOracleImpl(clParams_) FluidCenterPriceL2(infoName_, sequencerUptimeFeed_) {}

    /// @inheritdoc FluidCenterPriceL2
    function centerPrice() external view override returns (uint256 price_) {
        _ensureSequencerUpAndValid();
        return _getChainlinkExchangeRate();
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
    function getExchangeRate() external view virtual returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return _getChainlinkExchangeRate();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() external view virtual returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return _getChainlinkExchangeRate();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() external view virtual returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return _getChainlinkExchangeRate();
    }
}
