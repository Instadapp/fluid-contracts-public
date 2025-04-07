// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   Peg Oracle Implementation
/// @notice  This contract is used to get the exchange rate between pegged assets like sUSDE / USDC or USDE / USDC.
///          Price is adjusted for token decimals and optionally a IERC4626 source feed can be set (e.g. for sUSDE or sUSDS).
abstract contract PegOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _DECIMALS_PRICE_SCALER_MULTIPLIER;

    /// @notice IERC4626 source feed contract, e.g. sUSDE on mainnet 0x9d39a5de30e57443bff2a8307a4256c8797a3497
    IERC4626 internal immutable _ERC4626_FEED;

    uint8 internal immutable _COL_TOKEN_DECIMALS;
    uint8 internal immutable _DEBT_TOKEN_DECIMALS;

    // e.g. for  USDE / USDC -> 18 /  6
    //      for sUSDE / USDT -> 18 /  6
    //      for  USDE / GHO  -> 18 / 18
    constructor(uint8 colTokenDecimals_, uint8 debtTokenDecimals_, IERC4626 erc4626Feed_) {
        if (colTokenDecimals_ < 6 || debtTokenDecimals_ < 6 || colTokenDecimals_ > 18 || debtTokenDecimals_ > 18) {
            revert FluidOracleError(ErrorTypes.PegOracle__InvalidParams);
        }

        _ERC4626_FEED = erc4626Feed_;
        _COL_TOKEN_DECIMALS = colTokenDecimals_;
        _DEBT_TOKEN_DECIMALS = debtTokenDecimals_;

        int256 decimalsDiff_ = int256(uint256(colTokenDecimals_)) - int256(uint256(debtTokenDecimals_)); // max diff here is +12 to -12
        _DECIMALS_PRICE_SCALER_MULTIPLIER =
            10 ** uint256(int256(OracleUtils.RATE_OUTPUT_DECIMALS - 15) - decimalsDiff_);
        // erc4626 price feed is fetched in 1e15 precision. So with decimals e.g. when:
        // - 18 /  6 -> decimalsDiff_ = 18 - 6 = 12, so scaler = 10^(27 - 15 - 12) = 10^0 = 1
        //              output = 1e15 * 1 = 1e15
        // - 18 /  7 -> decimalsDiff_ = 18 - 7 = 11, so scaler = 10^(27 - 15 - 11) = 10^1 = 10
        //              output = 1e15 * 10 = 1e16
        // - 18 / 18 -> decimalsDiff_ = 18 - 18 = 0, so scaler = 10^(27 - 15 - 0) = 10^12 = 1e12
        //              output = 1e15 * 1e12 = 1e27
        // -  8 / 18 -> decimalsDiff_ = 8 - 18 = -10, so scaler = 10^(27 - 15 - (-10)) = 10^22 = 1e22
        //              output = 1e15 * 1e22 = 1e37
        // - 12 /  6 -> decimalsDiff_ = 12 - 6 = 6, so scaler = 10^(27 - 15 - 6) = 10^6 = 1e6
        //              output = 1e15 * 1e6 = 1e21
        // - 12 / 18 -> decimalsDiff_ = 12 - 18 = -6, so scaler = 10^(27 - 15 - (-6)) = 10^18 = 1e18
        //              output = 1e15 * 1e18 = 1e33
        // -  6 /  6 -> decimalsDiff_ = 6 - 6 = 0, so scaler = 10^(27 - 15 - 0) = 10^12 = 1e12
        //              output = 1e15 * 1e12 = 1e27s
    }

    /// @notice         Get the exchange rate for the pegged assets. Fetching from ERC4626 feed if configured.
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getPegExchangeRate() internal view returns (uint256 rate_) {
        rate_ = 1e15;
        if (address(_ERC4626_FEED) != address(0)) {
            rate_ = _ERC4626_FEED.convertToAssets(1e15);
        }

        return rate_ * _DECIMALS_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all peg oracle related data as utility for easy off-chain use / block explorer in a single view method
    function pegOracleData()
        public
        view
        returns (uint256 pegExchangeRate_, IERC4626 erc4626Feed_, uint256 colTokenDecimals_, uint256 debtTokenDecimals_)
    {
        return (_getPegExchangeRate(), _ERC4626_FEED, _COL_TOKEN_DECIMALS, _DEBT_TOKEN_DECIMALS);
    }
}
