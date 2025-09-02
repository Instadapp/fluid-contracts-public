// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { IRedstoneOracle } from "../interfaces/external/IRedstoneOracle.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { RedstoneStructs } from "./structs.sol";

/// @title   Redstone Oracle implementation
/// @notice  This contract is used to get the exchange rate from a Redstone Oracle
abstract contract RedstoneOracleImpl is OracleError, RedstoneStructs {
    /// @notice Redstone price oracle to check for the exchange rate
    IRedstoneOracle internal immutable _REDSTONE_ORACLE;
    /// @notice Flag to invert the price or not (to e.g. for WETH/USDC pool return prive of USDC per 1 WETH)
    bool internal immutable _REDSTONE_INVERT_RATE;

    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _REDSTONE_PRICE_SCALER_MULTIPLIER;
    /// @notice constant value for inverting price to reduce gas usage
    uint256 internal immutable _REDSTONE_INVERT_PRICE_DIVIDEND;

    address internal immutable _REDSTONE_ORACLE_NOT_SET_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice constructor sets the Redstone oracle data
    constructor(RedstoneOracleData memory oracleData_) {
        if (address(oracleData_.oracle) == address(0) || oracleData_.token0Decimals == 0) {
            revert FluidOracleError(ErrorTypes.RedstoneOracle__InvalidParams);
        }

        _REDSTONE_ORACLE = oracleData_.oracle;
        _REDSTONE_INVERT_RATE = oracleData_.invertRate;

        // for explanation on how to get to scaler multiplier and dividend see `chainlinkOracleImpl.sol`.
        // no support for token1Decimals with more than OracleUtils.RATE_OUTPUT_DECIMALS decimals for now as extremely unlikely case
        _REDSTONE_PRICE_SCALER_MULTIPLIER = address(oracleData_.oracle) == _REDSTONE_ORACLE_NOT_SET_ADDRESS
            ? 1
            : 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - oracleData_.token0Decimals);
        _REDSTONE_INVERT_PRICE_DIVIDEND = address(oracleData_.oracle) == _REDSTONE_ORACLE_NOT_SET_ADDRESS
            ? 1
            : 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + oracleData_.token0Decimals);
    }

    /// @dev           Get the exchange rate from Redstone oracle
    /// @param rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getRedstoneExchangeRate() internal view returns (uint256 rate_) {
        try _REDSTONE_ORACLE.getExchangeRate() returns (uint256 exchangeRate_) {
            if (_REDSTONE_INVERT_RATE) {
                // invert the price
                return _REDSTONE_INVERT_PRICE_DIVIDEND / exchangeRate_;
            } else {
                return exchangeRate_ * _REDSTONE_PRICE_SCALER_MULTIPLIER;
            }
        } catch {
            return 0;
        }
    }

    /// @notice returns all Redstone oracle related data as utility for easy off-chain use / block explorer in a single view method
    function redstoneOracleData()
        public
        view
        returns (uint256 redstoneExchangeRate_, IRedstoneOracle redstoneOracle_, bool redstoneInvertRate_)
    {
        return (
            address(_REDSTONE_ORACLE) == _REDSTONE_ORACLE_NOT_SET_ADDRESS ? 0 : _getRedstoneExchangeRate(),
            _REDSTONE_ORACLE,
            _REDSTONE_INVERT_RATE
        );
    }
}
