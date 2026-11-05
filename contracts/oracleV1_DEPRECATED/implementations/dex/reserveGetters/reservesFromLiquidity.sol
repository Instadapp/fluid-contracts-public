// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { DexOracleBase } from "../dexOracleBase.sol";

/// @notice reads the dex reserves directly from Liquidity (user supply / user debt)
abstract contract DexReservesFromLiquidity is DexOracleBase {
    constructor(address dexPool_, bool quoteInToken0_) DexOracleBase(dexPool_, quoteInToken0_) {}

    /// @dev Retrieves collateral amount from liquidity layer for a given token
    /// @param supplyTokenSlot_ The storage slot for the supply token data
    /// @param exchangePriceSlot_ The storage slot for the exchange price of the token
    /// @param isToken0_ Boolean indicating if the token is token0 (true) or token1 (false)
    /// @return tokenSupply_ The calculated liquidity collateral amount
    function _getLiquidityCollateral(
        bytes32 supplyTokenSlot_,
        bytes32 exchangePriceSlot_,
        bool isToken0_
    ) private view returns (uint tokenSupply_) {
        uint tokenSupplyData_ = LIQUIDITY.readFromStorage(supplyTokenSlot_);
        tokenSupply_ = (tokenSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & LiquidityCalcs.X64;
        tokenSupply_ =
            (tokenSupply_ >> LiquidityCalcs.DEFAULT_EXPONENT_SIZE) <<
            (tokenSupply_ & LiquidityCalcs.DEFAULT_EXPONENT_MASK);

        (uint256 exchangePrice_, ) = LiquidityCalcs.calcExchangePrices(LIQUIDITY.readFromStorage(exchangePriceSlot_));

        if (tokenSupplyData_ & 1 == 1) {
            // supply with interest is on
            unchecked {
                tokenSupply_ = (tokenSupply_ * exchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        // bring to 1e12 decimals
        unchecked {
            tokenSupply_ = isToken0_
                ? ((tokenSupply_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION)
                : ((tokenSupply_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION);
        }
    }

    /// @dev Retrieves debt amount from liquidity layer for a given token
    /// @param borrowTokenSlot_ The storage slot for the borrow token data
    /// @param exchangePriceSlot_ The storage slot for the exchange price of the token
    /// @param isToken0_ Boolean indicating if the token is token0 (true) or token1 (false)
    /// @return debtAmount_ The calculated liquidity debt amount adjusted to 1e12 decimals
    function _getLiquidityDebt(
        bytes32 borrowTokenSlot_,
        bytes32 exchangePriceSlot_,
        bool isToken0_
    ) private view returns (uint debtAmount_) {
        uint debtAmountData_ = LIQUIDITY.readFromStorage(borrowTokenSlot_);
        debtAmount_ = (debtAmountData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & LiquidityCalcs.X64;
        debtAmount_ =
            (debtAmount_ >> LiquidityCalcs.DEFAULT_EXPONENT_SIZE) <<
            (debtAmount_ & LiquidityCalcs.DEFAULT_EXPONENT_MASK);

        (, uint256 exchangePrice_) = LiquidityCalcs.calcExchangePrices(LIQUIDITY.readFromStorage(exchangePriceSlot_));

        if (debtAmountData_ & 1 == 1) {
            // debt with interest is on
            unchecked {
                debtAmount_ = (debtAmount_ * exchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        unchecked {
            debtAmount_ = isToken0_
                ? ((debtAmount_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION)
                : ((debtAmount_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION);
        }
    }

    /// @dev Get the col reserves at the Dex adjusted to 1e12 decimals
    function _getDexCollateralReserves()
        internal
        view
        virtual
        returns (uint256 token0Reserves_, uint256 token1Reserves_)
    {
        // Note check if smart col is enabled is done already via checking if total supply shares == 0
        token0Reserves_ = _getLiquidityCollateral(SUPPLY_TOKEN_0_SLOT, EXCHANGE_PRICE_TOKEN_0_SLOT, true);
        token1Reserves_ = _getLiquidityCollateral(SUPPLY_TOKEN_1_SLOT, EXCHANGE_PRICE_TOKEN_1_SLOT, false);
    }

    /// @dev Get the debt reserves at the Dex adjusted to 1e12 decimals
    function _getDexDebtReserves() internal view virtual returns (uint256 token0Reserves_, uint256 token1Reserves_) {
        // Note check if smart debt is enabled is done already via checking if total borrow shares == 0

        token0Reserves_ = _getLiquidityDebt(BORROW_TOKEN_0_SLOT, EXCHANGE_PRICE_TOKEN_0_SLOT, true);
        token1Reserves_ = _getLiquidityDebt(BORROW_TOKEN_1_SLOT, EXCHANGE_PRICE_TOKEN_1_SLOT, false);
    }
}
