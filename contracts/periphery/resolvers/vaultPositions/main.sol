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
    error FluidVaultPositionsResolver__InvalidParams();

    uint internal constant PAGE_SIZE = 3000;

    /// @notice constructor sets the immutable vault factory address
    /// @param vaultFactory_ The FluidVaultFactory contract address
    constructor(IFluidVaultFactory vaultFactory_) Variables(vaultFactory_) {
        if (address(vaultFactory_) == address(0)) {
            revert FluidVaultPositionsResolver__AddressZero();
        }
    }

    /// @notice Returns the NFT token IDs for a given vault using a paged approach, reading 3000 nfts per page.
    /// @dev Use this method on chains where retrieving all token IDs at once may run out of gas.
    ///      Call this repeatedly with increasing page numbers until hasNextPage is false, then use `getVaultPositionsForNftIds`.
    /// @param vault_ The address of the vault.
    /// @param page_ The current page to fetch (pagination index). start with page 0.
    /// @return nftIds_ Array of NFT token IDs for the specified page.
    /// @return hasNextPage_ True if there are more pages to fetch, false if this is the last page.
    function getAllVaultNftIdsPaged(
        address vault_,
        uint256 page_
    ) public view returns (uint256[] memory nftIds_, bool hasNextPage_) {
        uint256 totalPositions_ = FACTORY.totalSupply();

        uint256 startIndex_ = page_ * PAGE_SIZE;
        uint256 endIndex_ = startIndex_ + PAGE_SIZE;
        if (endIndex_ > totalPositions_) {
            endIndex_ = totalPositions_;
            hasNextPage_ = false;
        } else {
            hasNextPage_ = true;
        }

        uint256[] memory tempNftIds_ = new uint256[](endIndex_ - startIndex_);
        uint256 nftId_;
        uint256 j;
        for (uint256 i = startIndex_; i < endIndex_; ) {
            nftId_ = _tokenByIndex(i);
            unchecked {
                ++i;
            }
            if (_vaultByNftId(nftId_) == vault_) {
                tempNftIds_[j] = nftId_;
                unchecked {
                    ++j;
                }
            }
        }

        // adjust the array length based on how many were actually found
        nftIds_ = new uint256[](j);
        for (uint256 k; k < j; ++k) {
            nftIds_[k] = tempNftIds_[k];
        }
    }

    /// @notice Returns all NFT token IDs for the specified vault. Use `getAllVaultNftIdsPaged` if this runs out of gas!
    /// @param vault_ The address of the vault.
    /// @return nftIds_ Array of NFT token IDs belonging to the vault.
    function getAllVaultNftIds(address vault_) public view returns (uint256[] memory nftIds_) {
        uint256 totalPositions_ = FACTORY.totalSupply();

        /// get total positions for vault: Next 32 bits => 210-241 => Total positions
        uint256 totalVaultPositions_ = (_getVaultVariablesRaw(vault_) >> 210) & 0xFFFFFFFF;
        nftIds_ = new uint256[](totalVaultPositions_);

        // get nft Ids belonging to the vault_
        uint256 nftId_;
        uint256 j;
        for (uint256 i; i < totalPositions_; ) {
            nftId_ = _tokenByIndex(i);
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

    /// @notice Gets user positions for NFT IDs assumed to belong to a specific vault.
    /// @param nftIds_ Array of NFT IDs. Split reading into chunks if this runs out of gas!
    /// @param vault_ The address of the vault.
    /// @return positions_ Array of UserPosition for the NFT IDs.
    function getVaultPositionsForNftIds(
        uint256[] memory nftIds_,
        address vault_
    ) public view returns (UserPosition[] memory positions_) {
        if (vault_ == address(0)) {
            revert FluidVaultPositionsResolver__InvalidParams();
        }
        positions_ = new UserPosition[](nftIds_.length);

        // exchange prices are always the same for the same vault
        (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_).updateExchangePrices(
            _getVaultVariables2Raw(vault_)
        );

        address vaultCheck_;
        address nftOwner_;
        for (uint256 i; i < nftIds_.length; ++i) {
            (vaultCheck_, nftOwner_) = _vaultAndOwnerByNftId(nftIds_[i]);
            if (vault_ != vaultCheck_) {
                revert FluidVaultPositionsResolver__InvalidParams();
            }
            positions_[i] = _getVaultPosition(
                vault_,
                nftIds_[i],
                vaultSupplyExchangePrice_,
                vaultBorrowExchangePrice_,
                nftOwner_
            );
        }
    }

    /// @notice Gets user positions for a set of NFT IDs.
    /// @param nftIds_ Array of NFT IDs. Split reading into chunks if this runs out of gas!
    /// @return positions_ Array of UserPosition for each NFT ID.
    function getPositionsForNftIds(uint256[] memory nftIds_) public view returns (UserPosition[] memory positions_) {
        positions_ = new UserPosition[](nftIds_.length);

        address vault_;
        address nftOwner_;
        for (uint256 i; i < nftIds_.length; ++i) {
            (vault_, nftOwner_) = _vaultAndOwnerByNftId(nftIds_[i]);
            if (vault_ == address(0)) {
                // should never happen but make sure it wouldn't lead to a revert
                positions_[i] = UserPosition({ nftId: nftIds_[i], owner: address(0), supply: 0, borrow: 0 });
            } else {
                (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_)
                    .updateExchangePrices(_getVaultVariables2Raw(vault_));

                positions_[i] = _getVaultPosition(
                    vault_,
                    nftIds_[i],
                    vaultSupplyExchangePrice_,
                    vaultBorrowExchangePrice_,
                    nftOwner_
                );
            }
        }
    }

    /// @notice Gets all positions for the given vault. Use `getAllVaultNftIds` first if this runs out of gas!
    /// @param vault_ The address of the vault.
    /// @return positions_ Array of UserPosition for each position in the vault.
    function getAllVaultPositions(address vault_) public view returns (UserPosition[] memory positions_) {
        if (vault_ == address(0)) {
            revert FluidVaultPositionsResolver__InvalidParams();
        }
        // exchange prices are always the same for the same vault
        (, , uint vaultSupplyExchangePrice_, uint vaultBorrowExchangePrice_) = IFluidVault(vault_).updateExchangePrices(
            _getVaultVariables2Raw(vault_)
        );

        uint256 totalPositions_ = FACTORY.totalSupply();

        // get total positions for vault: Next 32 bits => 210-241 => Total positions
        uint256 totalVaultPositions_ = (_getVaultVariablesRaw(vault_) >> 210) & 0xFFFFFFFF;
        positions_ = new UserPosition[](totalVaultPositions_);

        uint256 nftId_;
        uint256 j;
        address vaultCheck_;
        address nftOwner_;
        for (uint256 i; i < totalPositions_; ) {
            nftId_ = _tokenByIndex(i);
            unchecked {
                ++i;
            }

            (vaultCheck_, nftOwner_) = _vaultAndOwnerByNftId(nftId_);
            if (vaultCheck_ == vault_) {
                positions_[j] = _getVaultPosition(
                    vault_,
                    nftId_,
                    vaultSupplyExchangePrice_,
                    vaultBorrowExchangePrice_,
                    nftOwner_
                );

                unchecked {
                    ++j;
                }
            }
        }
    }

    /// @notice Get the raw variables of a vault.
    /// @param vault_ The address of the vault.
    /// @return The raw variables of the vault.
    function _getVaultVariablesRaw(address vault_) internal view returns (uint) {
        return IFluidVault(vault_).readFromStorage(bytes32(uint256(0)));
    }

    /// @notice Get the raw variables of a vault (slot 1).
    /// @param vault_ The address of the vault.
    /// @return The raw variables of the vault (slot 1).
    function _getVaultVariables2Raw(address vault_) internal view returns (uint) {
        return IFluidVault(vault_).readFromStorage(bytes32(uint256(1)));
    }

    /// @notice Calculates the storage slot for a mapping.
    /// @param slot_ The slot index.
    /// @param key_ The mapping key.
    /// @return The calculated storage slot.
    function _calculateStorageSlotUintMapping(uint256 slot_, uint key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Liquidity contract for single mapping
    function _calculateStorageSlotIntMapping(uint256 slot_, int key_) public pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Get the position data of a vault.
    /// @param vault_ The address of the vault.
    /// @param positionId_ The ID of the position.
    /// @return The position data of the vault.
    function _getPositionDataRaw(address vault_, uint positionId_) internal view returns (uint) {
        return IFluidVault(vault_).readFromStorage(_calculateStorageSlotUintMapping(3, positionId_));
    }

    /// @notice Get the raw tick data of a vault.
    /// @param vault_ The address of the vault.
    /// @param tick_ The tick value.
    /// @return The raw tick data of the vault.
    // if tick > 0 then key_ = tick / 256
    // if tick < 0 then key_ = (tick / 256) - 1
    function _getTickDataRaw(address vault_, int tick_) internal view returns (uint) {
        return IFluidVault(vault_).readFromStorage(_calculateStorageSlotIntMapping(5, tick_));
    }

    /// @notice Returns a token ID at a given index.
    /// @param index_ The index to fetch.
    /// @return The tokenId at the given index.
    function _tokenByIndex(uint256 index_) internal pure returns (uint256) {
        return index_ + 1;
    }

    /// @notice Computes the address of a vault based on its given ID.
    /// @param vaultId_ The ID of the vault.
    /// @return vault_ The computed vault address.
    function _getVaultAddress(uint256 vaultId_) internal view returns (address vault_) {
        // @dev based on https://ethereum.stackexchange.com/a/61413

        // nonce of smart contract always starts with 1. so, with nonce 0 there won't be any deployment
        // hence, nonce of vault deployment starts with 1.
        bytes memory data;
        if (vaultId_ == 0x00) {
            return address(0);
        } else if (vaultId_ <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(FACTORY), uint8(vaultId_));
        } else if (vaultId_ <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), address(FACTORY), bytes1(0x81), uint8(vaultId_));
        } else if (vaultId_ <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), address(FACTORY), bytes1(0x82), uint16(vaultId_));
        } else if (vaultId_ <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), address(FACTORY), bytes1(0x83), uint24(vaultId_));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), address(FACTORY), bytes1(0x84), uint32(vaultId_));
        }

        return address(uint160(uint256(keccak256(data))));
    }

    /// @notice Returns the vault address for a given NFT ID.
    /// @param nftId_ The NFT ID.
    /// @return vault_ The vault address associated with the NFT ID.
    function _vaultByNftId(uint nftId_) internal view returns (address vault_) {
        uint tokenConfig_ = FACTORY.readFromStorage(keccak256(abi.encode(nftId_, 3)));
        vault_ = _getVaultAddress((tokenConfig_ >> 192) & X32);
    }

    /// @notice Returns the vault address and NFT owner for a given NFT ID.
    /// @param nftId_ The NFT ID.
    /// @return vault_ The vault address.
    /// @return nftOwner_ The NFT owner address.
    function _vaultAndOwnerByNftId(uint nftId_) internal view returns (address vault_, address nftOwner_) {
        uint tokenConfig_ = FACTORY.readFromStorage(keccak256(abi.encode(nftId_, 3)));
        vault_ = _getVaultAddress((tokenConfig_ >> 192) & X32);
        nftOwner_ = address(uint160(tokenConfig_));
    }

    /// @notice Gets the vault position for a given vault, NFT, and exchange prices.
    /// @param vault_ The vault address.
    /// @param nftId_ The NFT ID.
    /// @param vaultSupplyExchangePrice_ The vault supply exchange price.
    /// @param vaultBorrowExchangePrice_ The vault borrow exchange price.
    /// @param nftOwner_ The NFT owner.
    /// @return userPosition_ The UserPosition struct with the decoded position.
    function _getVaultPosition(
        address vault_,
        uint nftId_,
        uint vaultSupplyExchangePrice_,
        uint vaultBorrowExchangePrice_,
        address nftOwner_
    ) internal view returns (UserPosition memory userPosition_) {
        // @dev code below based on VaultResolver `positionByNftId()`
        userPosition_.nftId = nftId_;
        userPosition_.owner = nftOwner_;

        uint positionData_ = _getPositionDataRaw(vault_, nftId_);

        userPosition_.supply = (positionData_ >> 45) & X64;
        // Converting big number into normal number
        userPosition_.supply = (userPosition_.supply >> 8) << (userPosition_.supply & X8);

        if ((positionData_ & 1) != 1) {
            // not just a supply position

            int tick_ = (positionData_ & 2) == 2 ? int((positionData_ >> 2) & X19) : -int((positionData_ >> 2) & X19);
            userPosition_.borrow = (TickMath.getRatioAtTick(int24(tick_)) * userPosition_.supply) >> 96;

            uint tickData_ = _getTickDataRaw(vault_, tick_);
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
                unchecked {
                    userPosition_.borrow = userPosition_.borrow - dustBorrow_;
                }
            } else {
                userPosition_.borrow = 0;
            }

            userPosition_.borrow = (userPosition_.borrow * vaultBorrowExchangePrice_) / 1e12;
        }

        userPosition_.supply = (userPosition_.supply * vaultSupplyExchangePrice_) / 1e12;
    }
}
