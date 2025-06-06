// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidCappedRateL2 } from "../fluidCappedRateL2.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a ERC4626 source, e.g. SUSDE / USDE rate.
/// for L2 with sequencer uptime feed.
contract FluidERC4626CappedRateL2 is FluidCappedRateL2 {
    constructor(
        FluidCappedRateL2.CappedRateConstructorParams memory params_,
        address sequencerUptimeFeed_
    ) FluidCappedRateL2(params_, sequencerUptimeFeed_) {
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
