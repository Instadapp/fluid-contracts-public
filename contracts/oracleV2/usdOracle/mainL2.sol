// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";

import { FluidUsdOracle } from "./main.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

/// @title FluidUsdOracleSequencerL2
/// @notice L2 Chainlink sequencer uptime feed reads, grace-period math, and `sequencerL2Data()` view.
///
/// @dev **Core sequencer algorithm is copied 1:1 from `contracts/oracle/fluidOracleL2.sol` (`FluidOracleL2`).**
///
///      Intentional differences from v1 `FluidOracleL2`:
///      - `_ensureSequencerUpAndValid()` uses `FluidUsdOracleError` with `UsdOracle__SequencerDown` and
///        `UsdOracle__SequencerGracePeriod` instead of a single `FluidOracleL2__SequencerOutage`.
///      - Constructor rejects `sequencerUptimeFeed_ == address(0)` (UsdOracle-specific).
abstract contract FluidUsdOracleSequencerL2 is Error {
    /// @dev Chainlink L2 Sequencer Uptime feed to detect sequencer outages
    IChainlinkAggregatorV3 internal immutable _SEQUENCER_ORACLE;
    /// @dev max time period until oracle assumes normal behavior after a sequencer outage.
    uint256 internal constant _SEQUENCER_MAX_GRACE_PERIOD = 45 minutes;

    /// @notice Stores the Chainlink L2 sequencer uptime feed used for outage and grace-period checks.
    /// @param sequencerUptimeFeed_ Chainlink sequencer uptime aggregator; must not be `address(0)`.
    constructor(address sequencerUptimeFeed_) {
        if (sequencerUptimeFeed_ == address(0)) {
            _revert(ErrorTypes.UsdOracle__AddressZero);
        }
        _SEQUENCER_ORACLE = IChainlinkAggregatorV3(sequencerUptimeFeed_);
    }

    /// @notice Exposes Chainlink sequencer uptime feed state and grace-period diagnostics for off-chain monitoring and debugging.
    /// @dev When the sequencer is up, `gracePeriod_` is the outage-duration-based grace window (capped at `maxGracePeriod_`).
    ///      When the sequencer is down, `gracePeriod_` is set to `maxGracePeriod_` and `lastOutageStartedAt_` is derived from feed rounds.
    /// @return sequencerUptimeFeed_ Chainlink `IChainlinkAggregatorV3` sequencer uptime feed used by this contract.
    /// @return maxGracePeriod_ Upper bound on the grace period after a sequencer outage (`_SEQUENCER_MAX_GRACE_PERIOD`).
    /// @return isSequencerUp_ True if the feed’s latest answer indicates the sequencer is currently up (Chainlink convention: answer 0 = up).
    /// @return lastUptimeStartedAt_ Timestamp at the start of the current consecutive uptime window (0 if sequencer is down).
    /// @return gracePeriod_ Required wait after uptime resumes before prices are considered valid (capped); see `@dev`.
    /// @return gracePeriodPassed_ True if `block.timestamp - lastUptimeStartedAt_` exceeds `gracePeriod_` while the sequencer is up.
    /// @return lastOutageStartedAt_ Timestamp when the preceding downtime began (used for grace math; 0 when not applicable).
    /// @return isSequencerUpAndValid_ `isSequencerUp_ && gracePeriodPassed_`; matches `_ensureSequencerUpAndValid()` success conditions.
    function sequencerL2Data()
        public
        view
        returns (
            address sequencerUptimeFeed_,
            uint256 maxGracePeriod_,
            bool isSequencerUp_,
            uint256 lastUptimeStartedAt_,
            uint256 gracePeriod_,
            bool gracePeriodPassed_,
            uint256 lastOutageStartedAt_,
            bool isSequencerUpAndValid_
        )
    {
        uint80 uptimeStartRoundId_;
        (isSequencerUp_, uptimeStartRoundId_, lastUptimeStartedAt_) = _sequencerUpStatus();

        if (isSequencerUp_) {
            (gracePeriod_, gracePeriodPassed_, lastOutageStartedAt_) = _gracePeriod(
                uptimeStartRoundId_,
                lastUptimeStartedAt_
            );
        } else {
            gracePeriod_ = _SEQUENCER_MAX_GRACE_PERIOD;
            (uint80 roundId_, , , , ) = _SEQUENCER_ORACLE.latestRoundData();
            lastOutageStartedAt_ = _lastSequencerOutageStart(roundId_ + 1);
        }

        return (
            address(_SEQUENCER_ORACLE),
            _SEQUENCER_MAX_GRACE_PERIOD,
            isSequencerUp_,
            lastUptimeStartedAt_,
            gracePeriod_,
            gracePeriodPassed_,
            lastOutageStartedAt_,
            isSequencerUp_ && gracePeriodPassed_
        );
    }

    /// @dev Reverts with `UsdOracle__SequencerDown` if the feed reports the sequencer down, or `UsdOracle__SequencerGracePeriod`
    ///      if the sequencer is up but the grace window after the last outage has not elapsed.
    function _ensureSequencerUpAndValid() internal view {
        (bool isSequencerUp_, uint80 uptimeStartRoundId_, uint256 uptimeStartedAt_) = _sequencerUpStatus();

        if (!isSequencerUp_) {
            _revert(ErrorTypes.UsdOracle__SequencerDown);
        }

        (, bool gracePeriodPassed_, ) = _gracePeriod(uptimeStartRoundId_, uptimeStartedAt_);
        if (!gracePeriodPassed_) {
            _revert(ErrorTypes.UsdOracle__SequencerGracePeriod);
        }
    }

    /// @dev finds last round before `uptimeStartRoundId_` where sequencer status was down, incl. handling cases of
    /// consecutive rounds where status was down.
    function _lastSequencerOutageStart(uint80 uptimeStartRoundId_) private view returns (uint256 outageStartedAt_) {
        uint80 roundId_ = uptimeStartRoundId_;
        int256 answer_;
        uint256 startedAt_;
        do {
            (roundId_, answer_, startedAt_, , ) = _SEQUENCER_ORACLE.getRoundData(roundId_ - 1);
            if (answer_ != 0) {
                // sequencer was down at this round, update outage started at data
                outageStartedAt_ = startedAt_;
            } // else: while loop is going to break
        } while (answer_ != 0 && startedAt_ > 0);
    }

    /// @dev finds last round where sequencer status was up, incl. handling cases of consecutive rounds where status was up.
    function _sequencerUpStatus()
        private
        view
        returns (bool isSequencerUp_, uint80 uptimeStartRoundId_, uint256 uptimeStartedAt_)
    {
        (uint80 roundId_, int256 answer_, uint256 startedAt_, , ) = _SEQUENCER_ORACLE.latestRoundData();
        if (answer_ != 0) {
            // sequencer is down currently.
            return (false, 0, 0);
        }

        isSequencerUp_ = true;

        // cover case where there were other consecutive uptime report rounds in between
        uptimeStartRoundId_ = roundId_;
        uptimeStartedAt_ = startedAt_;
        if (uptimeStartedAt_ > 0) {
            do {
                (roundId_, answer_, startedAt_, , ) = _SEQUENCER_ORACLE.getRoundData(roundId_ - 1);
                if (answer_ == 0) {
                    // sequencer was up at this round, consecutive uptime so update uptime start data
                    uptimeStartRoundId_ = roundId_;
                    uptimeStartedAt_ = startedAt_;
                } // else: while loop is going to break
            } while (answer_ == 0 && startedAt_ > 0);
        } // else if startedAt == 0, then it is the first ever round.
    }

    /// @dev returns the `gracePeriod_` duration and if the grace period has `passed_` based on
    /// current uptime round data vs the last sequencer outage duration.
    function _gracePeriod(
        uint80 uptimeStartRoundId_,
        uint256 uptimeStartedAt_
    ) private view returns (uint256 gracePeriod_, bool passed_, uint256 outageStartedAt_) {
        uint256 uptimeDuration_ = block.timestamp - uptimeStartedAt_;
        if (uptimeStartedAt_ == 0 || uptimeDuration_ > _SEQUENCER_MAX_GRACE_PERIOD) {
            return (_SEQUENCER_MAX_GRACE_PERIOD, true, 0);
        }

        outageStartedAt_ = _lastSequencerOutageStart(uptimeStartRoundId_);

        // grace period is outage duration, capped at _SEQUENCER_MAX_GRACE_PERIOD
        gracePeriod_ = uptimeStartedAt_ - outageStartedAt_; // outage duration
        if (gracePeriod_ > _SEQUENCER_MAX_GRACE_PERIOD) {
            gracePeriod_ = _SEQUENCER_MAX_GRACE_PERIOD;
        }

        return (gracePeriod_, uptimeDuration_ > gracePeriod_, outageStartedAt_);
    }
}

/// @title FluidUsdOracleL2
/// @notice L2 variant of FluidUsdOracle with a built-in Chainlink sequencer uptime feed check.
///         Guarded price reads (getPrice, getPriceView, getPriceDetailed, getPriceDetailedView,
///         getPriceRawForMode, getPricesRawForMode) verify that the L2 sequencer is up and that a dynamic
///         grace period has elapsed.
///         The grace period equals the outage duration, capped at `_SEQUENCER_MAX_GRACE_PERIOD`.
///         Unguarded reads (getPriceDetailedViewRaw) skip the sequencer check; `_getPriceImplNoWrite` is self-call gated.
///
/// @dev Sequencer check happens in `_beforeGuardedPriceRead()` override.
///      Sequencer logic is in `FluidUsdOracleSequencerL2` above (copied 1:1 from `fluidOracleL2.sol`).
contract FluidUsdOracleL2 is FluidUsdOracle, FluidUsdOracleSequencerL2 {
    /// @notice Deploys the L2 USD oracle with the Liquidity contract used to resolve governance and a Chainlink sequencer uptime feed.
    /// @param liquidity_ Liquidity proxy address (same as `FluidUsdOracle`); governance read via `LIQUIDITY_GOVERNANCE_SLOT`.
    /// @param sequencerUptimeFeed_ Chainlink L2 sequencer uptime feed (`IChainlinkAggregatorV3`); must not be zero.
    constructor(
        address liquidity_,
        address sequencerUptimeFeed_
    ) FluidUsdOracle(liquidity_) FluidUsdOracleSequencerL2(sequencerUptimeFeed_) {}

    /// @dev Gates all guarded price reads behind the sequencer uptime + grace-period check.
    function _beforeGuardedPriceRead() internal view override {
        _ensureSequencerUpAndValid();
    }
}
