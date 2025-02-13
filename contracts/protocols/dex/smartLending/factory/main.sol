// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";
import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { CREATE3 } from "solmate/src/utils/CREATE3.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";

abstract contract Constants {
    address public immutable DEX_FACTORY;
    address public immutable LIQUIDITY;
}

abstract contract Variables is Owned {
    // ------------ storage variables from inherited contracts (Owned) come before vars here --------

    // ----------------------- slot 0 ---------------------------
    // address public owner;

    // 12 bytes empty

    // ----------------------- slot 1  ---------------------------
    /// @dev smart lending auths can update specific configs.
    /// owner can add/remove auths.
    /// Owner is auth by default.
    mapping(address => mapping(address => uint256)) internal _smartLendingAuths;

    // ----------------------- slot 2 ---------------------------
    /// @dev deployers can deploy new smartLendings.
    /// owner can add/remove deployers.
    /// Owner is deployer by default.
    mapping(address => uint256) internal _deployers;

    // ----------------------- slot 3 ---------------------------
    /// @notice list of all created tokens.
    /// @dev Solidity creates an automatic getter only to fetch at a certain position, so explicitly define a getter that returns all.
    address[] public createdTokens;

    // ----------------------- slot 4 ---------------------------

    /// @dev smart lending creation code, accessed via SSTORE2.
    address internal _smartLendingCreationCodePointer;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address owner_) Owned(owner_) {}
}

abstract contract Events {
    /// @dev Emitted when a new smart lending is deployed
    /// @param dexId The ID of the deployed DEX
    /// @param smartLending The address of the deployed smart lending
    event LogSmartLendingDeployed(uint256 dexId, address smartLending);

    /// @dev Emitted when a SmartLending auth is updated
    /// @param smartLending address of SmartLending
    /// @param auth address of auth whose status is being updated
    /// @param allowed updated status of auth
    event LogAuthUpdated(address smartLending, address auth, bool allowed);

    /// @dev Emitted when a deployer is modified by owner
    /// @param deployer address of deployer
    /// @param allowed updated status of deployer
    event LogDeployerUpdated(address deployer, bool allowed);

    /// @dev Emitted when the smart lending creation code is modified by owner
    /// @param creationCodePointer address of the creation code pointer
    event LogSetCreationCode(address creationCodePointer);
}

contract FluidSmartLendingFactory is Constants, Variables, Events, Error {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidSmartLendingFactoryError(ErrorTypes.SmartLendingFactory__ZeroAddress);
        }
        _;
    }

    constructor(
        address dexFactory_,
        address liquidity_,
        address owner_
    ) validAddress(dexFactory_) validAddress(liquidity_) validAddress(owner_) Variables(owner_) {
        LIQUIDITY = liquidity_;
        DEX_FACTORY = dexFactory_;
    }

    /// @dev Validates that msg.sender is deployer or owner
    modifier onlyDeployers() {
        if (!isDeployer(msg.sender)) {
            revert FluidSmartLendingFactoryError(ErrorTypes.SmartLendingFactory__Unauthorized);
        }
        _;
    }

    /// @notice List of all created tokens
    function allTokens() public view returns (address[] memory) {
        return createdTokens;
    }

    /// @notice Reads if a certain `auth_` address is an allowed auth for `smartLending_` or not. Owner is auth by default.
    function isSmartLendingAuth(address smartLending_, address auth_) public view returns (bool) {
        return auth_ == owner || _smartLendingAuths[smartLending_][auth_] == 1;
    }

    /// @notice Reads if a certain `deployer_` address is an allowed deployer or not. Owner is deployer by default.
    function isDeployer(address deployer_) public view returns (bool) {
        return deployer_ == owner || _deployers[deployer_] == 1;
    }

    /// @dev Retrieves the creation code for the SmartLending contract
    function smartLendingCreationCode() public view returns (bytes memory) {
        return SSTORE2.read(_smartLendingCreationCodePointer);
    }

    /// @notice Sets an address as allowed deployer or not. Only callable by owner.
    /// @param deployer_ Address to set deployer value for
    /// @param allowed_ Bool flag for whether address is allowed as deployer or not
    function updateDeployer(address deployer_, bool allowed_) external onlyOwner validAddress(deployer_) {
        _deployers[deployer_] = allowed_ ? 1 : 0;

        emit LogDeployerUpdated(deployer_, allowed_);
    }

    /// @notice Updates the authorization status of an address for a SmartLending contract. Only callable by owner.
    /// @param smartLending_ The address of the SmartLending contract
    /// @param auth_ The address to be updated
    /// @param allowed_ The new authorization status
    function updateSmartLendingAuth(
        address smartLending_,
        address auth_,
        bool allowed_
    ) external validAddress(smartLending_) validAddress(auth_) onlyOwner {
        _smartLendingAuths[smartLending_][auth_] = allowed_ ? 1 : 0;

        emit LogAuthUpdated(smartLending_, auth_, allowed_);
    }

    /// @notice Sets the `creationCode_` bytecode for new SmartLending contracts. Only callable by owner.
    /// @param creationCode_ New SmartLending contract creation code.
    function setSmartLendingCreationCode(bytes calldata creationCode_) external onlyOwner {
        if (creationCode_.length == 0) {
            revert FluidSmartLendingFactoryError(ErrorTypes.SmartLendingFactory__InvalidParams);
        }

        // write creation code to SSTORE2 pointer and set in mapping
        address creationCodePointer_ = SSTORE2.write(creationCode_);
        _smartLendingCreationCodePointer = creationCodePointer_;

        emit LogSetCreationCode(creationCodePointer_);
    }

    /// @notice Spell allows owner aka governance to do any arbitrary call on factory
    /// @param target_ Address to which the call needs to be delegated
    /// @param data_ Data to execute at the delegated address
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

    /// @notice Deploys a new SmartLending contract. Only callable by deployers.
    /// @param dexId_ The ID of the DEX for which the smart lending wrapper is being deployed
    /// @return smartLending_ The newly deployed SmartLending contract
    function deploy(uint256 dexId_) public onlyDeployers returns (address smartLending_) {
        if (getSmartLendingAddress(dexId_).code.length != 0) {
            revert FluidSmartLendingFactoryError(ErrorTypes.SmartLendingFactory__AlreadyDeployed);
        }

        // Use CREATE3 for deterministic deployments. Unfortunately it has 55k gas overhead
        smartLending_ = CREATE3.deploy(
            _getSalt(dexId_),
            abi.encodePacked(
                SSTORE2.read(_smartLendingCreationCodePointer), // creation code
                abi.encode(dexId_, LIQUIDITY, DEX_FACTORY, address(this)) // constructor params
            ),
            0
        );

        createdTokens.push(smartLending_); // Add the created token to the allTokens array

        emit LogSmartLendingDeployed(dexId_, smartLending_);
    }

    /// @notice Computes the address of a SmartLending contract based on a given dexId.
    /// @param dexId_ The ID of the DEX for which the SmartLending contract address is being computed.
    /// @return The computed address of the SmartLending contract.
    function getSmartLendingAddress(uint256 dexId_) public view returns (address) {
        return CREATE3.getDeployed(_getSalt(dexId_));
    }

    /// @notice Returns the total number of SmartLending contracts deployed by the factory.
    /// @return The total number of SmartLending contracts deployed.
    function totalSmartLendings() external view returns (uint256) {
        return createdTokens.length;
    }

    /// @notice                         Checks if a given address (`smartLending_`) corresponds to a valid smart lending.
    /// @param smartLending_            The smart lending address to check.
    /// @return                         Returns `true` if the given address corresponds to a valid smart lending, otherwise `false`.
    function isSmartLending(address smartLending_) public view returns (bool) {
        if (smartLending_.code.length == 0) {
            return false;
        } else {
            // DEX() function signature is 0x80935aa9
            (bool success_, bytes memory data_) = smartLending_.staticcall(hex"80935aa9");
            address dex_ = abi.decode(data_, (address));
            // DEX_ID() function signature is 0xf4b9a3fb
            (success_, data_) = dex_.staticcall(hex"f4b9a3fb");
            return success_ && smartLending_ == getSmartLendingAddress(abi.decode(data_, (uint256)));
        }
    }

    /// @dev unique deployment salt for the smart lending
    function _getSalt(uint256 dexId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(dexId_));
    }

    /// @dev Deploys a contract using the CREATE opcode with the provided bytecode (`bytecode_`).
    /// This is an internal function, meant to be used within the contract to facilitate the deployment of other contracts.
    /// @param bytecode_ The bytecode of the contract to be deployed.
    /// @return address_ Returns the address of the deployed contract.
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert FluidDexError(ErrorTypes.SmartLendingFactory__InvalidOperation);
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert FluidDexError(ErrorTypes.SmartLendingFactory__InvalidOperation);
        }
    }
}
