// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { ChainlinkOracleImpl } from "../implementations/chainlinkOracleImpl.sol";
import { UniV3OracleImpl } from "../implementations/uniV3OracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title   Chainlink with Fallback to UniV3 Oracle
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a Chainlink price feed or, if that feed fails, the price from a UniV3 TWAP delta checked Oracle.
contract CLFallbackUniV3Oracle is FluidOracle, ChainlinkOracleImpl, UniV3OracleImpl {
    /// @notice                  sets the Chainlink and UniV3 Oracle configs.
    /// @param infoName_         Oracle identify helper name.
    /// @param chainlinkParams_  ChainlinkOracle constructor params struct.
    /// @param uniV3Params_      UniV3Oracle constructor params struct.
    constructor(
        string memory infoName_,
        ChainlinkConstructorParams memory chainlinkParams_,
        UniV3ConstructorParams memory uniV3Params_
    ) ChainlinkOracleImpl(chainlinkParams_) UniV3OracleImpl(uniV3Params_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getChainlinkExchangeRate();
        if (exchangeRate_ == 0) {
            // if Chainlink fails, use UniV3 rate (TWAP checked)
            exchangeRate_ = _getUniV3ExchangeRate();

            if (exchangeRate_ == 0) {
                revert FluidOracleError(ErrorTypes.CLFallbackUniV3Oracle__ExchangeRateZero);
            }
        }
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getChainlinkExchangeRate();
        if (exchangeRate_ == 0) {
            // if Chainlink fails, use UniV3 rate (TWAP checked)
            exchangeRate_ = _getUniV3ExchangeRate();

            if (exchangeRate_ == 0) {
                revert FluidOracleError(ErrorTypes.CLFallbackUniV3Oracle__ExchangeRateZero);
            }
        }
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
