// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidWalletFactory {
    function walletImplementation() external returns(address);
}

/// @title      FluidWallet
/// @notice     Proxy for Fluid wallet as deployed by the FluidWalletFactory.
///             Basic Proxy with fallback to delegate and address for implementation contract at storage 0x0
//
contract FluidWallet {
    /// @notice Fluid Wallet Factory address.
    IFluidWalletFactory public immutable FACTORY;

    /// @notice Owner of the wallet.
    address public owner;

    function initialize(address owner_) public {
        if (owner == address(0)) {
            owner = owner_;
        } else {
            revert();
        }
    }

    constructor (address factory_) {
        FACTORY = IFluidWalletFactory(factory_);
    }

    receive() external payable {}

    fallback() external payable {
        address impl_ = FACTORY.walletImplementation();
        assembly {
            // @dev code below is taken from OpenZeppelin Proxy.sol _delegate function

            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), impl_, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}