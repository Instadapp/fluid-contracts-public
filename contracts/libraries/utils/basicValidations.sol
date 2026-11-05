// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

import { LibsErrorTypes as ErrorTypes } from "../errorTypes.sol";

/// @notice basic input validation modifiers for inheriting contracts.
abstract contract BasicValidations {
    error FluidBasicValidationsError(uint256 errorId_);

    modifier validAddress(address value_) {
        if (!_isValidAddress(value_)) {
            revert FluidBasicValidationsError(ErrorTypes.BasicValidations__AddressZero);
        }
        _;
    }

    function _isValidAddress(address value_) internal pure returns (bool) {
        return value_ != address(0);
    }
}
