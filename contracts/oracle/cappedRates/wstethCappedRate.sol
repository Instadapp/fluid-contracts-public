// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWstETH } from "../interfaces/external/IWstETH.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for WSTETH / ETH contract.
///
/// @dev WSTETH contract; on mainnet 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
contract FluidWSTETHCappedRate is IWstETH, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1e9) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IWstETH(_RATE_SOURCE).stEthPerToken();
    }

    /// @inheritdoc IWstETH
    function stEthPerToken() external view override returns (uint256) {
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e18
    }

    /// @inheritdoc IWstETH
    function tokensPerStEth() external view override returns (uint256) {
        return 1e45 / uint256(_slot0.rate); // scale to 1e18
    }
}
