// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IReSharePrice } from "../../interfaces/external/IReSharePrice.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for REUSD (Re Protocol).
/// @dev Rate source: Re Protocol Share Price Calculator, getSharePrice() returns 1e18 scale.
contract FluidREUSDCappedRate is FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1e9) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IReSharePrice(_RATE_SOURCE).getSharePrice();
    }
}
