// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { Bytecode1 } from "./bytecode1.sol";
import { Bytecode2 } from "./bytecode2.sol";

contract LongBytesHashVerify is Bytecode1, Bytecode2 {

    function setUp() public {
        
    }
    
    function test_VerifyLongBytesHash() public {
        bytes32 hash1 = keccak256(abi.encodePacked(bytecode1));
        bytes32 hash2 = keccak256(abi.encodePacked(bytecode2));

        console2.logBytes32(hash1);
        console2.logBytes32(hash2);
        console2.log(hash1 == hash2);
    }

}