// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Backed wrapped xStock V2 (ERC-4626-style).
interface IBackedWrapper {
    function convertToAssets(uint256 shares_) external view returns (uint256 assets_);

    function asset() external view returns (address);
}
