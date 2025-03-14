// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";

import { AddressCalcs } from "../libraries/addressCalcs.sol";

/// @title FluidContractFactory
/// @notice A contract that allows deployers to deploy any contract by passing the contract data in bytes
/// @dev The main objective of this contract is to avoid storing contract addresses in our protocols which requires 160 bits of storage
///      Instead, we can just store the nonce & deployment of this address to calculate the address realtime using "AddressCalcs" library
contract FluidContractFactory is Owned {
    /// @notice Thrown when an invalid operation is attempted
    error FluidContractFactory__InvalidOperation();

    /// @notice Emitted when a new contract is deployed
    /// @param addr The address of the deployed contract
    /// @param nonce The nonce used for deployment
    event LogContractDeployed(address indexed addr, uint256 indexed nonce);

    /// @notice Emitted when a deployer's count is updated
    /// @param deployer The address of the deployer
    /// @param count The new count for the deployer
    event LogUpdateDeployer(address indexed deployer, uint16 indexed count);

    /// @notice Mapping to store the deployment count for each deployer
    mapping(address => uint16) public deployer;

    /// @notice total number of contracts deployed
    uint256 public totalContracts;

    /// @notice Constructor to initialize the contract
    /// @param owner_ The address of the contract owner
    constructor(address owner_) Owned(owner_) {}

    /// @notice Updates the allowed deployments count for a specific deployer
    /// @param deployer_ The address of the deployer
    /// @param count_ The new count for the deployer
    /// @dev Only callable by the contract owner
    function updateDeployer(address deployer_, uint16 count_) public onlyOwner {
        deployer[deployer_] = count_;
        emit LogUpdateDeployer(deployer_, count_);
    }

    /// @notice Deploys a new contract
    /// @param contractCode_ The bytecode of the contract to deploy
    /// @return contractAddress_ The address of the deployed contract
    /// @dev Decrements the deployer's allowed deployments count if not the owner
    function deployContract(bytes calldata contractCode_) external returns (address contractAddress_) {
        if (msg.sender != owner) {
            // if deployer count is 0 then it'll underflow and hence solidity will throw error
            deployer[msg.sender] -= 1;
        }

        uint256 nonce_ = ++totalContracts;

        // compute contract address for nonce.
        contractAddress_ = getContractAddress(nonce_);

        if (contractAddress_ != _deploy(contractCode_)) {
            revert FluidContractFactory__InvalidOperation();
        }

        emit LogContractDeployed(contractAddress_, nonce_);
    }

    /// @notice Calculates the address of a contract for a given nonce
    /// @param nonce_ The nonce to use for address calculation
    /// @return contractAddress_ The calculated contract address
    function getContractAddress(uint256 nonce_) public view returns (address contractAddress_) {
        return AddressCalcs.addressCalc(address(this), nonce_);
    }

    /// @notice Internal function to deploy a contract
    /// @param bytecode_ The bytecode of the contract to deploy
    /// @return address_ The address of the deployed contract
    /// @dev Uses inline assembly for efficient deployment
    function _deploy(bytes memory bytecode_) internal returns (address address_) {
        if (bytecode_.length == 0) {
            revert FluidContractFactory__InvalidOperation();
        }
        /// @solidity memory-safe-assembly
        assembly {
            address_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }
        if (address_ == address(0)) {
            revert FluidContractFactory__InvalidOperation();
        }
    }
}
