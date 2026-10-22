//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FluidPaybackOnBehalfAuth } from "contracts/config/paybackOnBehalfAuth/main.sol";
import { Error as ConfigError } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { Error as LiquidityError } from "contracts/liquidity/error.sol";
import { ErrorTypes as LiquidityErrorTypes } from "contracts/liquidity/errorTypes.sol";
import { IFluidLiquidity } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidLiquidityUserModule } from "contracts/liquidity/userModule/main.sol";
import { Structs as AdminModuleStructs } from "contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "contracts/liquidity/adminModule/main.sol";
import { MockProtocol } from "contracts/mocks/mockProtocol.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";

/// To test run: forge test -vvv --match-path test/foundry/config/paybackOnBehalfAuth.t.sol
contract PaybackOnBehalfAuthTest is LiquidityBaseTest {
    FluidPaybackOnBehalfAuth internal handler;
    MockProtocol internal borrower;
    address internal constant MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal notMultisig;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event LogPaybackOnBehalf(address indexed token, int256 paybackAmount, address indexed onBehalf);

    function setUp() public virtual override {
        super.setUp();

        notMultisig = makeAddr("notMultisig");

        // re-register user module with operateOnBehalfOf selector
        vm.prank(admin);
        liquidity.removeImplementation(address(userModule));
        bytes4[] memory newUserSigs = new bytes4[](2);
        newUserSigs[0] = FluidLiquidityUserModule.operate.selector;
        newUserSigs[1] = FluidLiquidityUserModule.operateOnBehalfOf.selector;
        vm.prank(admin);
        liquidity.addImplementation(address(userModule), newUserSigs);

        // deploy handler
        handler = new FluidPaybackOnBehalfAuth(address(liquidity));

        // set handler as auth on liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // set up default mockProtocol allowances (not set in LiquidityBaseTest, only in LiquidityUserModuleBaseTest)
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // set up borrower (a mock protocol that will have debt)
        borrower = new MockProtocol(address(liquidity));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(borrower));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(borrower));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(borrower));

        // set up handler with borrow config so it can pay back on behalf
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(handler));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(handler));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(handler));

        // fund borrower for supply operations
        vm.prank(alice);
        USDC.transfer(address(borrower), 1e40);
        vm.prank(alice);
        IERC20(address(DAI)).transfer(address(borrower), 1e40);
        vm.deal(address(borrower), 1e40);

        // fund multisig with tokens and approve handler for payback via transferFrom
        vm.prank(alice);
        USDC.transfer(MULTISIG, 1e40);
        vm.prank(alice);
        IERC20(address(DAI)).transfer(MULTISIG, 1e40);
        vm.deal(MULTISIG, 1e40);

        vm.prank(MULTISIG);
        USDC.approve(address(handler), type(uint256).max);
        vm.prank(MULTISIG);
        IERC20(address(DAI)).approve(address(handler), type(uint256).max);
    }

    // ======== Constructor tests ========

    function test_constructor_RevertIfZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__InvalidParams)
        );
        new FluidPaybackOnBehalfAuth(address(0));
    }

    function test_constructor_SetsLiquidity() public {
        FluidPaybackOnBehalfAuth h = new FluidPaybackOnBehalfAuth(address(liquidity));
        assertEq(address(h.LIQUIDITY()), address(liquidity));
    }

    function test_constructor_SetsMultisig() public {
        assertEq(handler.TEAM_MULTISIG(), MULTISIG);
    }

    // ======== onlyMultisig modifier ========

    function test_paybackOnBehalf_RevertIfNotMultisig() public {
        vm.prank(notMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__Unauthorized)
        );
        handler.paybackOnBehalf(address(USDC), -int256(1 ether), address(borrower));
    }

    function test_rescueTokens_RevertIfNotMultisig() public {
        vm.prank(notMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__Unauthorized)
        );
        handler.rescueTokens(address(USDC), 1 ether, alice);
    }

    // ======== paybackOnBehalf validation ========

    function test_paybackOnBehalf_RevertIfAmountPositive() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__InvalidParams)
        );
        handler.paybackOnBehalf(address(USDC), int256(1 ether), address(borrower));
    }

    function test_paybackOnBehalf_RevertIfAmountZero() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__InvalidParams)
        );
        handler.paybackOnBehalf(address(USDC), int256(0), address(borrower));
    }

    function test_paybackOnBehalf_RevertIfOnBehalfZeroAddress() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__OperateOnBehalfAddressZero
            )
        );
        handler.paybackOnBehalf(address(USDC), -int256(1 ether), address(0));
    }

    // ======== paybackOnBehalf ERC20 ========

    function test_paybackOnBehalf_ERC20_Success() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        uint256 multisigBalanceBefore = USDC.balanceOf(MULTISIG);

        vm.prank(MULTISIG);
        (uint256 supplyExPrice, uint256 borrowExPrice) = handler.paybackOnBehalf(
            address(USDC),
            -int256(paybackAmount),
            address(borrower)
        );

        assertGt(supplyExPrice, 0, "supply exchange price should be > 0");
        assertGt(borrowExPrice, 0, "borrow exchange price should be > 0");

        uint256 multisigBalanceAfter = USDC.balanceOf(MULTISIG);
        assertEq(
            multisigBalanceBefore - multisigBalanceAfter,
            paybackAmount,
            "multisig balance should decrease by payback amount"
        );
    }

    function test_paybackOnBehalf_ERC20_DAI() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(DAI), alice, supplyAmount);
        _borrow(borrower, address(DAI), bob, borrowAmount);

        uint256 multisigBalanceBefore = IERC20(address(DAI)).balanceOf(MULTISIG);

        vm.prank(MULTISIG);
        handler.paybackOnBehalf(address(DAI), -int256(paybackAmount), address(borrower));

        uint256 multisigBalanceAfter = IERC20(address(DAI)).balanceOf(MULTISIG);
        assertEq(
            multisigBalanceBefore - multisigBalanceAfter,
            paybackAmount,
            "multisig DAI balance should decrease by payback amount"
        );
    }

    function test_paybackOnBehalf_ERC20_EmitsEvent() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        vm.expectEmit(true, true, false, true);
        emit LogPaybackOnBehalf(address(USDC), -int256(paybackAmount), address(borrower));

        vm.prank(MULTISIG);
        handler.paybackOnBehalf(address(USDC), -int256(paybackAmount), address(borrower));
    }

    // ======== paybackOnBehalf Native ========

    function test_paybackOnBehalf_Native_Success() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        uint256 liquidityBalanceBefore = address(liquidity).balance;

        vm.prank(MULTISIG);
        vm.deal(MULTISIG, paybackAmount);
        handler.paybackOnBehalf{ value: paybackAmount }(NATIVE_TOKEN, -int256(paybackAmount), address(borrower));

        assertEq(
            address(liquidity).balance,
            liquidityBalanceBefore + paybackAmount,
            "liquidity native balance should increase"
        );
    }

    function test_paybackOnBehalf_Native_EmitsEvent() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        vm.expectEmit(true, true, false, true);
        emit LogPaybackOnBehalf(NATIVE_TOKEN, -int256(paybackAmount), address(borrower));

        vm.prank(MULTISIG);
        vm.deal(MULTISIG, paybackAmount);
        handler.paybackOnBehalf{ value: paybackAmount }(NATIVE_TOKEN, -int256(paybackAmount), address(borrower));
    }

    function test_paybackOnBehalf_Native_RevertIfMsgValueTooLow() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        vm.prank(MULTISIG);
        vm.deal(MULTISIG, paybackAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        handler.paybackOnBehalf{ value: paybackAmount - 1 }(NATIVE_TOKEN, -int256(paybackAmount), address(borrower));
    }

    function test_paybackOnBehalf_Native_RevertIfMsgValueTooHigh() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;
        uint256 excessiveMsgValue = paybackAmount + 0.01 ether;

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        vm.prank(MULTISIG);
        vm.deal(MULTISIG, excessiveMsgValue);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        handler.paybackOnBehalf{ value: excessiveMsgValue }(NATIVE_TOKEN, -int256(paybackAmount), address(borrower));
    }

    function test_paybackOnBehalf_ERC20_RevertIfMsgValueSent() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        vm.prank(MULTISIG);
        vm.deal(MULTISIG, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__MsgValueForNonNativeToken
            )
        );
        handler.paybackOnBehalf{ value: 1 ether }(address(USDC), -int256(paybackAmount), address(borrower));
    }

    // ======== liquidityCallback ========

    function test_liquidityCallback_RevertIfNotLiquidity() public {
        vm.prank(notMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__Unauthorized)
        );
        handler.liquidityCallback(address(USDC), 1 ether, new bytes(0));
    }

    function test_liquidityCallback_RevertIfCalledByMultisig() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__Unauthorized)
        );
        handler.liquidityCallback(address(USDC), 1 ether, new bytes(0));
    }

    function test_liquidityCallback_RevertIfReentrancyNotEntered() public {
        // even when called by the actual Liquidity contract, callback must revert
        // if not triggered as part of a paybackOnBehalf flow (reentrancy status not entered)
        vm.prank(address(liquidity));
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__Unauthorized)
        );
        handler.liquidityCallback(address(USDC), 1 ether, new bytes(0));
    }

    // ======== rescueTokens ERC20 ========

    function test_rescueTokens_ERC20_Success() public {
        uint256 amount = 100e6;
        vm.prank(alice);
        USDC.transfer(address(handler), amount);

        uint256 aliceBalanceBefore = USDC.balanceOf(alice);

        vm.prank(MULTISIG);
        handler.rescueTokens(address(USDC), amount, alice);

        assertEq(USDC.balanceOf(alice), aliceBalanceBefore + amount, "alice should receive rescued tokens");
    }

    function test_rescueTokens_ERC20_DAI() public {
        uint256 amount = 100 ether;
        vm.prank(alice);
        IERC20(address(DAI)).transfer(address(handler), amount);

        uint256 aliceBalanceBefore = IERC20(address(DAI)).balanceOf(alice);

        vm.prank(MULTISIG);
        handler.rescueTokens(address(DAI), amount, alice);

        assertEq(
            IERC20(address(DAI)).balanceOf(alice),
            aliceBalanceBefore + amount,
            "alice should receive rescued DAI"
        );
    }

    function test_rescueTokens_RevertIfToZeroAddress() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__InvalidParams)
        );
        handler.rescueTokens(address(USDC), 100e6, address(0));
    }

    // ======== rescueTokens Native ========

    function test_rescueTokens_Native_Success() public {
        uint256 amount = 1 ether;
        vm.deal(address(handler), amount);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(MULTISIG);
        handler.rescueTokens(NATIVE_TOKEN, amount, alice);

        assertEq(alice.balance, aliceBalanceBefore + amount, "alice should receive rescued native tokens");
    }

    function test_rescueTokens_Native_RevertIfToZeroAddress() public {
        vm.prank(MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(ConfigError.FluidConfigError.selector, ErrorTypes.PaybackOnBehalfAuth__InvalidParams)
        );
        handler.rescueTokens(NATIVE_TOKEN, 1 ether, address(0));
    }

    // ======== receive ========

    function test_receive_AcceptsEth() public {
        uint256 balanceBefore = address(handler).balance;
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success, ) = address(handler).call{ value: 1 ether }("");
        assertTrue(success, "should accept ETH");
        assertEq(address(handler).balance, balanceBefore + 1 ether);
    }
}
