//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

library ErrorTypes {
    /***********************************|
    |         Infinite proxy            | 
    |__________________________________*/

    /// @notice thrown when an implementation does not exist
    uint256 internal constant InfiniteProxy__ImplementationNotExist = 50001;
}
