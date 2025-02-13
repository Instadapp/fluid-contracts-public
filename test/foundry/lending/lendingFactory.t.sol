//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { fTokenNativeUnderlying } from "../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { Events as LendingFactoryEvents } from "../../../contracts/protocols/lending/lendingFactory/events.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { FluidLiquidityProxy } from "../../../contracts/liquidity/proxy.sol";
import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { RandomAddresses } from "../utils/RandomAddresses.sol";

contract LendingFactoryTest is LiquidityBaseTest, LendingFactoryEvents, RandomAddresses {
    FluidLendingFactory factory;

    IFluidLiquidity liquidityProxy;

    function setUp() public virtual override {
        // native underlying tests must run in fork for WETH support
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        super.setUp();
        liquidityProxy = IFluidLiquidity(address(liquidity));

        factory = new FluidLendingFactory(liquidityProxy, admin);
    }

    function test_setAuth_RevertIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        factory.setAuth(address(alice), true);
    }

    function test_setAuth_RevertIfNotValidAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__ZeroAddress)
        );
        factory.setAuth(address(0), true);
    }

    function test_setAuth() public {
        vm.expectEmit(true, true, true, true);
        emit LendingFactoryEvents.LogSetAuth(address(alice), true);
        vm.prank(admin);
        factory.setAuth(address(alice), true);

        assertEq(factory.isAuth(address(alice)), true);
        vm.expectEmit(false, false, false, false);
        emit LendingFactoryEvents.LogSetAuth(address(alice), false);

        vm.prank(admin);
        factory.setAuth(address(alice), false);

        assertEq(factory.isAuth(address(alice)), false);
    }

    function test_setDeployer_RevertIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        factory.setDeployer(address(alice), true);
    }

    function test_setDeployer_RevertIfNotValidAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__ZeroAddress)
        );
        factory.setDeployer(address(0), true);
    }

    function test_setDeployer() public {
        vm.expectEmit(true, true, true, true);
        emit LendingFactoryEvents.LogSetDeployer(address(alice), true);
        vm.prank(admin);
        factory.setDeployer(address(alice), true);

        assertEq(factory.isDeployer(address(alice)), true);
        vm.expectEmit(false, false, false, false);
        emit LendingFactoryEvents.LogSetDeployer(address(alice), false);

        vm.prank(admin);
        factory.setDeployer(address(alice), false);

        assertEq(factory.isDeployer(address(alice)), false);
    }

    function test_setFTokenCreationCode() public {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        assertEq(factory.fTokenCreationCode("fToken"), type(fToken).creationCode);
    }

    function test_fTokenTypes() public {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", new bytes(0));

        string[] memory fTokenTypes = factory.fTokenTypes();
        assertEq(fTokenTypes.length, 0);

        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);

        fTokenTypes = factory.fTokenTypes();
        assertEq(fTokenTypes.length, 1);
        assertEq(fTokenTypes[0], "NativeUnderlying");

        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);

        fTokenTypes = factory.fTokenTypes();
        assertEq(fTokenTypes.length, 2);
        assertEq(fTokenTypes[0], "NativeUnderlying");
        assertEq(fTokenTypes[1], "fToken");
    }
}

contract LendingFactoryCreateTokenTest is LendingFactoryTest {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
    }

    function test_createToken_UnsetToken_RevertIffTokenTypeNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__InvalidParams)
        );
        vm.prank(admin);
        factory.createToken(address(USDC), "someFTokenType", false);
    }

    function test_createToken_RevertIfTokenAlreadyExists() public {
        vm.prank(admin);
        factory.createToken(address(USDC), "fToken", false);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__TokenExists)
        );
        vm.prank(admin);
        factory.createToken(address(USDC), "fToken", false);
    }

    function test_createToken_RevertIfLiquidityNotConfigured() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__LiquidityNotConfigured)
        );
        vm.prank(admin);
        factory.createToken(address(randomAddresses[0]), "fToken", false);
    }

    function test_createToken_RevertIfUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__Unauthorized)
        );
        vm.prank(alice);
        factory.createToken(address(randomAddresses[0]), "fToken", false);
    }

    function test_createToken_RevertIfAuth() public {
        vm.prank(admin);
        factory.setAuth(alice, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.LendingFactory__Unauthorized)
        );
        vm.prank(alice);
        factory.createToken(address(randomAddresses[0]), "fToken", false);
    }

    function test_createToken_AsDeployer() public {
        vm.prank(admin);
        factory.setDeployer(alice, true);

        vm.prank(alice);
        address token = factory.createToken(address(USDC), "fToken", false);
        assertTrue(token != address(0));
    }

    function test_createToken_fToken() public {
        uint256 expectedTokensArrayLength = 1;
        vm.expectEmit(false, true, true, false);
        emit LendingFactoryEvents.LogTokenCreated(address(0), address(USDC), expectedTokensArrayLength, "fToken");
        vm.prank(admin);
        address token = factory.createToken(address(USDC), "fToken", false);

        assertTrue(token != address(0));
        assertEq(IERC20Metadata(token).name(), "Fluid USDC");
        assertEq(IERC20Metadata(token).symbol(), "fUSDC");

        address[] memory allTokens = factory.allTokens();
        assertEq(allTokens.length, expectedTokensArrayLength);
        assertEq(allTokens[0], token);
    }

    function test_createToken_NativeUnderlyingToken() public {
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);

        address expectedTokenAddress = factory.computeToken(address(WETH_ADDRESS), "NativeUnderlying");
        uint256 expectedTokensArrayLength = 1;
        vm.expectEmit(true, true, true, true);
        emit LendingFactoryEvents.LogTokenCreated(
            expectedTokenAddress,
            address(WETH_ADDRESS),
            expectedTokensArrayLength,
            "NativeUnderlying"
        );

        vm.prank(admin);
        address token = factory.createToken(address(WETH_ADDRESS), "NativeUnderlying", true);

        assertEq(expectedTokenAddress, token);
        assertTrue(token != address(0));
        assertEq(IERC20Metadata(token).name(), "Fluid Wrapped Ether");
        assertEq(IERC20Metadata(token).symbol(), "fWETH");

        address[] memory allTokens = factory.allTokens();
        assertEq(allTokens.length, expectedTokensArrayLength);
        assertEq(allTokens[0], token);

        // todo assert token has no signature deposits
    }

    function test_allTokens() public {
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", type(fTokenNativeUnderlying).creationCode);

        vm.prank(admin);
        address token1 = factory.createToken(address(WETH_ADDRESS), "NativeUnderlying", true);
        vm.prank(admin);
        address token2 = factory.createToken(address(DAI), "fToken", false);

        address[] memory allTokens = factory.allTokens();
        assertEq(allTokens.length, 2);
        assertEq(allTokens[0], token1);
        assertEq(allTokens[1], token2);

        // todo assert token has no signature deposits
    }
}
