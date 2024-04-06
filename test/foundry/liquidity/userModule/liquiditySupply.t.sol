//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "./liquidityOperate.t.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";

import "forge-std/console2.sol";

contract LiquidityUserModuleSupplyTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            alice,
            address(0),
            address(0),
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT, 0, 0, 0),
            _simulateExchangePrices(resolver, address(USDC), supplyExchangePrice, borrowExchangePrice),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), address(USDC), 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleSupplyTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            alice,
            address(0),
            address(0),
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT, 0, 0),
            _simulateExchangePricesWithRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                0 // borrowRatio
            ),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), address(USDC), 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleSupplyTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            alice,
            address(0),
            address(0),
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT, 0, 0, 0),
            _simulateExchangePrices(resolver, NATIVE_TOKEN_ADDRESS, supplyExchangePrice, borrowExchangePrice),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), NATIVE_TOKEN_ADDRESS, 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleSupplyTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            alice,
            address(0),
            address(0),
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT, 0, 0),
            _simulateExchangePricesWithRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                0 // borrowRatio
            ),
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(resolver, address(mockProtocol), NATIVE_TOKEN_ADDRESS, 0, 0, 0),
            true
        );
    }
}

contract LiquidityUserModuleSupplyTests is LiquidityUserModuleBaseTest {
    function test_operate_RevertSupplyOperateAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).max) + 1,
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_RevertSupplyNoApprovalForTransfer() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        vm.prank(alice);
        USDC.approve(address(mockProtocol), 0);

        vm.expectRevert("ERC20: insufficient allowance");

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertSupplyNotEnoughTransferIn() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        mockProtocol.setTransferInsufficientMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertSupplyTransferTooMuch() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        mockProtocol.setTransferExcessMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertSupplyNotEnoughTransferInNative() public {
        uint256 balanceBefore = alice.balance;

        mockProtocol.setTransferInsufficientMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate{ value: DEFAULT_SUPPLY_AMOUNT }(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter, balanceBefore);
    }

    function test_operate_RevertSupplyTransferTooMuchNative() public {
        uint256 balanceBefore = alice.balance;

        vm.deal(address(mockProtocol), 100 ether);

        mockProtocol.setTransferExcessMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TransferAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate{ value: DEFAULT_SUPPLY_AMOUNT }(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        uint256 balanceAfter = alice.balance;
        assertEq(balanceAfter, balanceBefore);
    }
}

contract LiquidityUserModuleSupplyTestsInterestFree is LiquidityUserModuleSupplyTests {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
    }
}
