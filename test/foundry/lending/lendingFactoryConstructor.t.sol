// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";

/// @dev Regression tests for direct constructor input validation.
contract FluidLendingFactoryConstructorTest is Test {
    address internal constant VALID_LIQUIDITY = address(0xBEEF);
    address internal constant VALID_OWNER = address(0xCAFE);

    // Pins the constructor's `owner_`-vs-`owner` guard fix; also passes pre-fix, since the base
    // constructor already assigns `owner` before this modifier runs, so the two read the same value.
    function test_constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__ZeroAddress)
        );
        new FluidLendingFactory(IFluidLiquidity(VALID_LIQUIDITY), address(0));
    }

    function test_constructor_RevertsOnZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__ZeroAddress)
        );
        new FluidLendingFactory(IFluidLiquidity(address(0)), VALID_OWNER);
    }

    function test_constructor_AcceptsValidInputs() public {
        FluidLendingFactory factory = new FluidLendingFactory(IFluidLiquidity(VALID_LIQUIDITY), VALID_OWNER);
        // the parent `Owned` stored the owner; confirm the roundtrip.
        assertEq(factory.owner(), VALID_OWNER);
    }
}
