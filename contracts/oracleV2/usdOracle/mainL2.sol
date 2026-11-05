// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidUsdOracle } from "./main.sol";
import { FluidSequencerL2 } from "../common/sequencerL2.sol";

/// @title FluidUsdOracleL2
/// @notice L2 variant of FluidUsdOracle with a built-in Chainlink sequencer uptime feed check.
///         Guarded price reads (getPrice, getPriceView, getPriceDetailed, getPriceDetailedView,
///         getPriceRawForMode, getPricesRawForMode) verify that the L2 sequencer is up and that a dynamic
///         grace period has elapsed.
///         The grace period equals the outage duration, capped at `_SEQUENCER_MAX_GRACE_PERIOD`.
///         Unguarded reads (getPriceDetailedViewRaw) skip the sequencer check; `_getPriceImplNoWrite` is self-call gated.
///
/// @dev Sequencer check happens in `_beforeGuardedPriceRead()` override.
///      Sequencer logic is the shared `FluidSequencerL2` (`../common/sequencerL2.sol`).
contract FluidUsdOracleL2 is FluidUsdOracle, FluidSequencerL2 {
    /// @notice Deploys the L2 USD oracle with the Liquidity contract used to resolve governance and a Chainlink sequencer uptime feed.
    /// @param liquidity_ Liquidity proxy address (same as `FluidUsdOracle`); governance read via `LIQUIDITY_GOVERNANCE_SLOT`.
    /// @param sequencerUptimeFeed_ Chainlink L2 sequencer uptime feed (`IChainlinkAggregatorV3`); must have code.
    constructor(
        address liquidity_,
        address sequencerUptimeFeed_
    ) FluidUsdOracle(liquidity_) FluidSequencerL2(sequencerUptimeFeed_) {}

    /// @dev Gates all guarded price reads behind the sequencer uptime + grace-period check.
    function _beforeGuardedPriceRead() internal view override {
        _ensureSequencerUpAndValid();
    }
}
