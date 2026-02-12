// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "./interfaces/iFluidOracle.sol";
import { IFluidCappedRate } from "./interfaces/iFluidCappedRate.sol";
import { FluidCenterPrice } from "./fluidCenterPrice.sol";

import { LiquiditySlotsLink } from "../libraries/liquiditySlotsLink.sol";

import { Error as OracleError } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

interface IFluidLiquidity {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

abstract contract Events {
    /// @notice emitted when rebalancer successfully changes the contract rate
    event LogRebalanceRate(uint256 oldRate, uint256 newRate, uint256 oldMaxRate, uint256 newMaxRate);

    /// @notice emitted when the external rate is currently lower than the previous maximum rate by at least `_maxDownFromMaxReachedPercent`
    event LogRateBelowMaxReached();

    /// @notice emitted when the external rate increased faster than `_maxAPRPercent` allows
    event LogRateMaxAPRCapped();

    /// @notice Emitted when avoidForcedLiquidations col is updated
    event LogUpdateAvoidForcedLiquidationsCol(bool oldAvoidForcedLiquidations, bool newAvoidForcedLiquidations);

    /// @notice Emitted when avoidForcedLiquidations debt is updated
    event LogUpdateAvoidForcedLiquidationsDebt(bool oldAvoidForcedLiquidations, bool newAvoidForcedLiquidations);

    /// @notice Emitted when maxAPRPercent is updated
    event LogUpdateMaxAPRPercent(uint256 oldMaxAPRPercent, uint256 newMaxAPRPercent);

    /// @notice Emitted when _maxDownFromMaxReachedPercentCol is updated
    event LogUpdateMaxDownFromMaxReachedPercentCol(
        uint256 oldMaxDownFromMaxReachedPercent,
        uint256 newMaxDownFromMaxReachedPercent
    );

    /// @notice Emitted when _maxDownFromMaxReachedPercentDebt is updated
    event LogUpdateMaxDownFromMaxReachedPercentDebt(
        uint256 oldMaxDownFromMaxReachedPercent,
        uint256 newMaxDownFromMaxReachedPercent
    );

    /// @notice Emitted when max reached rate is reset to `_rate`
    event LogForceResetMaxRate(uint256 oldMaxRate, uint256 newMaxRate);

    /// @notice Emitted when _maxDebtUpCapPercent is updated
    event LogUpdateMaxDebtUpCapPercent(uint256 oldMaxDebtUpCapPercent, uint256 newMaxDebtUpCapPercent);

    /// @notice Emitted when _minHeartbeat is updated
    event LogUpdateMinHeartbeat(uint256 oldMinHeartbeat, uint256 newMinHeartbeat);

    /// @notice Emitted when _minUpdateDiffPercent is updated
    event LogUpdateMinUpdateDiffPercent(uint256 oldMinUpdateDiffPercent, uint256 newMinUpdateDiffPercent);
}

abstract contract Constants {
    /// @dev Ignoring leap years
    uint256 internal constant _SECONDS_PER_YEAR = 365 days;

    /// @dev 100% precision
    uint256 internal constant _SIX_DECIMALS = 1e6;

    uint256 internal constant _X3 = 7;

    /// @dev liquidity layer address
    address internal immutable _LIQUIDITY;

    /// @dev external exchange rate source contract
    address internal immutable _RATE_SOURCE;

    /// @dev flag if fetched rate should be inverted
    bool internal immutable _INVERT_CENTER_PRICE;

    /// @dev external exchange rate source multiplier to get to 1e27 decimals
    uint256 internal immutable _RATE_MULTIPLIER;
}

abstract contract Variables is Constants {
    // slot 0 flag bitmasks
    uint8 internal constant _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED = 1;
    uint8 internal constant _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED = 2;
    uint8 internal constant _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL = 4;
    uint8 internal constant _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT = 8;
    uint8 internal constant _FLAG_BITMASK_ALLOW_MAX_YIELD_JUMPS = 0xE0; // 1110 0000

    struct Slot0 {
        /// @dev exchange rate as fetched from external rate source in 1e27 decimals. max value 3.74e50
        uint168 rate;
        /// @dev time when last update for rate happened
        uint40 lastUpdateTime;
        /// @dev flags bitmap:
        /// Bit 1: true if the `_rate` value is currently < _maxReachedAPRCappedRate
        ///        bool internal _isRateBelowMaxReached;

        /// Bit 2: true if the `_rate` value is currently > _maxReachedAPRCappedRate, so capped because of the maxAPR limit
        ///        bool internal _isUpMaxAPRCapped;

        /// Bit 3: Col side: config flag to signal whether to protect users vs protect protocol depending on asset reliability (accept temporary bad debt if trusting peg).
        ///        flag should only be active for trusted assets where we assume any peg can only be temporary as when this flag is on
        ///        it can lead to bad debt until asset repeg is reached. For not 100% trusted assets better to liquidate on depeg and avoid any bad debt
        ///        Configurable by Governance and Liquidity guardians
        ///        bool internal _avoidForcedLiquidationsCol;

        /// Bit 4: same as Bit 3, but for debt side
        ///        bool internal _avoidForcedLiquidationsDebt;

        /// Bit 5: ----- empty -------

        /// Bits 6,7,8: uint3 -> allowed max yield jumps. each heartbeat update where minUpdateDiff is not reached increases this by 1,
        ///                      up to a maximum of 7. Reset to 0 for any update that is > min update diff.
        ///                      For any price update, the maximum price increase is:
        ///                      normal max yield increase since lastUpdateTime + maxYieldJumps * maxYield / HeartBeatDuration
        uint8 flags;
        /// @dev Minimum time after which an update can trigger, even if it does not reach `_minUpdateDiffPercent`. Max value = 16_777_215 -> ~194 days
        ///      Configurable by Governance.
        uint24 minHeartbeat;
        /// @dev Minimum difference to trigger update in percent 1e4 decimals, 10000 = 1%. Max value = 6,5535%
        ///      Configurable by Governance.
        uint16 minUpdateDiffPercent;
    }

    struct Slot1 {
        /// @dev tracks the maximum ever reached rate with respect of maxAPR percent (a temporary 100x spike does not increase this value beyond max apr increase).
        /// this is only updated IF `_rate` is not == `_maxReachedAPRCappedRate`, i.e. if `_isRateBelowMaxReached || _isUpMaxAPRCapped`. max value 3.74e50
        ///
        /// Can be reset synced to match `_rate` by Govnernance and Liquidity guardians, when wanting to force skip max APR or forcing reset after rate reduced
        uint168 maxReachedAPRCappedRate;
        /// @dev maximum yield APR that exchange rate can increase in each update
        /// in 1e2 precision, 1% = 100. max value-> 167_772,15%, can be set to 0 to force no rate increase possible for upwards cap
        ///
        /// Configurable by Governance and Liquidity guardians.
        uint24 maxAPRPercent;
        /// @dev Col side: maximum down percent reduction of `_maxReachedAPRCappedRate` for rates with downward cap protection.
        /// in 1e4 precision, 1% = 1e4. max value-> 1_677,7215 % (so max configurable value = _SIX_DECIMALS which is 100% -> removing downward cap entirely)
        ///
        /// Configurable by Governance and Liquidity guardians
        uint24 maxDownFromMaxReachedPercentCol;
        /// @dev same as above but for debt
        uint24 maxDownFromMaxReachedPercentDebt;
        /// @dev Debt side: maximum up percent cap on top of `_maxReachedAPRCappedRate`, only relevant when avoid forced liquidations attack for debt side is active,
        /// when _avoidForcedLiquidationsDebt flag is true. in 1e2 precision, 1% = 100. max value-> 655,35%, can be set to 0 to have same cap as on col side.
        ///
        /// Configurable by Governance and Liquidity guardians.
        uint16 maxDebtUpCapPercent;
    }

    Slot0 internal _slot0; // Used in default view methods

    Slot1 internal _slot1; // Used only in special cases, storage updates or admin related
}

abstract contract CappedRateInternals is Variables, Events, OracleError {
    /// @dev read the exchange rate from the external contract e.g. wstETH or rsETH exchange rate, yet to be scaled to 1e27
    /// To be implemented by inheriting contract
    function _getNewRateRaw() internal view virtual returns (uint256 exchangeRate_);

    /// @dev gets the percentage difference between `oldValue_` and `newValue_` in relation to `oldValue_` in percent (10000 = 1%, 1 = 0.0001%).
    function _percentDiffForValue(
        uint256 oldValue_,
        uint256 newValue_
    ) internal pure returns (uint256 configPercentDiff_) {
        unchecked {
            if (oldValue_ > newValue_) {
                configPercentDiff_ = ((oldValue_ - newValue_) * _SIX_DECIMALS) / oldValue_;
            } else if (newValue_ > oldValue_) {
                configPercentDiff_ = ((newValue_ - oldValue_) * _SIX_DECIMALS) / oldValue_;
            }
        }
    }

    /// @dev get new rate from external source and return updated related parameters.
    function _getUpdateRates(
        uint256 maxReachedRate_,
        Slot0 memory slot0_,
        uint256 maxAPRPercent_
    )
        internal
        view
        virtual
        returns (uint256 newRate_, uint256 maxRate_, bool isUpMaxAPRCapped_, bool isRateBelowMaxReached_)
    {
        newRate_ = _getNewRateRaw() * _RATE_MULTIPLIER;
        if (newRate_ == 0) {
            revert FluidOracleError(ErrorTypes.CappedRate__NewRateZero);
        }

        maxRate_ = _calcMaxAPRCappedRate(newRate_, maxReachedRate_, slot0_, maxAPRPercent_);
        isUpMaxAPRCapped_ = newRate_ > maxRate_;
        isRateBelowMaxReached_ = newRate_ < maxRate_;
    }

    /// @dev updates the values in storage according to the newly fetched rate from external source.
    function _updateRates(bool forceUpdate_) internal virtual returns (uint256 newRate_) {
        Slot0 memory slot0_ = _slot0;
        Slot1 memory slot1_ = _slot1;

        uint256 newMaxReachedRate_;
        bool isUpMaxAPRCapped_;
        bool isRateBelowMaxReached_;

        uint256 maxReachedAPRCappedRate_ = uint256(slot1_.maxReachedAPRCappedRate);

        (newRate_, newMaxReachedRate_, isUpMaxAPRCapped_, isRateBelowMaxReached_) = _getUpdateRates(
            maxReachedAPRCappedRate_,
            slot0_,
            uint256(slot1_.maxAPRPercent)
        );

        if (newRate_ > type(uint168).max || newMaxReachedRate_ > type(uint168).max) {
            revert FluidOracleError(ErrorTypes.CappedRate__StorageOverflow);
        }

        uint256 curRate_ = uint256(slot0_.rate);

        uint256 allowedMaxYieldJumps_ = 0;
        if (
            _percentDiffForValue(curRate_, newRate_) < uint256(slot0_.minUpdateDiffPercent) &&
            _percentDiffForValue(maxReachedAPRCappedRate_, newMaxReachedRate_) < uint256(slot0_.minUpdateDiffPercent)
        ) {
            if (forceUpdate_) {
                // min update diff not reached but update is forced anyway via heartbeat -> increase allowed max yield jumps
                allowedMaxYieldJumps_ = (uint256(slot0_.flags & _FLAG_BITMASK_ALLOW_MAX_YIELD_JUMPS) + 1) & _X3; // force max value possible 7
            } else {
                revert FluidOracleError(ErrorTypes.CappedRate__MinUpdateDiffNotReached);
            }
        }

        if (isUpMaxAPRCapped_) {
            // if this flag is true then the rate is always effectively upwards capped
            emit LogRateMaxAPRCapped();
        }
        if (isRateBelowMaxReached_) {
            uint256 downPercent_ = ((newMaxReachedRate_ - newRate_) * _SIX_DECIMALS) / newMaxReachedRate_;
            if (
                downPercent_ > slot1_.maxDownFromMaxReachedPercentCol ||
                downPercent_ > slot1_.maxDownFromMaxReachedPercentDebt
            ) {
                // only log this if the decrease is by more than `_maxDownFromMaxReachedPercent` so if the returned rate actually ends up getting
                // downwards capped (for either col or debt)
                emit LogRateBelowMaxReached();
            }
        }

        // storage slot 1 ALWAYS gets updated because of timestamp so no need to optimize much here
        slot0_.lastUpdateTime = uint40(block.timestamp);
        slot0_.rate = uint168(newRate_);
        slot0_.flags =
            (slot0_.flags & 0x1C) | // 0001 1100
            (isRateBelowMaxReached_ ? _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED : 0) |
            (isUpMaxAPRCapped_ ? _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED : 0) |
            (uint8(allowedMaxYieldJumps_) << 5);
        _slot0 = slot0_; // write to storage

        // storage slot 2 might not always change, only if max rate changes, which could be not needed e.g. if rate decreased
        if (maxReachedAPRCappedRate_ < newMaxReachedRate_) {
            _slot1.maxReachedAPRCappedRate = uint168(newMaxReachedRate_);
        }

        emit LogRebalanceRate(curRate_, newRate_, maxReachedAPRCappedRate_, newMaxReachedRate_);
    }

    /// @dev returns the downwards capped rate max(downCappedRate_, rate_), where downCappedRate_ is capped at maxReachedAPRCappedRate_ - _maxDownFromMaxReachedPercent %.
    function _calcDownCappedRate(
        uint256 rate_,
        uint256 maxReachedRate_,
        uint256 maxDownPercent_
    ) internal pure returns (uint256 downCappedRate_) {
        unchecked {
            downCappedRate_ = (maxReachedRate_ * (_SIX_DECIMALS - maxDownPercent_)) / _SIX_DECIMALS;
        }

        if (rate_ > downCappedRate_) {
            downCappedRate_ = rate_;
        }
    }

    /// @dev returns the upwards capped rate min(upCappedRate_, rate_), where upCappedRate_ is capped at maxReachedAPRCappedRate_ + _maxAPRPercent %
    /// adjusted for passed time since last update time.
    function _calcMaxAPRCappedRate(
        uint256 rate_,
        uint256 maxReachedRate_,
        Slot0 memory slot0_,
        uint256 maxAPRPercent_
    ) internal view returns (uint256 maxRate_) {
        unchecked {
            maxRate_ =
                (maxAPRPercent_ * uint256(100) * (block.timestamp - uint256(slot0_.lastUpdateTime))) /
                _SECONDS_PER_YEAR; // maxRate_ = max APR for passed time since last update time
            maxRate_ = (maxReachedRate_ * (_SIX_DECIMALS + maxRate_)) / _SIX_DECIMALS;

            // add allowed max yield jumps from any heartbeat update that did not marginally increase the rate but increased the timestamp
            uint256 allowedMaxYieldJumps_ = (slot0_.flags & _FLAG_BITMASK_ALLOW_MAX_YIELD_JUMPS);
            if (allowedMaxYieldJumps_ > 0) {
                uint256 maxAPRPerHeartbeat_ = (maxAPRPercent_ * uint256(100) * slot0_.minHeartbeat) / _SECONDS_PER_YEAR;
                maxRate_ = (maxRate_ * (_SIX_DECIMALS + allowedMaxYieldJumps_ * maxAPRPerHeartbeat_)) / _SIX_DECIMALS;
            }
        }

        if (rate_ > maxRate_) {
            // rate increase is capped at max rate
            return maxRate_;
        }
        if (rate_ < maxReachedRate_) {
            // if rate is lower than previous max reached rate, then previous max reached rate is the max rate
            return maxReachedRate_;
        }

        // rate is > maxReachedRate and < max allowed rate
        return rate_;
    }

    /// @dev returns true if last update timestamp is too long ago so heartbeat update should trigger
    function _isHeartbeatTrigger(Slot0 memory slot0_) internal view returns (bool) {
        unchecked {
            return ((uint256(slot0_.lastUpdateTime) + slot0_.minHeartbeat) < block.timestamp);
        }
    }

    /// @dev returns inverted rate if needed (when _INVERT_CENTER_PRICE flag is set to true)
    function _invertRateIfNeeded(uint256 exchangeRate_) internal view returns (uint256) {
        if (exchangeRate_ == 0) {
            return 0;
        }
        unchecked {
            return _INVERT_CENTER_PRICE ? 1e54 / exchangeRate_ : exchangeRate_;
        }
    }
}

abstract contract CappedRateAdmin is Variables, Events, OracleError {
    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1 where current liquidity owner on proxy is stored
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev only Liquidity Layer owner (governance) and guardians access modifier
    modifier onlyGuardians() {
        bool isGuardian_ = (IFluidLiquidity(_LIQUIDITY).readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_GUARDIANS_MAPPING_SLOT,
                msg.sender
            )
        ) & 1) == 1;

        bool isGovernance_ = address(uint160(IFluidLiquidity(_LIQUIDITY).readFromStorage(GOVERNANCE_SLOT))) ==
            msg.sender;

        if (!isGuardian_ && !isGovernance_) {
            revert FluidOracleError(ErrorTypes.CappedRate__Unauthorized);
        }
        _;
    }

    /// @dev only Liquidity Layer owner (governance) access modifier
    modifier onlyGovernance() {
        if (address(uint160(IFluidLiquidity(_LIQUIDITY).readFromStorage(GOVERNANCE_SLOT))) != msg.sender) {
            revert FluidOracleError(ErrorTypes.CappedRate__Unauthorized);
        }
        _;
    }

    /// @notice Updates the avoidForcedLiquidations_ col side config flag. Only callable by Liquidity Layer guardians
    function updateAvoidForcedLiquidationsCol(bool avoid_) external onlyGuardians {
        bool oldAvoidForcedLiquidations_ = _slot0.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL ==
            _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL;
        _slot0.flags = (_slot0.flags & 0xFB) | (avoid_ ? _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL : 0); // mask F1011
        emit LogUpdateAvoidForcedLiquidationsCol(oldAvoidForcedLiquidations_, avoid_);
    }

    /// @notice Updates the avoidForcedLiquidations_ debt side config flag. Only callable by Liquidity Layer guardians
    function updateAvoidForcedLiquidationsDebt(bool avoid_) external onlyGuardians {
        bool oldAvoidForcedLiquidations_ = _slot0.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT ==
            _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT;
        _slot0.flags = (_slot0.flags & 0xF7) | (avoid_ ? _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT : 0); // mask F0111
        emit LogUpdateAvoidForcedLiquidationsDebt(oldAvoidForcedLiquidations_, avoid_);
    }

    /// @notice resets max reached rate to current `_rate` value. Only callable by Liquidity Layer guardians
    function forceResetMaxRate() external onlyGuardians {
        uint256 oldMaxRate_ = uint256(_slot1.maxReachedAPRCappedRate);
        _slot1.maxReachedAPRCappedRate = _slot0.rate;
        emit LogForceResetMaxRate(oldMaxRate_, uint256(_slot1.maxReachedAPRCappedRate));
    }

    /// @notice Updates the maxAPRPercent_ config, in 1e4 percent (1% = 1e4). Only callable by Governance
    function updateMaxAPRPercent(uint256 newMaxAPRPercent_) external onlyGuardians {
        if (newMaxAPRPercent_ > type(uint24).max * uint256(100)) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMaxAPRPercent_ = uint256(_slot1.maxAPRPercent) * uint256(100);
        _slot1.maxAPRPercent = uint24(newMaxAPRPercent_ / uint256(100));
        emit LogUpdateMaxAPRPercent(oldMaxAPRPercent_, newMaxAPRPercent_);
    }

    /// @notice Updates the _maxDownFromMaxReachedPercentCol config. Only callable by Liquidity Layer guardians.
    ///         Set to 100% (1e6) to completely remove down peg (same as updateAvoidForcedLiquidationsCol = false)
    function updateMaxDownFromMaxReachedPercentCol(uint256 newMaxDownFromMaxReachedPercent_) external onlyGuardians {
        if (newMaxDownFromMaxReachedPercent_ > _SIX_DECIMALS) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMaxDownFromMaxReachedPercent_ = uint256(_slot1.maxDownFromMaxReachedPercentCol);
        _slot1.maxDownFromMaxReachedPercentCol = uint24(newMaxDownFromMaxReachedPercent_);
        emit LogUpdateMaxDownFromMaxReachedPercentCol(
            oldMaxDownFromMaxReachedPercent_,
            newMaxDownFromMaxReachedPercent_
        );
    }

    /// @notice Updates the _maxDownFromMaxReachedPercentDebt config. Only callable by Liquidity Layer guardians.
    ///         Set to 100% (1e6) to completely remove down peg.
    function updateMaxDownFromMaxReachedPercentDebt(uint256 newMaxDownFromMaxReachedPercent_) external onlyGuardians {
        if (newMaxDownFromMaxReachedPercent_ > _SIX_DECIMALS) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMaxDownFromMaxReachedPercent_ = uint256(_slot1.maxDownFromMaxReachedPercentDebt);
        _slot1.maxDownFromMaxReachedPercentDebt = uint24(newMaxDownFromMaxReachedPercent_);
        emit LogUpdateMaxDownFromMaxReachedPercentDebt(
            oldMaxDownFromMaxReachedPercent_,
            newMaxDownFromMaxReachedPercent_
        );
    }

    /// @notice Updates the _maxDebtUpCapPercent config. Only callable by Liquidity Layer guardians.
    function updateMaxDebtUpCapPercent(uint256 newMaxDebtUpCapPercent_) external onlyGuardians {
        if (newMaxDebtUpCapPercent_ > type(uint16).max * uint256(100)) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMaxDebtUpCapPercent_ = uint256(_slot1.maxDebtUpCapPercent) * uint256(100);
        _slot1.maxDebtUpCapPercent = uint16(newMaxDebtUpCapPercent_ / uint256(100));
        emit LogUpdateMaxDebtUpCapPercent(oldMaxDebtUpCapPercent_, newMaxDebtUpCapPercent_);
    }

    /// @notice Updates the _minHeartbeat config. Only callable by Governance.
    function updateMinHeartbeat(uint256 newMinHeartbeat_) external onlyGovernance {
        if (newMinHeartbeat_ > type(uint24).max || newMinHeartbeat_ == 0) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMinHeartbeat_ = uint256(_slot0.minHeartbeat);
        _slot0.minHeartbeat = uint24(newMinHeartbeat_);
        emit LogUpdateMinHeartbeat(oldMinHeartbeat_, newMinHeartbeat_);
    }

    /// @notice Updates the _minUpdateDiffPercent config. Only callable by Governance.
    function updateMinUpdateDiffPercent(uint256 newMinUpdateDiffPercent_) external onlyGovernance {
        if (newMinUpdateDiffPercent_ > type(uint16).max || newMinUpdateDiffPercent_ == 0) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        uint256 oldMinUpdateDiffPercent_ = uint256(_slot0.minUpdateDiffPercent);
        _slot0.minUpdateDiffPercent = uint16(newMinUpdateDiffPercent_);
        emit LogUpdateMinUpdateDiffPercent(oldMinUpdateDiffPercent_, newMinUpdateDiffPercent_);
    }
}

/// @notice This contract stores an exchange rate with caps in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
abstract contract FluidCappedRateBase is CappedRateInternals, CappedRateAdmin, IFluidCappedRate {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        _;
    }

    struct CappedRateConstructorParams {
        string infoName;
        address liquidity;
        address rateSource;
        uint256 rateMultiplier;
        bool invertCenterPrice;
        uint256 minUpdateDiffPercent;
        uint256 minHeartbeat;
        bool avoidForcedLiquidationsCol;
        bool avoidForcedLiquidationsDebt;
        uint256 maxAPRPercent;
        uint256 maxDownFromMaxReachedPercentCol;
        uint256 maxDownFromMaxReachedPercentDebt;
        uint256 maxDebtUpCapPercent;
    }

    constructor(
        CappedRateConstructorParams memory params_
    ) validAddress(params_.liquidity) validAddress(params_.rateSource) {
        if (
            params_.rateMultiplier == 0 ||
            params_.rateMultiplier > 1e21 ||
            params_.minUpdateDiffPercent == 0 ||
            params_.minUpdateDiffPercent > type(uint16).max ||
            params_.minHeartbeat == 0 ||
            params_.minHeartbeat > type(uint24).max ||
            params_.maxDownFromMaxReachedPercentCol > _SIX_DECIMALS ||
            params_.maxDownFromMaxReachedPercentDebt > _SIX_DECIMALS ||
            params_.maxAPRPercent > type(uint24).max * uint256(100) ||
            params_.maxDebtUpCapPercent > type(uint16).max * uint256(100)
        ) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
        _LIQUIDITY = params_.liquidity;
        _RATE_SOURCE = params_.rateSource;
        _RATE_MULTIPLIER = params_.rateMultiplier;
        _INVERT_CENTER_PRICE = params_.invertCenterPrice;

        _slot0.rate = uint168(_getNewRateRaw() * _RATE_MULTIPLIER);
        _slot0.lastUpdateTime = uint40(block.timestamp);

        _slot0.minUpdateDiffPercent = uint16(params_.minUpdateDiffPercent);
        _slot0.minHeartbeat = uint24(params_.minHeartbeat);

        _slot0.flags =
            (params_.avoidForcedLiquidationsCol ? _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL : 0) |
            (params_.avoidForcedLiquidationsDebt ? _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT : 0);

        _slot1.maxAPRPercent = uint24(params_.maxAPRPercent / uint256(100));
        _slot1.maxDownFromMaxReachedPercentCol = (params_.maxDownFromMaxReachedPercentCol == 0 &&
            !params_.avoidForcedLiquidationsCol)
            ? uint24(_SIX_DECIMALS) // set to 100% by default when this config is not active
            : uint24(params_.maxDownFromMaxReachedPercentCol);
        _slot1.maxDownFromMaxReachedPercentDebt = uint24(params_.maxDownFromMaxReachedPercentDebt);
        _slot1.maxDebtUpCapPercent = uint16(params_.maxDebtUpCapPercent / uint256(100));
        _slot1.maxReachedAPRCappedRate = _slot0.rate;
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() public view virtual returns (uint256 exchangeRate_) {
        // deprecated legacy support method -> Should not be used anywhere anymore.
        Slot0 memory slot0_ = _slot0;

        if (_isHeartbeatTrigger(slot0_)) {
            Slot1 memory slot1_ = _slot1;
            (exchangeRate_, , , ) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
            return exchangeRate_;
        }
        return uint256(slot0_.rate);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() public view virtual returns (uint256 exchangeRate_) {
        // for col -> up APR capped (avoid overpricing exploit), down no cap
        Slot0 memory slot0_ = _slot0;

        if (_isHeartbeatTrigger(slot0_)) {
            Slot1 memory slot1_ = _slot1;
            uint256 maxReachedRate_;
            bool isUpMaxAPRCapped_;
            (exchangeRate_, maxReachedRate_, isUpMaxAPRCapped_, ) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
            return isUpMaxAPRCapped_ ? maxReachedRate_ : exchangeRate_;
        }

        return
            (slot0_.flags & _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED == _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED) // is _isUpMaxAPRCapped
                ? uint256(_slot1.maxReachedAPRCappedRate)
                : uint256(slot0_.rate);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() public view virtual returns (uint256 exchangeRate_) {
        // for col -> up max APR cap, down capped (avoid forced liquidations attack)
        Slot0 memory slot0_ = _slot0;

        Slot1 memory slot1_; // only read if needed

        uint256 maxReachedRate_;
        bool isUpMaxAPRCapped_;
        bool isRateBelowMaxReached_;

        if (_isHeartbeatTrigger(slot0_)) {
            slot1_ = _slot1;
            (exchangeRate_, maxReachedRate_, isUpMaxAPRCapped_, isRateBelowMaxReached_) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
        } else {
            isUpMaxAPRCapped_ = slot0_.flags & _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED == _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED;
            isRateBelowMaxReached_ =
                slot0_.flags & _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED == _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED;
            exchangeRate_ = uint256(slot0_.rate);
        }

        if (isUpMaxAPRCapped_) {
            return maxReachedRate_ > 0 ? maxReachedRate_ : uint256(_slot1.maxReachedAPRCappedRate);
        }

        if (
            isRateBelowMaxReached_ &&
            (slot0_.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL == _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL)
        ) {
            // is _avoidForcedLiquidationsCol
            if (slot1_.maxReachedAPRCappedRate == 0) {
                slot1_ = _slot1;
            }

            return
                _calcDownCappedRate(
                    exchangeRate_,
                    maxReachedRate_ > 0 ? maxReachedRate_ : uint256(slot1_.maxReachedAPRCappedRate),
                    uint256(slot1_.maxDownFromMaxReachedPercentCol)
                );
        }

        return exchangeRate_;
    }

    /// @inheritdoc IFluidCappedRate
    function getExchangeRateOperateDebt() public view virtual returns (uint256 exchangeRate_) {
        // for debt -> up no cap, down capped (avoid underpricing exploit)
        Slot0 memory slot0_ = _slot0;

        Slot1 memory slot1_; // only read if needed

        uint256 maxReachedRate_;
        bool isRateBelowMaxReached_;

        if (_isHeartbeatTrigger(slot0_)) {
            slot1_ = _slot1;
            (exchangeRate_, maxReachedRate_, , isRateBelowMaxReached_) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
        } else {
            exchangeRate_ = uint256(slot0_.rate);
            isRateBelowMaxReached_ =
                slot0_.flags & _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED == _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED;
        }

        if (!isRateBelowMaxReached_) {
            return exchangeRate_;
        }

        if (slot1_.maxReachedAPRCappedRate == 0) {
            slot1_ = _slot1;
        }

        return
            _calcDownCappedRate(
                exchangeRate_,
                maxReachedRate_ > 0 ? maxReachedRate_ : uint256(slot1_.maxReachedAPRCappedRate),
                uint256(slot1_.maxDownFromMaxReachedPercentDebt)
            );
    }

    /// @inheritdoc IFluidCappedRate
    function getExchangeRateLiquidateDebt() public view virtual returns (uint256 exchangeRate_) {
        // for debt -> up max APR capped (avoid forced liquidations attack), down capped
        Slot0 memory slot0_ = _slot0;
        Slot1 memory slot1_; // only read if needed

        uint256 maxReachedRate_;
        bool isRateBelowMaxReached_;
        bool isUpMaxAPRCapped_;

        if (_isHeartbeatTrigger(slot0_)) {
            slot1_ = _slot1;
            (exchangeRate_, maxReachedRate_, isUpMaxAPRCapped_, isRateBelowMaxReached_) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
        } else {
            exchangeRate_ = uint256(slot0_.rate);
            isRateBelowMaxReached_ =
                slot0_.flags & _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED == _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED;
            isUpMaxAPRCapped_ = slot0_.flags & _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED == _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED;
        }

        if (
            isUpMaxAPRCapped_ &&
            (slot0_.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT ==
                _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT)
        ) {
            // is _avoidForcedLiquidationsDebt
            // case _rate > _maxReachedAPRCappedRate
            if (maxReachedRate_ == 0) {
                slot1_ = _slot1;
                maxReachedRate_ = uint256(slot1_.maxReachedAPRCappedRate);
            }
            // add max up cap percent on top
            maxReachedRate_ =
                (maxReachedRate_ * (_SIX_DECIMALS + uint256(slot1_.maxDebtUpCapPercent) * uint256(100))) /
                _SIX_DECIMALS;

            // return max(exchangeRate_, maxReachedRate_) where maxReachedRate_ is maxAPRReachedRate + maxDebtUpCapPercent on top
            return exchangeRate_ > maxReachedRate_ ? maxReachedRate_ : exchangeRate_;
        }

        if (!isRateBelowMaxReached_) {
            return exchangeRate_;
        }

        if (slot1_.maxReachedAPRCappedRate == 0) {
            slot1_ = _slot1;
        }

        return
            _calcDownCappedRate(
                exchangeRate_,
                maxReachedRate_ > 0 ? maxReachedRate_ : uint256(slot1_.maxReachedAPRCappedRate),
                uint256(slot1_.maxDownFromMaxReachedPercentDebt)
            );
    }

    /// @notice Rebalance the stored rates according to the newly fetched rate from the external source.
    /// @dev The rate is only updated if the difference between the current rate and the new rate is greater than or
    ///      equal to the minimum update difference percentage for either rate or maxRate OR if the heartbeat is reached
    function rebalance() external {
        _updateRates(_isHeartbeatTrigger(_slot0));
    }

    /// @notice Returns rates: capped and uncapped, and current cap status
    /// @return rate_ The rate_ value: last fetched value from external source with no cap up and no cap down as in storage
    /// @return maxReachedRate_ The maximum reached upward capped rate for col: within APR percent limit as in storage
    /// @return maxUpCappedRateDebt_ The maximum reached upward capped rate for debt: up to `maxReachedRate_` + `maxDebtUpCapPercent` on top
    /// @return isRateBelowMaxReached_ Indicates if the rate is currently below the maximum reached APR capped rate flag as in storage
    /// @return isUpMaxAPRCapped_ Indicates if the rate is currently capped due to exceeding the maximum APR limit flag as in storage
    /// @return downCappedRateCol_ The capped downward rate on col side
    /// @return downCappedRateDebt_ The capped downward rate on debt side
    /// @return isDownCappedCol_ Indicates if the rate is currently getting downward capped on col side
    /// @return isDownCappedDebt_ Indicates if the rate is currently getting downward capped on debt side
    /// @return isUpCapped_ Indicates if the rate is currently getting upward capped
    function getRatesAndCaps()
        public
        view
        returns (
            uint256 rate_,
            uint256 maxReachedRate_,
            uint256 maxUpCappedRateDebt_,
            bool isRateBelowMaxReached_,
            bool isUpMaxAPRCapped_,
            uint256 downCappedRateCol_,
            uint256 downCappedRateDebt_,
            bool isDownCappedCol_,
            bool isDownCappedDebt_,
            bool isUpCapped_
        )
    {
        Slot0 memory slot0_ = _slot0;
        Slot1 memory slot1_ = _slot1;

        if (_isHeartbeatTrigger(slot0_)) {
            (rate_, maxReachedRate_, isUpMaxAPRCapped_, isRateBelowMaxReached_) = _getUpdateRates(
                uint256(slot1_.maxReachedAPRCappedRate),
                slot0_,
                uint256(slot1_.maxAPRPercent)
            );
        } else {
            rate_ = uint256(slot0_.rate);
            maxReachedRate_ = uint256(slot1_.maxReachedAPRCappedRate);
            isRateBelowMaxReached_ =
                slot0_.flags & _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED == _FLAG_BITMASK_IS_RATE_BELOW_MAX_REACHED;
            isUpMaxAPRCapped_ = slot0_.flags & _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED == _FLAG_BITMASK_IS_UP_MAX_APR_CAPPED;
        }

        downCappedRateCol_ = _calcDownCappedRate(0, maxReachedRate_, uint256(slot1_.maxDownFromMaxReachedPercentCol));
        downCappedRateDebt_ = _calcDownCappedRate(0, maxReachedRate_, uint256(slot1_.maxDownFromMaxReachedPercentDebt));

        maxUpCappedRateDebt_ =
            (maxReachedRate_ * (_SIX_DECIMALS + uint256(slot1_.maxDebtUpCapPercent) * uint256(100))) /
            _SIX_DECIMALS;
        if (rate_ > maxReachedRate_ && rate_ < maxUpCappedRateDebt_) {
            // maxUpCappedRateDebt_ capped at + maxDebtUpCapPercent, but less if rate is less
            maxUpCappedRateDebt_ = rate_;
        }

        isDownCappedCol_ = rate_ < downCappedRateCol_;
        isDownCappedDebt_ = rate_ < downCappedRateDebt_;
        isUpCapped_ = rate_ > maxReachedRate_;
    }

    /// @notice returns how much the new rate OR new max rate would be different from current value in storage in percent (10000 = 1%, 1 = 0.0001%).
    function configPercentDiff() public view virtual returns (uint256 configPercentDiff_) {
        Slot0 memory slot0_ = _slot0;
        Slot1 memory slot1_ = _slot1;

        (uint256 newRate_, uint256 newMaxReachedRate_, , ) = _getUpdateRates(
            uint256(slot1_.maxReachedAPRCappedRate),
            slot0_,
            uint256(slot1_.maxAPRPercent)
        );

        uint256 rateDiff_ = _percentDiffForValue(uint256(slot0_.rate), newRate_);
        uint256 maxRateDiff_ = _percentDiffForValue(uint256(slot1_.maxReachedAPRCappedRate), newMaxReachedRate_);

        return rateDiff_ > maxRateDiff_ ? rateDiff_ : maxRateDiff_;
    }

    /// @notice returns all config vars, last update timestamp, and external rate source oracle address
    function configData()
        external
        view
        returns (
            address liquidity_,
            uint16 minUpdateDiffPercent_,
            uint24 minHeartbeat_,
            uint40 lastUpdateTime_,
            address rateSource_,
            bool invertCenterPrice_,
            bool avoidForcedLiquidationsCol_,
            bool avoidForcedLiquidationsDebt_,
            uint256 maxAPRPercent_,
            uint24 maxDownFromMaxReachedPercentCol_,
            uint24 maxDownFromMaxReachedPercentDebt_,
            uint256 maxDebtUpCapPercent_
        )
    {
        Slot0 memory slot0_ = _slot0;
        Slot1 memory slot1_ = _slot1;
        return (
            _LIQUIDITY,
            slot0_.minUpdateDiffPercent,
            slot0_.minHeartbeat,
            slot0_.lastUpdateTime,
            _RATE_SOURCE,
            _INVERT_CENTER_PRICE,
            (slot0_.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL) == _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_COL,
            (slot0_.flags & _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT) ==
                _FLAG_BITMASK_AVOID_FORCED_LIQUIDATIONS_DEBT,
            uint256(slot1_.maxAPRPercent) * uint256(100),
            slot1_.maxDownFromMaxReachedPercentCol,
            slot1_.maxDownFromMaxReachedPercentDebt,
            uint256(slot1_.maxDebtUpCapPercent) * uint256(100)
        );
    }

    /// @notice returns true if last update timestamp is > min heart time update time ago so heartbeat update should trigger
    function isHeartbeatTrigger() public view returns (bool) {
        return _isHeartbeatTrigger(_slot0);
    }
}

/// @notice This contract stores an exchange rate in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
abstract contract FluidCappedRate is FluidCappedRateBase, FluidCenterPrice {
    constructor(
        CappedRateConstructorParams memory params_
    ) FluidCappedRateBase(params_) FluidCenterPrice(params_.infoName) {}

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external override(IFluidCappedRate, FluidCenterPrice) returns (uint256 price_) {
        // for centerPrice -> no up cap, no down cap
        Slot0 memory slot0_ = _slot0;
        if (_isHeartbeatTrigger(slot0_)) {
            return _invertRateIfNeeded(_updateRates(true));
        }

        return _invertRateIfNeeded(uint256(slot0_.rate));
    }

    /// @inheritdoc FluidCenterPrice
    function infoName() public view override(IFluidOracle, FluidCenterPrice) returns (string memory) {
        return super.infoName();
    }

    /// @inheritdoc IFluidOracle
    function targetDecimals() public pure override(IFluidOracle, FluidCenterPrice) returns (uint8) {
        return _TARGET_DECIMALS;
    }
}
