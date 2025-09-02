// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IRLPPrice } from "../interfaces/external/IRLPPrice.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for RLP / USD Oracle.
///
/// @dev RLP price contract; 0xaE2364579D6cB4Bbd6695846C1D595cA9AF3574d
contract FluidRLPCappedRate is FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1e9) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        IRLPPrice.Price memory price_ = IRLPPrice(_RATE_SOURCE).lastPrice();
        return price_.price;
    }
}
