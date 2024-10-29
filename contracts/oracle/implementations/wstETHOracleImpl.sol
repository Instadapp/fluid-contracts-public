// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWstETH } from "../interfaces/external/IWstETH.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   wstETH Oracle Implementation
/// @notice  This contract is used to get the exchange rate between wstETH and stETH
abstract contract WstETHOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _WSTETH_PRICE_SCALER_MULTIPLIER;

    /// @notice WSTETH contract, e.g. on mainnet 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
    IWstETH internal immutable _WSTETH;

    /// @notice constructor sets the wstETH `wstETH_` token address.
    constructor(IWstETH wstETH_) {
        if (address(wstETH_) == address(0)) {
            revert FluidOracleError(ErrorTypes.WstETHOracle__InvalidParams);
        }

        _WSTETH = wstETH_;

        _WSTETH_PRICE_SCALER_MULTIPLIER = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - 18); // e.g. 1e9
    }

    /// @notice         Get the exchange rate from wstETH contract
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getWstETHExchangeRate() internal view returns (uint256 rate_) {
        return _WSTETH.stEthPerToken() * _WSTETH_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all wWtETH oracle related data as utility for easy off-chain use / block explorer in a single view method
    function wstETHOracleData() public view returns (uint256 wstETHExchangeRate_, IWstETH wstETH_) {
        return (_getWstETHExchangeRate(), _WSTETH);
    }
}
