// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";

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

abstract contract Constants {
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X24 = 0xffffff;

    uint256 internal constant THREE_DECIMALS = 1e3;

    /// @dev cooldown for config updates is 4 days
    uint256 public constant COOLDOWN = 4 days;

    /// @dev max percent range change allowed is 20%
    uint256 public constant MAX_PERCENT_RANGE_CHANGE_ALLOWED = 20 * 1e4;

    /// @dev shift time must be >= 2 days <= 12 days (except for wsteth and weeth eth dexes)
    uint256 public constant MIN_SHIFT_TIME = 2 days;
    uint256 public constant MAX_SHIFT_TIME = 12 days;

    /// @notice Team multisigs allowed to trigger methods
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

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

contract FluidRangeAuthDex is Variables, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__InvalidParams);
        }
        _;
    }

    /// @dev Validates that an address is the team multisig
    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__Unauthorized);
        }
        _;
    }

    constructor(address wstethEthDex_, address weethEthDex_) {
        if ((block.chainid == 1) && (wstethEthDex_ == address(0) || weethEthDex_ == address(0))) {
            revert FluidConfigError(ErrorTypes.RangeAuthDex__InvalidParams);
        }
        WSTETH_ETH_DEX = wstethEthDex_;
        WEETH_ETH_DEX = weethEthDex_;
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
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex
    /// @param upperRangePercent_ The new upper range to be set
    /// @param lowerRangePercent_ The new lower range to be set
    function setRanges(
        address dex_,
        uint256 upperRangePercent_,
        uint256 lowerRangePercent_,
        uint256 shiftTime_
    ) external onlyMultisig {
        _validateLastUpdateTime(dex_, UpdateType.RANGES);
        _validateShiftTime(dex_, shiftTime_);

        (uint256 currentUpperRangePercent_, uint256 currentLowerRangePercent_) = getRanges(dex_);

        _validateChange(currentUpperRangePercent_, upperRangePercent_);
        _validateChange(currentLowerRangePercent_, lowerRangePercent_);

        dexLastUpdateTimestamp[dex_][UpdateType.RANGES] = block.timestamp;

        IFluidDexT1Admin(dex_).updateRangePercents(upperRangePercent_, lowerRangePercent_, shiftTime_);

        emit LogSetRanges(dex_, upperRangePercent_, lowerRangePercent_, shiftTime_);
    }

    /// @notice Sets the upper and lower range for a dex by percentage to change from current config
    /// @dev This function can only be called by team multisig
    /// @param dex_ The address of the dex
    /// @param newUpperRangePercentage_ The new upper range percentage change, 10000 = 1%. Positive to increase, negative to decrease
    /// @param newLowerRangePercentage_ The new lower range percentage change, 10000 = 1%. Positive to increase, negative to decrease
    function setRangesByPercentage(
        address dex_,
        int256 newUpperRangePercentage_,
        int256 newLowerRangePercentage_,
        uint256 shiftTime_
    ) external onlyMultisig {
        _validateLastUpdateTime(dex_, UpdateType.RANGES);
        _validateShiftTime(dex_, shiftTime_);

        _validatePercentChange(_abs(newUpperRangePercentage_));
        _validatePercentChange(_abs(newLowerRangePercentage_));

        (uint256 currentUpperRangePercent_, uint256 currentLowerRangePercent_) = getRanges(dex_);

        uint256 newUpperRangePercent_ = _getNewRange(currentUpperRangePercent_, newUpperRangePercentage_);
        uint256 newLowerRangePercent_ = _getNewRange(currentLowerRangePercent_, newLowerRangePercentage_);

        dexLastUpdateTimestamp[dex_][UpdateType.RANGES] = block.timestamp;

        IFluidDexT1Admin(dex_).updateRangePercents(newUpperRangePercent_, newLowerRangePercent_, shiftTime_);

        emit LogSetRanges(dex_, newUpperRangePercent_, newLowerRangePercent_, shiftTime_);
    }

    /// @notice Sets the upper and lower threshold percent for a dex
    /// @dev This function can only be called by team multisig
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
    ) external onlyMultisig {
        _validateLastUpdateTime(dex_, UpdateType.THRESHOLD);
        _validateShiftTime(dex_, shiftTime_);

        (
            uint256 currentUpperThresholdPercent_,
            uint256 currentLowerThresholdPercent_,
            uint256 currentThresholdShiftTime_
        ) = getThresholdConfig(dex_);

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
        if (oldValue_ == 0 || oldValue_ == newValue_) {
            return 0;
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
