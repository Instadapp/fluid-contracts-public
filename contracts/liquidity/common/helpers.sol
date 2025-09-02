// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { Variables } from "./variables.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

/// @dev ReentrancyGuard based on OpenZeppelin implementation.
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/security/ReentrancyGuard.sol
abstract contract ReentrancyGuard is Variables, Error {
    uint8 internal constant REENTRANCY_NOT_ENTERED = 1;
    uint8 internal constant REENTRANCY_ENTERED = 2;

    constructor() {
        // on logic contracts, switch reentrancy to entered so no call is possible (forces delegatecall)
        _status = REENTRANCY_ENTERED; 
    }

    /// @dev Prevents a contract from calling itself, directly or indirectly.
    /// See OpenZeppelin implementation for more info
    modifier reentrancy() {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == REENTRANCY_ENTERED) {
            revert FluidLiquidityError(ErrorTypes.LiquidityHelpers__Reentrancy);
        }

        // Any calls to nonReentrant after this point will fail
        _status = REENTRANCY_ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = REENTRANCY_NOT_ENTERED;
    }
}

abstract contract CommonHelpers is ReentrancyGuard {
    /// @dev Returns the current admin (governance).
    function _getGovernanceAddr() internal view returns (address governance_) {
        assembly {
            governance_ := sload(GOVERNANCE_SLOT)
        }
    }
}
