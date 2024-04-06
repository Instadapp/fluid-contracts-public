// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { FallbackOracleImpl } from "../implementations/fallbackOracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title   Chainlink / Redstone Oracle (with fallback)
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a Chainlink price feed or a Redstone Oracle with one of them being used as main source and
///          the other one acting as a fallback if the main source fails for any reason. Reverts if fetched rate is 0.
contract FallbackCLRSOracle is FluidOracle, FallbackOracleImpl {
    /// @notice                     sets the main source, Chainlink Oracle and Redstone Oracle data.
    /// @param mainSource_          which oracle to use as main source: 1 = Chainlink, 2 = Redstone (other one is fallback).
    /// @param chainlinkParams_     chainlink Oracle constructor params struct.
    /// @param redstoneOracle_      Redstone Oracle data. (address can be set to zero address if using Chainlink only)
    constructor(
        uint8 mainSource_,
        ChainlinkConstructorParams memory chainlinkParams_,
        RedstoneOracleData memory redstoneOracle_
    ) FallbackOracleImpl(mainSource_, chainlinkParams_, redstoneOracle_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getRateWithFallback();

        if (exchangeRate_ == 0) {
            revert FluidOracleError(ErrorTypes.FallbackCLRSOracle__ExchangeRateZero);
        }
    }

    /// @notice which oracle to use as main source:
    ///          - 1 = Chainlink ONLY (no fallback)
    ///          - 2 = Chainlink with Redstone Fallback
    ///          - 3 = Redstone with Chainlink Fallback
    function FALLBACK_ORACLE_MAIN_SOURCE() public view returns (uint8) {
        return _FALLBACK_ORACLE_MAIN_SOURCE;
    }
}
