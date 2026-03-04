// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "./interfaces/iFluidOracle.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { IChainlinkAggregatorV3 } from "./interfaces/external/IChainlinkAggregatorV3.sol";
import { Error as OracleError } from "./error.sol";

/// @title   FluidOracleL2
/// @notice  Base contract that any Fluid Oracle L2 must implement
abstract contract FluidOracleL2 is IFluidOracle, OracleError {
    /// @dev Chainlink L2 Sequencer Uptime feed to detect sequencer outages
    IChainlinkAggregatorV3 internal immutable _SEQUENCER_ORACLE;
    /// @dev max time period until oracle assumes normal behavior after a sequencer outage.
    uint256 internal constant _SEQUENCER_MAX_GRACE_PERIOD = 45 minutes;

    /// @notice sets the L2 sequencer uptime Chainlink feed
    constructor(address sequencerUptimeFeed_) {
        _SEQUENCER_ORACLE = IChainlinkAggregatorV3(sequencerUptimeFeed_);
    }

    /// @notice returns all sequencer uptime feed related data
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

    /// @dev ensures that the sequencer is up and grace period has passed
    function _ensureSequencerUpAndValid() internal view {
        (bool isSequencerUp_, uint80 uptimeStartRoundId_, uint256 uptimeStartedAt_) = _sequencerUpStatus();

        if (!isSequencerUp_) {
            revert FluidOracleError(ErrorTypes.FluidOracleL2__SequencerOutage);
        }

        (, bool gracePeriodPassed_, ) = _gracePeriod(uptimeStartRoundId_, uptimeStartedAt_);
        if (!gracePeriodPassed_) {
            revert FluidOracleError(ErrorTypes.FluidOracleL2__SequencerOutage);
        }
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() external view virtual returns (uint256 exchangeRate_);

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() external view virtual returns (uint256 exchangeRate_);

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() external view virtual returns (uint256 exchangeRate_);

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
