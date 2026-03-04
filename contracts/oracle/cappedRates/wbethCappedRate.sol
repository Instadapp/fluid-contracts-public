// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWBETHOracle } from "../interfaces/external/IWBETHOracle.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for WBETH / ETH Oracle.
contract FluidWBETHCappedRate is IWBETHOracle, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1e9) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IWBETHOracle(_RATE_SOURCE).exchangeRate();
    }

    /// @inheritdoc IWBETHOracle
    function exchangeRate() external view override returns (uint256) {
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e18
    }
}
