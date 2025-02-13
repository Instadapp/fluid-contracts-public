// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { UniV3CheckCLRSOracleL2 } from "./uniV3CheckCLRSOracleL2.sol";
import { WstETHOracleImpl } from "../implementations/wstETHOracleImpl.sol";
import { FallbackOracleImpl2 } from "../implementations/fallbackOracleImpl2.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { ErrorTypes } from "../errorTypes.sol";

// @dev uses FallbackOracleImpl2 to avoid conflicts with already used ChainlinkOracleImpl, RedstoneOracleImpl and
// FallbackOracleImpl in UniV3CheckCLRSOracle.

/// @title   CLRSOracle combined with a uniV3CheckCLRSOracle.
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          1. rate from Chainlink price feeds (or Redstone as fallback).
///          2. result from 1. combined with a uniV3CheckCLRSOracle to get from someToken <> someToken2
///          e.g. when going from wstETH to USDC:
///          1. wstETH -> stETH -> ETH Chainlink feed.
///          2. ETH -> USDC via UniV3 ETH <> USDC pool checked against ETH -> USDC Chainlink feed.
contract CLRS2UniV3CheckCLRSOracleL2 is FluidOracleL2, FallbackOracleImpl2, UniV3CheckCLRSOracleL2 {
    struct CLRS2ConstructorParams {
        /// @param fallbackMainSource             which oracle to use as main source for wstETH <> CLRS: 1 = Chainlink, 2 = Redstone (other one is fallback).
        uint8 fallbackMainSource;
        /// @param chainlinkParams                chainlink Oracle constructor params struct for wstETH <> CLRS.
        ChainlinkConstructorParams chainlinkParams;
        /// @param redstoneOracle                 Redstone Oracle data for wstETH <> CLRS. (address can be set to zero address if using Chainlink only)
        RedstoneOracleData redstoneOracle;
    }

    /// @notice                      constructs a CLRS2UniV3CheckCLRSOracleL2 with all inherited contracts
    /// @param infoName_             Oracle identify helper name.
    /// @param cLRS2Params_          CLRS2ConstructorParams for wstETH <> CLRS Token2 conversion
    /// @param uniV3CheckCLRSParams_ UniV3CheckCLRSOracle constructor params
    /// @param sequencerUptimeFeed_  L2 sequencer uptime Chainlink feed
    constructor(
        string memory infoName_,
        CLRS2ConstructorParams memory cLRS2Params_,
        UniV3CheckCLRSConstructorParams memory uniV3CheckCLRSParams_,
        address sequencerUptimeFeed_
    )
        FallbackOracleImpl2(cLRS2Params_.fallbackMainSource, cLRS2Params_.chainlinkParams, cLRS2Params_.redstoneOracle)
        UniV3CheckCLRSOracleL2(infoName_, uniV3CheckCLRSParams_, sequencerUptimeFeed_)
    {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(FluidOracleL2, UniV3CheckCLRSOracleL2)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate for wstETH <> CLRS feed. uses FallbackOracleImpl2
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.CLRS2UniV3CheckCLRSOracleL2__ExchangeRateZero);
        }

        // 2. get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0. Combine this rate with existing.
        //    (super.getExchangeRate returns UniV3CheckCLRSOracleL2 rate, no other inherited contract has this.)
        //    includes _ensureSequencerUpAndValid();
        exchangeRate_ = (super.getExchangeRateOperate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(FluidOracleL2, UniV3CheckCLRSOracleL2)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate for wstETH <> CLRS feed. uses FallbackOracleImpl2
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.CLRS2UniV3CheckCLRSOracleL2__ExchangeRateZero);
        }

        // 2. get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0. Combine this rate with existing.
        //    (super.getExchangeRate returns UniV3CheckCLRSOracleL2 rate, no other inherited contract has this.)
        //    includes _ensureSequencerUpAndValid();
        exchangeRate_ = (super.getExchangeRateLiquidate() * exchangeRate_) / (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        override(FluidOracleL2, UniV3CheckCLRSOracleL2)
        returns (uint256 exchangeRate_)
    {
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
