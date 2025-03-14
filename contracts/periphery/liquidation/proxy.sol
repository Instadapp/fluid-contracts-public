// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";

import { SafeTransfer } from "../../libraries/safeTransfer.sol";

contract VaultLiquidator is Owned {
    address constant public ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant public DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // @notice temporary implementation address set for fallback
    address private _implementation;

    // @notice whitelisted rebalancers
    mapping (address => bool) public rebalancer; 
    // @notice whitelisted implementations
    mapping (address => bool) public implementation;
    
    error FluidVaultT1Liquidator__InvalidOperation();
    error FluidVaultT1Liquidator__InvalidImplementation();
    error FluidVaultT1Liquidator__InvalidFallback();

    event ToggleRebalancer(
        address indexed rebalancer,
        bool indexed status
    );

    event ToggleImplementation(
        address indexed implementation,
        bool indexed status
    );

    event Withdraw(
        address indexed to,
        address indexed token,
        uint256 amount
    );

    constructor (
        address owner_,
        address[] memory rebalancers_,
        address[] memory implementations_
    ) Owned(owner_) {
        require(owner_ != address(0), "Owner cannot be the zero address");

        for (uint256 i = 0; i < rebalancers_.length; i++) {
            rebalancer[rebalancers_[i]] = true;
            emit ToggleRebalancer(rebalancers_[i], true);
        }

        for (uint256 i = 0; i < implementations_.length; i++) {
            implementation[implementations_[i]] = true;
            emit ToggleImplementation(implementations_[i], true);
        }

        _implementation = DEAD_ADDRESS;
    }

    modifier isRebalancer() {
        if (!rebalancer[msg.sender] && msg.sender != owner) {
            revert FluidVaultT1Liquidator__InvalidOperation();
        }
        _;
    }

    modifier isImplementation(address implementation_) {
        if (!implementation[implementation_] || _implementation != DEAD_ADDRESS) {
            revert FluidVaultT1Liquidator__InvalidImplementation();
        }
        _implementation = implementation_;
        _;
        _implementation = address(DEAD_ADDRESS);
    }

    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            if iszero(succeeded) {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    function toggleRebalancer(address rebalancer_, bool status_) public onlyOwner {
        rebalancer[rebalancer_] = status_;
        emit ToggleRebalancer(rebalancer_, status_);
    }

    function toggleImplementation(address implementation_, bool status_) public onlyOwner {
        implementation[implementation_] = status_;
        emit ToggleImplementation(implementation_, status_);
    }

    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) {
            _spell(targets_[i], calldatas_[i]);
        }
    }

    function withdraw(address to_, address[] memory tokens_, uint256[] memory amounts_) public onlyOwner {
        for (uint i = 0; i < tokens_.length; i++) {
            if (tokens_[i] == ETH_ADDRESS) {
                SafeTransfer.safeTransferNative(payable(to_), amounts_[i]);
            } else {
                SafeTransfer.safeTransfer(tokens_[i], to_, amounts_[i]);
            }
            emit Withdraw(to_, tokens_[i], amounts_[i]);
        }
    }

    receive() payable external {}

    function execute(address implementation_, bytes memory data_) public isRebalancer() isImplementation(implementation_) {
        _spell(implementation_, data_);
    }

    fallback() external payable {
        if (_implementation != DEAD_ADDRESS) {
            bytes memory response_ = _spell(_implementation, msg.data);
            assembly {
                return(add(response_, 32), mload(response_))
            }
        } else {
            revert FluidVaultT1Liquidator__InvalidFallback();
        }
    }
}
