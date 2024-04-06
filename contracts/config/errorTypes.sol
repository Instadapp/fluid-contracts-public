// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |    ExpandPercentConfigHandler     | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant ExpandPercentConfigHandler__AddressZero = 100001;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant ExpandPercentConfigHandler__Unauthorized = 100002;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant ExpandPercentConfigHandler__InvalidParams = 100003;

    /// @notice thrown when no update is currently needed
    uint256 internal constant ExpandPercentConfigHandler__NoUpdate = 100004;

    /// @notice thrown when slot is not used, e.g. when borrow token is 0 there is no borrow data
    uint256 internal constant ExpandPercentConfigHandler__SlotDoesNotExist = 100005;

    /***********************************|
    |      EthenaRateConfigHandler      | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant EthenaRateConfigHandler__AddressZero = 100011;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant EthenaRateConfigHandler__Unauthorized = 100012;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant EthenaRateConfigHandler__InvalidParams = 100013;

    /// @notice thrown when no update is currently needed
    uint256 internal constant EthenaRateConfigHandler__NoUpdate = 100014;

    /***********************************|
    |       MaxBorrowConfigHandler      | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant MaxBorrowConfigHandler__AddressZero = 100021;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant MaxBorrowConfigHandler__Unauthorized = 100022;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant MaxBorrowConfigHandler__InvalidParams = 100023;

    /// @notice thrown when no update is currently needed
    uint256 internal constant MaxBorrowConfigHandler__NoUpdate = 100024;
}
