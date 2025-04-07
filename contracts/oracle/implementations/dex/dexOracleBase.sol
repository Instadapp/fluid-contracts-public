// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error as OracleError } from "../../error.sol";

interface IFluidStorageReadable {
    function readFromStorage(bytes32 slot_) external view returns (uint result_);
}

abstract contract DexOracleAdjustResult {
    uint256 internal immutable RESULT_MULTIPLIER;
    uint256 internal immutable RESULT_DIVISOR;

    constructor(uint256 resultMultiplier_, uint256 resultDivisor_) {
        RESULT_MULTIPLIER = resultMultiplier_ == 0 ? 1 : resultMultiplier_;
        RESULT_DIVISOR = resultDivisor_ == 0 ? 1 : resultDivisor_;
    }
}

abstract contract DexOracleBase is DexOracleAdjustResult, OracleError {
    IFluidDexT1 internal immutable DEX_;

    IFluidStorageReadable internal constant LIQUIDITY =
        IFluidStorageReadable(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    /// @dev if true, convert all reserves token1 into token0. otherwise all token0 into token1.
    bool internal immutable QUOTE_IN_TOKEN0;

    /// @dev internal immutables read from DEX at time of deployment
    bytes32 internal immutable SUPPLY_TOKEN_0_SLOT;
    bytes32 internal immutable SUPPLY_TOKEN_1_SLOT;
    bytes32 internal immutable BORROW_TOKEN_0_SLOT;
    bytes32 internal immutable BORROW_TOKEN_1_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_1_SLOT;

    uint256 internal immutable TOKEN_0_NUMERATOR_PRECISION;
    uint256 internal immutable TOKEN_0_DENOMINATOR_PRECISION;
    uint256 internal immutable TOKEN_1_NUMERATOR_PRECISION;
    uint256 internal immutable TOKEN_1_DENOMINATOR_PRECISION;

    constructor(address dexPool_, bool quoteInToken0_) {
        if (dexPool_ == address(0)) {
            revert FluidOracleError(ErrorTypes.DexOracle__InvalidParams);
        }

        DEX_ = IFluidDexT1(dexPool_);
        QUOTE_IN_TOKEN0 = quoteInToken0_;

        IFluidDexT1.ConstantViews memory constantViews_ = DEX_.constantsView();
        EXCHANGE_PRICE_TOKEN_0_SLOT = constantViews_.exchangePriceToken0Slot;
        EXCHANGE_PRICE_TOKEN_1_SLOT = constantViews_.exchangePriceToken1Slot;
        SUPPLY_TOKEN_0_SLOT = constantViews_.supplyToken0Slot;
        SUPPLY_TOKEN_1_SLOT = constantViews_.supplyToken1Slot;
        BORROW_TOKEN_0_SLOT = constantViews_.borrowToken0Slot;
        BORROW_TOKEN_1_SLOT = constantViews_.borrowToken1Slot;

        IFluidDexT1.ConstantViews2 memory constantViews2_ = DEX_.constantsView2();
        TOKEN_0_NUMERATOR_PRECISION = constantViews2_.token0NumeratorPrecision;
        TOKEN_0_DENOMINATOR_PRECISION = constantViews2_.token0DenominatorPrecision;
        TOKEN_1_NUMERATOR_PRECISION = constantViews2_.token1NumeratorPrecision;
        TOKEN_1_DENOMINATOR_PRECISION = constantViews2_.token1DenominatorPrecision;
    }

    /// @dev returns combined Dex debt reserves in quote token, scaled to quote token decimals
    function _getDexReservesCombinedInQuoteToken(
        uint256 conversionPrice_,
        uint256 token0Reserves_,
        uint256 token1Reserves_
    ) internal view virtual returns (uint256 reserves_) {
        if (QUOTE_IN_TOKEN0) {
            // e.g. for USDC / ETH DEX when:
            // "token0RealReserves": "6534_060871000000", // USDC
            // "token1RealReserves": "1_330669697660", // ETH
            // "lastStoredPrice": "0_000293732487359446271393792",
            // 6534_060871000000 + (1_330669697660 * (1e54 / 0_000293732487359446271393792)) / 1e27 = 11064_270347051701 USDC

            // Conversion price must be inverted to be token0/token1
            conversionPrice_ = 1e54 / conversionPrice_;

            reserves_ = token0Reserves_ + (token1Reserves_ * conversionPrice_) / (1e27);

            // bring reserves to token0 decimals
            reserves_ = ((reserves_ * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION);
        } else {
            // e.g. for USDC / ETH DEX when:
            // "token0RealReserves": "6534_060871000000", // USDC
            // "token1RealReserves": "1_330669697660", // ETH
            // "lastStoredPrice": "0_000293732487359446271393792",
            // 1_330669697660 + (6534_060871000000 * 0_000293732487359446271393792) / 1e27 = 3_249935649856 ETH

            reserves_ = token1Reserves_ + (token0Reserves_ * conversionPrice_) / (1e27);

            // bring reserves to token1 decimals
            reserves_ = ((reserves_ * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
        }
    }

    /// @notice Returns the base configuration data of the FluidDexOracle.
    ///
    /// @return dexPool_ The address of the Dex pool.
    /// @return quoteInToken0_ A boolean indicating if the quote is in token0.
    /// @return liquidity_ The address of liquidity layer.
    /// @return resultMultiplier_ The result multiplier.
    /// @return resultDivisor_ The result divisor.
    function dexOracleData()
        public
        view
        returns (
            address dexPool_,
            bool quoteInToken0_,
            address liquidity_,
            uint256 resultMultiplier_,
            uint256 resultDivisor_
        )
    {
        return (address(DEX_), QUOTE_IN_TOKEN0, address(LIQUIDITY), RESULT_MULTIPLIER, RESULT_DIVISOR);
    }
}
