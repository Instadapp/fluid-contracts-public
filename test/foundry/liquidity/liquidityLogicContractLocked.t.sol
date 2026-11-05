// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidLiquidityUserModuleMainnet } from "../../../contracts/liquidity/userModule/mainMainnet.sol";
import { FluidLiquidityAdminModuleMainnet } from "../../../contracts/liquidity/adminModule/mainMainnet.sol";
import { Error } from "../../../contracts/liquidity/error.sol";
import { ErrorTypes } from "../../../contracts/liquidity/errorTypes.sol";

contract LiquidityLogicContractLockedTest is Test {
    // slot 1 packs `uint8 _status` (byte 0) and `uint8 _reentrancyStatus` (byte 1)
    uint256 internal constant LOCKED_SLOT_1 = 2 | (1 << 8);

    function test_constructor_LocksUserModuleLogic() public {
        FluidLiquidityUserModuleMainnet logic_ = new FluidLiquidityUserModuleMainnet();
        assertEq(uint256(vm.load(address(logic_), bytes32(uint256(1)))), LOCKED_SLOT_1);
    }

    function test_constructor_LocksAdminModuleLogic() public {
        FluidLiquidityAdminModuleMainnet logic_ = new FluidLiquidityAdminModuleMainnet(1e10 * 1e18);
        assertEq(uint256(vm.load(address(logic_), bytes32(uint256(1)))), LOCKED_SLOT_1);
    }

    function test_operate_RevertIfCalledOnLogicContract() public {
        FluidLiquidityUserModuleMainnet logic_ = new FluidLiquidityUserModuleMainnet();
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.LiquidityHelpers__Reentrancy)
        );
        logic_.operate(makeAddr("token"), 1, 0, address(0), address(0), "");
    }
}
