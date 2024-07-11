// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { UniV3CheckCLRSOracle } from "./uniV3CheckCLRSOracle.sol";
import { WstETHOracleImpl } from "../implementations/wstETHOracleImpl.sol";
import { FallbackOracleImpl2 } from "../implementations/fallbackOracleImpl2.sol";
import { IWstETH } from "../interfaces/external/IWstETH.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { ErrorTypes } from "../errorTypes.sol";

// @dev uses FallbackOracleImpl2 to avoid conflicts with already used ChainlinkOracleImpl, RedstoneOracleImpl and
// FallbackOracleImpl in UniV3CheckCLRSOracle.

/// @title   wstETHCLRSOracle combined with a uniV3CheckCLRSOracle.
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          1. wstETH Oracle price in combination with rate from Chainlink price feeds (or Redstone as fallback).
///             combining those two into one rate resulting in wstETH <> someToken
///          2. result from 1. combined with a uniV3CheckCLRSOracle to get from someToken <> someToken2
///          e.g. when going from wstETH to USDC:
///          1. wstETH -> stETH wstETH Oracle, stETH -> ETH Chainlink feed.
///          2. ETH -> USDC via UniV3 ETH <> USDC pool checked against ETH -> USDC Chainlink feed.
contract WstETHCLRS2UniV3CheckCLRSOracle is FluidOracle, WstETHOracleImpl, FallbackOracleImpl2, UniV3CheckCLRSOracle {
    struct WstETHCLRS2ConstructorParams {
        /// @param wstETH                         address of the wstETH contract
        IWstETH wstETH;
        /// @param fallbackMainSource             which oracle to use as main source for wstETH <> CLRS: 1 = Chainlink, 2 = Redstone (other one is fallback).
        uint8 fallbackMainSource;
        /// @param chainlinkParams                chainlink Oracle constructor params struct for wstETH <> CLRS.
        ChainlinkConstructorParams chainlinkParams;
        /// @param redstoneOracle                 Redstone Oracle data for wstETH <> CLRS. (address can be set to zero address if using Chainlink only)
        RedstoneOracleData redstoneOracle;
    }

    /// @notice                       constructs a WstETHCLRS2UniV3CheckCLRSOracle with all inherited contracts
    /// @param infoName_         Oracle identify helper name.
    /// @param wstETHCLRS2Params_    WstETHCLRS2ConstructorParams for wstETH <> CLRS Token2 conversion
    /// @param uniV3CheckCLRSParams_ UniV3CheckCLRSOracle constructor params
    constructor(
        string memory infoName_,
        WstETHCLRS2ConstructorParams memory wstETHCLRS2Params_,
        UniV3CheckCLRSConstructorParams memory uniV3CheckCLRSParams_
    )
        WstETHOracleImpl(wstETHCLRS2Params_.wstETH)
        FallbackOracleImpl2(
            wstETHCLRS2Params_.fallbackMainSource,
            wstETHCLRS2Params_.chainlinkParams,
            wstETHCLRS2Params_.redstoneOracle
        )
        UniV3CheckCLRSOracle(infoName_, uniV3CheckCLRSParams_)
    {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate()
        public
        view
        override(FluidOracle, UniV3CheckCLRSOracle)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate for stETH <> CLRS feed. uses FallbackOracleImpl2
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.WstETHCLRS2UniV3CheckCLRSOracle__ExchangeRateZero);
        }

        // 2. combine CLRS feed price with wstETH price to have wstETH <> stETH <> SomeToken fully converted
        exchangeRate_ = (_getWstETHExchangeRate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);

        // 3. get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0. Combine this rate with existing.
        //    (super.getExchangeRate returns UniV3CheckCLRSOracle rate, no other inherited contract has this.)
        exchangeRate_ = (super.getExchangeRateOperate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate()
        public
        view
        override(FluidOracle, UniV3CheckCLRSOracle)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate for stETH <> CLRS feed. uses FallbackOracleImpl2
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.WstETHCLRS2UniV3CheckCLRSOracle__ExchangeRateZero);
        }

        // 2. combine CLRS feed price with wstETH price to have wstETH <> stETH <> SomeToken fully converted
        exchangeRate_ = (_getWstETHExchangeRate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);

        // 3. get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0. Combine this rate with existing.
        //    (super.getExchangeRate returns UniV3CheckCLRSOracle rate, no other inherited contract has this.)
        exchangeRate_ = (super.getExchangeRateLiquidate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view override(FluidOracle, UniV3CheckCLRSOracle) returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @notice which oracle to use as main source:
    ///          - 1 = Chainlink ONLY (no fallback)
    ///          - 2 = Chainlink with Redstone Fallback
    ///          - 3 = Redstone with Chainlink Fallback
    function FALLBACK_ORACLE2_MAIN_SOURCE() public view returns (uint8) {
        return _FALLBACK_ORACLE2_MAIN_SOURCE;
    }
}
