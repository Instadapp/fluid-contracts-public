// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";

abstract contract Constants {
    IFluidReserveContract public immutable RESERVE_CONTRACT;
    IFluidLiquidity public immutable LIQUIDITY;

    /// @notice supply token at Liquidity which borrow rate is based on
    address public immutable SUPPLY_TOKEN;
    /// @notice borrow token at Liquidity for which the borrow rate is managed
    address public immutable BORROW_TOKEN;

    /// @notice buffer at kink1 for the rate. borrow rate = supply rate + buffer. In percent (100 = 1%, 1 = 0.01%)
    int256 public immutable RATE_BUFFER_KINK1;
    /// @notice buffer at kink2 for the rate. borrow rate = supply rate + buffer. In percent (100 = 1%, 1 = 0.01%)
    /// @dev only used if CURRENT borrow rate mode at Liquidity is V2 (with 2 kinks).
    int256 public immutable RATE_BUFFER_KINK2;

    /// @dev minimum percent difference to trigger an update. In percent (100 = 1%, 1 = 0.01%)
    uint256 public immutable MIN_UPDATE_DIFF;

    bytes32 internal immutable _LIQUDITY_SUPPLY_TOTAL_AMOUNTS_SLOT;
    bytes32 internal immutable _LIQUDITY_SUPPLY_EXCHANGE_PRICES_AND_CONFIG_SLOT;

    bytes32 internal immutable _LIQUDITY_BORROW_RATE_DATA_SLOT;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xff;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
    uint256 internal constant FOUR_DECIMALS = 10000;
}

abstract contract Events {
    /// @notice emitted when borrow rate for `BORROW_TOKEN` is updated based on
    ///          supply rate of `SUPPLY_TOKEN` + buffer.
    event LogUpdateRate(
        uint256 supplyRate,
        uint256 oldRateKink1,
        uint256 newRateKink1,
        uint256 oldRateKink2,
        uint256 newRateKink2
    );
}

/// @notice Sets borrow rate for `BORROW_TOKEN` at Liquidaty based on supply rate of `SUPPLY_TOKEN` + buffer.
contract FluidBufferRateHandler is Constants, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        IFluidLiquidity liquidity_,
        address supplyToken_,
        address borrowToken_,
        int256 rateBufferKink1_,
        int256 rateBufferKink2_,
        uint256 minUpdateDiff_
    )
        validAddress(address(reserveContract_))
        validAddress(address(liquidity_))
        validAddress(supplyToken_)
        validAddress(borrowToken_)
    {
        if (
            minUpdateDiff_ == 0 ||
            // rate buffer should be within +100% to - 100%
            rateBufferKink1_ > 1e4 ||
            rateBufferKink1_ < -int256(1e4) ||
            rateBufferKink2_ > 1e4 ||
            rateBufferKink2_ < -int256(1e4)
        ) {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__InvalidParams);
        }

        RESERVE_CONTRACT = reserveContract_;
        LIQUIDITY = liquidity_;
        SUPPLY_TOKEN = supplyToken_;
        BORROW_TOKEN = borrowToken_;
        MIN_UPDATE_DIFF = minUpdateDiff_;

        RATE_BUFFER_KINK1 = rateBufferKink1_;
        RATE_BUFFER_KINK2 = rateBufferKink2_;

        _LIQUDITY_SUPPLY_TOTAL_AMOUNTS_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            supplyToken_
        );
        _LIQUDITY_SUPPLY_EXCHANGE_PRICES_AND_CONFIG_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            supplyToken_
        );

        _LIQUDITY_BORROW_RATE_DATA_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
            borrowToken_
        );
    }

    function configPercentDiff() public view returns (uint256 configPercentDiff_) {
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(_LIQUDITY_BORROW_RATE_DATA_SLOT);

        (uint256 newRateKink1_, uint256 newRateKink2_) = _calcBorrowRates(supplyTokenLendingRate(), rateConfig_);

        uint256 rateVersion_ = rateConfig_ & 0xF;
        if (rateVersion_ == 1) {
            uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) &
                X16;
            configPercentDiff_ = _percentDiffForValue(oldRateKink1_, newRateKink1_);
        } else if (rateVersion_ == 2) {
            uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) &
                X16;
            uint256 oldRateKink2_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) &
                X16;

            configPercentDiff_ = _percentDiffForValue(oldRateKink1_, newRateKink1_);
            uint256 rateKink2Diff_ = _percentDiffForValue(oldRateKink2_, newRateKink2_);
            // final diff = biggest diff between all config values
            configPercentDiff_ = configPercentDiff_ > rateKink2Diff_ ? configPercentDiff_ : rateKink2Diff_;
        } else {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__RateVersionUnsupported);
        }
    }

    function rebalance() external onlyRebalancer {
        uint256 supplyLendingRate_ = supplyTokenLendingRate();
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(_LIQUDITY_BORROW_RATE_DATA_SLOT);

        uint256 rateVersion_ = rateConfig_ & 0xF;
        if (rateVersion_ == 1) {
            _rebalanceRateV1(supplyLendingRate_, rateConfig_);
        } else if (rateVersion_ == 2) {
            _rebalanceRateV2(supplyLendingRate_, rateConfig_);
        } else {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__RateVersionUnsupported);
        }
    }

    /// @notice returns the current calculcated borrow rates at kink1 and kink 2 (for rate data v2).
    function calcBorrowRates() public view returns (uint256 rateKink1_, uint256 rateKink2_) {
        return _calcBorrowRates(supplyTokenLendingRate(), LIQUIDITY.readFromStorage(_LIQUDITY_BORROW_RATE_DATA_SLOT));
    }

    /// @notice  get current `SUPPLY_TOKEN` lending `rate_` at Liquidity
    function supplyTokenLendingRate() public view returns (uint256 rate_) {
        // @dev logic here based on Liquidity Resolver .getOverallTokenData()
        uint256 totalAmounts_ = LIQUIDITY.readFromStorage(_LIQUDITY_SUPPLY_TOTAL_AMOUNTS_SLOT);

        // Extract supply & borrow amounts
        uint256 supplyRawInterest_ = totalAmounts_ & X64;
        supplyRawInterest_ =
            (supplyRawInterest_ >> DEFAULT_EXPONENT_SIZE) <<
            (supplyRawInterest_ & DEFAULT_EXPONENT_MASK);

        uint256 borrowRawInterest_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) &
            X64;
        borrowRawInterest_ =
            (borrowRawInterest_ >> DEFAULT_EXPONENT_SIZE) <<
            (borrowRawInterest_ & DEFAULT_EXPONENT_MASK);

        if (supplyRawInterest_ > 0) {
            uint256 exchangePriceAndConfig_ = LIQUIDITY.readFromStorage(
                _LIQUDITY_SUPPLY_EXCHANGE_PRICES_AND_CONFIG_SLOT
            );

            // use old exchange prices for supply rate to be at same level as borrow rate from storage.
            // Note the rate here can be a tiny bit with higher precision because we use borrowWithInterest_ / supplyWithInterest_
            // which has higher precision than the utilization used from storage in LiquidityCalcs
            uint256 supplyWithInterest_ = (supplyRawInterest_ *
                ((exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64)) /
                EXCHANGE_PRICES_PRECISION; // normalized from raw
            uint256 borrowWithInterest_ = (borrowRawInterest_ *
                ((exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64)) /
                EXCHANGE_PRICES_PRECISION; // normalized from raw

            uint256 borrowRate_ = exchangePriceAndConfig_ & X16;
            uint256 fee_ = (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14;

            rate_ =
                (borrowRate_ * (FOUR_DECIMALS - fee_) * borrowWithInterest_) /
                (supplyWithInterest_ * FOUR_DECIMALS);
        }
    }

    /// @dev calculates current borrow rates at kinks for supply rate and current rate data
    function _calcBorrowRates(
        uint256 supplyRate_,
        uint256 rateConfig_
    ) internal view returns (uint256 rateKink1_, uint256 rateKink2_) {
        // rate can never be <0, > X16.
        rateKink1_ = (int256(supplyRate_) + RATE_BUFFER_KINK1) > 0
            ? uint256((int256(supplyRate_) + RATE_BUFFER_KINK1))
            : 0;
        // rate can never be > X16
        rateKink1_ = rateKink1_ > X16 ? X16 : rateKink1_;
        if ((rateConfig_ & 0xF) == 1) {
            // v1: only 1 kink
            // rate at last kink must always be <= rate at 100% utilization
            uint256 rateAtUtilizationMax_ = (rateConfig_ >>
                LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) & X16;
            if (rateKink1_ > rateAtUtilizationMax_) {
                rateKink1_ = rateAtUtilizationMax_;
            }
        } else {
            // v2: 2 kinks
            // rate can never be <0, > X16.
            rateKink2_ = (int256(supplyRate_) + RATE_BUFFER_KINK2) > 0
                ? uint256(int256(supplyRate_) + RATE_BUFFER_KINK2)
                : 0;
            // rate can never be > X16
            rateKink2_ = rateKink2_ > X16 ? X16 : rateKink2_;
            // rate at kink must always be <= rate at 100% utilization
            uint256 rateAtUtilizationMax_ = (rateConfig_ >>
                LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) & X16;
            if (rateKink1_ > rateAtUtilizationMax_) {
                rateKink1_ = rateAtUtilizationMax_;
            }
            if (rateKink2_ > rateAtUtilizationMax_) {
                rateKink2_ = rateAtUtilizationMax_;
            }
        }
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

    /// @dev rebalances for a RateV1 config
    function _rebalanceRateV1(uint256 supplyRate_, uint256 rateConfig_) internal {
        AdminModuleStructs.RateDataV1Params memory rateData_;

        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) & X16;
        (rateData_.rateAtUtilizationKink, ) = _calcBorrowRates(supplyRate_, rateConfig_);

        // check if diff is enough to trigger update
        if (_percentDiffForValue(oldRateKink1_, rateData_.rateAtUtilizationKink) < MIN_UPDATE_DIFF) {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__NoUpdate);
        }

        rateData_.token = BORROW_TOKEN;
        // values that stay the same: kink, rate at 0%, rate at 100%
        rateData_.rateAtUtilizationZero =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) &
            X16;
        rateData_.kink = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
        rateData_.rateAtUtilizationMax =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) &
            X16;

        // trigger update
        AdminModuleStructs.RateDataV1Params[] memory params_ = new AdminModuleStructs.RateDataV1Params[](1);
        params_[0] = rateData_;
        LIQUIDITY.updateRateDataV1s(params_);

        // emit event
        emit LogUpdateRate(supplyRate_, oldRateKink1_, rateData_.rateAtUtilizationKink, 0, 0);
    }

    /// @dev rebalances for a RateV2 config
    function _rebalanceRateV2(uint256 supplyRate_, uint256 rateConfig_) internal {
        AdminModuleStructs.RateDataV2Params memory rateData_;

        uint256 oldRateKink1_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) & X16;
        uint256 oldRateKink2_ = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) & X16;
        (rateData_.rateAtUtilizationKink1, rateData_.rateAtUtilizationKink2) = _calcBorrowRates(
            supplyRate_,
            rateConfig_
        );

        // check if diff is enough to trigger update
        if (
            _percentDiffForValue(oldRateKink1_, rateData_.rateAtUtilizationKink1) < MIN_UPDATE_DIFF &&
            _percentDiffForValue(oldRateKink2_, rateData_.rateAtUtilizationKink2) < MIN_UPDATE_DIFF
        ) {
            revert FluidConfigError(ErrorTypes.BufferRateConfigHandler__NoUpdate);
        }

        rateData_.token = BORROW_TOKEN;
        // values that stay the same: kink1, kink2, rate at 0%, rate at 100%
        rateData_.rateAtUtilizationZero =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) &
            X16;
        rateData_.kink1 = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) & X16;
        rateData_.kink2 = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) & X16;
        rateData_.rateAtUtilizationMax =
            (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) &
            X16;

        // trigger update
        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = rateData_;
        LIQUIDITY.updateRateDataV2s(params_);

        // emit event
        emit LogUpdateRate(
            supplyRate_,
            oldRateKink1_,
            rateData_.rateAtUtilizationKink1,
            oldRateKink2_,
            rateData_.rateAtUtilizationKink2
        );
    }
}
