//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IFluidVaultFactory is IERC721Enumerable {
    /// @notice Minting an NFT Vault for the user
    function mint(uint256 vaultId_, address user_) external returns (uint256 tokenId_);

    /// @notice returns owner of Vault which is also an NFT
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @notice Global auth is auth for all vaults
    function isGlobalAuth(address auth_) external view returns (bool);

    /// @notice Vault auth is auth for a specific vault
    function isVaultAuth(address vault_, address auth_) external view returns (bool);

    /// @notice Total vaults deployed.
    function totalVaults() external view returns (uint256);

    /// @notice Compute vaultAddress
    function getVaultAddress(uint256 vaultId) external view returns (address);

    /// @notice read uint256 `result_` for a storage `slot_` key
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}
