// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";
import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { StorageRead } from "../../../libraries/storageRead.sol";

abstract contract DexFactoryVariables is Owned, StorageRead, Error {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // ------------ storage variables from inherited contracts (Owned) come before vars here --------

    // ----------------------- slot 0 ---------------------------
    // address public owner; // from Owned

    // 12 bytes empty

    // ----------------------- slot 1  ---------------------------
    /// @dev deployer can deploy new Dex Pool contract
    /// owner can add/remove deployer.
    /// Owner is deployer by default.
    mapping(address => bool) internal _deployers;

    // ----------------------- slot 2  ---------------------------
    /// @dev global auths can update any dex pool config.
    /// owner can add/remove global auths.
    /// Owner is global auth by default.
    mapping(address => bool) internal _globalAuths;

    // ----------------------- slot 3  ---------------------------
    /// @dev dex auths can update specific dex config.
    /// owner can add/remove dex auths.
    /// Owner is dex auth by default.
    /// dex => auth => add/remove
    mapping(address => mapping(address => bool)) internal _dexAuths;

    // ----------------------- slot 4 ---------------------------
    /// @dev total no of dexes deployed by the factory
    /// only addresses that have deployer role or owner can deploy new dex pool.
    uint256 internal _totalDexes;

    // ----------------------- slot 5 ---------------------------
    /// @dev dex deployment logics for deploying dex pool
    /// These logic contracts hold the deployment logics of specific dexes and are called via .delegatecall inside deployDex().
    /// only addresses that have owner can add/remove new dex deployment logic.
    mapping(address => bool) internal _dexDeploymentLogics;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address owner_) Owned(owner_) {}
}

abstract contract DexFactoryEvents {
    /// @dev Emitted when a new dex is deployed.
    /// @param dex The address of the newly deployed dex.
    /// @param dexId The id of the newly deployed dex.
    event LogDexDeployed(address indexed dex, uint256 indexed dexId);

    /// @dev Emitted when the deployer is modified by owner.
    /// @param deployer Address whose deployer status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    event LogSetDeployer(address indexed deployer, bool indexed allowed);

    /// @dev Emitted when the globalAuth is modified by owner.
    /// @param globalAuth Address whose globalAuth status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    event LogSetGlobalAuth(address indexed globalAuth, bool indexed allowed);

    /// @dev Emitted when the dexAuth is modified by owner.
    /// @param dexAuth Address whose dexAuth status is updated.
    /// @param allowed Indicates whether the address is authorized as a deployer or not.
    /// @param dex Address of the specific dex related to the authorization change.
    event LogSetDexAuth(address indexed dexAuth, bool indexed allowed, address indexed dex);

    /// @dev Emitted when the dex deployment logic is modified by owner.
    /// @param dexDeploymentLogic The address of the dex deployment logic contract.
    /// @param allowed  Indicates whether the address is authorized as a deployer or not.
    event LogSetDexDeploymentLogic(address indexed dexDeploymentLogic, bool indexed allowed);
}

abstract contract DexFactoryCore is DexFactoryVariables, DexFactoryEvents {
    constructor(address owner_) validAddress(owner_) DexFactoryVariables(owner_) {}

    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidDexFactoryError(ErrorTypes.DexFactory__InvalidParams);
        }
        _;
    }
}

/// @dev Implements Dex Factory auth-only callable methods. Owner / auths can set various config values and
/// can define the allow-listed deployers.
abstract contract DexFactoryAuth is DexFactoryCore {
    /// @notice                         Sets an address (`deployer_`) as allowed deployer or not.
    ///                                 This function can only be called by the owner.
    /// @param deployer_                The address to be set as deployer.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to deploy dexes.
    function setDeployer(address deployer_, bool allowed_) external onlyOwner validAddress(deployer_) {
        _deployers[deployer_] = allowed_;

        emit LogSetDeployer(deployer_, allowed_);
    }

    /// @notice                         Sets an address (`globalAuth_`) as a global authorization or not.
    ///                                 This function can only be called by the owner.
    /// @param globalAuth_              The address to be set as global authorization.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to update any dex config.
    function setGlobalAuth(address globalAuth_, bool allowed_) external onlyOwner validAddress(globalAuth_) {
        _globalAuths[globalAuth_] = allowed_;

        emit LogSetGlobalAuth(globalAuth_, allowed_);
    }

    /// @notice                         Sets an address (`dexAuth_`) as allowed dex authorization or not for a specific dex (`dex_`).
    ///                                 This function can only be called by the owner.
    /// @param dex_                     The address of the dex for which the authorization is being set.
    /// @param dexAuth_                 The address to be set as dex authorization.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to update the specific dex config.
    function setDexAuth(address dex_, address dexAuth_, bool allowed_) external onlyOwner validAddress(dexAuth_) {
        _dexAuths[dex_][dexAuth_] = allowed_;

        emit LogSetDexAuth(dexAuth_, allowed_, dex_);
    }

    /// @notice                         Sets an address as allowed dex deployment logic (`deploymentLogic_`) contract or not.
    ///                                 This function can only be called by the owner.
    /// @param deploymentLogic_         The address of the dex deployment logic contract to be set.
    /// @param allowed_                 A boolean indicating whether the specified address is allowed to deploy new type of dex.
    function setDexDeploymentLogic(
        address deploymentLogic_,
        bool allowed_
    ) public onlyOwner validAddress(deploymentLogic_) {
        _dexDeploymentLogics[deploymentLogic_] = allowed_;

        emit LogSetDexDeploymentLogic(deploymentLogic_, allowed_);
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

    /// @notice                         Checks if the provided address (`globalAuth_`) has global dex authorization privileges.
    /// @param globalAuth_              The address to be checked for global authorization privileges.
    /// @return                         Returns `true` if the given address has global authorization privileges, otherwise `false`.
    function isGlobalAuth(address globalAuth_) public view returns (bool) {
        return _globalAuths[globalAuth_] || owner == globalAuth_;
    }

    /// @notice                         Checks if the provided address (`dexAuth_`) has dex authorization privileges for the specified dex (`dex_`).
    /// @param dex_                     The address of the dex to check.
    /// @param dexAuth_                 The address to be checked for dex authorization privileges.
    /// @return                         Returns `true` if the given address has dex authorization privileges for the specified dex, otherwise `false`.
    function isDexAuth(address dex_, address dexAuth_) public view returns (bool) {
        return _dexAuths[dex_][dexAuth_] || owner == dexAuth_;
    }

    /// @notice                         Checks if the provided (`dexDeploymentLogic_`) address has authorization for dex deployment.
    /// @param dexDeploymentLogic_      The address of the dex deploy logic to check for authorization privileges.
    /// @return                         Returns `true` if the given address has authorization privileges for dex deployment, otherwise `false`.
    function isDexDeploymentLogic(address dexDeploymentLogic_) public view returns (bool) {
        return _dexDeploymentLogics[dexDeploymentLogic_];
    }
}

/// @dev implements DexFactory deploy dex related methods.
abstract contract DexFactoryDeployment is DexFactoryCore, DexFactoryAuth {
    /// @dev                            Deploys a contract using the CREATE opcode with the provided bytecode (`bytecode_`).
    ///                                 This is an internal function, meant to be used within the contract to facilitate the deployment of other contracts.
    /// @param bytecode_                The bytecode of the contract to be deployed.
    /// @return address_                Returns the address of the deployed contract.
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert FluidDexError(ErrorTypes.DexFactory__InvalidOperation);
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert FluidDexError(ErrorTypes.DexFactory__InvalidOperation);
        }
    }

    /// @notice                       Deploys a new dex using the specified deployment logic `dexDeploymentLogic_` and data `dexDeploymentData_`.
    ///                               Only accounts with deployer access or the owner can deploy a new dex.
    /// @param dexDeploymentLogic_    The address of the dex deployment logic contract.
    /// @param dexDeploymentData_     The data to be used for dex deployment.
    /// @return dex_                  Returns the address of the newly deployed dex.
    function deployDex(address dexDeploymentLogic_, bytes calldata dexDeploymentData_) external returns (address dex_) {
        // Revert if msg.sender doesn't have deployer access or is an owner.
        if (!isDeployer(msg.sender)) revert FluidDexError(ErrorTypes.DexFactory__Unauthorized);
        // Revert if dexDeploymentLogic_ is not whitelisted.
        if (!isDexDeploymentLogic(dexDeploymentLogic_)) revert FluidDexError(ErrorTypes.DexFactory__Unauthorized);

        // Dex ID for the new dex and also acts as `nonce` for CREATE
        uint256 dexId_ = ++_totalDexes;

        // compute dex address for dex id.
        dex_ = getDexAddress(dexId_);

        // deploy the dex using dex deployment logic by making .delegatecall
        (bool success_, bytes memory data_) = dexDeploymentLogic_.delegatecall(dexDeploymentData_);

        if (!(success_ && dex_ == _deploy(abi.decode(data_, (bytes))) && isDex(dex_))) {
            revert FluidDexError(ErrorTypes.DexFactory__InvalidDexAddress);
        }

        emit LogDexDeployed(dex_, dexId_);
    }

    /// @notice                       Computes the address of a dex based on its given ID (`dexId_`).
    /// @param dexId_                 The ID of the dex.
    /// @return dex_                  Returns the computed address of the dex.
    function getDexAddress(uint256 dexId_) public view returns (address dex_) {
        return AddressCalcs.addressCalc(address(this), dexId_);
    }

    /// @notice                         Checks if a given address (`dex_`) corresponds to a valid dex.
    /// @param dex_                     The dex address to check.
    /// @return                         Returns `true` if the given address corresponds to a valid dex, otherwise `false`.
    function isDex(address dex_) public view returns (bool) {
        if (dex_.code.length == 0) {
            return false;
        } else {
            // DEX_ID() function signature is 0xf4b9a3fb
            (bool success_, bytes memory data_) = dex_.staticcall(hex"f4b9a3fb");
            return success_ && dex_ == getDexAddress(abi.decode(data_, (uint256)));
        }
    }

    /// @notice                   Returns the total number of dexes deployed by the factory.
    /// @return                   Returns the total number of dexes.
    function totalDexes() external view returns (uint256) {
        return _totalDexes;
    }
}

/// @title Fluid DexFactory
/// @notice creates Fluid dex protocol dexes, which are interacting with Fluid Liquidity to deposit / borrow funds.
/// Dexes are created at a deterministic address, given an incrementing `dexId` (see `getDexAddress()`).
/// Dexes can only be deployed by allow-listed deployer addresses.
/// @dev Note the deployed dexes start out with no config at Liquidity contract.
/// This must be done by Liquidity auths in a separate step, otherwise no deposits will be possible.
/// This contract is not upgradeable. It supports adding new dex deployment logic contracts for new, future dexes.
contract FluidDexFactory is DexFactoryCore, DexFactoryAuth, DexFactoryDeployment {
    constructor(address owner_) DexFactoryCore(owner_) {}
}
