// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETH } from "../interfaces/external/IWeETH.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for WEETH / ETH contract.
///
/// @dev WEETH contract; on mainnet 0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee
contract FluidWEETHCappedRate is IWeETH, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IWeETH(_RATE_SOURCE).getEETHByWeETH(1e27);
    }

    /// @inheritdoc IWeETH
    function getEETHByWeETH(uint256 _weETHAmount) external view override returns (uint256) {
        return (uint256(_slot0.rate) * _weETHAmount) / 1e27;
    }

    /// @inheritdoc IWeETH
    function getWeETHByeETH(uint256 _eETHAmount) external view override returns (uint256) {
        return (1e27 * _eETHAmount) / uint256(_slot0.rate);
    }
}
