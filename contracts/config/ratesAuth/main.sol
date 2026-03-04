// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";

abstract contract Constants {
    IFluidLiquidity public immutable LIQUIDITY;
    /// @notice Team multisigs allowed to trigger methods
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    uint256 internal constant X16 = 0xffff;

    uint256 public immutable PERCENT_RATE_CHANGE_ALLOWED;
    uint256 public immutable COOLDOWN;
}

abstract contract Events {
    /// @notice emitted when borrow rate for specified borrow token is updated based on
    ///         team multisig input of rate at kinks
    event LogUpdateRateAtKink(
        address borrowToken,
        uint256 oldRateKink1,
        uint256 newRateKink1,
        uint256 oldRateKink2,
        uint256 newRateKink2
    );
}

abstract contract Structs {
    struct RateAtKinkV1 {
        address token;
        uint256 rateAtUtilizationKink;
    }

    struct RateAtKinkV2 {
        address token;
        uint256 rateAtUtilizationKink1;
        uint256 rateAtUtilizationKink2;
    }
}

abstract contract Variables {
    /// @notice  last timestamp when a token's rate was updated
    mapping(address => uint256) public tokenLastUpdateTimestamp;
}

/// @notice Sets borrow rate for specified borrow token at Liquidity based on team multisig input.
contract FluidRatesAuth is Constants, Error, Events, Structs, Variables {
    /// @dev Validates that an address is a multisig (taken from reserve auth)
    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.RatesAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_, uint256 percentRateChangeAllowed_, uint256 cooldown_) {
        if (liquidity_ == address(0)) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidParams);
        }
        if (percentRateChangeAllowed_ == 0 || cooldown_ == 0) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidParams);
        }
        if (percentRateChangeAllowed_ > 1e4) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        PERCENT_RATE_CHANGE_ALLOWED = percentRateChangeAllowed_;
        COOLDOWN = cooldown_;
    }

    function updateRateDataV1(RateAtKinkV1 calldata rateStruct_) external onlyMultisig {
        bytes32 borrowRateDataSlot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
            rateStruct_.token
        );
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(borrowRateDataSlot_);
        if (rateConfig_ & 0xF != 1) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidVersion);
        }

        if (block.timestamp - tokenLastUpdateTimestamp[rateStruct_.token] < COOLDOWN) {
            revert FluidConfigError(ErrorTypes.RatesAuth__CooldownLeft);
        }

        AdminModuleStructs.RateDataV1Params memory rateData_;
        rateData_.token = rateStruct_.token;

        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) & X16;

        // checks the diff to be lesser than allowed
        if (_percentDiffForValue(oldRateKink1_, rateStruct_.rateAtUtilizationKink) > PERCENT_RATE_CHANGE_ALLOWED) {
            revert FluidConfigError(ErrorTypes.RatesAuth__NoUpdate);
        }

        // setting up the rateData_ struct
        rateData_.token = rateStruct_.token;
        rateData_.kink = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
        rateData_.rateAtUtilizationZero =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) &
            X16;
        rateData_.rateAtUtilizationKink = rateStruct_.rateAtUtilizationKink;
        rateData_.rateAtUtilizationMax =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) &
            X16;

        AdminModuleStructs.RateDataV1Params[] memory liquidityParams_ = new AdminModuleStructs.RateDataV1Params[](1);
        liquidityParams_[0] = rateData_;
        LIQUIDITY.updateRateDataV1s(liquidityParams_);

        tokenLastUpdateTimestamp[rateData_.token] = block.timestamp;

        emit LogUpdateRateAtKink(rateData_.token, oldRateKink1_, rateStruct_.rateAtUtilizationKink, 0, 0);
    }

    function updateRateDataV2(RateAtKinkV2 calldata rateStruct_) external onlyMultisig {
        bytes32 borrowRateDataSlot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
            rateStruct_.token
        );
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(borrowRateDataSlot_);
        if (rateConfig_ & 0xF != 2) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidVersion);
        }

        if (block.timestamp - tokenLastUpdateTimestamp[rateStruct_.token] < COOLDOWN) {
            revert FluidConfigError(ErrorTypes.RatesAuth__CooldownLeft);
        }

        AdminModuleStructs.RateDataV2Params memory rateData_;

        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) & X16;
        uint256 oldRateKink2_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) & X16;

        if (
            _percentDiffForValue(oldRateKink1_, rateStruct_.rateAtUtilizationKink1) > PERCENT_RATE_CHANGE_ALLOWED ||
            _percentDiffForValue(oldRateKink2_, rateStruct_.rateAtUtilizationKink2) > PERCENT_RATE_CHANGE_ALLOWED
        ) {
            revert FluidConfigError(ErrorTypes.RatesAuth__NoUpdate);
        }

        // setting up the rateData_ struct
        rateData_.token = rateStruct_.token;
        rateData_.kink1 = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) & X16;
        rateData_.kink2 = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) & X16;
        rateData_.rateAtUtilizationZero =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) &
            X16;
        rateData_.rateAtUtilizationKink1 = rateStruct_.rateAtUtilizationKink1;
        rateData_.rateAtUtilizationKink2 = rateStruct_.rateAtUtilizationKink2;
        rateData_.rateAtUtilizationMax =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) &
            X16;

        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = rateData_;
        LIQUIDITY.updateRateDataV2s(params_);
        tokenLastUpdateTimestamp[rateStruct_.token] = block.timestamp;

        emit LogUpdateRateAtKink(
            rateStruct_.token,
            oldRateKink1_,
            rateStruct_.rateAtUtilizationKink1,
            oldRateKink2_,
            rateStruct_.rateAtUtilizationKink2
        );
    }

    /// @dev gets the percentage difference between `oldValue_` and `newValue_` in relation to `oldValue_`
    function _percentDiffForValue(
        uint256 oldValue_,
        uint256 newValue_
    ) internal pure returns (uint256 configPercentDiff_) {
        if (oldValue_ == newValue_) {
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

        configPercentDiff_ = (configPercentDiff_ * 1e4) / oldValue_;
    }
}
