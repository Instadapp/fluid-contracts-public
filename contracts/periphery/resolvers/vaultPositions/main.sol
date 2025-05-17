// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidVaultResolver } from "../vault/iVaultResolver.sol";
import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";
import { TickMath } from "../../../libraries/tickMath.sol";

/// @title Fluid Vault protocol Positions Resolver for all vault types.
/// @notice This contract resolves positions for Fluid Vaults, providing functionality to retrieve NFT IDs and positions for a given vault.
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
        for (uint256 i; i < totalPositions_; ) {
            nftId_ = FACTORY.tokenByIndex(i);
            unchecked {
                ++i;
            }
            if (_vaultByNftId(nftId_) == vault_) {
                nftIds_[j] = nftId_;

                unchecked {
                    ++j;
                }
            }
        }
    }

    function getPositionsForNftIds(uint256[] memory nftIds_) public view returns (UserPosition[] memory positions_) {
        positions_ = new UserPosition[](nftIds_.length);

        for (uint256 i; i < nftIds_.length; ++i) {
            address vault_ = _vaultByNftId(nftIds_[i]);
            if (vault_ == address(0)) {
                // should never happen but make sure it wouldn't lead to a revert
                positions_[i] = UserPosition({ nftId: nftIds_[i], owner: address(0), supply: 0, borrow: 0 });
            } else {
                (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_)
                    .updateExchangePrices(VAULT_RESOLVER.getVaultVariables2Raw(vault_));

                positions_[i] = _getVaultPosition(
                    vault_,
                    nftIds_[i],
                    vaultSupplyExchangePrice_,
                    vaultBorrowExchangePrice_
                );
            }
        }
    }

    function getAllVaultPositions(address vault_) public view returns (UserPosition[] memory positions_) {
        if (vault_ != address(0)) {
            // exchange prices are always the same for the same vault
            (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_)
                .updateExchangePrices(VAULT_RESOLVER.getVaultVariables2Raw(vault_));

            uint256 totalPositions_ = FACTORY.totalSupply();

            // get total positions for vault: Next 32 bits => 210-241 => Total positions
            uint256 totalVaultPositions_ = (VAULT_RESOLVER.getVaultVariablesRaw(vault_) >> 210) & 0xFFFFFFFF;
            positions_ = new UserPosition[](totalVaultPositions_);

            uint256 nftId_;
            uint256 j;
            for (uint256 i; i < totalPositions_; ) {
                nftId_ = FACTORY.tokenByIndex(i);
                unchecked {
                    ++i;
                }

                if (_vaultByNftId(nftId_) == vault_) {
                    positions_[j] = _getVaultPosition(
                        vault_,
                        nftId_,
                        vaultSupplyExchangePrice_,
                        vaultBorrowExchangePrice_
                    );

                    unchecked {
                        ++j;
                    }
                }
            }
        }
    }

    function _vaultByNftId(uint nftId_) internal view returns (address vault_) {
        uint tokenConfig_ = FACTORY.readFromStorage(keccak256(abi.encode(nftId_, 3)));
        vault_ = FACTORY.getVaultAddress((tokenConfig_ >> 192) & X32);
    }

    function _getVaultPosition(
        address vault_,
        uint nftId_,
        uint vaultSupplyExchangePrice_,
        uint vaultBorrowExchangePrice_
    ) internal view returns (UserPosition memory userPosition_) {
        // @dev code below based on VaultResolver `positionByNftId()`
        userPosition_.nftId = nftId_;
        userPosition_.owner = FACTORY.ownerOf(nftId_);

        uint positionData_ = VAULT_RESOLVER.getPositionDataRaw(vault_, nftId_);

        userPosition_.supply = (positionData_ >> 45) & X64;
        // Converting big number into normal number
        userPosition_.supply = (userPosition_.supply >> 8) << (userPosition_.supply & X8);

        if ((positionData_ & 1) != 1) {
            // not just a supply position

            int tick_ = (positionData_ & 2) == 2 ? int((positionData_ >> 2) & X19) : -int((positionData_ >> 2) & X19);
            userPosition_.borrow = (TickMath.getRatioAtTick(int24(tick_)) * userPosition_.supply) >> 96;

            uint tickData_ = VAULT_RESOLVER.getTickDataRaw(vault_, tick_);
            uint tickId_ = (positionData_ >> 21) & X24;
            if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId_)) {
                (tick_, userPosition_.borrow, userPosition_.supply, , ) = IFluidVault(vault_).fetchLatestPosition(
                    tick_,
                    tickId_,
                    userPosition_.borrow,
                    tickData_
                );
            }

            uint dustBorrow_ = (positionData_ >> 109) & X64;
            // Converting big number into normal number
            dustBorrow_ = (dustBorrow_ >> 8) << (dustBorrow_ & X8);

            if (userPosition_.borrow > dustBorrow_) {
                userPosition_.borrow = userPosition_.borrow - dustBorrow_;
            } else {
                userPosition_.borrow = 0;
            }

            userPosition_.borrow = (userPosition_.borrow * vaultBorrowExchangePrice_) / 1e12;
        }

        userPosition_.supply = (userPosition_.supply * vaultSupplyExchangePrice_) / 1e12;
    }
}
