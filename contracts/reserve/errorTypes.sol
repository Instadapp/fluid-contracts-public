// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |               Reserve             | 
    |__________________________________*/

    /// @notice thrown when an unauthorized caller is trying to execute an auth-protected method
    uint256 internal constant ReserveContract__Unauthorized = 90001;

    /// @notice thrown when an input address is zero
    uint256 internal constant ReserveContract__AddressZero = 90002;

    /// @notice thrown when input arrays has different lenghts
    uint256 internal constant ReserveContract__InvalidInputLenghts = 90003;

    /// @notice thrown when renounceOwnership is called
    uint256 internal constant ReserveContract__RenounceOwnershipUnsupported = 90004;

    /// @notice thrown when wrong msg.value is at time of rebalancing
    uint256 internal constant ReserveContract__WrongValueSent = 90005;

    /// @notice thrown when there is insufficient allowance to a protocol
    uint256 internal constant ReserveContract__InsufficientAllowance = 90006;
}
