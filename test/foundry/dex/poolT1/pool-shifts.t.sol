//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidDexT1Shift } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/shift.sol";

import "forge-std/console2.sol";

contract DexPoolShiftsTestOldLogic is Test {
    FluidDexT1 internal constant DEX_WSTETH_ETH = FluidDexT1(payable(0x0B1a513ee24972DAEf112bC777a5610d4325C9e7));
    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant WSTETH_HOLDER = 0x3c22ec75ea5D745c78fc84762F7F1E6D82a2c5BF;

    IERC20 internal constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21324219);
        vm.deal(WSTETH_HOLDER, 1e20);
    }

    function _doSwap() internal {
        vm.prank(WSTETH_HOLDER);
        DEX_WSTETH_ETH.swapIn{ value: 1e18 }(false, 1e18, 1, WSTETH_HOLDER);
    }

    function _doSwapTest() internal {
        // swap will fail
        vm.expectRevert();
        _doSwap();

        // pass time until shift complete
        vm.warp(block.timestamp + 13 hours);
        // swap still fails
        vm.expectRevert();
        _doSwap();

        // do other direction swap to trigger complete the shift
        vm.prank(WSTETH_HOLDER);
        WSTETH.approve(address(DEX_WSTETH_ETH), 1e19);
        vm.prank(WSTETH_HOLDER);
        DEX_WSTETH_ETH.swapIn(true, 1e18, 1, WSTETH_HOLDER);

        // now swap should work again
        _doSwap();
    }

    function test_withoutAnyShiftActive() public {
        // swap should work
        _doSwap();
    }

    function test_shiftCenterPrice() public {
        // setting to old WSTETH center price 0xf1442714E502723D5bB253B806Fd7555BEE0336C, nonce 5
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateCenterPriceAddress(5, 50e4, 12 hours);

        _doSwapTest();
    }

    function test_shiftRange() public {
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateRangePercents(1e4, 1e4, 12 hours);

        _doSwapTest();
    }

    function test_shiftThreshold() public {
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateThresholdPercent(1e4, 1e4, 12 hours, 12 hours);

        _doSwapTest();
    }
}

contract DexPoolShiftsTestNewLogic is Test {
    FluidDexT1 internal constant DEX_WSTETH_ETH = FluidDexT1(payable(0x0B1a513ee24972DAEf112bC777a5610d4325C9e7));
    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant WSTETH_HOLDER = 0x3c22ec75ea5D745c78fc84762F7F1E6D82a2c5BF;

    IERC20 internal constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    address internal constant DEPLOYER_CONTRACT = 0x4EC7b668BAF70d4A4b0FC7941a7708A07b6d45Be;
    address internal constant OLD_SHIFT = 0x5B6B500981d7Faa8c83Be20514EA8067fbd42304;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21324219);
        vm.deal(WSTETH_HOLDER, 1e20);

        // deploy new Shift logic contract and set it to be used for the WSTETH_ETH dex via etch
        FluidDexT1Shift newShift = new FluidDexT1Shift(DEPLOYER_CONTRACT);
        vm.etch(OLD_SHIFT, address(newShift).code);
    }

    function _doSwap() internal {
        vm.prank(WSTETH_HOLDER);
        DEX_WSTETH_ETH.swapIn{ value: 1e18 }(false, 1e18, 1, WSTETH_HOLDER);
    }

    function _doSwapTest() internal {
        // swap will ALWAYS pass
        _doSwap();

        // pass time until shift complete
        vm.warp(block.timestamp + 13 hours);
        _doSwap();

        // do other direction swap to trigger complete the shift
        vm.prank(WSTETH_HOLDER);
        WSTETH.approve(address(DEX_WSTETH_ETH), 1e19);
        vm.prank(WSTETH_HOLDER);
        DEX_WSTETH_ETH.swapIn(true, 1e18, 1, WSTETH_HOLDER);

        // now swap should still work
        _doSwap();
    }

    function test_withoutAnyShiftActive() public {
        // swap should work
        _doSwap();
    }

    function test_shiftCenterPrice() public {
        // setting to old WSTETH center price 0xf1442714E502723D5bB253B806Fd7555BEE0336C, nonce 5
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateCenterPriceAddress(5, 50e4, 12 hours);

        _doSwapTest();
    }

    function test_shiftRange() public {
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateRangePercents(1e4, 1e4, 12 hours);

        _doSwapTest();
    }

    function test_shiftThreshold() public {
        vm.prank(GOVERNANCE);
        FluidDexT1Admin(address(DEX_WSTETH_ETH)).updateThresholdPercent(1e4, 1e4, 12 hours, 12 hours);

        _doSwapTest();
    }
}
