// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { SSTORE2 } from "solady/utils/SSTORE2.sol";

import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";

contract SoladyCompatibilityForkTest is Test {
    function setUp() public {
        // unpinned: pointer code is immutable, and Infura cannot serve proofs for old blocks
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function test_fork_soladyReadsLiveSolmatePointers() public {
        address factory_ = 0x54B91A0D94cb471F37f949c60F7Fa7935b551D03;

        string[] memory fTokenTypes_ = new string[](2);
        fTokenTypes_[0] = "fToken";
        fTokenTypes_[1] = "NativeUnderlying";

        for (uint256 i = 0; i < fTokenTypes_.length; ++i) {
            string memory fTokenType_ = fTokenTypes_[i];

            bytes32 slot_ = keccak256(abi.encode(keccak256(abi.encode(fTokenType_)), uint256(5)));
            address pointer_ = address(uint160(uint256(vm.load(factory_, slot_))));

            assertNotEq(pointer_, address(0));

            bytes memory soladyRead_ = SSTORE2.read(pointer_);
            bytes memory factoryRead_ = IFluidLendingFactory(factory_).fTokenCreationCode(fTokenType_);

            assertGt(factoryRead_.length, 0);
            assertEq(soladyRead_, factoryRead_);
        }
    }
}
