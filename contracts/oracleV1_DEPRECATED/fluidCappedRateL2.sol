// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCappedRateBase } from "./fluidCappedRate.sol";
import { IFluidOracle } from "./interfaces/iFluidOracle.sol";
import { IFluidCappedRate } from "./interfaces/iFluidCappedRate.sol";
import { FluidCenterPriceL2 } from "./fluidCenterPriceL2.sol";

/// @notice This contract stores an exchange rate in intervals to optimize gas cost for an L2
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
abstract contract FluidCappedRateL2 is FluidCappedRateBase, FluidCenterPriceL2 {
    constructor(
        CappedRateConstructorParams memory params_,
        address sequencerUptimeFeed_
    ) FluidCappedRateBase(params_) FluidCenterPriceL2(params_.infoName, sequencerUptimeFeed_) {}

    /// @inheritdoc FluidCenterPriceL2
    function centerPrice() external override(IFluidCappedRate, FluidCenterPriceL2) returns (uint256 price_) {
        _ensureSequencerUpAndValid();

        // for centerPrice -> no up cap, no down cap
        Slot0 memory slot0_ = _slot0;
        if (_isHeartbeatTrigger(slot0_)) {
            return _updateRates(true);
        }

        return uint256(slot0_.rate);
    }

    /// @inheritdoc FluidCenterPriceL2
    function infoName() public view override(IFluidOracle, FluidCenterPriceL2) returns (string memory) {
        return super.infoName();
    }

    /// @inheritdoc IFluidOracle
    function targetDecimals() public pure override(IFluidOracle, FluidCenterPriceL2) returns (uint8) {
        return _TARGET_DECIMALS;
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRate();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc IFluidCappedRate
    function getExchangeRateOperateDebt() public view virtual override returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperateDebt();
    }

    /// @inheritdoc IFluidCappedRate
    function getExchangeRateLiquidateDebt() public view virtual override returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidateDebt();
    }
}
