// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { IRedstoneOracle } from "../interfaces/external/IRedstoneOracle.sol";
import { Error as OracleError } from "../error.sol";
import { ChainlinkOracleImpl } from "./chainlinkOracleImpl.sol";
import { RedstoneOracleImpl } from "./redstoneOracleImpl.sol";

/// @title   Fallback Oracle implementation
/// @notice  This contract is used to get the exchange rate from a main oracle feed and a fallback oracle feed.
//
// @dev     inheriting contracts should implement a view method to expose `_FALLBACK_ORACLE_MAIN_SOURCE`
abstract contract FallbackOracleImpl is OracleError, RedstoneOracleImpl, ChainlinkOracleImpl {
    /// @dev which oracle to use as main source:
    /// - 1 = Chainlink ONLY (no fallback)
    /// - 2 = Chainlink with Redstone Fallback
    /// - 3 = Redstone with Chainlink Fallback
    uint8 internal immutable _FALLBACK_ORACLE_MAIN_SOURCE;

    /// @notice                     sets the main source, Chainlink Oracle and Redstone Oracle data.
    /// @param mainSource_          which oracle to use as main source:
    ///                                  - 1 = Chainlink ONLY (no fallback)
    ///                                  - 2 = Chainlink with Redstone Fallback
    ///                                  - 3 = Redstone with Chainlink Fallback
    /// @param chainlinkParams_     chainlink Oracle constructor params struct.
    /// @param redstoneOracle_      Redstone Oracle data. (address can be set to zero address if using Chainlink only)
    constructor(
        uint8 mainSource_,
        ChainlinkConstructorParams memory chainlinkParams_,
        RedstoneOracleData memory redstoneOracle_
    )
        ChainlinkOracleImpl(chainlinkParams_)
        RedstoneOracleImpl(
            address(redstoneOracle_.oracle) == address(0)
                ? RedstoneOracleData(IRedstoneOracle(_REDSTONE_ORACLE_NOT_SET_ADDRESS), false, 1)
                : redstoneOracle_
        )
    {
        if (mainSource_ < 1 || mainSource_ > 3) {
            revert FluidOracleError(ErrorTypes.FallbackOracle__InvalidParams);
        }
        _FALLBACK_ORACLE_MAIN_SOURCE = mainSource_;
    }

    /// @dev returns the exchange rate for the main oracle source, or the fallback source (if configured) if the main exchange rate
    /// fails to be fetched. If returned rate is 0, fetching rate failed or something went wrong.
    /// @return exchangeRate_ exchange rate
    /// @return fallback_ whether fallback was necessary or not
    function _getRateWithFallback() internal view returns (uint256 exchangeRate_, bool fallback_) {
        if (_FALLBACK_ORACLE_MAIN_SOURCE == 1) {
            // 1 = Chainlink ONLY (no fallback)
            exchangeRate_ = _getChainlinkExchangeRate();
        } else if (_FALLBACK_ORACLE_MAIN_SOURCE == 2) {
            // 2 = Chainlink with Redstone Fallback
            exchangeRate_ = _getChainlinkExchangeRate();
            if (exchangeRate_ == 0) {
                fallback_ = true;
                exchangeRate_ = _getRedstoneExchangeRate();
            }
        } else {
            // 3 = Redstone with Chainlink Fallback
            exchangeRate_ = _getRedstoneExchangeRate();
            if (exchangeRate_ == 0) {
                fallback_ = true;
                exchangeRate_ = _getChainlinkExchangeRate();
            }
        }
    }

    /// @dev returns the exchange rate for Chainlink, or Redstone if configured & Chainlink fails.
    function _getChainlinkOrRedstoneAsFallback() internal view returns (uint256 exchangeRate_) {
        exchangeRate_ = _getChainlinkExchangeRate();

        if (exchangeRate_ == 0 && _FALLBACK_ORACLE_MAIN_SOURCE != 1) {
            // Chainlink failed but Redstone is configured too -> try Redstone
            exchangeRate_ = _getRedstoneExchangeRate();
        }
    }
}
