// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { FallbackCLRSOracleL2 } from "./fallbackCLRSOracleL2.sol";
import { FallbackOracleImpl2 } from "../implementations/fallbackOracleImpl2.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title   Ratio of 2 Chainlink / Redstone Oracles (with fallback) for Layer 2 (with sequencer outage detection)
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          1. the price from a Chainlink price feed or a Redstone Oracle with one of them being used as main source and
///          the other one acting as a fallback if the main source fails for any reason. Reverts if fetched rate is 0.
///          2. set into ratio with another price fetched the same way.
///          I.e. it is possible to do Chainlink Oracle / Chainlink Oracle. E.g. wstETH per 1 weETH on a L2 via CL feeds.
contract Ratio2xFallbackCLRSOracleL2 is FluidOracleL2, FallbackOracleImpl2, FallbackCLRSOracleL2 {
    /// @notice                       sets the two CLRS oracle configs
    /// @param infoName_              Oracle identify helper name.
    /// @param cLRSParams1_           CLRS Fallback Oracle data for ratio dividend
    /// @param cLRSParams2_           CLRS Fallback Oracle data for ratio divisor
    /// @param sequencerUptimeFeed_   L2 sequencer uptime Chainlink feed
    constructor(
        string memory infoName_,
        FallbackCLRSOracleL2.CLRSConstructorParams memory cLRSParams1_,
        FallbackCLRSOracleL2.CLRSConstructorParams memory cLRSParams2_,
        address sequencerUptimeFeed_
    )
        FallbackCLRSOracleL2(infoName_, cLRSParams1_, sequencerUptimeFeed_)
        FallbackOracleImpl2(cLRSParams2_.mainSource, cLRSParams2_.chainlinkParams, cLRSParams2_.redstoneOracle)
    {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        override(FluidOracleL2, FallbackCLRSOracleL2)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate from FallbackOracleImpl2 for divisor (cLRSParams2_)
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.Ratio2xFallbackCLRSOracleL2__ExchangeRateZero);
        }

        // 2. get rate from FallbackCLRSOracleL2 (cLRSParams1_). This already checks and reverts in case of price being 0.
        //    (super.getExchangeRate returns FallbackCLRSOracleL2 rate, no other inherited contract has this.)
        //    includes _ensureSequencerUpAndValid();

        // 3. Setting into ratio cLRSParams1_ rate / cLRSParams2_ rate
        exchangeRate_ = (super.getExchangeRateOperate() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) / exchangeRate_;
        // e.g. FallbackCLRSOracleL2 configured to return weETH rate, _getRateWithFallback2 configured to return wstETH:
        // result is wstETH per weETH
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        override(FluidOracleL2, FallbackCLRSOracleL2)
        returns (uint256 exchangeRate_)
    {
        // 1. get CLRS Oracle rate from FallbackOracleImpl2 for divisor
        (exchangeRate_, ) = _getRateWithFallback2();
        if (exchangeRate_ == 0) {
            // revert if fetched exchange rate is 0
            revert FluidOracleError(ErrorTypes.Ratio2xFallbackCLRSOracleL2__ExchangeRateZero);
        }

        // 2. get rate from FallbackCLRSOracleL2. This already checks and reverts in case of price being 0.
        //    (super.getExchangeRate returns FallbackCLRSOracleL2 rate, no other inherited contract has this.)
        //    includes _ensureSequencerUpAndValid();
        exchangeRate_ = (super.getExchangeRateLiquidate() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) / exchangeRate_;
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        override(FluidOracleL2, FallbackCLRSOracleL2)
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
