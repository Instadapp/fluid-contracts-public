// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Vm.sol";
import "forge-std/console2.sol";

// ============ IMPORT YOUR CONTRACTS ============ //

// 1) The logic (implementation) contract
import { FluidWETHWrapper } from "../../../../contracts/periphery/wethWrapper/main.sol";

// 2) The minimal UUPS-compatible proxy
import { FluidWethWrapperProxy } from "../../../../contracts/periphery/wethWrapper/proxy.sol";

// ============ INTERFACES ============ //
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface ERC20 {
    function balanceOf(address) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

/// TO test run:  forge test -vvv --match-path test/foundry/periphery/wethWrapper/wethWrapperLive.t.sol
contract FluidWETHWrapperLiveTest is Test {
    // ============ Mainnet Constants ============ //

    /// WETH contract
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// FluidVault address
    address constant FLUID_VAULT = 0x0C8C77B7FF4c2aF7F6CEBbe67350A490E3DD6cB3;

    // deployed weth wrapper address
    address constant WRAPPER = 0xbf915F77cA55161F84BA807ffd4d25636aa949dD;

    /// Test addresses
    address constant OWNER = address(0x0Ed35B1609Ec45c7079E80d11149a52717e4859A);
    address constant OWNER2 = address(0xdead);

    /// Fork RPC
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    // ============ Contract References ============ //

    /// The proxy we will interact with (cast back to the logic’s ABI)
    FluidWETHWrapper public wrapper;
    IWETH public weth;
    ERC20 public usdc;

    uint64 public nftId;

    // ============ setUp() ============ //

    function setUp() external {
        // 1) Fork mainnet at a certain block
        vm.createSelectFork(MAINNET_RPC_URL, 21724166);

        // 2) Cast the proxy’s address back to the logic ABI
        wrapper = FluidWETHWrapper(payable(address(0xbf915F77cA55161F84BA807ffd4d25636aa949dD)));

        // 3) check current owner
        console.log("`owner()` is:", wrapper.owner());

        // Give test addresses some ETH
        deal(OWNER2, 10 ether);

        // Save references
        weth = IWETH(MAINNET_WETH);
        usdc = ERC20(wrapper.BORROW_TOKEN());

        nftId = wrapper.nftId();
        console.log("Minted NFT ID:", nftId);

        vm.startPrank(OWNER);

        // Transfer ownership to OWNER2 to mirror your original example
        wrapper.transferOwnership(OWNER2);
        console.log("Owner after transfer:", wrapper.owner());

        vm.stopPrank();
    }

    // ============ Tests ============ //

    function testSupply() external {
        vm.startPrank(OWNER2);

        // Wrap 10 ETH into WETH
        weth.deposit{ value: 10 ether }();
        // Approve the wrapper to pull our WETH
        weth.approve(address(wrapper), 10 ether);

        // Now supply via the wrapper
        wrapper.supply(
            MAINNET_WETH, // asset
            10 ether, // amount
            OWNER2, // onBehalfOf
            0 // referralCode
        );

        (uint256 supply, ) = wrapper.getPosition();
        console.log("Supplied amount after supply:", supply);

        vm.stopPrank();
    }

    function testWithdraw() external {
        vm.startPrank(OWNER2);

        // 1) Supply first
        weth.deposit{ value: 10 ether }();
        weth.approve(address(wrapper), 10 ether);
        wrapper.supply(MAINNET_WETH, 10 ether, OWNER2, 0);

        (uint256 supply, ) = wrapper.getPosition();
        console.log("Supplied amount before withdraw:", supply);

        // 2) Withdraw some portion
        uint256 beforeBal = weth.balanceOf(OWNER2);
        wrapper.withdraw(MAINNET_WETH, 3 ether, OWNER2);
        uint256 afterBal = weth.balanceOf(OWNER2);

        console.log("WETH withdrawn:", afterBal - beforeBal);
        assertEq(afterBal - beforeBal, 3 ether);

        (supply, ) = wrapper.getPosition();
        console.log("Supplied amount after withdraw:", supply);

        vm.stopPrank();
    }

    function testMaxWithdraw() external {
        vm.startPrank(OWNER2);

        weth.deposit{ value: 10 ether }();
        weth.approve(address(wrapper), 10 ether);
        wrapper.supply(MAINNET_WETH, 10 ether, OWNER2, 0);

        (uint256 supply, ) = wrapper.getPosition();
        console.log("Supplied amount before withdraw:", supply);

        uint256 beforeBal = weth.balanceOf(OWNER2);
        // Pass in type(uint256).max for a "withdraw all" request
        wrapper.withdraw(MAINNET_WETH, type(uint256).max, OWNER2);
        uint256 afterBal = weth.balanceOf(OWNER2);

        console.log("WETH withdrawn:", afterBal - beforeBal);
        assertGt(afterBal, beforeBal);

        (supply, ) = wrapper.getPosition();
        console.log("Supplied amount after max withdraw:", supply);

        vm.stopPrank();
    }

    function testBorrow() external {
        vm.startPrank(OWNER2);

        // 1) Supply WETH
        weth.deposit{ value: 10 ether }();
        weth.approve(address(wrapper), 10 ether);
        wrapper.supply(MAINNET_WETH, 10 ether, OWNER2, 0);

        uint256 beforeBal = usdc.balanceOf(OWNER2);

        (uint256 supply, uint256 borrowAmountWithInterest) = wrapper.getPosition();
        console.log("Borrow amount before borrow:", borrowAmountWithInterest);

        // 2) Borrow 2 USDC
        wrapper.borrow(
            address(usdc), // asset
            2 * 1e6, // amount
            0, // interestRateMode
            0, // referralCode
            OWNER2 // onBehalfOf
        );

        uint256 afterBal = usdc.balanceOf(OWNER2);

        console.log("USDC balance after borrow:", afterBal - beforeBal);
        assertEq(afterBal - beforeBal, 2 * 1e6);

        (supply, borrowAmountWithInterest) = wrapper.getPosition();
        console.log("Borrow amount after borrow:", borrowAmountWithInterest);

        vm.stopPrank();
    }

    function testRepay() external {
        vm.startPrank(OWNER2);

        // 1) Supply WETH
        weth.deposit{ value: 10 ether }();
        weth.approve(address(wrapper), 10 ether);
        wrapper.supply(MAINNET_WETH, 10 ether, OWNER2, 0);

        // 2) Borrow 2 USDC
        wrapper.borrow(address(usdc), 2 * 1e6, 0, 0, OWNER2);

        (uint256 supply, uint256 borrowAmountWithInterest) = wrapper.getPosition();
        console.log("Borrow amount before repay:", borrowAmountWithInterest);

        // 3) Repay 1 USDC
        usdc.approve(address(wrapper), 1 * 1e6);
        wrapper.repay(address(usdc), 1 * 1e6, 0, OWNER2);

        (supply, borrowAmountWithInterest) = wrapper.getPosition();
        console.log("Borrow amount after repay:", borrowAmountWithInterest);

        vm.stopPrank();
    }

    function testMaxRepay() external {
        vm.startPrank(OWNER2);

        // 1) Supply WETH
        weth.deposit{ value: 10 ether }();
        weth.approve(address(wrapper), 10 ether);
        wrapper.supply(MAINNET_WETH, 10 ether, OWNER2, 0);

        // 2) Borrow 2 USDC
        wrapper.borrow(address(usdc), 2 * 1e6, 0, 0, OWNER2);

        // 3) Check how much we owe
        (uint256 supply, uint256 borrowAmountWithInterest) = wrapper.getPosition();
        console.log("Borrow amount (with interest):", borrowAmountWithInterest);

        // Give ourselves USDC to repay
        deal(address(usdc), OWNER2, borrowAmountWithInterest);

        // 4) Repay max
        usdc.approve(address(wrapper), type(uint256).max);
        wrapper.repay(address(usdc), type(uint256).max, 0, OWNER2);

        (supply, borrowAmountWithInterest) = wrapper.getPosition();

        console.log("Borrow amount after repay:", borrowAmountWithInterest);
        assertEq(borrowAmountWithInterest, 0);

        vm.stopPrank();
    }
}
