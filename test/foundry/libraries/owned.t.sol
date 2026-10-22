// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Owned } from "../../../contracts/libraries/Owned.sol";

contract OwnedHarness is Owned {
    constructor(address owner_) Owned(owner_) {}

    function guarded() external view onlyOwner returns (bool) {
        return true;
    }
}

contract OwnedTest is Test {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    OwnedHarness internal owned;

    function setUp() public {
        owned = new OwnedHarness(owner);
    }

    function test_onlyOwner_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Owned.Access__Unauthorized.selector);
        owned.guarded();
    }

    function test_onlyOwner_WhenOwner() public {
        vm.prank(owner);
        assertTrue(owned.guarded());
    }

    function test_transferOwnership_RevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Owned.Access__Unauthorized.selector);
        owned.transferOwnership(alice);
    }

    function test_transferOwnership() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, alice);
        vm.prank(owner);
        owned.transferOwnership(alice);
        assertEq(owned.owner(), alice);
    }
}
