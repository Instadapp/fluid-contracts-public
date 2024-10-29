// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";
import { ERC721 } from "./ERC721/ERC721.sol";
import { ErrorTypes } from "../errorTypes.sol";

import { StorageRead } from "../../../libraries/storageRead.sol";

abstract contract VaultFactoryVariables is Owned, ERC721, StorageRead {
    /// @dev ERC721 tokens name
    string internal constant ERC721_NAME = "Fluid Vault";
    /// @dev ERC721 tokens symbol
    string internal constant ERC721_SYMBOL = "fVLT";

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // ------------ storage variables from inherited contracts (Owned and ERC721) come before vars here --------

    // ----------------------- slot 0 ---------------------------
    // address public owner; // from Owned

    // 12 bytes empty

    // ----------------------- slot 1 ---------------------------
    // string public name;

    // ----------------------- slot 2 ---------------------------
    // string public symbol;

    // ----------------------- slot 3 ---------------------------
    // mapping(uint256 => uint256) internal _tokenConfig;

    // ----------------------- slot 4 ---------------------------
    // mapping(address => mapping(uint256 => uint256)) internal _ownerConfig;

    // ----------------------- slot 5 ---------------------------
    // uint256 public totalSupply;

    // ----------------------- slot 6 ---------------------------
    // mapping(uint256 => address) public getApproved;

    // ----------------------- slot 7  ---------------------------
    // mapping(address => mapping(address => bool)) public isApprovedForAll;

    // ----------------------- slot 8  ---------------------------
    /// @dev deployer can deploy new Vault contract
    /// owner can add/remove deployer.
    /// Owner is deployer by default.
    mapping(address => bool) internal _deployers;

    // ----------------------- slot 9  ---------------------------
    /// @dev global auths can update any vault config.
    /// owner can add/remove global auths.
    /// Owner is global auth by default.
    mapping(address => bool) internal _globalAuths;

    // ----------------------- slot 10  ---------------------------
    /// @dev vault auths can update specific vault config.
    /// owner can add/remove vault auths.
    /// Owner is vault auth by default.
    /// vault => auth => add/remove
    mapping(address => mapping(address => bool)) internal _vaultAuths;

    // ----------------------- slot 11 ---------------------------
    /// @dev total no of vaults deployed by the factory
    /// only addresses that have deployer role or owner can deploy new vault.
    uint256 internal _totalVaults;

    // ----------------------- slot 12 ---------------------------
    /// @dev vault deployment logics for deploying vault
    /// These logic contracts hold the deployment logics of specific vaults and are called via .delegatecall inside deployVault().
    /// only addresses that have owner can add/remove new vault deployment logic.
    mapping(address => bool) internal _vaultDeploymentLogics;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address owner_) Owned(owner_) ERC721(ERC721_NAME, ERC721_SYMBOL) {}
}

abstract contract VaultFactoryEvents {
    /// @dev Emitted when a new vault is deployed.
    /// @param vault The address of the newly deployed vault.
    /// @param vaultId The id of the newly deployed vault.
    event VaultDeployed(address indexed vault, uint256 indexed vaultId);

    /// @dev Emitted when a new token/position is minted by a vault.
    /// @param vault The address of the vault that minted the token.
    /// @param user The address of the user who received the minted token.
    /// @param tokenId The ID of the newly minted token.
    event NewPositionMinted(address indexed vault, address indexed user, uint256 indexed tokenId);

    /// @dev Emitted when the deployer is modified by owner.
    /// @param deployer Address whose deployer status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    event LogSetDeployer(address indexed deployer, bool indexed allowed);

    /// @dev Emitted when the globalAuth is modified by owner.
    /// @param globalAuth Address whose globalAuth status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    event LogSetGlobalAuth(address indexed globalAuth, bool indexed allowed);

    /// @dev Emitted when the vaultAuth is modified by owner.
    /// @param vaultAuth Address whose vaultAuth status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    /// @param vault Address of the specific vault related to the authorization change.
    event LogSetVaultAuth(address indexed vaultAuth, bool indexed allowed, address indexed vault);

    /// @dev Emitted when the vault deployment logic is modified by owner.
    /// @param vaultDeploymentLogic The address of the vault deployment logic contract.
    /// @param allowed  Indicates whether the address is authorized as a deployer or not.
    event LogSetVaultDeploymentLogic(address indexed vaultDeploymentLogic, bool indexed allowed);
}

abstract contract VaultFactoryCore is VaultFactoryVariables, VaultFactoryEvents {
    constructor(address owner_) validAddress(owner_) VaultFactoryVariables(owner_) {}

    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactory__InvalidParams);
        }
        _;
    }
}

/// @dev Implements Vault Factory auth-only callable methods. Owner / auths can set various config values and
/// can define the allow-listed deployers.
abstract contract VaultFactoryAuth is VaultFactoryCore {
    /// @notice                         Sets an address (`deployer_`) as allowed deployer or not.
    ///                                 This function can only be called by the owner.
    /// @param deployer_                The address to be set as deployer.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to deploy vaults.
    function setDeployer(address deployer_, bool allowed_) external onlyOwner validAddress(deployer_) {
        _deployers[deployer_] = allowed_;

        emit LogSetDeployer(deployer_, allowed_);
    }

    /// @notice                         Sets an address (`globalAuth_`) as a global authorization or not.
    ///                                 This function can only be called by the owner.
    /// @param globalAuth_              The address to be set as global authorization.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to update any vault config.
    function setGlobalAuth(address globalAuth_, bool allowed_) external onlyOwner validAddress(globalAuth_) {
        _globalAuths[globalAuth_] = allowed_;

        emit LogSetGlobalAuth(globalAuth_, allowed_);
    }

    /// @notice                         Sets an address (`vaultAuth_`) as allowed vault authorization or not for a specific vault (`vault_`).
    ///                                 This function can only be called by the owner.
    /// @param vault_                   The address of the vault for which the authorization is being set.
    /// @param vaultAuth_               The address to be set as vault authorization.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to update the specific vault config.
    function setVaultAuth(
        address vault_,
        address vaultAuth_,
        bool allowed_
    ) external onlyOwner validAddress(vaultAuth_) {
        _vaultAuths[vault_][vaultAuth_] = allowed_;

        emit LogSetVaultAuth(vaultAuth_, allowed_, vault_);
    }

    /// @notice                         Sets an address as allowed vault deployment logic (`deploymentLogic_`) contract or not.
    ///                                 This function can only be called by the owner.
    /// @param deploymentLogic_         The address of the vault deployment logic contract to be set.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to deploy new type of vault.
    function setVaultDeploymentLogic(
        address deploymentLogic_,
        bool allowed_
    ) public onlyOwner validAddress(deploymentLogic_) {
        _vaultDeploymentLogics[deploymentLogic_] = allowed_;

        emit LogSetVaultDeploymentLogic(deploymentLogic_, allowed_);
    }

    /// @notice                         Spell allows owner aka governance to do any arbitrary call on factory
    /// @param target_                  Address to which the call needs to be delegated
    /// @param data_                    Data to execute at the delegated address
    function spell(address target_, bytes memory data_) external onlyOwner returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /// @notice                         Checks if the provided address (`deployer_`) is authorized as a deployer.
    /// @param deployer_                The address to be checked for deployer authorization.
    /// @return                         Returns `true` if the address is a deployer, otherwise `false`.
    function isDeployer(address deployer_) public view returns (bool) {
        return _deployers[deployer_] || owner == deployer_;
    }

    /// @notice                         Checks if the provided address (`globalAuth_`) has global vault authorization privileges.
    /// @param globalAuth_              The address to be checked for global authorization privileges.
    /// @return                         Returns `true` if the given address has global authorization privileges, otherwise `false`.
    function isGlobalAuth(address globalAuth_) public view returns (bool) {
        return _globalAuths[globalAuth_] || owner == globalAuth_;
    }

    /// @notice                         Checks if the provided address (`vaultAuth_`) has vault authorization privileges for the specified vault (`vault_`).
    /// @param vault_                   The address of the vault to check.
    /// @param vaultAuth_               The address to be checked for vault authorization privileges.
    /// @return                         Returns `true` if the given address has vault authorization privileges for the specified vault, otherwise `false`.
    function isVaultAuth(address vault_, address vaultAuth_) public view returns (bool) {
        return _vaultAuths[vault_][vaultAuth_] || owner == vaultAuth_;
    }

    /// @notice                         Checks if the provided (`vaultDeploymentLogic_`) address has authorization for vault deployment.
    /// @param vaultDeploymentLogic_    The address of the vault deploy logic to check for authorization privileges.
    /// @return                         Returns `true` if the given address has authorization privileges for vault deployment, otherwise `false`.
    function isVaultDeploymentLogic(address vaultDeploymentLogic_) public view returns (bool) {
        return _vaultDeploymentLogics[vaultDeploymentLogic_];
    }
}

/// @dev implements VaultFactory deploy vault related methods.
abstract contract VaultFactoryDeployment is VaultFactoryCore, VaultFactoryAuth {
    /// @dev                            Deploys a contract using the CREATE opcode with the provided bytecode (`bytecode_`).
    ///                                 This is an internal function, meant to be used within the contract to facilitate the deployment of other contracts.
    /// @param bytecode_                The bytecode of the contract to be deployed.
    /// @return address_                Returns the address of the deployed contract.
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert FluidVaultError(ErrorTypes.VaultFactory__InvalidOperation);
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactory__InvalidOperation);
        }
    }

    /// @notice                         Deploys a new vault using the specified deployment logic `vaultDeploymentLogic_` and data `vaultDeploymentData_`.
    ///                                 Only accounts with deployer access or the owner can deploy a new vault.
    /// @param vaultDeploymentLogic_    The address of the vault deployment logic contract.
    /// @param vaultDeploymentData_     The data to be used for vault deployment.
    /// @return vault_                  Returns the address of the newly deployed vault.
    function deployVault(
        address vaultDeploymentLogic_,
        bytes calldata vaultDeploymentData_
    ) external returns (address vault_) {
        // Revert if msg.sender doesn't have deployer access or is an owner.
        if (!isDeployer(msg.sender)) revert FluidVaultError(ErrorTypes.VaultFactory__Unauthorized);
        // Revert if vaultDeploymentLogic_ is not whitelisted.
        if (!isVaultDeploymentLogic(vaultDeploymentLogic_))
            revert FluidVaultError(ErrorTypes.VaultFactory__Unauthorized);

        // Vault ID for the new vault and also acts as `nonce` for CREATE
        uint256 vaultId_ = ++_totalVaults;

        // compute vault address for vault id.
        vault_ = getVaultAddress(vaultId_);

        // deploy the vault using vault deployment logic by making .delegatecall
        (bool success_, bytes memory data_) = vaultDeploymentLogic_.delegatecall(vaultDeploymentData_);

        if (!(success_ && vault_ == _deploy(abi.decode(data_, (bytes))) && isVault(vault_))) {
            revert FluidVaultError(ErrorTypes.VaultFactory__InvalidVaultAddress);
        }

        emit VaultDeployed(vault_, vaultId_);
    }

    /// @notice                         Computes the address of a vault based on its given ID (`vaultId_`).
    /// @param vaultId_                 The ID of the vault.
    /// @return vault_                  Returns the computed address of the vault.
    function getVaultAddress(uint256 vaultId_) public view returns (address vault_) {
        // @dev based on https://ethereum.stackexchange.com/a/61413

        // nonce of smart contract always starts with 1. so, with nonce 0 there won't be any deployment
        // hence, nonce of vault deployment starts with 1.
        bytes memory data;
        if (vaultId_ == 0x00) {
            return address(0);
        } else if (vaultId_ <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(this), uint8(vaultId_));
        } else if (vaultId_ <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), address(this), bytes1(0x81), uint8(vaultId_));
        } else if (vaultId_ <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), address(this), bytes1(0x82), uint16(vaultId_));
        } else if (vaultId_ <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), address(this), bytes1(0x83), uint24(vaultId_));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), address(this), bytes1(0x84), uint32(vaultId_));
        }

        return address(uint160(uint256(keccak256(data))));
    }

    /// @notice                         Checks if a given address (`vault_`) corresponds to a valid vault.
    /// @param vault_                   The vault address to check.
    /// @return                         Returns `true` if the given address corresponds to a valid vault, otherwise `false`.
    function isVault(address vault_) public view returns (bool) {
        if (vault_.code.length == 0) {
            return false;
        } else {
            // VAULT_ID() function signature is 0x540acabc
            (bool success_, bytes memory data_) = vault_.staticcall(hex"540acabc");
            return success_ && vault_ == getVaultAddress(abi.decode(data_, (uint256)));
        }
    }

    /// @notice                   Returns the total number of vaults deployed by the factory.
    /// @return                   Returns the total number of vaults.
    function totalVaults() external view returns (uint256) {
        return _totalVaults;
    }
}

abstract contract VaultFactoryERC721 is VaultFactoryCore, VaultFactoryDeployment {
    /// @notice                   Mints a new ERC721 token for a specific vault (`vaultId_`) to a specified user (`user_`).
    ///                           Only the corresponding vault is authorized to mint a token.
    /// @param vaultId_           The ID of the vault that's minting the token.
    /// @param user_              The address receiving the minted token.
    /// @return tokenId_          The ID of the newly minted token.
    function mint(uint256 vaultId_, address user_) external returns (uint256 tokenId_) {
        if (msg.sender != getVaultAddress(vaultId_)) revert FluidVaultError(ErrorTypes.VaultFactory__InvalidVault);

        // Using _mint() instead of _safeMint() to allow any msg.sender to receive ERC721 without onERC721Received holder.
        tokenId_ = _mint(user_, vaultId_);

        emit NewPositionMinted(msg.sender, user_, tokenId_);
    }

    /// @notice                   Returns the URI of the specified token ID (`id_`).
    ///                           In this implementation, an empty string is returned as no specific URI is defined.
    /// @param id_                The ID of the token to query.
    /// @return                   An empty string since no specific URI is defined in this implementation.
    function tokenURI(uint256 id_) public view virtual override returns (string memory) {
        return "";
    }
}

/// @title Fluid VaultFactory
/// @notice creates Fluid vault protocol vaults, which are interacting with Fluid Liquidity to deposit / borrow funds.
/// Vaults are created at a deterministic address, given an incrementing `vaultId` (see `getVaultAddress()`).
/// Vaults can only be deployed by allow-listed deployer addresses.
/// This factory also implements ERC721-Enumerable, the NFTs are used to represent created user positions. Only vaults
/// can mint new NFTs.
/// @dev Note the deployed vaults start out with no config at Liquidity contract.
/// This must be done by Liquidity auths in a separate step, otherwise no deposits will be possible.
/// This contract is not upgradeable. It supports adding new vault deployment logic contracts for new, future vaults.
contract FluidVaultFactory is VaultFactoryCore, VaultFactoryAuth, VaultFactoryDeployment, VaultFactoryERC721 {
    constructor(address owner_) VaultFactoryCore(owner_) {}
}
