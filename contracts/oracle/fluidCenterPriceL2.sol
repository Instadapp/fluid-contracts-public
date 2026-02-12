// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidCenterPrice } from "./interfaces/iFluidCenterPrice.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error as OracleError } from "./error.sol";
import { IChainlinkAggregatorV3 } from "./interfaces/external/IChainlinkAggregatorV3.sol";

/// @title   FluidCenterPriceL2
/// @notice  Base contract that any Fluid Center Price L2 must implement
abstract contract FluidCenterPriceL2 is IFluidCenterPrice, OracleError {
    /// @dev short helper string to easily identify the center price oracle. E.g. token symbols
    //
    // using a bytes32 because string can not be immutable.
    bytes32 private immutable _infoName;

    uint8 internal constant _TARGET_DECIMALS = 27; // target decimals for center price and contract rates is always 27

    /// @dev Chainlink L2 Sequencer Uptime feed to detect sequencer outages
    IChainlinkAggregatorV3 internal immutable _SEQUENCER_ORACLE;
    /// @dev max time period until oracle assumes normal behavior after a sequencer outage.
    uint256 internal constant _SEQUENCER_MAX_GRACE_PERIOD = 45 minutes;

    constructor(string memory infoName_, address sequencerUptimeFeed_) {
        if (bytes(infoName_).length > 32 || bytes(infoName_).length == 0) {
            revert FluidOracleError(ErrorTypes.FluidOracle__InvalidInfoName);
        }

        // convert string to bytes32
        bytes32 infoNameBytes32_;
        assembly {
            infoNameBytes32_ := mload(add(infoName_, 32))
        }
        _infoName = infoNameBytes32_;

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

    /// @inheritdoc IFluidCenterPrice
    function targetDecimals() public pure virtual returns (uint8) {
        return _TARGET_DECIMALS;
    }

    /// @inheritdoc IFluidCenterPrice
    function infoName() public view virtual returns (string memory) {
        // convert bytes32 to string
        uint256 length_;
        while (length_ < 32 && _infoName[length_] != 0) {
            length_++;
        }
        bytes memory infoNameBytes_ = new bytes(length_);
        for (uint256 i; i < length_; i++) {
            infoNameBytes_[i] = _infoName[i];
        }
        return string(infoNameBytes_);
    }

    /// @inheritdoc IFluidCenterPrice
    function centerPrice() external virtual returns (uint256 price_);

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
