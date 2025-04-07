// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { UniV3CheckCLRSOracle } from "../oracles/uniV3CheckCLRSOracle.sol";

/// @DEV DEPRECATED. USE GENERIC ORACLE INSTEAD. WILL BE REMOVED SOON.

/// @title   UniswapV3 checked against Chainlink / Redstone Oracle for Layer 2 (with sequencer outage detection). Either one reported as exchange rate.
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a UniV3 pool (compared against 3 TWAPs) and (optionally) comparing it against a Chainlink
///          or Redstone price (one of Chainlink or Redstone being the main source and the other one the fallback source).
///          Alternatively it can also use Chainlink / Redstone as main price and use UniV3 as check price.
/// @dev     The process for getting the aggregate oracle price is:
///           1. Fetch the UniV3 TWAPS, the latest interval is used as the current price
///           2. Verify this price is within an acceptable DELTA from the Uniswap TWAPS e.g.:
///              a. 240 to 60s
///              b. 60 to 15s
///              c. 15 to 1s (last block)
///              d. 1 to 0s (current)
///           3. (unless UniV3 only mode): Verify this price is within an acceptable DELTA from the Chainlink / Redstone Oracle
///           4. If it passes all checks, return the price. Otherwise use fallbacks, usually to Chainlink. In extreme edge-cases revert.
/// @dev     For UniV3 with check mode, if fetching the check price fails, the UniV3 rate is used directly.
contract UniV3CheckCLRSOracleL2 is FluidOracleL2, UniV3CheckCLRSOracle {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        UniV3CheckCLRSConstructorParams memory params_,
        address sequencerUptimeFeed_
    ) UniV3CheckCLRSOracle(infoName_, targetDecimals_, params_) FluidOracleL2(sequencerUptimeFeed_) {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate()
        public
        view
        virtual
        override(UniV3CheckCLRSOracle, FluidOracleL2)
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
        override(UniV3CheckCLRSOracle, FluidOracleL2)
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
        override(UniV3CheckCLRSOracle, FluidOracleL2)
        returns (uint256 exchangeRate_)
    {
        return getExchangeRateOperate();
    }
}
