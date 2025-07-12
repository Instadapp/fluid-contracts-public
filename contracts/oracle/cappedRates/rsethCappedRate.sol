// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IRsETHLRTOracle } from "../interfaces/external/IRsETHLRTOracle.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for RSETH / ETH LRT Oracle.
///
/// @dev RSETH LRT oracle contract; 0x349A73444b1a310BAe67ef67973022020d70020d
contract FluidRSETHCappedRate is IRsETHLRTOracle, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1e9) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IRsETHLRTOracle(_RATE_SOURCE).rsETHPrice();
    }

    /// @inheritdoc IRsETHLRTOracle
    function rsETHPrice() external view override returns (uint256) {
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e18
    }
}
