// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a ERC4626 source, e.g. SUSDE / USDE rate.
///
/// @dev e.g. SUSDE contract; on mainnet 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497
/// @dev e.g. SUSDS contract; on mainnet 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD
contract FluidERC4626CappedRate is FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return IERC4626(_RATE_SOURCE).convertToAssets(1e27);
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
    /// scenario where all the conditions are met. see IERC4626
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return (uint256(_slot0.rate) * assets) / 1e27;
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
    /// scenario where all the conditions are met. see IERC4626
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return (shares * 1e27) / uint256(_slot0.rate);
    }
}
