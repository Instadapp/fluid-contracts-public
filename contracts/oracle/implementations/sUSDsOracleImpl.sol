// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   sUSDs Oracle Implementation
/// @notice  This contract is used to get the exchange rate between sUSDs and USDs, adjusted for token decimals
///          of a debt token (e.g. USDC / USDT)
abstract contract SUSDsOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _SUSDS_PRICE_SCALER_MULTIPLIER;

    /// @notice SUSDS contract
    IERC4626 internal immutable _SUSDS;

    uint8 internal immutable _DEBT_TOKEN_DECIMALS;

    /// @notice constructor sets the sUSDs `sUSDs_` token address.
    constructor(IERC4626 sUSDs_, uint8 debtTokenDecimals_) {
        if (address(sUSDs_) == address(0) || debtTokenDecimals_ < 6) {
            revert FluidOracleError(ErrorTypes.SUSDsOracle__InvalidParams);
        }

        _SUSDS = sUSDs_;

        // debt token decimals is used to make sure the returned exchange rate is scaled correctly e.g.
        // for an exchange rate between sUSDs and USDC (this Oracle returning amount of USDC for 1e18 sUSDs).
        _DEBT_TOKEN_DECIMALS = debtTokenDecimals_;

        _SUSDS_PRICE_SCALER_MULTIPLIER = 10 ** (debtTokenDecimals_ - 6);
        // e.g. when:
        // - debtTokenDecimals_ = 6 -> scaler multiplier is 1
        // - debtTokenDecimals_ = 7 -> scaler multiplier is 10
        // - debtTokenDecimals_ = 18 -> scaler multiplier is 1e12
        // -> gets 1e15 returned exchange rate to 1e27
    }

    /// @notice         Get the exchange rate from sUSDs contract (amount of USDe for 1 sUSDs)
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getSUSDsExchangeRate() internal view returns (uint256 rate_) {
        return _SUSDS.convertToAssets(1e15) * _SUSDS_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all sUSDs oracle related data as utility for easy off-chain use / block explorer in a single view method
    function sUSDsOracleData()
        public
        view
        returns (uint256 sUSDsExchangeRate_, IERC4626 sUSDs_, uint256 debtTokenDecimals_)
    {
        return (_getSUSDsExchangeRate(), _SUSDS, _DEBT_TOKEN_DECIMALS);
    }
}
