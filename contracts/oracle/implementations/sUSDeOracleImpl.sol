// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   sUSDe Oracle Implementation
/// @notice  This contract is used to get the exchange rate between sUSDe and USDe, adjusted for token decimals
///          of a debt token (e.g. USDC / USDT)
abstract contract SUSDeOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _SUSDE_PRICE_SCALER_MULTIPLIER;

    /// @notice SUSDE contract, e.g. on mainnet 0x9d39a5de30e57443bff2a8307a4256c8797a3497
    IERC4626 internal immutable _SUSDE;

    uint8 internal immutable _DEBT_TOKEN_DECIMALS;

    /// @notice constructor sets the sUSDe `sUSDe_` token address.
    constructor(IERC4626 sUSDe_, uint8 debtTokenDecimals_) {
        if (address(sUSDe_) == address(0) || debtTokenDecimals_ < 6) {
            revert FluidOracleError(ErrorTypes.SUSDeOracle__InvalidParams);
        }

        _SUSDE = sUSDe_;

        // debt token decimals is used to make sure the returned exchange rate is scaled correctly e.g.
        // for an exchange rate between sUSDe and USDC (this Oracle returning amount of USDC for 1e18 sUSDe).
        _DEBT_TOKEN_DECIMALS = debtTokenDecimals_;

        _SUSDE_PRICE_SCALER_MULTIPLIER = 10 ** (debtTokenDecimals_ - 6);
        // e.g. when:
        // - debtTokenDecimals_ = 6 -> scaler multiplier is 1
        // - debtTokenDecimals_ = 7 -> scaler multiplier is 10
        // - debtTokenDecimals_ = 18 -> scaler multiplier is 1e12
        // -> gets 1e15 returned exchange rate to 1e27
    }

    /// @notice         Get the exchange rate from sUSDe contract (amount of USDe for 1 sUSDe)
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getSUSDeExchangeRate() internal view returns (uint256 rate_) {
        return _SUSDE.convertToAssets(1e15) * _SUSDE_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all sUSDe oracle related data as utility for easy off-chain use / block explorer in a single view method
    function sUSDeOracleData()
        public
        view
        returns (uint256 sUSDeExchangeRate_, IERC4626 sUSDe_, uint256 debtTokenDecimals_)
    {
        return (_getSUSDeExchangeRate(), _SUSDE, _DEBT_TOKEN_DECIMALS);
    }
}
