// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";

/// @notice Fluid Vault Factory ERC721 base contract. Implements the ERC721 standard, based on Solmate.
/// In addition, implements ERC721 Enumerable.
/// Modern, minimalist, and gas efficient ERC-721 with Enumerable implementation.
///
/// @author Instadapp
/// @author Modified Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 is Error {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    // token id => token config
    // uint160 0 - 159: address:: owner
    // uint32 160 - 191: uint32:: index
    // uint32 192 - 223: uint32:: vaultId
    // uint32 224 - 255: uint32:: null
    mapping(uint256 => uint256) internal _tokenConfig;

    // owner => slot => index
    /*
    // slot 0: 
    // uint32 0 - 31: uint32:: balanceOf
    // uint224 32 - 255: 7 tokenIds each of uint32 packed
    // slot N (N >= 1)
    // uint32 * 8 each tokenId
    */
    mapping(address => mapping(uint256 => uint256)) internal _ownerConfig;

    /// @notice returns `owner_` of NFT with `id_`
    function ownerOf(uint256 id_) public view virtual returns (address owner_) {
        if ((owner_ = address(uint160(_tokenConfig[id_]))) == address(0))
            revert FluidVaultError(ErrorTypes.ERC721__InvalidParams);
    }

    /// @notice returns total count of NFTs owned by `owner_`
    function balanceOf(address owner_) public view virtual returns (uint256) {
        if (owner_ == address(0)) revert FluidVaultError(ErrorTypes.ERC721__InvalidParams);

        return _ownerConfig[owner_][0] & type(uint32).max;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC721Enumerable STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice total amount of tokens stored by the contract.
    uint256 public totalSupply;

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice trackes if a NFT id is approved for a certain address.
    mapping(uint256 => address) public getApproved;

    /// @notice trackes if all the NFTs of an owner are approved for a certain other address.
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice approves an NFT with `id_` to be spent (transferred) by `spender_`
    function approve(address spender_, uint256 id_) public virtual {
        address owner_ = address(uint160(_tokenConfig[id_]));
        if (!(msg.sender == owner_ || isApprovedForAll[owner_][msg.sender]))
            revert FluidVaultError(ErrorTypes.ERC721__Unauthorized);

        getApproved[id_] = spender_;

        emit Approval(owner_, spender_, id_);
    }

    /// @notice approves all NFTs owned by msg.sender to be spent (transferred) by `operator_`
    function setApprovalForAll(address operator_, bool approved_) public virtual {
        isApprovedForAll[msg.sender][operator_] = approved_;

        emit ApprovalForAll(msg.sender, operator_, approved_);
    }

    /// @notice transfers an NFT with `id_` `from_` address `to_` address without safe check
    function transferFrom(address from_, address to_, uint256 id_) public virtual {
        uint256 tokenConfig_ = _tokenConfig[id_];
        if (from_ != address(uint160(tokenConfig_))) revert FluidVaultError(ErrorTypes.ERC721__InvalidParams);

        if (!(msg.sender == from_ || isApprovedForAll[from_][msg.sender] || msg.sender == getApproved[id_]))
            revert FluidVaultError(ErrorTypes.ERC721__Unauthorized);

        // call _transfer with vaultId extracted from tokenConfig_
        _transfer(from_, to_, id_, (tokenConfig_ >> 192) & type(uint32).max);

        delete getApproved[id_];

        emit Transfer(from_, to_, id_);
    }

    /// @notice transfers an NFT with `id_` `from_` address `to_` address
    function safeTransferFrom(address from_, address to_, uint256 id_) public virtual {
        transferFrom(from_, to_, id_);

        if (
            !(to_.code.length == 0 ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, id_, "") ==
                ERC721TokenReceiver.onERC721Received.selector)
        ) revert FluidVaultError(ErrorTypes.ERC721__UnsafeRecipient);
    }

    /// @notice transfers an NFT with `id_` `from_` address `to_` address, passing `data_` to `onERC721Received` callback
    function safeTransferFrom(address from_, address to_, uint256 id_, bytes calldata data_) public virtual {
        transferFrom(from_, to_, id_);

        if (
            !((to_.code.length == 0) ||
                ERC721TokenReceiver(to_).onERC721Received(msg.sender, from_, id_, data_) ==
                ERC721TokenReceiver.onERC721Received.selector)
        ) revert FluidVaultError(ErrorTypes.ERC721__UnsafeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721Enumerable LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a token ID at a given `index_` of all the tokens stored by the contract.
    /// Use along with {totalSupply} to enumerate all tokens.
    function tokenByIndex(uint256 index_) external view returns (uint256) {
        if (index_ >= totalSupply) {
            revert FluidVaultError(ErrorTypes.ERC721__OutOfBoundsIndex);
        }
        return index_ + 1;
    }

    /// @notice Returns a token ID owned by `owner_` at a given `index_` of its token list.
    /// Use along with {balanceOf} to enumerate all of `owner_`'s tokens.
    function tokenOfOwnerByIndex(address owner_, uint256 index_) external view returns (uint256) {
        if (index_ >= balanceOf(owner_)) {
            revert FluidVaultError(ErrorTypes.ERC721__OutOfBoundsIndex);
        }

        index_ = index_ + 1;
        return (_ownerConfig[owner_][index_ / 8] >> ((index_ % 8) * 32)) & type(uint32).max;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId_) public view virtual returns (bool) {
        return
            interfaceId_ == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId_ == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId_ == 0x5b5e139f || // ERC165 Interface ID for ERC721Metadata
            interfaceId_ == 0x780e9d63; // ERC165 Interface ID for ERC721Enumberable
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from_, address to_, uint256 id_, uint256 vaultId_) internal {
        if (to_ == address(0)) {
            revert FluidVaultError(ErrorTypes.ERC721__InvalidOperation);
        } else if (from_ == address(0)) {
            _add(to_, id_, vaultId_);
        } else if (to_ != from_) {
            _remove(from_, id_);
            _add(to_, id_, vaultId_);
        }
    }

    function _add(address user_, uint256 id_, uint256 vaultId_) private {
        uint256 ownerConfig_ = _ownerConfig[user_][0];
        unchecked {
            // index starts from `1`
            uint256 balanceOf_ = (ownerConfig_ & type(uint32).max) + 1;

            _tokenConfig[id_] = (uint160(user_) | (balanceOf_ << 160) | (vaultId_ << 192));

            _ownerConfig[user_][0] = (ownerConfig_ & ~uint256(type(uint32).max)) | (balanceOf_);

            uint256 wordIndex_ = (balanceOf_ / 8);
            _ownerConfig[user_][wordIndex_] = _ownerConfig[user_][wordIndex_] | (id_ << ((balanceOf_ % 8) * 32));
        }
    }

    function _remove(address user_, uint256 id_) private {
        uint256 temp_ = _tokenConfig[id_];

        // fetching `id_` details and deleting it.
        uint256 tokenIndex_ = (temp_ >> 160) & type(uint32).max;
        _tokenConfig[id_] = 0;

        // fetching & updating balance
        temp_ = _ownerConfig[user_][0];
        uint256 lastTokenIndex_ = (temp_ & type(uint32).max); // (lastTokenIndex_ = balanceOf)
        _ownerConfig[user_][0] = (temp_ & ~uint256(type(uint32).max)) | (lastTokenIndex_ - 1);

        {
            unchecked {
                uint256 lastTokenWordIndex_ = (lastTokenIndex_ / 8);
                uint256 lastTokenBitShift_ = (lastTokenIndex_ % 8) * 32;
                temp_ = _ownerConfig[user_][lastTokenWordIndex_];

                // replace `id_` tokenId with `last` tokenId.
                if (lastTokenIndex_ != tokenIndex_) {
                    uint256 wordIndex_ = (tokenIndex_ / 8);
                    uint256 bitShift_ = (tokenIndex_ % 8) * 32;

                    // temp_ here is _ownerConfig[user_][lastTokenWordIndex_];
                    uint256 lastTokenId_ = uint256((temp_ >> lastTokenBitShift_) & type(uint32).max);
                    if (wordIndex_ == lastTokenWordIndex_) {
                        // this case, when lastToken and currentToken are in same slot.
                        // updating temp_ as we will remove the lastToken from this slot itself
                        temp_ = (temp_ & ~(uint256(type(uint32).max) << bitShift_)) | (lastTokenId_ << bitShift_);
                    } else {
                        _ownerConfig[user_][wordIndex_] =
                            (_ownerConfig[user_][wordIndex_] & ~(uint256(type(uint32).max) << bitShift_)) |
                            (lastTokenId_ << bitShift_);
                    }
                    _tokenConfig[lastTokenId_] =
                        (_tokenConfig[lastTokenId_] & ~(uint256(type(uint32).max) << 160)) |
                        (tokenIndex_ << 160);
                }

                // temp_ here is _ownerConfig[user_][lastTokenWordIndex_];
                _ownerConfig[user_][lastTokenWordIndex_] = temp_ & ~(uint256(type(uint32).max) << lastTokenBitShift_);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to_, uint256 vaultId_) internal virtual returns (uint256 id_) {

        unchecked {
            ++totalSupply;
        }

        id_ = totalSupply;
        if (id_ >= type(uint32).max || _tokenConfig[id_] != 0) revert FluidVaultError(ErrorTypes.ERC721__InvalidParams);

        _transfer(address(0), to_, id_, vaultId_);

        emit Transfer(address(0), to_, id_);
    }
}

abstract contract ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
