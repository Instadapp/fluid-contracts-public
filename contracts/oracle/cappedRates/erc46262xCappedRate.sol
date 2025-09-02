// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract ERC46262xCappedRateVariables {
    /// @notice external exchange rate source contract 2
    address public immutable RATE_SOURCE2;
    constructor(address rateSource2_) {
        RATE_SOURCE2 = rateSource2_;
    }
}

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for 2 ERC4626 sources, e.g. CSUSDL / USDL rate
///
/// @dev e.g. CSUSDL 0xbEeFc011e94f43b8B7b455eBaB290C7Ab4E216f1 + WUSDL 0x7751e2f4b8ae93ef6b79d86419d42fe3295a4559
contract FluidERC46262xCappedRate is ERC46262xCappedRateVariables, FluidCappedRate {
    constructor(
        FluidCappedRate.CappedRateConstructorParams memory params_,
        address rateSource2_
    ) validAddress(rateSource2_) ERC46262xCappedRateVariables(rateSource2_) FluidCappedRate(params_) {
        if (_RATE_MULTIPLIER != 1) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        return (IERC4626(_RATE_SOURCE).convertToAssets(1e27) * IERC4626(RATE_SOURCE2).convertToAssets(1e27)) / 1e27;
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
