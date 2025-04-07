// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidDexFactory {
    /// @notice Global auth is auth for all dexes
    function isGlobalAuth(address auth_) external view returns (bool);

    /// @notice Dex auth is auth for a specific dex
    function isDexAuth(address vault_, address auth_) external view returns (bool);

    /// @notice Total dexes deployed.
    function totalDexes() external view returns (uint256);

    /// @notice Compute dexAddress
    function getDexAddress(uint256 dexId_) external view returns (address);

    /// @notice read uint256 `result_` for a storage `slot_` key
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}
