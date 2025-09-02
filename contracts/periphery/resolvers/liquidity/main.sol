// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { IFluidLiquidityResolver } from "./iLiquidityResolver.sol";
import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @notice Fluid Liquidity resolver
/// Implements various view-only methods to give easy access to Liquidity data.
contract FluidLiquidityResolver is IFluidLiquidityResolver, Variables, Structs {
    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice thrown if an input param address is zero
    error FluidLiquidityResolver__AddressZero();

    constructor(IFluidLiquidity liquidity_) Variables(liquidity_) {
        if (address(liquidity_) == address(0)) {
            revert FluidLiquidityResolver__AddressZero();
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getRevenueCollector() public view returns (address) {
        return address(uint160(LIQUIDITY.readFromStorage(bytes32(0))));
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getRevenue(address token_) public view returns (uint256 revenueAmount_) {
        uint256 liquidityTokenBalance_ = token_ == _NATIVE_TOKEN_ADDRESS
            ? address(LIQUIDITY).balance
            : IERC20(token_).balanceOf(address(LIQUIDITY));

        uint256 exchangePricesAndConfig_ = getExchangePricesAndConfig(token_);
        if (exchangePricesAndConfig_ == 0) {
            return 0;
        }

        return LiquidityCalcs.calcRevenue(getTotalAmounts(token_), exchangePricesAndConfig_, liquidityTokenBalance_);
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getStatus() public view returns (uint256) {
        return LIQUIDITY.readFromStorage(bytes32(LiquiditySlotsLink.LIQUIDITY_STATUS_SLOT));
    }

    /// @inheritdoc IFluidLiquidityResolver
    function isAuth(address auth_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_AUTHS_MAPPING_SLOT, auth_)
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function isGuardian(address guardian_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_GUARDIANS_MAPPING_SLOT,
                    guardian_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserClass(address user_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT,
                    user_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getExchangePricesAndConfig(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getRateConfig(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getTotalAmounts(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getConfigs2(address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_CONFIGS2_MAPPING_SLOT,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserSupply(address user_, address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                    user_,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserBorrow(address user_, address token_) public view returns (uint256) {
        return
            LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                    user_,
                    token_
                )
            );
    }

    /// @inheritdoc IFluidLiquidityResolver
    function listedTokens() public view returns (address[] memory listedTokens_) {
        uint256 length_ = LIQUIDITY.readFromStorage(bytes32(LiquiditySlotsLink.LIQUIDITY_LISTED_TOKENS_ARRAY_SLOT));

        listedTokens_ = new address[](length_);

        uint256 startingSlotForArrayElements_ = uint256(
            keccak256(abi.encode(LiquiditySlotsLink.LIQUIDITY_LISTED_TOKENS_ARRAY_SLOT))
        );

        for (uint256 i; i < length_; i++) {
            listedTokens_[i] = address(uint160(LIQUIDITY.readFromStorage(bytes32(startingSlotForArrayElements_ + i))));
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getTokenRateData(address token_) public view returns (RateData memory rateData_) {
        uint256 rateConfig_ = getRateConfig(token_);

        rateData_.version = rateConfig_ & 0xF;

        if (rateData_.version == 1) {
            rateData_.rateDataV1.token = token_;
            rateData_.rateDataV1.rateAtUtilizationZero =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) &
                X16;
            rateData_.rateDataV1.kink = (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) & X16;
            rateData_.rateDataV1.rateAtUtilizationKink =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) &
                X16;
            rateData_.rateDataV1.rateAtUtilizationMax =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX) &
                X16;
        } else if (rateData_.version == 2) {
            rateData_.rateDataV2.token = token_;
            rateData_.rateDataV2.rateAtUtilizationZero =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO) &
                X16;
            rateData_.rateDataV2.kink1 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationKink1 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1) &
                X16;
            rateData_.rateDataV2.kink2 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationKink2 =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2) &
                X16;
            rateData_.rateDataV2.rateAtUtilizationMax =
                (rateConfig_ >> LiquiditySlotsLink.BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX) &
                X16;
        } else if (rateData_.version > 0) {
            // when version is 0 -> token not configured yet. do not revert, just return 0 for all values
            revert("not-valid-rate-version");
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getTokensRateData(address[] calldata tokens_) public view returns (RateData[] memory rateDatas_) {
        uint256 length_ = tokens_.length;
        rateDatas_ = new RateData[](length_);

        for (uint256 i; i < length_; i++) {
            rateDatas_[i] = getTokenRateData(tokens_[i]);
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getOverallTokenData(
        address token_
    ) public view returns (Structs.OverallTokenData memory overallTokenData_) {
        overallTokenData_.rateData = getTokenRateData(token_);

        uint256 exchangePriceAndConfig_ = getExchangePricesAndConfig(token_);
        if (exchangePriceAndConfig_ > 0) {
            uint256 totalAmounts_ = getTotalAmounts(token_);

            (overallTokenData_.supplyExchangePrice, overallTokenData_.borrowExchangePrice) = LiquidityCalcs
                .calcExchangePrices(exchangePriceAndConfig_);

            overallTokenData_.borrowRate = exchangePriceAndConfig_ & X16;
            overallTokenData_.fee = (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14;
            overallTokenData_.lastStoredUtilization =
                (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) &
                X14;
            overallTokenData_.storageUpdateThreshold =
                (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD) &
                X14;
            overallTokenData_.lastUpdateTimestamp =
                (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) &
                X33;
            overallTokenData_.maxUtilization = FOUR_DECIMALS;
            if ((exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2) & 1 == 1) {
                overallTokenData_.maxUtilization = getConfigs2(token_) & X14;
            }

            // Extract supply & borrow amounts
            uint256 temp_ = totalAmounts_ & X64;
            overallTokenData_.supplyRawInterest = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE) & X64;
            overallTokenData_.supplyInterestFree = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) & X64;
            overallTokenData_.borrowRawInterest = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            // no & mask needed for borrow interest free as it occupies the last bits in the storage slot
            temp_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE);
            overallTokenData_.borrowInterestFree = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);

            uint256 supplyWithInterest_;
            uint256 borrowWithInterest_;
            if (overallTokenData_.supplyRawInterest > 0) {
                // use old exchange prices for supply rate to be at same level as borrow rate from storage.
                // Note the rate here can be a tiny bit with higher precision because we use borrowWithInterest_ / supplyWithInterest_
                // which has higher precision than the utilization used from storage in LiquidityCalcs
                supplyWithInterest_ =
                    (overallTokenData_.supplyRawInterest *
                        ((exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) &
                            X64)) /
                    EXCHANGE_PRICES_PRECISION; // normalized from raw
                borrowWithInterest_ =
                    (overallTokenData_.borrowRawInterest *
                        ((exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) &
                            X64)) /
                    EXCHANGE_PRICES_PRECISION; // normalized from raw

                overallTokenData_.supplyRate = supplyWithInterest_ == 0
                    ? 0
                    : (overallTokenData_.borrowRate * (FOUR_DECIMALS - overallTokenData_.fee) * borrowWithInterest_) /
                        (supplyWithInterest_ * FOUR_DECIMALS);
            }

            supplyWithInterest_ =
                (overallTokenData_.supplyRawInterest * overallTokenData_.supplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION; // normalized from raw
            overallTokenData_.totalSupply = supplyWithInterest_ + overallTokenData_.supplyInterestFree;
            borrowWithInterest_ =
                (overallTokenData_.borrowRawInterest * overallTokenData_.borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION; // normalized from raw
            overallTokenData_.totalBorrow = borrowWithInterest_ + overallTokenData_.borrowInterestFree;

            overallTokenData_.revenue = getRevenue(token_);
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getOverallTokensData(
        address[] memory tokens_
    ) public view returns (Structs.OverallTokenData[] memory overallTokensData_) {
        uint256 length_ = tokens_.length;
        overallTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            overallTokensData_[i] = getOverallTokenData(tokens_[i]);
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getAllOverallTokensData() public view returns (Structs.OverallTokenData[] memory overallTokensData_) {
        return getOverallTokensData(listedTokens());
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserSupplyData(
        address user_,
        address token_
    )
        public
        view
        returns (Structs.UserSupplyData memory userSupplyData_, Structs.OverallTokenData memory overallTokenData_)
    {
        overallTokenData_ = getOverallTokenData(token_);
        uint256 userSupply_ = getUserSupply(user_, token_);

        if (userSupply_ > 0) {
            // if userSupply_ == 0 -> user not configured yet for token at Liquidity
            userSupplyData_.modeWithInterest = userSupply_ & 1 == 1;
            userSupplyData_.supply = BigMathMinified.fromBigNumber(
                (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            // get updated expanded withdrawal limit
            userSupplyData_.withdrawalLimit = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
                userSupply_,
                userSupplyData_.supply
            );

            userSupplyData_.lastUpdateTimestamp =
                (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) &
                X33;
            userSupplyData_.expandPercent = (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;
            userSupplyData_.expandDuration = (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24;
            userSupplyData_.baseWithdrawalLimit = BigMathMinified.fromBigNumber(
                (userSupply_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            if (userSupplyData_.modeWithInterest) {
                // convert raw amounts to normal for withInterest mode
                userSupplyData_.supply =
                    (userSupplyData_.supply * overallTokenData_.supplyExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
                userSupplyData_.withdrawalLimit =
                    (userSupplyData_.withdrawalLimit * overallTokenData_.supplyExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
                userSupplyData_.baseWithdrawalLimit =
                    (userSupplyData_.baseWithdrawalLimit * overallTokenData_.supplyExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
            }

            userSupplyData_.withdrawableUntilLimit = userSupplyData_.supply > userSupplyData_.withdrawalLimit
                ? userSupplyData_.supply - userSupplyData_.withdrawalLimit
                : 0;
            uint balanceOf_ = token_ == _NATIVE_TOKEN_ADDRESS
                ? address(LIQUIDITY).balance
                : TokenInterface(token_).balanceOf(address(LIQUIDITY));

            userSupplyData_.withdrawable = balanceOf_ > userSupplyData_.withdrawableUntilLimit
                ? userSupplyData_.withdrawableUntilLimit
                : balanceOf_;
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserMultipleSupplyData(
        address user_,
        address[] calldata tokens_
    )
        public
        view
        returns (
            Structs.UserSupplyData[] memory userSuppliesData_,
            Structs.OverallTokenData[] memory overallTokensData_
        )
    {
        uint256 length_ = tokens_.length;
        userSuppliesData_ = new Structs.UserSupplyData[](length_);
        overallTokensData_ = new Structs.OverallTokenData[](length_);

        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i], overallTokensData_[i]) = getUserSupplyData(user_, tokens_[i]);
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserBorrowData(
        address user_,
        address token_
    )
        public
        view
        returns (Structs.UserBorrowData memory userBorrowData_, Structs.OverallTokenData memory overallTokenData_)
    {
        overallTokenData_ = getOverallTokenData(token_);
        uint256 userBorrow_ = getUserBorrow(user_, token_);

        if (userBorrow_ > 0) {
            // if userBorrow_ == 0 -> user not configured yet for token at Liquidity

            userBorrowData_.modeWithInterest = userBorrow_ & 1 == 1;

            userBorrowData_.borrow = BigMathMinified.fromBigNumber(
                (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            // get updated expanded borrow limit
            userBorrowData_.borrowLimit = LiquidityCalcs.calcBorrowLimitBeforeOperate(
                userBorrow_,
                userBorrowData_.borrow
            );

            userBorrowData_.lastUpdateTimestamp =
                (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP) &
                X33;
            userBorrowData_.expandPercent = (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14;
            userBorrowData_.expandDuration = (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24;
            userBorrowData_.baseBorrowLimit = BigMathMinified.fromBigNumber(
                (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );
            userBorrowData_.maxBorrowLimit = BigMathMinified.fromBigNumber(
                (userBorrow_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );

            if (userBorrowData_.modeWithInterest) {
                // convert raw amounts to normal for withInterest mode
                userBorrowData_.borrow =
                    (userBorrowData_.borrow * overallTokenData_.borrowExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
                userBorrowData_.borrowLimit =
                    (userBorrowData_.borrowLimit * overallTokenData_.borrowExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
                userBorrowData_.baseBorrowLimit =
                    (userBorrowData_.baseBorrowLimit * overallTokenData_.borrowExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
                userBorrowData_.maxBorrowLimit =
                    (userBorrowData_.maxBorrowLimit * overallTokenData_.borrowExchangePrice) /
                    EXCHANGE_PRICES_PRECISION;
            }

            userBorrowData_.borrowLimitUtilization =
                (overallTokenData_.maxUtilization * overallTokenData_.totalSupply) /
                1e4;

            // uncollected revenue is counting towards available balanceOf.
            // because of this "borrowable" would be showing an amount that can go above 100% utilization, causing a revert.
            // need to take into consideration the borrowable amount until the max utilization limit, which depends on the total
            // borrow amount (not user specific)
            uint borrowableUntilUtilizationLimit_ = userBorrowData_.borrowLimitUtilization >
                overallTokenData_.totalBorrow
                ? userBorrowData_.borrowLimitUtilization - overallTokenData_.totalBorrow
                : 0;

            uint borrowableUntilBorrowLimit_ = userBorrowData_.borrowLimit > userBorrowData_.borrow
                ? userBorrowData_.borrowLimit - userBorrowData_.borrow
                : 0;

            userBorrowData_.borrowableUntilLimit = borrowableUntilBorrowLimit_ > borrowableUntilUtilizationLimit_
                ? borrowableUntilUtilizationLimit_
                : borrowableUntilBorrowLimit_;

            // if available balance at Liquidity is less than the borrowableUntilLimit amount, then the balance is
            // the limiting borrowable amount.
            uint balanceOf_ = token_ == _NATIVE_TOKEN_ADDRESS
                ? address(LIQUIDITY).balance
                : TokenInterface(token_).balanceOf(address(LIQUIDITY));

            userBorrowData_.borrowable = balanceOf_ > userBorrowData_.borrowableUntilLimit
                ? userBorrowData_.borrowableUntilLimit
                : balanceOf_;
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserMultipleBorrowData(
        address user_,
        address[] calldata tokens_
    )
        public
        view
        returns (
            Structs.UserBorrowData[] memory userBorrowingsData_,
            Structs.OverallTokenData[] memory overallTokensData_
        )
    {
        uint256 length_ = tokens_.length;
        userBorrowingsData_ = new UserBorrowData[](length_);
        overallTokensData_ = new Structs.OverallTokenData[](length_);

        for (uint256 i; i < length_; i++) {
            (userBorrowingsData_[i], overallTokensData_[i]) = getUserBorrowData(user_, tokens_[i]);
        }
    }

    /// @inheritdoc IFluidLiquidityResolver
    function getUserMultipleBorrowSupplyData(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    )
        public
        view
        returns (
            Structs.UserSupplyData[] memory userSuppliesData_,
            Structs.OverallTokenData[] memory overallSupplyTokensData_,
            Structs.UserBorrowData[] memory userBorrowingsData_,
            Structs.OverallTokenData[] memory overallBorrowTokensData_
        )
    {
        uint256 length_ = supplyTokens_.length;
        userSuppliesData_ = new Structs.UserSupplyData[](length_);
        overallSupplyTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i], overallSupplyTokensData_[i]) = getUserSupplyData(user_, supplyTokens_[i]);
        }

        length_ = borrowTokens_.length;
        userBorrowingsData_ = new UserBorrowData[](length_);
        overallBorrowTokensData_ = new Structs.OverallTokenData[](length_);
        for (uint256 i; i < length_; i++) {
            (userBorrowingsData_[i], overallBorrowTokensData_[i]) = getUserBorrowData(user_, borrowTokens_[i]);
        }
    }
}
