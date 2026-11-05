// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IUSDOracle } from "../interfaces/iUSDOracle.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

/// @title TokenAmtResolver
/// @notice Utility for converting between token amounts and USD values using the FluidUsdOracle.
///         All USD values are in 1e27 precision (1 USD = 1e27).
///         Inheritable by auth contracts, limit handlers, resolvers, or any consumer that needs
///         token <-> USD conversions.
abstract contract TokenAmtResolver is Error {
    uint256 private constant ORACLE_PRECISION = 1e27;

    /// @notice Converts a token amount to its USD value using the oracle's getPriceRawForMode.
    /// @param usdOracle_ Address of the FluidUsdOracle.
    /// @param token_ The token address.
    /// @param amount_ The token amount in token decimals.
    /// @param priceMode_ The price mode (PRICE_MODE_MARKET = 1, PRICE_MODE_PEG = 2).
    /// @return usdValue_ The USD value in 1e27 precision.
    function _getUsdValueForTokenAmount(
        address usdOracle_,
        address token_,
        uint256 amount_,
        uint8 priceMode_
    ) internal view returns (uint256 usdValue_) {
        (uint256 price_, uint8 decimals_, ) = IUSDOracle(usdOracle_).getPriceRawForMode(token_, priceMode_);
        if (price_ == 0) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__PriceZero);
        }

        // price_ is USD per 1 whole token in 1e27 precision.
        // amount_ is in token decimals. So:
        // usdValue = amount * price / 10^decimals
        usdValue_ = (amount_ * price_) / (10 ** uint256(decimals_));
    }

    /// @notice Converts a USD value to a token amount using the oracle's getPriceRawForMode.
    /// @param usdOracle_ Address of the FluidUsdOracle.
    /// @param token_ The token address.
    /// @param usdValue_ The USD value in 1e27 precision.
    /// @param priceMode_ The price mode (PRICE_MODE_MARKET = 1, PRICE_MODE_PEG = 2).
    /// @return amount_ The token amount in token decimals.
    function _getTokenAmountForUsdValue(
        address usdOracle_,
        address token_,
        uint256 usdValue_,
        uint8 priceMode_
    ) internal view returns (uint256 amount_) {
        (uint256 price_, uint8 decimals_, ) = IUSDOracle(usdOracle_).getPriceRawForMode(token_, priceMode_);
        if (price_ == 0) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__PriceZero);
        }

        // Inverse of above:
        // amount = usdValue * 10^decimals / price
        amount_ = (usdValue_ * (10 ** uint256(decimals_))) / price_;
    }
}
