//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

library ErrorTypes {
    /***********************************|
    |         Infinite proxy            | 
    |__________________________________*/

    /// @notice thrown when an implementation does not exist
    uint256 internal constant InfiniteProxy__ImplementationNotExist = 50001;

    /***********************************|
    |          RollbackModule           | 
    |__________________________________*/

    uint256 internal constant InfiniteProxyRollback__Unauthorized = 50010;

    uint256 internal constant InfiniteProxyRollback__Expired = 50011;

    uint256 internal constant InfiniteProxyRollback__NotRegistered = 50012;

    uint256 internal constant InfiniteProxyRollback__NoRollbackSigs = 50013;

    uint256 internal constant InfiniteProxyRollback__AlreadyExists = 50014;

    uint256 internal constant InfiniteProxyRollback__SigAlreadyExists = 50015;

    uint256 internal constant InfiniteProxyRollback__SigSlotCollision = 50016;

    uint256 internal constant InfiniteProxyRollback__NotExpired = 50017;

    uint256 internal constant InfiniteProxyRollback__ZeroDummyImplementation = 50018;

    uint256 internal constant InfiniteProxyRollback__NotAllowed = 50019;
}
