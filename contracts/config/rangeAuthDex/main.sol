// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";

interface IFluidDexT1Admin {
    /// @notice updates the upper and lower percent configs for a dex
    /// @param upperPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerPercent_ in 4 decimals, 10000 = 1%
    /// @param shiftTime_ in secs, in how much time the upper percent configs change should be fully done
    function updateRangePercents(uint upperPercent_, uint lowerPercent_, uint shiftTime_) external;

    /// @param upperThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param thresholdShiftTime_ in secs, in how much time the threshold percent should take to shift the ranges
    /// @param shiftTime_ in secs, in how much time the upper config changes should be fully done.
    function updateThresholdPercent(
        uint upperThresholdPercent_,
        uint lowerThresholdPercent_,
        uint thresholdShiftTime_,
        uint shiftTime_
    ) external;
}

abstract contract Events {
    /// @notice emitted when multisig successfully changes the upper and lower range percent configs
    event LogSetRanges(address dex, uint upperPercent, uint lowerPercent, uint shiftTime);

    /// @notice emitted when multisig successfully changes threshold configs
    event LogSetThresholdConfig(
        address dex,
        uint upperPercent,
        uint lowerPercent,
        uint thresholdShiftTime,
        uint shiftTime
    );
}

abstract contract Constants is FluidAuthLevels {
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X24 = 0xffffff;

    uint256 internal constant THREE_DECIMALS = 1e3;

    /// @dev cooldown for config updates is 1 day
    uint256 public constant COOLDOWN = 1 days;

    /// @dev max percent range change allowed is 30%
    uint256 public constant MAX_PERCENT_RANGE_CHANGE_ALLOWED = 30 * 1e4;

    /// @dev shift time must be >= 2 days <= 12 days (except for wsteth and weeth eth dexes)
    uint256 public constant MIN_SHIFT_TIME = 2 days;
    uint256 public constant MAX_SHIFT_TIME = 12 days;

    /// @notice auth gate resolving multisig/governance identity; MID-level auths pass `onlyAuthLevelMid`.
    IFluidAuthGate public immutable AUTH_GATE;

    /// @dev wsteth eth dex, must shift instantly (only on mainnet)
    address public immutable WSTETH_ETH_DEX;

    /// @dev weeth eth dex, must shift instantly (only on mainnet)
    address public immutable WEETH_ETH_DEX;
}

abstract contract Variables is Constants {
    enum UpdateType {
        RANGES, // 0
        THRESHOLD // 1
    }

    /// @notice dex => UpdateType => last update time when a Dex config was updated
    mapping(address => mapping(UpdateType => uint256)) public dexLastUpdateTimestamp;
}

contract FluidRangeAuthDex is Variables, Error, Events, BasicValidations {
    modifier onlyAuthLevelMid() {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        _;
    }

    constructor(address wstethEthDex_, address weethEthDex_, address authGate_) validAddress(authGate_) {
        if (
            (block.chainid == 1 && (wstethEthDex_ == address(0) || weethEthDex_ == address(0))) ||
            IFluidAuthGateLiquidity(authGate_).LIQUIDITY() == address(0)
        ) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__InvalidParams);
        }
        WSTETH_ETH_DEX = wstethEthDex_;
        WEETH_ETH_DEX = weethEthDex_;
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    function getRanges(address dex_) public view returns (uint256 upperRangePercent_, uint256 lowerRangePercent_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));

        upperRangePercent_ = (dexVariables2_ >> 27) & X20;
        lowerRangePercent_ = (dexVariables2_ >> 47) & X20;
    }

    function getThresholdConfig(
        address dex_
    )
        public
        view
        returns (uint256 upperThresholdPercent_, uint256 lowerThresholdPercent_, uint256 thresholdShiftTime_)
    {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));

        upperThresholdPercent_ = ((dexVariables2_ >> 68) & X10) * THREE_DECIMALS;
        lowerThresholdPercent_ = ((dexVariables2_ >> 78) & X10) * THREE_DECIMALS;
        thresholdShiftTime_ = (dexVariables2_ >> 88) & X24;
    }

    /// @notice Sets the upper and lower range for a dex
    ///         Reverts if both ranges equal the current ones or either moves more than 30%.
    /// @param dex_ The address of the dex
    /// @param upperRangePercent_ The new upper range to be set
    /// @param lowerRangePercent_ The new lower range to be set
    function setRanges(
        address dex_,
        uint256 upperRangePercent_,
        uint256 lowerRangePercent_,
        uint256 shiftTime_
    ) external onlyAuthLevelMid {
        _validateLastUpdateTime(dex_, UpdateType.RANGES);
        _validateShiftTime(dex_, shiftTime_);

        (uint256 currentUpperRangePercent_, uint256 currentLowerRangePercent_) = getRanges(dex_);
        if (upperRangePercent_ == currentUpperRangePercent_ && lowerRangePercent_ == currentLowerRangePercent_) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__NoChange);
        }

        _validateChange(currentUpperRangePercent_, upperRangePercent_);
        _validateChange(currentLowerRangePercent_, lowerRangePercent_);

        dexLastUpdateTimestamp[dex_][UpdateType.RANGES] = block.timestamp;

        IFluidDexT1Admin(dex_).updateRangePercents(upperRangePercent_, lowerRangePercent_, shiftTime_);

        emit LogSetRanges(dex_, upperRangePercent_, lowerRangePercent_, shiftTime_);
    }

    /// @notice Sets the upper and lower range for a dex by percentage to change from current config
    ///         Reverts if a delta exceeds 30% or the resulting ranges equal the current ones.
    /// @param dex_ The address of the dex
    /// @param newUpperRangePercentage_ The new upper range percentage change, 10000 = 1%. Positive to increase, negative to decrease
    /// @param newLowerRangePercentage_ The new lower range percentage change, 10000 = 1%. Positive to increase, negative to decrease
    function setRangesByPercentage(
        address dex_,
        int256 newUpperRangePercentage_,
        int256 newLowerRangePercentage_,
        uint256 shiftTime_
    ) external onlyAuthLevelMid {
        _validateLastUpdateTime(dex_, UpdateType.RANGES);
        _validateShiftTime(dex_, shiftTime_);

        _validatePercentChange(_abs(newUpperRangePercentage_));
        _validatePercentChange(_abs(newLowerRangePercentage_));

        (uint256 currentUpperRangePercent_, uint256 currentLowerRangePercent_) = getRanges(dex_);

        uint256 newUpperRangePercent_ = _getNewRange(currentUpperRangePercent_, newUpperRangePercentage_);
        uint256 newLowerRangePercent_ = _getNewRange(currentLowerRangePercent_, newLowerRangePercentage_);
        if (newUpperRangePercent_ == currentUpperRangePercent_ && newLowerRangePercent_ == currentLowerRangePercent_) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__NoChange);
        }

        dexLastUpdateTimestamp[dex_][UpdateType.RANGES] = block.timestamp;

        IFluidDexT1Admin(dex_).updateRangePercents(newUpperRangePercent_, newLowerRangePercent_, shiftTime_);

        emit LogSetRanges(dex_, newUpperRangePercent_, newLowerRangePercent_, shiftTime_);
    }

    /// @notice Sets the upper and lower threshold percent for a dex
    ///         Reverts if nothing changes at the DEX's 0.1% threshold precision, a field moves more than 30%, or a
    ///         threshold moves off 0 (switching threshold rebalancing on is left to governance or a DEX auth).
    /// @param dex_ The address of the dex
    /// @param upperThresholdPercent_ The new upper threshold percent, 10000 = 1%
    /// @param lowerThresholdPercent_ The new lower threshold percent, 10000 = 1%
    /// @param thresholdShiftTime_ The new threshold shift time
    function setThresholdConfig(
        address dex_,
        uint256 upperThresholdPercent_,
        uint256 lowerThresholdPercent_,
        uint256 thresholdShiftTime_,
        uint256 shiftTime_
    ) external onlyAuthLevelMid {
        _validateLastUpdateTime(dex_, UpdateType.THRESHOLD);
        _validateShiftTime(dex_, shiftTime_);

        (
            uint256 currentUpperThresholdPercent_,
            uint256 currentLowerThresholdPercent_,
            uint256 currentThresholdShiftTime_
        ) = getThresholdConfig(dex_);
        // the DEX stores thresholds in 0.1% steps, so compare at that precision
        if (
            upperThresholdPercent_ / THREE_DECIMALS == currentUpperThresholdPercent_ / THREE_DECIMALS &&
            lowerThresholdPercent_ / THREE_DECIMALS == currentLowerThresholdPercent_ / THREE_DECIMALS &&
            thresholdShiftTime_ == currentThresholdShiftTime_
        ) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__NoChange);
        }

        _validateChange(currentUpperThresholdPercent_, upperThresholdPercent_);
        _validateChange(currentLowerThresholdPercent_, lowerThresholdPercent_);
        _validateChange(currentThresholdShiftTime_, thresholdShiftTime_);

        dexLastUpdateTimestamp[dex_][UpdateType.THRESHOLD] = block.timestamp;

        IFluidDexT1Admin(dex_).updateThresholdPercent(
            upperThresholdPercent_,
            lowerThresholdPercent_,
            thresholdShiftTime_,
            shiftTime_
        );

        emit LogSetThresholdConfig(
            dex_,
            upperThresholdPercent_,
            lowerThresholdPercent_,
            thresholdShiftTime_,
            shiftTime_
        );
    }

    function _percentDiffForValue(
        uint256 oldValue_,
        uint256 newValue_
    ) internal pure returns (uint256 configPercentDiff_) {
        if (oldValue_ == newValue_) {
            return 0;
        }
        if (oldValue_ == 0) {
            // a 0 threshold is re-centring switched off, not unset; switching it on is not a capped nudge
            return type(uint256).max;
        }

        if (oldValue_ > newValue_) {
            // % of how much new value would be smaller
            configPercentDiff_ = oldValue_ - newValue_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 10 -> 2000 (20%)
        } else {
            // % of how much new value would be bigger
            configPercentDiff_ = newValue_ - oldValue_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 8 -> 2500 (25%)
        }

        configPercentDiff_ = (configPercentDiff_ * 1e6) / oldValue_;
    }

    function _getNewRange(uint256 currentRange_, int256 newRangePercentage_) internal pure returns (uint256 newRange_) {
        if (newRangePercentage_ > 0) {
            /// @dev newRangePercentage_ is 10000 = 1%
            newRange_ = currentRange_ + (currentRange_ * uint256(newRangePercentage_)) / 1e6;
        } else {
            newRange_ = currentRange_ - (currentRange_ * uint256(-newRangePercentage_)) / 1e6;
        }
    }

    function _validatePercentChange(uint256 percent_) internal pure {
        if (percent_ > MAX_PERCENT_RANGE_CHANGE_ALLOWED) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__ExceedAllowedPercentageChange);
        }
    }

    function _validateChange(uint256 oldConfig_, uint256 newConfig_) internal pure {
        uint256 configPercentage_ = _percentDiffForValue(oldConfig_, newConfig_);
        _validatePercentChange(configPercentage_);
    }

    function _validateShiftTime(address dex_, uint256 shiftTime_) internal view {
        if ((block.chainid == 1) && (dex_ == WSTETH_ETH_DEX || dex_ == WEETH_ETH_DEX)) {
            /// @dev wsteth eth and weeth dex has zero shift time
            if (shiftTime_ != 0) {
                revert FluidConfigError(ErrorTypes.RangeAuthDex__InvalidShiftTime);
            }
        } else {
            if (shiftTime_ < MIN_SHIFT_TIME || shiftTime_ > MAX_SHIFT_TIME) {
                revert FluidConfigError(ErrorTypes.RangeAuthDex__InvalidShiftTime);
            }
        }
    }

    function _validateLastUpdateTime(address dex_, UpdateType updateType_) internal view {
        if (block.timestamp - dexLastUpdateTimestamp[dex_][updateType_] < COOLDOWN) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__CooldownLeft);
        }
    }

    function _abs(int256 value_) internal pure returns (uint256) {
        return value_ > 0 ? uint256(value_) : uint256(-value_);
    }
}
