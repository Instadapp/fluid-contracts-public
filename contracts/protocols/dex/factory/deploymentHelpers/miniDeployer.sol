// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";

/// @title MiniDeployer
/// @notice A contract that allows deployers to deploy any contract by passing the contract data in bytes
/// @dev The main objective of this contract is to avoid storing contract addresses in our protocols which requires 160 bits of storage
///      Instead, we can just store the nonce & deployment of this address to calculate the address realtime using "AddressCalcs" library
contract MiniDeployer is Owned {
    /// @notice Thrown when an invalid operation is attempted
    error MiniDeployer__InvalidOperation();

    /// @notice Emitted when a new contract is deployed
    event LogContractDeployed(address indexed contractAddress);

    /// @notice Constructor to initialize the contract
    /// @param owner_ The address of the contract owner
    constructor(address owner_) Owned(owner_) {}

    /// @notice Internal function to deploy a contract
    /// @param bytecode_ The bytecode of the contract to deploy
    /// @return address_ The address of the deployed contract
    /// @dev Uses inline assembly for efficient deployment
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert MiniDeployer__InvalidOperation();
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert MiniDeployer__InvalidOperation();
        }
    }

    /// @notice Deploys a new contract
    /// @param contractCode_ The bytecode of the contract to deploy
    /// @return contractAddress_ The address of the deployed contract
    /// @dev Decrements the deployer's allowed deployments count if not the owner
    function deployContract(bytes calldata contractCode_) external onlyOwner returns (address contractAddress_) {
        contractAddress_ = _deploy(contractCode_);

        emit LogContractDeployed(contractAddress_);
    }
}
