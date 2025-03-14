// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { FallbackCLRSOracle } from "../oracles/fallbackCLRSOracle.sol";

/// @DEV DEPRECATED. USE GENERIC ORACLE INSTEAD. WILL BE REMOVED SOON.

/// @title   Chainlink / Redstone Oracle (with fallback) for Layer 2 (with sequencer outage detection)
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a Chainlink price feed or a Redstone Oracle with one of them being used as main source and
///          the other one acting as a fallback if the main source fails for any reason. Reverts if fetched rate is 0.
contract FallbackCLRSOracleL2 is FluidOracleL2, FallbackCLRSOracle {
    struct CLRSConstructorParams {
        /// @param mainSource                     which oracle to use as main source for wstETH <> CLRS: 1 = Chainlink, 2 = Redstone (other one is fallback).
        uint8 mainSource;
        /// @param chainlinkParams                chainlink Oracle constructor params struct for wstETH <> CLRS.
        ChainlinkConstructorParams chainlinkParams;
        /// @param redstoneOracle                 Redstone Oracle data for wstETH <> CLRS. (address can be set to zero address if using Chainlink only)
        RedstoneOracleData redstoneOracle;
    }

    /// @notice                       sets the main source, Chainlink Oracle and Redstone Oracle data.
    /// @param infoName_              Oracle identify helper name.
    /// @param cLRSParams_            CLRS Fallback Oracle data
    /// @param sequencerUptimeFeed_   L2 sequencer uptime Chainlink feed
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        CLRSConstructorParams memory cLRSParams_,
        address sequencerUptimeFeed_
    )
        FallbackCLRSOracle(
            infoName_,
            targetDecimals_,
            cLRSParams_.mainSource,
            cLRSParams_.chainlinkParams,
            cLRSParams_.redstoneOracle
        )
        FluidOracleL2(sequencerUptimeFeed_)
    {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        virtual
        override(FallbackCLRSOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate()
        public
        view
        virtual
        override(FallbackCLRSOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate()
        public
        view
        virtual
        override(FallbackCLRSOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
