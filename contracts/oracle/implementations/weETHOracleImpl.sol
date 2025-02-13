// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETH } from "../interfaces/external/IWeETH.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   weETH Oracle Implementation
/// @notice  This contract is used to get the exchange rate between weETH and eETH
abstract contract WeETHOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _WEETH_PRICE_SCALER_MULTIPLIER;

    /// @notice WEETH contract, e.g. on mainnet 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee
    IWeETH internal immutable _WEETH;

    /// @notice constructor sets the weETH (Etherfi's wrapped eETH) `weETH_` token address.
    constructor(IWeETH weETH_) {
        if (address(weETH_) == address(0)) {
            revert FluidOracleError(ErrorTypes.WeETHOracle__InvalidParams);
        }

        _WEETH = weETH_;

        _WEETH_PRICE_SCALER_MULTIPLIER = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - 18); // e.g. 1e9
    }

    /// @notice         Get the exchange rate from weETH contract
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getWeETHExchangeRate() internal view returns (uint256 rate_) {
        return _WEETH.getEETHByWeETH(1e18) * _WEETH_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all weETH oracle related data as utility for easy off-chain use / block explorer in a single view method
    function weETHOracleData() public view returns (uint256 weETHExchangeRate_, IWeETH weETH_) {
        return (_getWeETHExchangeRate(), _WEETH);
    }
}
