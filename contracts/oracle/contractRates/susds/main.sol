// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidContractRate } from "../../fluidContractRate.sol";

/// @notice This contract stores the rate of USDS for 1 sUSDS in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
/// @dev SUSDS contract; on mainnet 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD
contract SUSDSContractRate is FluidContractRate {
    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) FluidContractRate(infoName_, rateSource_, minUpdateDiffPercent_, minHeartBeat_) {}

    function _getNewRate1e27() internal view virtual override returns (uint256 exchangeRate_) {
        return IERC4626(_RATE_SOURCE).convertToAssets(1e27); // scale to 1e27
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
    /// scenario where all the conditions are met. see IERC4626
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return (_rate * assets) / 1e27;
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
    /// scenario where all the conditions are met. see IERC4626
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return (shares * 1e27) / _rate;
    }
}
