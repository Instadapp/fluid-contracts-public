// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";
import { Structs as VaultResolverStructs } from "../vault/structs.sol";
import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";

contract FluidVaultPositionsResolver is Variables, Structs {
    /// @notice thrown if an input param address is zero
    error FluidVaultPositionsResolver__AddressZero();

    /// @notice constructor sets the immutable vault resolver and vault factory address
    constructor(
        IFluidVaultResolver vaultResolver_,
        IFluidVaultFactory vaultFactory_
    ) Variables(vaultResolver_, vaultFactory_) {
        if (address(vaultResolver_) == address(0) || address(vaultFactory_) == address(0)) {
            revert FluidVaultPositionsResolver__AddressZero();
        }
    }

    function getAllVaultNftIds(address vault_) public view returns (uint256[] memory nftIds_) {
        uint256 totalPositions_ = FACTORY.totalSupply();

        /// get total positions for vault: Next 32 bits => 210-241 => Total positions
        uint256 totalVaultPositions_ = (VAULT_RESOLVER.getVaultVariablesRaw(vault_) >> 210) & 0xFFFFFFFF;
        nftIds_ = new uint256[](totalVaultPositions_);

        // get nft Ids belonging to the vault_
        uint256 nftId_;
        uint256 j;
        for (uint256 i; i < totalPositions_; ++i) {
            nftId_ = FACTORY.tokenByIndex(i);
            if (VAULT_RESOLVER.vaultByNftId(nftId_) != vault_) {
                continue;
            }
            nftIds_[j] = nftId_;
            ++j;
        }
    }

    function getPositionsForNftIds(uint256[] memory nftIds_) public view returns (UserPosition[] memory positions_) {
        positions_ = new UserPosition[](nftIds_.length);

        VaultResolverStructs.UserPosition memory userPosition_;
        for (uint256 i; i < nftIds_.length; ++i) {
            (userPosition_, ) = VAULT_RESOLVER.positionByNftId(nftIds_[i]);

            positions_[i].nftId = nftIds_[i];
            positions_[i].owner = userPosition_.owner;
            positions_[i].supply = userPosition_.supply;
            positions_[i].borrow = userPosition_.borrow;
        }
    }

    function getAllVaultPositions(address vault_) public view returns (UserPosition[] memory positions_) {
        return getPositionsForNftIds(getAllVaultNftIds(vault_));
    }
}
