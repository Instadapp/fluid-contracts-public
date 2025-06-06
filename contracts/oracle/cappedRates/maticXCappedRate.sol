// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IMaticXChildPool } from "../interfaces/external/IMaticXChildPool.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for MATICX / MATIC Oracle.
///
/// @dev MaticX Child pool contract on Polygon 0xfd225c9e6601c9d38d8f98d8731bf59efcf8c0e3
contract FluidMaticXCappedRate is FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        (exchangeRate_, , ) = IMaticXChildPool(_RATE_SOURCE).convertMaticXToMatic(1e27);
    }
}
