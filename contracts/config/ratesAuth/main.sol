// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";

abstract contract Constants is FluidAuthLevels {
    IFluidLiquidity public immutable LIQUIDITY;
    /// @notice auth gate resolving multisig/governance identity; MID-level auths pass `onlyAuthLevelMid`.
    IFluidAuthGate public immutable AUTH_GATE;

    uint256 internal constant X16 = 0xffff;

    /// @dev max relative borrow-rate change per update; 3000 / 1e4 = 30%.
    uint256 public constant RATE_RELATIVE_MAX_DELTA = 3000;

    /// @dev cooldown between updates for the same token.
    uint256 public constant COOLDOWN = 1 days;

    /// @dev max absolute change for utilization kink positions per update (10 pp on the 10_000 = 100% scale).
    uint256 internal constant KINK_MAX_ABSOLUTE_DELTA = 1000;

    /// @dev max absolute borrow-rate change per update (100 == 1% APR). Applies as a floor when the relative
    ///      term is smaller: allowed |Δ| = max(RATE_RELATIVE_MAX_DELTA relative, RATE_ABSOLUTE_MAX_DELTA absolute).
    uint256 internal constant RATE_ABSOLUTE_MAX_DELTA = 100;
}

abstract contract Events {
    /// @notice emitted when a V1 borrow rate curve is updated
    event LogUpdateRateDataV1(AdminModuleStructs.RateDataV1Params oldRate, AdminModuleStructs.RateDataV1Params newRate);

    /// @notice emitted when a V2 borrow rate curve is updated
    event LogUpdateRateDataV2(AdminModuleStructs.RateDataV2Params oldRate, AdminModuleStructs.RateDataV2Params newRate);
}

abstract contract Variables {
    /// @notice last timestamp when a token's rate was updated
    mapping(address => uint256) public tokenLastUpdateTimestamp;
}

/// @notice Sets borrow rate for specified borrow token at Liquidity based on team multisig input.
contract FluidRatesAuth is Constants, Error, Events, Variables, BasicValidations {
    modifier onlyAuthLevelMid() {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        _;
    }

    constructor(address liquidity_, address authGate_) validAddress(liquidity_) validAddress(authGate_) {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() != liquidity_) {
            revert FluidConfigError(ErrorTypes.RatesAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    /// @notice Update V1 rate curve. For kink, rateAtUtilizationKink, and rateAtUtilizationMax,
    ///         calldata `0` means "leave unchanged" (previous stored value is kept).
    ///         `rateAtUtilizationZero` is the only field where `0` is a real literal value (not a skip sentinel).
    ///         All rates are capped at max(RATE_RELATIVE_MAX_DELTA relative, RATE_ABSOLUTE_MAX_DELTA absolute)
    ///         per update in both directions. Kinks are capped at KINK_MAX_ABSOLUTE_DELTA absolute.
    ///         Reverts `RatesAuth__NoChange` if the resolved config matches the current one.
    function updateRateDataV1(AdminModuleStructs.RateDataV1Params calldata rateStruct_) external onlyAuthLevelMid {
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

        uint256 oldKink_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
        uint256 oldRateZero_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) & X16;
        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) & X16;
        uint256 oldRateMax_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) & X16;

        AdminModuleStructs.RateDataV1Params memory out_;
        out_.token = rateStruct_.token;
        out_.kink = rateStruct_.kink == 0 ? oldKink_ : rateStruct_.kink;
        out_.rateAtUtilizationZero = rateStruct_.rateAtUtilizationZero;
        out_.rateAtUtilizationKink = rateStruct_.rateAtUtilizationKink == 0
            ? oldRateKink1_
            : rateStruct_.rateAtUtilizationKink;
        out_.rateAtUtilizationMax = rateStruct_.rateAtUtilizationMax == 0
            ? oldRateMax_
            : rateStruct_.rateAtUtilizationMax;

        if (
            out_.kink == oldKink_ &&
            out_.rateAtUtilizationZero == oldRateZero_ &&
            out_.rateAtUtilizationKink == oldRateKink1_ &&
            out_.rateAtUtilizationMax == oldRateMax_
        ) {
            // a no-op would still stamp the cooldown, locking the token for everyone incl. HIGH
            revert FluidConfigError(ErrorTypes.RatesAuth__NoChange);
        }

        _requireKinkAbsoluteDelta(oldKink_, out_.kink);
        _requireBorrowRateDelta(oldRateZero_, out_.rateAtUtilizationZero);
        _requireBorrowRateDelta(oldRateKink1_, out_.rateAtUtilizationKink);
        _requireBorrowRateDelta(oldRateMax_, out_.rateAtUtilizationMax);

        AdminModuleStructs.RateDataV1Params[] memory liquidityParams_ = new AdminModuleStructs.RateDataV1Params[](1);
        liquidityParams_[0] = out_;
        LIQUIDITY.updateRateDataV1s(liquidityParams_);

        tokenLastUpdateTimestamp[rateStruct_.token] = block.timestamp;

        emit LogUpdateRateDataV1(
            AdminModuleStructs.RateDataV1Params({
                token: rateStruct_.token,
                kink: oldKink_,
                rateAtUtilizationZero: oldRateZero_,
                rateAtUtilizationKink: oldRateKink1_,
                rateAtUtilizationMax: oldRateMax_
            }),
            out_
        );
    }

    /// @notice Update V2 rate curve. Same semantics as V1: calldata `0` = leave unchanged for all fields
    ///         except `rateAtUtilizationZero` (where `0` is a real literal). Caps same as V1.
    ///         Reverts `RatesAuth__NoChange` if the resolved config matches the current one.
    function updateRateDataV2(AdminModuleStructs.RateDataV2Params calldata rateStruct_) external onlyAuthLevelMid {
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

        uint256 oldRateZero_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) & X16;
        uint256 oldKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) & X16;
        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) & X16;
        uint256 oldKink2_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) & X16;
        uint256 oldRateKink2_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) & X16;
        uint256 oldRateMax_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) & X16;

        AdminModuleStructs.RateDataV2Params memory out_;
        out_.token = rateStruct_.token;
        out_.kink1 = rateStruct_.kink1 == 0 ? oldKink1_ : rateStruct_.kink1;
        out_.kink2 = rateStruct_.kink2 == 0 ? oldKink2_ : rateStruct_.kink2;
        out_.rateAtUtilizationZero = rateStruct_.rateAtUtilizationZero;
        out_.rateAtUtilizationKink1 = rateStruct_.rateAtUtilizationKink1 == 0
            ? oldRateKink1_
            : rateStruct_.rateAtUtilizationKink1;
        out_.rateAtUtilizationKink2 = rateStruct_.rateAtUtilizationKink2 == 0
            ? oldRateKink2_
            : rateStruct_.rateAtUtilizationKink2;
        out_.rateAtUtilizationMax = rateStruct_.rateAtUtilizationMax == 0
            ? oldRateMax_
            : rateStruct_.rateAtUtilizationMax;

        if (
            out_.kink1 == oldKink1_ &&
            out_.kink2 == oldKink2_ &&
            out_.rateAtUtilizationZero == oldRateZero_ &&
            out_.rateAtUtilizationKink1 == oldRateKink1_ &&
            out_.rateAtUtilizationKink2 == oldRateKink2_ &&
            out_.rateAtUtilizationMax == oldRateMax_
        ) {
            // a no-op would still stamp the cooldown, locking the token for everyone incl. HIGH
            revert FluidConfigError(ErrorTypes.RatesAuth__NoChange);
        }

        _requireKinkAbsoluteDelta(oldKink1_, out_.kink1);
        _requireKinkAbsoluteDelta(oldKink2_, out_.kink2);
        _requireBorrowRateDelta(oldRateZero_, out_.rateAtUtilizationZero);
        _requireBorrowRateDelta(oldRateKink1_, out_.rateAtUtilizationKink1);
        _requireBorrowRateDelta(oldRateKink2_, out_.rateAtUtilizationKink2);
        _requireBorrowRateDelta(oldRateMax_, out_.rateAtUtilizationMax);

        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = out_;
        LIQUIDITY.updateRateDataV2s(params_);
        tokenLastUpdateTimestamp[rateStruct_.token] = block.timestamp;

        emit LogUpdateRateDataV2(
            AdminModuleStructs.RateDataV2Params({
                token: rateStruct_.token,
                kink1: oldKink1_,
                kink2: oldKink2_,
                rateAtUtilizationZero: oldRateZero_,
                rateAtUtilizationKink1: oldRateKink1_,
                rateAtUtilizationKink2: oldRateKink2_,
                rateAtUtilizationMax: oldRateMax_
            }),
            out_
        );
    }

    function _absoluteDiff(uint256 a_, uint256 b_) internal pure returns (uint256) {
        unchecked {
            return a_ > b_ ? a_ - b_ : b_ - a_;
        }
    }

    /// @dev relative diff of `new_` vs `old_` in 1e4 scale. Returns `type(uint256).max` when `old_ == 0`
    ///      so the relative leg is always exceeded and only the absolute cap applies.
    function _relativeDiff(uint256 old_, uint256 new_) internal pure returns (uint256) {
        if (old_ == 0) {
            return type(uint256).max;
        }
        return (_absoluteDiff(old_, new_) * 1e4) / old_;
    }

    function _requireKinkAbsoluteDelta(uint256 oldValue_, uint256 newValue_) internal pure {
        if (_absoluteDiff(oldValue_, newValue_) > KINK_MAX_ABSOLUTE_DELTA) {
            revert FluidConfigError(ErrorTypes.RatesAuth__AllowedDeltaExceeded);
        }
    }

    /// @dev all borrow rates: allowed |Δ| = max(RATE_RELATIVE_MAX_DELTA relative, RATE_ABSOLUTE_MAX_DELTA absolute).
    ///      Reverts when the change exceeds both caps simultaneously (equivalent to exceeding the larger of the two).
    function _requireBorrowRateDelta(uint256 old_, uint256 new_) internal pure {
        if (old_ == new_) {
            return;
        }
        if (
            _absoluteDiff(old_, new_) > RATE_ABSOLUTE_MAX_DELTA && _relativeDiff(old_, new_) > RATE_RELATIVE_MAX_DELTA
        ) {
            revert FluidConfigError(ErrorTypes.RatesAuth__AllowedDeltaExceeded);
        }
    }
}
