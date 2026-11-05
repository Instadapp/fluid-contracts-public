// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Structs {
    struct UserPosition {
        uint nftId;
        address owner;
        uint supply;
        uint borrow;
    }
}
