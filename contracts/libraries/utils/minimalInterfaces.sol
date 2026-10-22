// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @notice Minimal shared probe interfaces used across resolvers / oracles / config.
///         Prefer importing from here instead of redefining one-selector interfaces per file.

/// @dev Slot reader present on Liquidity, vaults, DEX pools, factories, etc.
interface IFluidStorageReadable {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

/// @dev Hard-coded access type on permissioned-stack protocols (`FluidAccessType.PUBLIC` / `PERMISSIONED`).
///      Missing on production contracts — callers should try/catch and default to public (`0`).
interface IFluidAccessTypeView {
    function ACCESS_TYPE() external view returns (uint8);
}

/// @dev Factory / protocol deployment name on the permissioned stack.
///      Missing on production factories — callers should try/catch and default to `""`.
interface IFluidDeploymentNameView {
    function deploymentName() external view returns (string memory);
}
