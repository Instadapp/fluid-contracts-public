// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {Events} from "../../../../contracts/periphery/buyback/events.sol";
import {FluidBuyback} from "../../../../contracts/periphery/buyback/main.sol";
import {FluidBuybackProxy} from "../../../../contracts/periphery/buyback/proxy.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

interface IFluidBuyback {
    function getOwner() external view returns (address);
    function isRebalancer(address rebalancer_) external view returns (bool);
    function getBuybackDSA() external view returns (address);
    function transferOwnership(address owner_) external;
    function updateRebalancer(address rebalancer_, bool isActive_) external;
    function collectFluidTokensToTreasury(uint256 amount_) external;
    function collectTokensToTreasury(address token_, uint256 amount_) external;
    function initialize(address owner_, address[] memory rebalancers_) external;
}

contract FluidBuybackTest is Test, Events {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    FluidBuybackProxy public buybackProxy;
    FluidBuyback public buybackImplementation;

    address internal constant OWNER_ADDRESS = address(10);
    address internal constant REBALANCER_ADDRESS = address(11);
    address internal constant TREASURY_ADDRESS = 0x28849D2b63fA8D361e5fc15cB8aBB13019884d09;
    address internal constant INSTA_DEX_SIMULATION_ADDRESS = 0x49B159E897b7701769B1E66061C8dcCd7240c461;

    address internal constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant FLUID_TOKEN_ADDRESS = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public {
        // Deploy the buyback implementation
        buybackImplementation = new FluidBuyback();

        address[] memory rebalancers_ = new address[](1);
        rebalancers_[0] = REBALANCER_ADDRESS;

        // Deploy the buyback proxy and initialize
        buybackProxy = new FluidBuybackProxy(
            address(buybackImplementation),
            abi.encodeWithSignature("initialize(address,address[])", OWNER_ADDRESS, rebalancers_)
        );
    }

    function test_getOwner() public view {
        assertEq(IFluidBuyback(address(buybackProxy)).getOwner(), OWNER_ADDRESS);
    }

    function test_isRebalancer() public view {
        assertEq(IFluidBuyback(address(buybackProxy)).isRebalancer(REBALANCER_ADDRESS), true);
    }

    function test_updateRebalancer() public {
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRebalancer(address(2), true);

        vm.prank(OWNER_ADDRESS);
        IFluidBuyback(address(buybackProxy)).updateRebalancer(address(2), true);
        assertEq(IFluidBuyback(address(buybackProxy)).isRebalancer(address(2)), true);
    }

    function test_collectFluidTokensToTreasury() public {
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit LogCollectFluidTokensToTreasury(1000000000000000000);

        // Top up the buyback proxy with some Fluid tokens
        uint256 initialBalance = IERC20Upgradeable(FLUID_TOKEN_ADDRESS).balanceOf(TREASURY_ADDRESS);
        deal(FLUID_TOKEN_ADDRESS, address(buybackProxy), 1000000000000000000);

        vm.prank(REBALANCER_ADDRESS);
        IFluidBuyback(address(buybackProxy)).collectFluidTokensToTreasury(1000000000000000000);

        // Check the balance of the tokens in the treasury
        assertEq(
            IERC20Upgradeable(FLUID_TOKEN_ADDRESS).balanceOf(TREASURY_ADDRESS), initialBalance + 1000000000000000000
        );
    }

    function test_collectTokensToTreasury() public {
        uint256 initialBalance = IERC20Upgradeable(USDT_ADDRESS).balanceOf(TREASURY_ADDRESS);
        deal(USDT_ADDRESS, address(buybackProxy), 1000000000000000000);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit LogCollectTokensToTreasury(USDT_ADDRESS, 1000000000000000000);

        // Collect the tokens to the treasury
        vm.prank(OWNER_ADDRESS);
        IFluidBuyback(address(buybackProxy)).collectTokensToTreasury(USDT_ADDRESS, 1000000000000000000);

        assertEq(IERC20Upgradeable(USDT_ADDRESS).balanceOf(TREASURY_ADDRESS), initialBalance + 1000000000000000000);
    }

    function test_collectNativeTokensToTreasury() public {
        uint256 initialBalance = TREASURY_ADDRESS.balance;
        deal(address(buybackProxy), 1000000000000000000);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit LogCollectTokensToTreasury(ETH_ADDRESS, 1000000000000000000);

        vm.prank(OWNER_ADDRESS);
        IFluidBuyback(address(buybackProxy)).collectTokensToTreasury(ETH_ADDRESS, 1000000000000000000);

        assertEq(TREASURY_ADDRESS.balance, initialBalance + 1000000000000000000);
    }
}

// forge test --fork-url https://virtual.mainnet.eu.rpc.tenderly.co/d091343c-b6cf-4a47-a22f-1a9f3a4a22d0 --match-contract FluidBuybackTest -vvv
