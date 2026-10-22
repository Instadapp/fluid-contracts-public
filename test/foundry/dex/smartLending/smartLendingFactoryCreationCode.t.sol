// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidSmartLendingFactory } from "../../../../contracts/protocols/dex/smartLending/factory/main.sol";
import { Error } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";

contract FluidSmartLendingFactoryCreationCodeTest is Test {
    FluidSmartLendingFactory internal factory;

    function setUp() public {
        factory = new FluidSmartLendingFactory(makeAddr("dexFactory"), makeAddr("liquidity"), address(this));
    }

    function test_smartLendingCreationCode_WhenNotSet() public view {
        // a read of the zero pointer would burn the whole gas budget instead of returning
        assertEq(factory.smartLendingCreationCode{ gas: 100_000 }().length, 0);
    }

    function test_deploy_RevertIfCreationCodeNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidSmartLendingFactoryError.selector,
                ErrorTypes.SmartLendingFactory__InvalidOperation
            )
        );
        factory.deploy{ gas: 200_000 }(1);
    }

    function test_smartLendingCreationCode_WhenSet() public {
        bytes memory creationCode_ = hex"6080604052";
        factory.setSmartLendingCreationCode(creationCode_);
        assertEq(factory.smartLendingCreationCode(), creationCode_);
    }
}
