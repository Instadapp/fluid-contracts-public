// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { SafeTransfer } from "../../libraries/safeTransfer.sol";
import { Events } from "./events.sol";
import { Structs } from "./structs.sol";
import { CommonHelpers } from "../common/helpers.sol";
import { IFluidLiquidityAdmin } from "../interfaces/iLiquidity.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

abstract contract AdminModuleConstants is Error {
    /// @dev hard cap value for max borrow limit, used as sanity check. Usually 10x of total supply.
    uint256 public immutable NATIVE_TOKEN_MAX_BORROW_LIMIT_CAP;

    constructor(uint256 nativeTokenMaxBorrowLimitCap_) {
        if (nativeTokenMaxBorrowLimitCap_ == 0) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
        }

        NATIVE_TOKEN_MAX_BORROW_LIMIT_CAP = nativeTokenMaxBorrowLimitCap_;
    }
}

/// @notice Fluid Liquidity Governance only related methods
abstract contract GovernanceModule is IFluidLiquidityAdmin, CommonHelpers, Events, AdminModuleConstants {
    /// @notice only governance guard
    modifier onlyGovernance() {
        if (_getGovernanceAddr() != msg.sender) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__OnlyGovernance);
        }
        _;
    }

    /// @dev checks that `value_` is a valid address (not zero address)
    function _checkValidAddress(address value_) internal pure {
        if (value_ == address(0)) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__AddressZero);
        }
    }

    /// @dev checks that `value_` address is a contract
    function _checkIsContract(address value_) internal view {
        if (value_.code.length == 0) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__AddressNotAContract);
        }
    }

    /// @dev checks that `value_` address is a contract (which includes address zero check) or the native token
    function _checkIsContractOrNativeAddress(address value_) internal view {
        if (value_.code.length == 0 && value_ != NATIVE_TOKEN_ADDRESS) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__AddressNotAContract);
        }
    }

    /// @dev checks that `token_` decimals are between `MIN_TOKEN_DECIMALS` and `MAX_TOKEN_DECIMALS` (inclusive).
    function _checkTokenDecimalsRange(address token_) internal view {
        uint8 decimals_ = token_ == NATIVE_TOKEN_ADDRESS ? NATIVE_TOKEN_DECIMALS : IERC20Metadata(token_).decimals();
        if (decimals_ < MIN_TOKEN_DECIMALS || decimals_ > MAX_TOKEN_DECIMALS) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__TokenInvalidDecimalsRange);
        }
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateAuths(AddressBool[] calldata authsStatus_) external onlyGovernance {
        uint256 length_ = authsStatus_.length;
        for (uint256 i; i < length_; ) {
            _checkValidAddress(authsStatus_[i].addr);

            _isAuth[authsStatus_[i].addr] = authsStatus_[i].value ? 1 : 0;

            unchecked {
                ++i;
            }
        }

        emit LogUpdateAuths(authsStatus_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateGuardians(AddressBool[] calldata guardiansStatus_) external onlyGovernance {
        uint256 length_ = guardiansStatus_.length;
        for (uint256 i; i < length_; ) {
            _checkValidAddress(guardiansStatus_[i].addr);

            _isGuardian[guardiansStatus_[i].addr] = guardiansStatus_[i].value ? 1 : 0;

            unchecked {
                ++i;
            }
        }

        emit LogUpdateGuardians(guardiansStatus_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRevenueCollector(address revenueCollector_) external onlyGovernance {
        _checkValidAddress(revenueCollector_);

        _revenueCollector = revenueCollector_;

        emit LogUpdateRevenueCollector(revenueCollector_);
    }
}

abstract contract AuthInternals is Error, CommonHelpers, Events {
    /// @dev computes rata data packed uint256 for version 1 rate input params telling desired values
    /// at different uzilitation points (0%, kink, 100%)
    /// @param rataDataV1Params_ rata data params for a given token
    /// @return rateData_ packed uint256 rate data
    function _computeRateDataPackedV1(
        RateDataV1Params memory rataDataV1Params_
    ) internal pure returns (uint256 rateData_) {
        if (rataDataV1Params_.rateAtUtilizationZero > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_ZERO);
        }
        if (rataDataV1Params_.rateAtUtilizationKink > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_KINK);
        }
        if (rataDataV1Params_.rateAtUtilizationMax > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_MAX);
        }
        if (
            // kink must not be 0 or >= 100% (being 0 or 100% would lead to division through 0 at calculation time)
            rataDataV1Params_.kink == 0 ||
            rataDataV1Params_.kink >= FOUR_DECIMALS ||
            // for the last part of rate curve a spike increase must be present as utilization grows.
            // declining rate is supported before kink. kink to max must be increasing.
            // @dev Note rates can be equal, that leads to a 0 slope which is supported in calculation code.
            rataDataV1Params_.rateAtUtilizationKink > rataDataV1Params_.rateAtUtilizationMax
        ) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
        }

        rateData_ =
            1 | // version
            (rataDataV1Params_.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV1Params_.kink << LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) |
            (rataDataV1Params_.rateAtUtilizationKink << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) |
            (rataDataV1Params_.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX);
    }

    /// @dev computes rata data packed uint256 for rate version 2 input params telling desired values
    /// at different uzilitation points (0%, kink1, kink2, 100%)
    /// @param rataDataV2Params_ rata data params for a given token
    /// @return rateData_ packed uint256 rate data
    function _computeRateDataPackedV2(
        RateDataV2Params memory rataDataV2Params_
    ) internal pure returns (uint256 rateData_) {
        if (rataDataV2Params_.rateAtUtilizationZero > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_ZERO);
        }
        if (rataDataV2Params_.rateAtUtilizationKink1 > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_KINK1);
        }
        if (rataDataV2Params_.rateAtUtilizationKink2 > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_KINK2);
        }
        if (rataDataV2Params_.rateAtUtilizationMax > X16) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_MAX_V2);
        }
        if (
            // kink can not be 0, >= 100% or >= kink2 (would lead to division through 0 at calculation time)
            rataDataV2Params_.kink1 == 0 ||
            rataDataV2Params_.kink1 >= FOUR_DECIMALS ||
            rataDataV2Params_.kink1 >= rataDataV2Params_.kink2 ||
            // kink2 can not be >= 100% (must be > kink1 already checked)
            rataDataV2Params_.kink2 >= FOUR_DECIMALS ||
            // for the last part of rate curve a spike increase must be present as utilization grows.
            // declining rate is supported before kink2. kink2 to max must be increasing.
            // @dev Note rates can be equal, that leads to a 0 slope which is supported in calculation code.
            rataDataV2Params_.rateAtUtilizationKink2 > rataDataV2Params_.rateAtUtilizationMax
        ) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
        }

        rateData_ =
            2 | // version
            (rataDataV2Params_.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV2Params_.kink1 << LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) |
            (rataDataV2Params_.rateAtUtilizationKink1 <<
                LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) |
            (rataDataV2Params_.kink2 << LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) |
            (rataDataV2Params_.rateAtUtilizationKink2 <<
                LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) |
            (rataDataV2Params_.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX);
    }

    /// @dev updates the exchange prices in storage for `token_` and returns `supplyExchangePrice_` and `borrowExchangePrice_`.
    /// Recommended to use only in a method that later calls `_updateExchangePricesAndRates()`.
    function _updateExchangePrices(
        address token_
    ) internal returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        uint256 exchangePricesAndConfig_ = _exchangePricesAndConfig[token_];

        // calculate the new exchange prices based on earned interest
        (supplyExchangePrice_, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(exchangePricesAndConfig_);

        // ensure values written to storage do not exceed the dedicated bit space in packed uint256 slots
        if (supplyExchangePrice_ > X64 || borrowExchangePrice_ > X64) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXCHANGE_PRICES);
        }

        // write updated exchangePrices_ for token to storage
        _exchangePricesAndConfig[token_] =
            (exchangePricesAndConfig_ &
                // mask to update bits: 58-218 (timestamp and exchange prices)
                0xfffffffff80000000000000000000000000000000000000003ffffffffffffff) |
            (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
            (supplyExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (borrowExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE);

        emit LogUpdateExchangePrices(
            token_,
            supplyExchangePrice_,
            borrowExchangePrice_,
            exchangePricesAndConfig_ & X16, // borrow rate is unchanged -> read from exchangePricesAndConfig_
            (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14 // utilization is unchanged -> read from exchangePricesAndConfig_
        );

        return (supplyExchangePrice_, borrowExchangePrice_);
    }

    /// @dev updates the exchange prices + rates in storage for `token_` and returns `supplyExchangePrice_` and `borrowExchangePrice_`
    function _updateExchangePricesAndRates(
        address token_
    ) internal returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        uint256 exchangePricesAndConfig_ = _exchangePricesAndConfig[token_];
        // calculate the new exchange prices based on earned interest
        (supplyExchangePrice_, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(exchangePricesAndConfig_);

        uint256 totalAmounts_ = _totalAmounts[token_];

        // calculate updated ratios
        // set supplyRatio_ = supplyWithInterest here, using that value for total supply before finish calc supplyRatio
        uint256 supplyRatio_ = ((BigMathMinified.fromBigNumber(
            (totalAmounts_ & X64),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        ) * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION);
        // set borrowRatio_ = borrowWithInterest here, using that value for total borrow before finish calc borrowRatio
        uint256 borrowRatio_ = ((BigMathMinified.fromBigNumber(
            (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        ) * borrowExchangePrice_) / EXCHANGE_PRICES_PRECISION);

        uint256 supplyInterestFree_ = BigMathMinified.fromBigNumber(
            (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        uint256 borrowInterestFree_ = BigMathMinified.fromBigNumber(
            // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
            (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        // calculate utilization: totalBorrow / totalSupply. If no supply, utilization must be 0 (avoid division by 0)
        uint256 utilization_ = 0;
        if (supplyRatio_ > 0 || supplyInterestFree_ > 0) {
            utilization_ = (((borrowRatio_ + borrowInterestFree_) * FOUR_DECIMALS) /
                (supplyRatio_ + supplyInterestFree_));
        }

        // finish calculating supply & borrow ratio
        // ########## calculating supply ratio ##########
        // supplyRatio_ holds value of supplyWithInterest below
        if (supplyRatio_ > supplyInterestFree_) {
            // supplyRatio_ is ratio with 1 bit as 0 as supply interest raw is bigger
            supplyRatio_ = ((supplyInterestFree_ * FOUR_DECIMALS) / supplyRatio_) << 1;
            // because of checking to divide by bigger amount, ratio can never be > 100%
        } else if (supplyRatio_ < supplyInterestFree_) {
            // supplyRatio_ is ratio with 1 bit as 1 as supply interest free is bigger
            supplyRatio_ = (((supplyRatio_ * FOUR_DECIMALS) / supplyInterestFree_) << 1) | 1;
            // because of checking to divide by bigger amount, ratio can never be > 100%
        } else {
            // supplies match exactly (supplyWithInterest  == supplyInterestFree)
            if (supplyRatio_ > 0) {
                // supplies are not 0 -> set ratio to 1 (with first bit set to 0, doesn't matter)
                supplyRatio_ = FOUR_DECIMALS << 1;
            } else {
                // if total supply = 0
                supplyRatio_ = 0;
            }
        }

        // ########## calculating borrow ratio ##########
        // borrowRatio_ holds value of borrowWithInterest below
        if (borrowRatio_ > borrowInterestFree_) {
            // borrowRatio_ is ratio with 1 bit as 0 as borrow interest raw is bigger
            borrowRatio_ = ((borrowInterestFree_ * FOUR_DECIMALS) / borrowRatio_) << 1;
            // because of checking to divide by bigger amount, ratio can never be > 100%
        } else if (borrowRatio_ < borrowInterestFree_) {
            // borrowRatio_ is ratio with 1 bit as 1 as borrow interest free is bigger
            borrowRatio_ = (((borrowRatio_ * FOUR_DECIMALS) / borrowInterestFree_) << 1) | 1;
            // because of checking to divide by bigger amount, ratio can never be > 100%
        } else {
            // borrows match exactly (borrowWithInterest  == borrowInterestFree)
            if (borrowRatio_ > 0) {
                // borrows are not 0 -> set ratio to 1 (with first bit set to 0, doesn't matter)
                borrowRatio_ = FOUR_DECIMALS << 1;
            } else {
                // if total borrows = 0
                borrowRatio_ = 0;
            }
        }

        // updated borrow rate from utilization
        uint256 borrowRate_ = LiquidityCalcs.calcBorrowRateFromUtilization(_rateData[token_], utilization_);

        // ensure values written to storage do not exceed the dedicated bit space in packed uint256 slots
        if (supplyExchangePrice_ > X64 || borrowExchangePrice_ > X64) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXCHANGE_PRICES);
        }
        if (utilization_ > X14) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__UTILIZATION);
        }

        // write updated exchangePrices_ for token to storage
        _exchangePricesAndConfig[token_] =
            (exchangePricesAndConfig_ &
                // mask to update bits: 0-15 (borrow rate), 30-43 (utilization), 58-248 (timestamp, exchange prices, ratios)
                0xfe000000000000000000000000000000000000000000000003fff0003fff0000) |
            borrowRate_ | // already includes an overflow check in `calcBorrowRateFromUtilization`
            (utilization_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) |
            (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
            (supplyExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (borrowExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) |
            // ratios can never be > 100%, no overflow check needed
            (supplyRatio_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) |
            (borrowRatio_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO);

        emit LogUpdateExchangePrices(token_, supplyExchangePrice_, borrowExchangePrice_, borrowRate_, utilization_);

        return (supplyExchangePrice_, borrowExchangePrice_);
    }
}

/// @notice Fluid Liquidity Auths only related methods
abstract contract AuthModule is AuthInternals, GovernanceModule {
    using BigMathMinified for uint256;

    /// @dev max update on storage threshold as a sanity check. threshold is in 1e2, so 500 = 5%.
    /// A higher threshold is not allowed as it would cause the borrow rate to be updated too rarely.
    uint256 private constant MAX_TOKEN_CONFIG_UPDATE_THRESHOLD = 500;

    /// @dev only auths guard
    modifier onlyAuths() {
        if (_isAuth[msg.sender] & 1 != 1 && _getGovernanceAddr() != msg.sender) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__OnlyAuths);
        }
        _;
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function collectRevenue(address[] calldata tokens_) external onlyAuths {
        address payable revenueCollector_ = payable(_revenueCollector);
        if (revenueCollector_ == address(0)) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__RevenueCollectorNotSet);
        }

        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; ) {
            _checkIsContractOrNativeAddress(tokens_[i]);

            bool isNativeToken_ = tokens_[i] == NATIVE_TOKEN_ADDRESS;

            // get revenue amount with updated interest etc.
            uint256 revenueAmount_ = LiquidityCalcs.calcRevenue(
                _totalAmounts[tokens_[i]],
                _exchangePricesAndConfig[tokens_[i]],
                isNativeToken_ ? address(this).balance : IERC20(tokens_[i]).balanceOf(address(this))
            );

            if (revenueAmount_ > 0) {
                // transfer token amount to revenueCollector address
                if (isNativeToken_) {
                    SafeTransfer.safeTransferNative(revenueCollector_, revenueAmount_);
                } else {
                    SafeTransfer.safeTransfer(tokens_[i], revenueCollector_, revenueAmount_);
                }
            }

            emit LogCollectRevenue(tokens_[i], revenueAmount_);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function changeStatus(uint256 newStatus_) external onlyAuths {
        if (newStatus_ == 0 || newStatus_ > 2) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
        }

        _status = newStatus_;

        emit LogChangeStatus(newStatus_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRateDataV1s(RateDataV1Params[] calldata tokensRateData_) external onlyAuths {
        uint256 length_ = tokensRateData_.length;
        uint256 rateData_;

        for (uint256 i; i < length_; ) {
            _checkIsContractOrNativeAddress(tokensRateData_[i].token);

            // token that is being listed must have between 6 and 18 decimals.
            // setting rate data is the first step for listing a token, so this check blocks any
            // unsupported token to ever be listed at Liquidity
            _checkTokenDecimalsRange(tokensRateData_[i].token);

            rateData_ = _rateData[tokensRateData_[i].token];

            // apply current rate data to exchange prices before updating to new rate data
            if (rateData_ != 0) {
                _updateExchangePrices(tokensRateData_[i].token);
            }

            _rateData[tokensRateData_[i].token] = _computeRateDataPackedV1(tokensRateData_[i]);

            if (rateData_ != 0) {
                // apply new rate data to borrow rate
                _updateExchangePricesAndRates(tokensRateData_[i].token);
            }

            unchecked {
                ++i;
            }
        }

        emit LogUpdateRateDataV1s(tokensRateData_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRateDataV2s(RateDataV2Params[] calldata tokensRateData_) external onlyAuths {
        uint256 length_ = tokensRateData_.length;
        uint256 rateData_;

        for (uint256 i; i < length_; ) {
            _checkIsContractOrNativeAddress(tokensRateData_[i].token);

            // token that is being listed must have between 6 and 18 decimals.
            // setting rate data is the first step for listing a token, so this check blocks any
            // unsupported token to ever be listed at Liquidity
            _checkTokenDecimalsRange(tokensRateData_[i].token);

            rateData_ = _rateData[tokensRateData_[i].token];

            // apply current rate data to exchange prices before updating to new rate data
            if (rateData_ != 0) {
                _updateExchangePrices(tokensRateData_[i].token);
            }

            _rateData[tokensRateData_[i].token] = _computeRateDataPackedV2(tokensRateData_[i]);

            if (rateData_ != 0) {
                // apply new rate data to borrow rate
                _updateExchangePricesAndRates(tokensRateData_[i].token);
            }

            unchecked {
                ++i;
            }
        }

        emit LogUpdateRateDataV2s(tokensRateData_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateTokenConfigs(TokenConfig[] calldata tokenConfigs_) external onlyAuths {
        uint256 length_ = tokenConfigs_.length;
        uint256 exchangePricesAndConfig_;
        uint256 supplyExchangePrice_;
        uint256 borrowExchangePrice_;

        for (uint256 i; i < length_; ) {
            _checkIsContractOrNativeAddress(tokenConfigs_[i].token);
            if (_rateData[tokenConfigs_[i].token] == 0) {
                // rate data must be configured before token config
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidConfigOrder);
            }
            if (tokenConfigs_[i].fee > FOUR_DECIMALS) {
                // fee can not be > 100%
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__FEE);
            }
            if (tokenConfigs_[i].maxUtilization > FOUR_DECIMALS) {
                // borrows above 100% should never be possible
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__MAX_UTILIZATION);
            }
            if (tokenConfigs_[i].threshold > MAX_TOKEN_CONFIG_UPDATE_THRESHOLD) {
                // update on storage threshold can not be > MAX_TOKEN_CONFIG_UPDATE_THRESHOLD
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__THRESHOLD);
            }

            exchangePricesAndConfig_ = _exchangePricesAndConfig[tokenConfigs_[i].token];

            // extract exchange prices
            supplyExchangePrice_ =
                (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) &
                X64;
            borrowExchangePrice_ =
                (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) &
                X64;

            if (supplyExchangePrice_ > 0 && borrowExchangePrice_ > 0) {
                // calculate the current exchange prices based on earned interest before updating fee + timestamp in storage
                (supplyExchangePrice_, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(
                    exchangePricesAndConfig_
                );

                // ensure values written to storage do not exceed the dedicated bit space in packed uint256 slots
                if (supplyExchangePrice_ > X64 || borrowExchangePrice_ > X64) {
                    revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXCHANGE_PRICES);
                }
            } else {
                // exchange prices can only increase once set so if either one is 0, the other must be 0 too.
                supplyExchangePrice_ = EXCHANGE_PRICES_PRECISION;
                borrowExchangePrice_ = EXCHANGE_PRICES_PRECISION;

                _listedTokens.push(tokenConfigs_[i].token);
            }

            // max utilization of 100% is default, configs2 slot is not used in that case
            bool usesConfigs2_ = tokenConfigs_[i].maxUtilization != FOUR_DECIMALS;

            _exchangePricesAndConfig[tokenConfigs_[i].token] =
                // mask to set bits 16-29 (fee), 44-218 (update storage threshold, timestamp, exchange prices)
                // and flag for uses configs2 at bit 249
                (exchangePricesAndConfig_ & 0xfdfffffff80000000000000000000000000000000000000000000fffc000ffff) |
                (tokenConfigs_[i].fee << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) |
                (tokenConfigs_[i].threshold << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD) |
                (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
                (supplyExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
                (borrowExchangePrice_ << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) |
                ((uint256(usesConfigs2_ ? 1 : 0)) << uint256(LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2));

            _configs2[tokenConfigs_[i].token] =
                // set max utilization at bits 0-14
                (_configs2[tokenConfigs_[i].token] &
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc000) |
                (usesConfigs2_ ? tokenConfigs_[i].maxUtilization : 0);

            unchecked {
                ++i;
            }
        }

        emit LogUpdateTokenConfigs(tokenConfigs_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserClasses(AddressUint256[] calldata userClasses_) external onlyAuths {
        uint256 length_ = userClasses_.length;
        for (uint256 i = 0; i < length_; ) {
            if (userClasses_[i].value > 1) {
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
            }
            _checkIsContract(userClasses_[i].addr);

            _userClass[userClasses_[i].addr] = userClasses_[i].value;

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserClasses(userClasses_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserWithdrawalLimit(address user_, address token_, uint256 newLimit_) external onlyAuths {
        _checkIsContract(user_);
        _checkIsContractOrNativeAddress(token_);

        // get current user config data from storage
        uint256 userSupplyData_ = _userSupplyData[user_][token_];
        if (userSupplyData_ == 0) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotDefined);
        }

        // get current user supply amount
        uint256 userSupply_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        userSupply_ = (userSupply_ >> DEFAULT_EXPONENT_SIZE) << (userSupply_ & DEFAULT_EXPONENT_MASK);

        // maxExpansionLimit_ => withdrawal limit expandPercent (is in 1e2 decimals)
        uint256 maxExpansionLimit_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;
        maxExpansionLimit_ = userSupply_ - ((userSupply_ * maxExpansionLimit_) / FOUR_DECIMALS);

        if (newLimit_ == 0 || newLimit_ < maxExpansionLimit_) {
            // instant full expansion, and if that goes below base limit then fully down to 0.
            // if we were to set a limit that goes below max expansion limit, then after 1 deposit or 1 withdrawal it would
            // become based on the max expansion limit again (unless it goes below base limit), which can be confusing.
            // Also updating base limit here to avoid the change after 1 interaction might have undesired effects.
            // So limiting update to max. full expansion. If more is desired, this must be called again after some withdraws.
            newLimit_ = maxExpansionLimit_;
        } else if (newLimit_ == type(uint256).max || newLimit_ > userSupply_) {
            // current withdrawable 0 (sets current user supply as limit).
            newLimit_ = userSupply_;
        }
        // else => new limit is between > max expansion and < user supply.

        // set input limit as new current limit. instant withdrawable will be userSupply_ - newLimit_

        uint256 baseLimit_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18;
        baseLimit_ = (baseLimit_ >> DEFAULT_EXPONENT_SIZE) << (baseLimit_ & DEFAULT_EXPONENT_MASK);
        if (userSupply_ < baseLimit_) {
            newLimit_ = 0;
            // Note if new limit goes below base limit, it follows default behavior: first there must be a withdrawal
            // that brings user supply below base limit, then the limit will be set to 0.
            // otherwise we would have the same problem as described above after 1 interaction.
        }

        // Update on storage
        _userSupplyData[user_][token_] =
            // mask to update bits 65-161 (withdrawal limit, timestamp)
            (userSupplyData_ & 0xFFFFFFFFFFFFFFFFFFFFFFFC000000000000000000000001FFFFFFFFFFFFFFFF) |
            (newLimit_.toBigNumber(DEFAULT_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN) <<
                LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // converted to BigNumber can not overflow
            (block.timestamp << LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);

        emit LogUpdateUserWithdrawalLimit(user_, token_, newLimit_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserSupplyConfigs(UserSupplyConfig[] memory userSupplyConfigs_) external onlyAuths {
        uint256 userSupplyData_;
        uint256 totalAmounts_;
        uint256 totalSupplyRawInterest_;
        uint256 totalSupplyInterestFree_;
        uint256 supplyConversion_;
        uint256 withdrawLimitConversion_;
        uint256 supplyExchangePrice_;

        for (uint256 i; i < userSupplyConfigs_.length; ) {
            _checkIsContract(userSupplyConfigs_[i].user);
            _checkIsContractOrNativeAddress(userSupplyConfigs_[i].token);
            if (_exchangePricesAndConfig[userSupplyConfigs_[i].token] == 0) {
                // token config must be configured before setting any user supply config
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidConfigOrder);
            }
            if (
                userSupplyConfigs_[i].mode > 1 ||
                // can not set expand duration to 0 as that could cause a division by 0 in LiquidityCalcs.
                // having expand duration as 0 is anyway not an expected config so removing the possibility for that.
                // if no expansion is wanted, simply set expandDuration to 1 and expandPercent to 0.
                userSupplyConfigs_[i].expandDuration == 0
            ) {
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
            }
            if (userSupplyConfigs_[i].expandPercent > FOUR_DECIMALS) {
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXPAND_PERCENT);
            }
            if (userSupplyConfigs_[i].expandDuration > X24) {
                // duration is max 24 bits
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXPAND_DURATION);
            }
            if (userSupplyConfigs_[i].baseWithdrawalLimit == 0) {
                // base withdrawal limit can not be 0. As a side effect, this ensures that there is no supply config
                // where all values would be 0, so configured users can be differentiated in the mapping.
                revert FluidLiquidityError(ErrorTypes.AdminModule__LimitZero);
            }
            // @dev baseWithdrawalLimit has no max bits amount as it is in normal token amount & converted to BigNumber

            // get current user config data from storage
            userSupplyData_ = _userSupplyData[userSupplyConfigs_[i].user][userSupplyConfigs_[i].token];

            // if userSupplyData_ == 0 (new setup) or if mode is unchanged, normal update is possible.
            // else if mode changes, values have to be converted from raw <> normal etc.
            if (
                userSupplyData_ == 0 ||
                (userSupplyData_ & 1 == 0 && userSupplyConfigs_[i].mode == 0) ||
                (userSupplyData_ & 1 == 1 && userSupplyConfigs_[i].mode == 1)
            ) {
                // Updating user data on storage

                _userSupplyData[userSupplyConfigs_[i].user][userSupplyConfigs_[i].token] =
                    // mask to update first bit + bits 162-217 (expand percentage, expand duration, base limit)
                    (userSupplyData_ & 0xfffffffffc00000000000003fffffffffffffffffffffffffffffffffffffffe) |
                    (userSupplyConfigs_[i].mode) | // at first bit
                    (userSupplyConfigs_[i].expandPercent << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) |
                    (userSupplyConfigs_[i].expandDuration << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) |
                    // convert base withdrawal limit to BigNumber for storage (10 | 8). (below this, 100% can be withdrawn)
                    (userSupplyConfigs_[i].baseWithdrawalLimit.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT);
            } else {
                // mode changes -> values have to be converted from raw <> normal etc.

                // if the mode changes then update _exchangePricesAndConfig related data in storage always
                // update exchange prices timely before applying changes that affect utilization, rate etc.
                _updateExchangePrices(userSupplyConfigs_[i].token);

                // get updated exchange prices for the token
                (supplyExchangePrice_, ) = LiquidityCalcs.calcExchangePrices(
                    _exchangePricesAndConfig[userSupplyConfigs_[i].token]
                );

                totalAmounts_ = _totalAmounts[userSupplyConfigs_[i].token];
                totalSupplyRawInterest_ = BigMathMinified.fromBigNumber(
                    (totalAmounts_ & X64),
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                );
                totalSupplyInterestFree_ = BigMathMinified.fromBigNumber(
                    (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                );

                // read current user supply & withdraw limit values
                // here supplyConversion_ = user supply amount
                supplyConversion_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
                supplyConversion_ =
                    (supplyConversion_ >> DEFAULT_EXPONENT_SIZE) <<
                    (supplyConversion_ & DEFAULT_EXPONENT_MASK);

                withdrawLimitConversion_ =
                    (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) &
                    X64; // here withdrawLimitConversion_ = previous user withdraw limit
                withdrawLimitConversion_ =
                    (withdrawLimitConversion_ >> DEFAULT_EXPONENT_SIZE) <<
                    (withdrawLimitConversion_ & DEFAULT_EXPONENT_MASK);

                // conversion of balance and limit according to the mode change
                if (userSupplyData_ & 1 == 0 && userSupplyConfigs_[i].mode == 1) {
                    // Changing balance from interest free to with interest -> normal amounts to raw amounts
                    // -> must divide by exchange price.

                    // decreasing interest free total supply
                    totalSupplyInterestFree_ = totalSupplyInterestFree_ > supplyConversion_
                        ? totalSupplyInterestFree_ - supplyConversion_
                        : 0;

                    supplyConversion_ = (supplyConversion_ * EXCHANGE_PRICES_PRECISION) / supplyExchangePrice_;
                    withdrawLimitConversion_ =
                        (withdrawLimitConversion_ * EXCHANGE_PRICES_PRECISION) /
                        supplyExchangePrice_;

                    // increasing raw (with interest) total supply
                    totalSupplyRawInterest_ += supplyConversion_;
                } else if (userSupplyData_ & 1 == 1 && userSupplyConfigs_[i].mode == 0) {
                    // Changing balance from with interest to interest free-> raw amounts to normal amounts
                    // -> must multiply by exchange price.

                    // decreasing raw (with interest) supply
                    totalSupplyRawInterest_ = totalSupplyRawInterest_ > supplyConversion_
                        ? totalSupplyRawInterest_ - supplyConversion_
                        : 0;

                    supplyConversion_ = (supplyConversion_ * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION;
                    withdrawLimitConversion_ =
                        (withdrawLimitConversion_ * supplyExchangePrice_) /
                        EXCHANGE_PRICES_PRECISION;

                    // increasing interest free total supply
                    totalSupplyInterestFree_ += supplyConversion_;
                }

                // change new converted amounts to BigNumber for storage
                supplyConversion_ = supplyConversion_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                );
                withdrawLimitConversion_ = withdrawLimitConversion_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN // withdrawal limit stores the amount that must stay supplied after withdrawal
                );

                // Updating user data on storage
                _userSupplyData[userSupplyConfigs_[i].user][userSupplyConfigs_[i].token] =
                    // mask to set bits 0-128 and 162-217 (all except last process timestamp)
                    (userSupplyData_ & 0xfffffffffc00000000000003fffffffe00000000000000000000000000000000) |
                    (userSupplyConfigs_[i].mode) |
                    (supplyConversion_ << LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) | // BigNumber converted can not overflow
                    (withdrawLimitConversion_ << LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) | // BigNumber converted can not overflow
                    (userSupplyConfigs_[i].expandPercent << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) |
                    (userSupplyConfigs_[i].expandDuration << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) |
                    // convert base withdrawal limit to BigNumber for storage (10 | 8). (below this, 100% can be withdrawn)
                    (userSupplyConfigs_[i].baseWithdrawalLimit.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT);

                // change new total amounts to BigNumber for storage
                totalSupplyRawInterest_ = totalSupplyRawInterest_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                );
                totalSupplyInterestFree_ = totalSupplyInterestFree_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                );

                // Updating total supplies on storage
                _totalAmounts[userSupplyConfigs_[i].token] =
                    // mask to set bits 0-127
                    (totalAmounts_ & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000) |
                    (totalSupplyRawInterest_) | // BigNumber converted can not overflow
                    (totalSupplyInterestFree_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE); // BigNumber converted can not overflow

                // trigger update borrow rate, utilization, ratios etc.
                _updateExchangePricesAndRates(userSupplyConfigs_[i].token);
            }

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserSupplyConfigs(userSupplyConfigs_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserBorrowConfigs(UserBorrowConfig[] memory userBorrowConfigs_) external onlyAuths {
        uint256 userBorrowData_;
        uint256 totalAmounts_;
        uint256 totalBorrowRawInterest_;
        uint256 totalBorrowInterestFree_;
        uint256 borrowingConversion_;
        uint256 debtCeilingConversion_;
        uint256 borrowExchangePrice_;

        for (uint256 i; i < userBorrowConfigs_.length; ) {
            _checkIsContract(userBorrowConfigs_[i].user);
            _checkIsContractOrNativeAddress(userBorrowConfigs_[i].token);
            if (_exchangePricesAndConfig[userBorrowConfigs_[i].token] == 0) {
                // token config must be configured before setting any user borrow config
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidConfigOrder);
            }
            if (
                userBorrowConfigs_[i].mode > 1 ||
                // max debt ceiling must not be smaller than base debt ceiling. Also covers case where max = 0 but base > 0
                userBorrowConfigs_[i].baseDebtCeiling > userBorrowConfigs_[i].maxDebtCeiling ||
                // can not set expand duration to 0 as that could cause a division by 0 in LiquidityCalcs.
                // having expand duration as 0 is anyway not an expected config so removing the possibility for that.
                // if no expansion is wanted, simply set expandDuration to 1 and expandPercent to 0.
                userBorrowConfigs_[i].expandDuration == 0 ||
                // sanity check that max borrow limit can never be more than 10x the total token supply.
                // protects against that even if someone could artificially inflate token supply to a point where
                // Fluid precision trade-offs could become problematic, can not inflate too much.
                (userBorrowConfigs_[i].maxDebtCeiling >
                    (
                        userBorrowConfigs_[i].token == NATIVE_TOKEN_ADDRESS
                            ? NATIVE_TOKEN_MAX_BORROW_LIMIT_CAP
                            : 10 * IERC20(userBorrowConfigs_[i].token).totalSupply()
                    ))
            ) {
                revert FluidLiquidityError(ErrorTypes.AdminModule__InvalidParams);
            }
            if (userBorrowConfigs_[i].expandPercent > X14) {
                // expandPercent is max 14 bits
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXPAND_PERCENT_BORROW);
            }
            if (userBorrowConfigs_[i].expandDuration > X24) {
                // duration is max 24 bits
                revert FluidLiquidityError(ErrorTypes.AdminModule__ValueOverflow__EXPAND_DURATION_BORROW);
            }
            if (userBorrowConfigs_[i].baseDebtCeiling == 0 || userBorrowConfigs_[i].maxDebtCeiling == 0) {
                // limits can not be 0. As a side effect, this ensures that there is no borrow config
                // where all values would be 0, so configured users can be differentiated in the mapping.
                revert FluidLiquidityError(ErrorTypes.AdminModule__LimitZero);
            }
            // @dev baseDebtCeiling & maxDebtCeiling have no max bits amount as they are in normal token amount
            // and then converted to BigNumber

            // get current user config data from storage
            userBorrowData_ = _userBorrowData[userBorrowConfigs_[i].user][userBorrowConfigs_[i].token];

            // if userBorrowData_ == 0 (new setup) or if mode is unchanged, normal update is possible.
            // else if mode changes, values have to be converted from raw <> normal etc.
            if (
                userBorrowData_ == 0 ||
                (userBorrowData_ & 1 == 0 && userBorrowConfigs_[i].mode == 0) ||
                (userBorrowData_ & 1 == 1 && userBorrowConfigs_[i].mode == 1)
            ) {
                // Updating user data on storage

                _userBorrowData[userBorrowConfigs_[i].user][userBorrowConfigs_[i].token] =
                    // mask to update first bit (mode) + bits 162-235 (debt limit values)
                    (userBorrowData_ & 0xfffff0000000000000000003fffffffffffffffffffffffffffffffffffffffe) |
                    (userBorrowConfigs_[i].mode) |
                    (userBorrowConfigs_[i].expandPercent << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) |
                    (userBorrowConfigs_[i].expandDuration << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) |
                    // convert base debt limit to BigNumber for storage (10 | 8). (borrow is always possible below this)
                    (userBorrowConfigs_[i].baseDebtCeiling.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) |
                    // convert max debt limit to BigNumber for storage (10 | 8). (no borrowing ever possible above this)
                    (userBorrowConfigs_[i].maxDebtCeiling.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);
            } else {
                // mode changes -> values have to be converted from raw <> normal etc.

                // if the mode changes then update _exchangePricesAndConfig related data in storage always
                // update exchange prices timely before applying changes that affect utilization, rate etc.
                _updateExchangePrices(userBorrowConfigs_[i].token);

                // get updated exchange prices for the token
                (, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(
                    _exchangePricesAndConfig[userBorrowConfigs_[i].token]
                );

                totalAmounts_ = _totalAmounts[userBorrowConfigs_[i].token];
                totalBorrowRawInterest_ = BigMathMinified.fromBigNumber(
                    (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64,
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                );
                totalBorrowInterestFree_ = BigMathMinified.fromBigNumber(
                    // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
                    (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE),
                    DEFAULT_EXPONENT_SIZE,
                    DEFAULT_EXPONENT_MASK
                );

                // read current user borrowing & borrow limit values
                borrowingConversion_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64; // here borrowingConversion_ = user borrow amount
                borrowingConversion_ =
                    (borrowingConversion_ >> DEFAULT_EXPONENT_SIZE) <<
                    (borrowingConversion_ & DEFAULT_EXPONENT_MASK);

                debtCeilingConversion_ =
                    (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) &
                    X64; // here debtCeilingConversion_ = previous user borrow limit
                debtCeilingConversion_ =
                    (debtCeilingConversion_ >> DEFAULT_EXPONENT_SIZE) <<
                    (debtCeilingConversion_ & DEFAULT_EXPONENT_MASK);

                // conversion of balance and limit according to the mode change
                if (userBorrowData_ & 1 == 0 && userBorrowConfigs_[i].mode == 1) {
                    // Changing balance from interest free to with interest -> normal amounts to raw amounts
                    // -> must divide by exchange price.

                    // decreasing interest free total borrow; total = total - user borrow
                    totalBorrowInterestFree_ = totalBorrowInterestFree_ > borrowingConversion_
                        ? totalBorrowInterestFree_ - borrowingConversion_
                        : 0;

                    // round up for user borrow amount
                    borrowingConversion_ = FixedPointMathLib.mulDivUp(
                        borrowingConversion_,
                        EXCHANGE_PRICES_PRECISION,
                        borrowExchangePrice_
                    );
                    debtCeilingConversion_ =
                        (debtCeilingConversion_ * EXCHANGE_PRICES_PRECISION) /
                        borrowExchangePrice_;

                    // increasing raw (with interest) total borrow
                    totalBorrowRawInterest_ += borrowingConversion_;
                } else if (userBorrowData_ & 1 == 1 && userBorrowConfigs_[i].mode == 0) {
                    // Changing balance from with interest to interest free-> raw amounts to normal amounts
                    // -> must multiply by exchange price.

                    // decreasing raw (with interest) borrow; total = total - user borrow raw
                    totalBorrowRawInterest_ = totalBorrowRawInterest_ > borrowingConversion_
                        ? totalBorrowRawInterest_ - borrowingConversion_
                        : 0;

                    // round up for user borrow amount
                    borrowingConversion_ = FixedPointMathLib.mulDivUp(
                        borrowingConversion_,
                        borrowExchangePrice_,
                        EXCHANGE_PRICES_PRECISION
                    );
                    debtCeilingConversion_ =
                        (debtCeilingConversion_ * borrowExchangePrice_) /
                        EXCHANGE_PRICES_PRECISION;

                    // increasing interest free total borrow
                    totalBorrowInterestFree_ += borrowingConversion_;
                }

                // change new converted amounts to BigNumber for storage
                borrowingConversion_ = borrowingConversion_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_UP
                );
                debtCeilingConversion_ = debtCeilingConversion_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_DOWN
                );

                // Updating user data on storage
                _userBorrowData[userBorrowConfigs_[i].user][userBorrowConfigs_[i].token] =
                    // mask to update bits 0-128 and bits 162-235 (all except last process timestamp)
                    (userBorrowData_ & 0xfffff0000000000000000003fffffffe00000000000000000000000000000000) |
                    (userBorrowConfigs_[i].mode) |
                    (borrowingConversion_ << LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) | // BigNumber converted can not overflow
                    (debtCeilingConversion_ << LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) | // BigNumber converted can not overflow
                    (userBorrowConfigs_[i].expandPercent << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) |
                    (userBorrowConfigs_[i].expandDuration << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) |
                    // convert base debt limit to BigNumber for storage (10 | 8). (borrow is always possible below this)
                    (userBorrowConfigs_[i].baseDebtCeiling.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) |
                    // convert max debt limit to BigNumber for storage (10 | 8). (no borrowing ever possible above this)
                    (userBorrowConfigs_[i].maxDebtCeiling.toBigNumber(
                        SMALL_COEFFICIENT_SIZE,
                        DEFAULT_EXPONENT_SIZE,
                        BigMathMinified.ROUND_DOWN
                    ) << LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);

                // change new total amounts to BigNumber for storage
                totalBorrowRawInterest_ = totalBorrowRawInterest_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_UP
                );
                totalBorrowInterestFree_ = totalBorrowInterestFree_.toBigNumber(
                    DEFAULT_COEFFICIENT_SIZE,
                    DEFAULT_EXPONENT_SIZE,
                    BigMathMinified.ROUND_UP
                );

                // Updating total borrowings on storage
                _totalAmounts[userBorrowConfigs_[i].token] =
                    // mask to set bits 128-255
                    (totalAmounts_ & 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff) |
                    (totalBorrowRawInterest_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) | // BigNumber converted can not overflow
                    (totalBorrowInterestFree_ << LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE); // BigNumber converted can not overflow

                // trigger update borrow rate, utilization, ratios etc.
                _updateExchangePricesAndRates(userBorrowConfigs_[i].token);
            }

            unchecked {
                ++i;
            }
        }

        emit LogUpdateUserBorrowConfigs(userBorrowConfigs_);
    }
}

/// @notice Fluid Liquidity Guardians only related methods
abstract contract GuardianModule is AuthModule {
    /// @dev only guardians guard
    modifier onlyGuardians() {
        if (_isGuardian[msg.sender] & 1 != 1 && _getGovernanceAddr() != msg.sender) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__OnlyGuardians);
        }
        _;
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function pauseUser(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) public onlyGuardians {
        _checkIsContract(user_);
        if (_userClass[user_] == 1) {
            revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotPausable);
        }

        uint256 userData_;

        // pause supply tokens
        uint256 length_ = supplyTokens_.length;

        if (length_ > 0) {
            for (uint256 i; i < length_; ) {
                _checkIsContractOrNativeAddress(supplyTokens_[i]);
                // userData_ => userSupplyData_
                userData_ = _userSupplyData[user_][supplyTokens_[i]];
                if (userData_ == 0) {
                    revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotDefined);
                }
                // set last bit of _userSupplyData (pause flag) to 1
                _userSupplyData[user_][supplyTokens_[i]] =
                    userData_ |
                    (1 << LiquiditySlotsLink.BITS_USER_SUPPLY_IS_PAUSED);

                unchecked {
                    ++i;
                }
            }
        }

        // pause borrow tokens
        length_ = borrowTokens_.length;

        if (length_ > 0) {
            for (uint256 i; i < length_; ) {
                _checkIsContractOrNativeAddress(borrowTokens_[i]);
                // userData_ => userBorrowData_
                userData_ = _userBorrowData[user_][borrowTokens_[i]];
                if (userData_ == 0) {
                    revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotDefined);
                }
                // set last bit of _userBorrowData (pause flag) to 1
                _userBorrowData[user_][borrowTokens_[i]] =
                    userData_ |
                    (1 << LiquiditySlotsLink.BITS_USER_BORROW_IS_PAUSED);

                unchecked {
                    ++i;
                }
            }
        }

        emit LogPauseUser(user_, supplyTokens_, borrowTokens_);
    }

    /// @inheritdoc IFluidLiquidityAdmin
    function unpauseUser(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) public onlyGuardians {
        _checkIsContract(user_);

        uint256 userData_;

        // unpause supply tokens
        uint256 length_ = supplyTokens_.length;

        if (length_ > 0) {
            for (uint256 i; i < length_; ) {
                _checkIsContractOrNativeAddress(supplyTokens_[i]);
                // userData_ => userSupplyData_
                userData_ = _userSupplyData[user_][supplyTokens_[i]];
                if ((userData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_IS_PAUSED) & 1 != 1) {
                    revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotPaused);
                }

                // set last bit of _userSupplyData (pause flag) to 0
                _userSupplyData[user_][supplyTokens_[i]] =
                    userData_ &
                    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

                unchecked {
                    ++i;
                }
            }
        }

        // unpause borrow tokens
        length_ = borrowTokens_.length;

        if (length_ > 0) {
            for (uint256 i; i < length_; ) {
                _checkIsContractOrNativeAddress(borrowTokens_[i]);
                // userData_ => userBorrowData_
                userData_ = _userBorrowData[user_][borrowTokens_[i]];
                if ((userData_ >> LiquiditySlotsLink.BITS_USER_BORROW_IS_PAUSED) & 1 != 1) {
                    revert FluidLiquidityError(ErrorTypes.AdminModule__UserNotPaused);
                }
                // set last bit of _userBorrowData (pause flag) to 0
                _userBorrowData[user_][borrowTokens_[i]] =
                    userData_ &
                    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

                unchecked {
                    ++i;
                }
            }
        }

        emit LogUnpauseUser(user_, supplyTokens_, borrowTokens_);
    }
}

/// @title Fluid Liquidity AdminModule
/// @notice Fluid Liquidity auth protected methods to configure things such as:
/// guardians, auths, governance, revenue, token configs, allowances etc.
/// Accessibility of methods is restricted to Governance, Auths or Guardians. Governance is Auth & Governance by default
contract FluidLiquidityAdminModule is AdminModuleConstants, GuardianModule {
    constructor(uint256 nativeTokenMaxBorrowLimitCap_) AdminModuleConstants(nativeTokenMaxBorrowLimitCap_) {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateExchangePrices(
        address[] calldata tokens_
    ) external returns (uint256[] memory supplyExchangePrices_, uint256[] memory borrowExchangePrices_) {
        uint256 tokensLength_ = tokens_.length;

        supplyExchangePrices_ = new uint256[](tokensLength_);
        borrowExchangePrices_ = new uint256[](tokensLength_);

        for (uint256 i; i < tokensLength_; ) {
            _checkIsContractOrNativeAddress(tokens_[i]);
            (supplyExchangePrices_[i], borrowExchangePrices_[i]) = _updateExchangePricesAndRates(tokens_[i]);

            unchecked {
                ++i;
            }
        }
    }
}
