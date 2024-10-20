//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestERC20Dec6 } from "../../testERC20Dec6.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";

import "forge-std/console2.sol";

/// @notice implements a series of tests that should run for all types of operations: supply, withdraw, borrow, payback
abstract contract LiquidityUserModuleOperateTestSuite is LiquidityUserModuleBaseTest {
    IERC20 internal _token;
    int256 internal _supplyAmount;
    int256 internal _borrowAmount;
    address internal _fromUser;
    address internal _withdrawTo;
    address internal _borrowTo;
    uint256 internal _totalAmounts;
    uint256 internal _exchangePricesAndConfig;
    uint256 internal _supplyExchangePrice;
    uint256 internal _borrowExchangePrice;
    uint256 internal _userSupplyData;
    uint256 internal _userBorrowData;
    bool internal _expectTransferEvents;

    function _setTestOperateParams(
        address token,
        int256 supplyAmount,
        int256 borrowAmount,
        address fromUser,
        address withdrawTo,
        address borrowTo,
        uint256 totalAmounts,
        uint256 exchangePricesAndConfig,
        uint256 supplyExchangePrice,
        uint256 borrowExchangePrice,
        uint256 userSupplyData,
        uint256 userBorrowData,
        bool expectTransferEvents
    ) internal {
        _token = IERC20(token);
        _supplyAmount = supplyAmount;
        _borrowAmount = borrowAmount;
        _fromUser = fromUser;
        _withdrawTo = withdrawTo;
        _borrowTo = borrowTo;
        _totalAmounts = totalAmounts;
        _exchangePricesAndConfig = exchangePricesAndConfig;
        _supplyExchangePrice = supplyExchangePrice;
        _borrowExchangePrice = borrowExchangePrice;
        _userSupplyData = userSupplyData;
        _userBorrowData = userBorrowData;
        _expectTransferEvents = expectTransferEvents;
    }

    function _readTokenBalance(address user) private view returns (uint256) {
        if (address(_token) == NATIVE_TOKEN_ADDRESS) {
            return user.balance;
        } else {
            return _token.balanceOf(user);
        }
    }

    function _getMsgValueAmount(int256 supplyAmount, int256 borrowAmount) private view returns (uint256 value) {
        if (address(_token) == NATIVE_TOKEN_ADDRESS) {
            value += supplyAmount > 0 ? uint256(supplyAmount) : 0;
            value += borrowAmount < 0 ? uint256(-borrowAmount) : 0;
        }
    }

    function test_operate_ReturnValues() public {
        _runDefaultOperateReturnValuesTest();
    }

    function test_operate_StorageValues() public {
        _runDefaultOperateStorageValuesTest();
    }

    function test_operate_Balances() public {
        _runDefaultOperateBalancesTest();
    }

    function test_operate_LogOperate() public {
        _runDefaultLogOperateTest();
    }

    function test_operate_RevertUserNotDefined() public {
        _runDefaultRevertUserNotDefinedTest();
    }

    function test_operate_RevertUserPaused() public {
        _runDefaultRevertUserPausedTest();
    }

    /***********************************|
    |         RUN TEST METHODS          | 
    |__________________________________*/

    function _runDefaultOperateReturnValuesTest() internal {
        vm.prank(_fromUser);
        (uint256 supplyExchangePrice, uint256 borrowExchangePrice) = mockProtocol.operate{
            value: _getMsgValueAmount(_supplyAmount, _borrowAmount)
        }(address(_token), _supplyAmount, _borrowAmount, _withdrawTo, _borrowTo, abi.encode(_fromUser));

        assertEq(supplyExchangePrice, _supplyExchangePrice);
        assertEq(borrowExchangePrice, _borrowExchangePrice);
    }

    function _runDefaultOperateStorageValuesTest() internal {
        // tests for updates of userSupplyData / userBorrowData / exchangePricesAndConfig / totalAmounts in storage

        vm.prank(_fromUser);
        mockProtocol.operate{ value: _getMsgValueAmount(_supplyAmount, _borrowAmount) }(
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            abi.encode(_fromUser)
        );

        // sort of integration test with resolver together to check values in storage:
        assertEq(_exchangePricesAndConfig, resolver.getExchangePricesAndConfig(address(_token)));

        assertEq(_totalAmounts, resolver.getTotalAmounts(address(_token)));

        assertEq(_userSupplyData, resolver.getUserSupply(address(mockProtocol), address(_token)));

        assertEq(_userBorrowData, resolver.getUserBorrow(address(mockProtocol), address(_token)));
    }

    function _runDefaultOperateBalancesTest() internal {
        uint256 balanceBeforeFromUser = _readTokenBalance(_fromUser);
        uint256 balanceBeforeWithdrawTo = _readTokenBalance(_withdrawTo);
        uint256 balanceBeforeBorrowTo = _readTokenBalance(_borrowTo);

        vm.prank(_fromUser);
        mockProtocol.operate{ value: _getMsgValueAmount(_supplyAmount, _borrowAmount) }(
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            abi.encode(_fromUser)
        );

        // assert balance changes
        uint256 expectedBalanceFromUser = balanceBeforeFromUser;
        if (_supplyAmount > 0) {
            expectedBalanceFromUser -= uint256(_supplyAmount);
        }
        if (_borrowAmount < 0) {
            expectedBalanceFromUser -= uint256(-_borrowAmount);
        }
        if (_withdrawTo == _fromUser && _supplyAmount < 0) {
            expectedBalanceFromUser += uint256(-_supplyAmount);
        }
        if (_borrowTo == _fromUser && _borrowAmount > 0) {
            expectedBalanceFromUser += uint256(_borrowAmount);
        }

        uint256 expectedBalanceWithdrawTo = balanceBeforeWithdrawTo;
        if (_withdrawTo == _fromUser) {
            expectedBalanceWithdrawTo = expectedBalanceFromUser;
        } else {
            if (_supplyAmount < 0) {
                expectedBalanceWithdrawTo += uint256(-_supplyAmount);
            }
            if (_borrowTo == _withdrawTo && _borrowAmount > 0) {
                expectedBalanceWithdrawTo += uint256(_borrowAmount);
            }
        }

        uint256 expectedBalanceBorrowTo = balanceBeforeBorrowTo;
        if (_borrowTo == _fromUser) {
            expectedBalanceBorrowTo = expectedBalanceFromUser;
        } else if (_borrowTo == _withdrawTo) {
            expectedBalanceBorrowTo = expectedBalanceWithdrawTo;
        } else {
            if (_borrowAmount > 0) {
                expectedBalanceBorrowTo += uint256(_borrowAmount);
            }
        }

        uint256 balanceAfterFromUser = _readTokenBalance(_fromUser);
        uint256 balanceAfterWithdrawTo = _readTokenBalance(_withdrawTo);
        uint256 balanceAfterBorrowTo = _readTokenBalance(_borrowTo);

        assertEq(balanceAfterFromUser, expectedBalanceFromUser);
        assertEq(balanceAfterWithdrawTo, expectedBalanceWithdrawTo);
        assertEq(balanceAfterBorrowTo, expectedBalanceBorrowTo);
    }

    function _runDefaultLogOperateTest() internal {
        if (_expectTransferEvents && address(_token) != NATIVE_TOKEN_ADDRESS) {
            // expect transfer of _token to happen from _fromUser to Liquidity for supply
            if (_supplyAmount > 0 && _borrowAmount < 0) {
                // supply and payback
                vm.expectEmit(true, true, false, true, address(_token));
                emit Transfer(_fromUser, address(liquidity), uint256(_supplyAmount + (-_borrowAmount)));
            } else if (_supplyAmount > 0) {
                // supply
                vm.expectEmit(true, true, false, true, address(_token));
                emit Transfer(_fromUser, address(liquidity), uint256(_supplyAmount));
            }

            // expect transfer of _token to happen from _fromUser to Liquidity for payback, if not covered
            // by other combined transfers
            if (_supplyAmount <= 0 && _borrowAmount < 0) {
                vm.expectEmit(true, true, false, true, address(_token));
                emit Transfer(_fromUser, address(liquidity), uint256(-_borrowAmount));
            }

            // expect transfer of _token to happen from Liquidity to _withdrawToUser
            if (_supplyAmount < 0 && _borrowAmount > 0 && _withdrawTo == _borrowTo) {
                // withdraw and borrow to same user
                vm.expectEmit(true, true, false, true, address(_token));
                emit Transfer(address(liquidity), _withdrawTo, uint256((-_supplyAmount) + _borrowAmount));
            } else {
                if (_supplyAmount < 0) {
                    // withdraw
                    vm.expectEmit(true, true, false, true, address(_token));
                    emit Transfer(address(liquidity), _withdrawTo, uint256(-_supplyAmount));
                }

                if (_borrowAmount > 0) {
                    // borrow
                    vm.expectEmit(true, true, false, true, address(_token));
                    emit Transfer(address(liquidity), _borrowTo, uint256(_borrowAmount));
                }
            }
        }

        // set expected event
        vm.expectEmit(true, true, true, true);
        emit LogOperate(
            address(mockProtocol),
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            _totalAmounts,
            _exchangePricesAndConfig
        );

        // execute operate
        vm.prank(_fromUser);
        mockProtocol.operate{ value: _getMsgValueAmount(_supplyAmount, _borrowAmount) }(
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            abi.encode(_fromUser)
        );
    }

    function _runDefaultRevertUserNotDefinedTest() internal {
        if (address(_token) != NATIVE_TOKEN_ADDRESS) {
            _setApproval(_token, address(mockProtocolUnauthorized), _fromUser);
        }

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserNotDefined)
        );

        // execute operate
        vm.prank(_fromUser);
        mockProtocolUnauthorized.operate{ value: _getMsgValueAmount(_supplyAmount, _borrowAmount) }(
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            abi.encode(_fromUser)
        );
    }

    function _runDefaultRevertUserPausedTest() internal {
        if (_supplyAmount != 0 && _borrowAmount != 0) {
            _pauseUser(address(liquidity), admin, address(mockProtocol), address(_token), address(_token));
        } else if (_supplyAmount != 0) {
            _pauseUser(address(liquidity), admin, address(mockProtocol), address(_token), address(0));
        } else if (_borrowAmount != 0) {
            _pauseUser(address(liquidity), admin, address(mockProtocol), address(0), address(_token));
        } else {
            revert("catch unsupported test case should test revert operate amounts zero explicitly");
        }

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));

        // execute operate
        vm.prank(_fromUser);
        mockProtocol.operate{ value: _getMsgValueAmount(_supplyAmount, _borrowAmount) }(
            address(_token),
            _supplyAmount,
            _borrowAmount,
            _withdrawTo,
            _borrowTo,
            abi.encode(_fromUser)
        );
    }
}

contract LiquidityUserModuleOperateTests is LiquidityUserModuleBaseTest {
    function test_operate_RevertOperateAmountsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(0), address(0), address(0), abi.encode(alice));
    }

    function test_operate_RevertMsgValueForNonNativeToken() public {
        // expect revert: there should not be msg.value if the token is not the native token
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MsgValueForNonNativeToken)
        );

        vm.prank(alice);
        mockProtocol.operate{ value: DEFAULT_SUPPLY_AMOUNT }(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_RevertReentrancy() public {
        mockProtocol.setReentrancyFromCallback(true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.LiquidityHelpers__Reentrancy)
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
    }

    function test_operate_AfterUnpaused() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        _pauseUser(address(liquidity), admin, address(mockProtocol), address(USDC), address(0));
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
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

        // now unpause and execute again
        _unpauseUser(address(liquidity), admin, address(mockProtocol), address(USDC), address(0));
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
        assertEq(balanceAfter, balanceBefore - DEFAULT_SUPPLY_AMOUNT);
    }
}

contract LiquidityUserModuleOperateTotalAmountsOverflowTests is LiquidityUserModuleBaseTest {
    function test_operate_RevertValueOverflowTotalSupplyWithInterest() public {
        // supply max
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_SUPPLY
            )
        );

        // supply above max
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e28), int256(0), address(0), address(0), abi.encode(alice));
    }

    function test_operate_WithdrawWhenAboveTotalSupplyWithInterestLimit() public {
        // supply max
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
        // simulate total amounts to be > max
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(uint256(int256(type(int128).max) + 1e30), 0, 0, 0);
        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        // expect deposit to revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_SUPPLY
            )
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e28), int256(0), address(0), address(0), abi.encode(alice));

        // expect withdraw to work
        vm.prank(alice);
        mockProtocol.operate(address(USDC), -int256(1e28), int256(0), alice, address(0), abi.encode(alice));
    }

    function test_operate_RevertValueOverflowTotalSupplyInterestFree() public {
        // supply max
        vm.prank(alice);
        mockProtocolInterestFree.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_SUPPLY
            )
        );

        // supply above max
        vm.prank(alice);
        mockProtocolInterestFree.operate(
            address(USDC),
            int256(1e28),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
    }

    // Note supply interest free can never go above limit

    function test_operate_RevertValueOverflowTotalBorrowWithInterest() public {
        TestERC20Dec6(address(USDC)).mint(alice, 1e72);

        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e70,
            maxDebtCeiling: 1e71
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // supply max
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
        // borrow max
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(type(int128).max), address(0), alice, abi.encode(alice));

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_BORROW
            )
        );

        // borrow above max
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));
    }

    function test_operate_PaybackwWhenAboveTotalBorrowWithInterestLimit() public {
        TestERC20Dec6(address(USDC)).mint(alice, 1e72);
        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e70,
            maxDebtCeiling: 1e71
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // supply max
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
        // borrow max
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(type(int128).max), address(0), alice, abi.encode(alice));
        // simulate total amounts to be > max
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(
            uint256(int256(type(int128).max)),
            0,
            uint256(int256(type(int128).max) + 1e30),
            0
        );
        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        // expect borrow to revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_BORROW
            )
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1e29), address(0), alice, abi.encode(alice));

        // expect payback to work
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), -int256(1e29), address(0), address(0), abi.encode(alice));
    }

    function test_operate_RevertValueOverflowTotalBorrowInterestFree() public {
        TestERC20Dec6(address(USDC)).mint(alice, 1e72);
        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocolInterestFree),
            token: address(USDC),
            mode: 0,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e70,
            maxDebtCeiling: 1e71
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // supply max
        vm.prank(alice);
        mockProtocolInterestFree.operate(
            address(USDC),
            int256(type(int128).max),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
        // borrow max
        vm.prank(alice);
        mockProtocolInterestFree.operate(
            address(USDC),
            int256(0),
            int256(type(int128).max),
            address(0),
            alice,
            abi.encode(alice)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__TOTAL_BORROW
            )
        );

        // borrow above max
        vm.prank(alice);
        mockProtocolInterestFree.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));
    }

    // Note borrow interest free can never go above limit
}

contract LiquidityUserModuleOperateExchangePricesStorageUpdateTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // sets storage update threshold to 1%
        _setDefaultTokenConfigs(address(liquidity), admin, address(USDC));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_NoStorageUpdateJustDeposit() public {
        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // make sure total amounts and userSupplyData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_StorageUpdateBecauseOfTimeDiff() public {
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        vm.warp(block.timestamp + 1 days + 1);

        _supply(mockProtocol, address(USDC), alice, 100); // supply insignificant amount that would not cause an update

        // make sure total amounts and userSupplyData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_NoStorageUpdateBelowTimeDiff() public {
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        vm.warp(block.timestamp + 1 days);

        _supply(mockProtocol, address(USDC), alice, 100); // supply insignificant amount that would not cause an update

        // make sure total amounts and userSupplyData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_NoStorageUpdateBelowUpdateThresholdUtilization() public {
        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // changes utilization from 0 to 0.99%
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 101);

        // make sure total amounts and userBorrowData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_StorageUpdateBecauseOfUtilization() public {
        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // changes utilization from 0 to 1.01%
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 99);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        // expect utilization to be 1.01%
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 101);
    }

    function test_operate_StorageUpdateBecauseOfSupplyRatioAboveUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup

        // supply DEFAULT_SUPPLY_AMOUNT without interest
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now supply 0.011 ether as with interest, which causes ratio to change by 1.1%
        _supply(mockProtocol, address(USDC), alice, 0.011 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertSupplyRatio(resolver, address(USDC), 0, 9891); // ratio after the 1.1% difference + rounding is 98,91 %
    }

    function test_operate_NoStorageUpdateBelowUpdateThresholdSupplyRatio() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup

        // supply DEFAULT_SUPPLY_AMOUNT without interest
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now supply 0.0099 ether as with interest, which causes ratio to change by 0.99%
        _supply(mockProtocol, address(USDC), alice, 0.0099 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_StorageUpdateBecauseOfSupplyRatioModeChangeBelowUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup

        // supply DEFAULT_SUPPLY_AMOUNT without interest -> mode bit is still 0
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocolInterestFree), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now supply interest free again a tiny amount 0.001 ether which causes ratio to flip as
        // supply interest free is > supply with interest for the first time
        _supply(mockProtocolInterestFree, address(USDC), alice, 0.001 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocolInterestFree), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertSupplyRatio(resolver, address(USDC), 1, 9990); // ratio is at 99.90% after the tiny borrow amount
    }

    function test_operate_StorageUpdateBecauseOfSupplyRatioModeChangeAboveUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup

        // supply DEFAULT_SUPPLY_AMOUNT without interest -> mode bit is still 0
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userSupplyDataBefore = resolver.getUserSupply(address(mockProtocolInterestFree), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now supply interest free again an amount that would also affect ratio but main cause for update is
        // supply interest free is > supply with interest for the first time
        _supply(mockProtocolInterestFree, address(USDC), alice, 0.011 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userSupplyDataBefore, resolver.getUserSupply(address(mockProtocolInterestFree), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertSupplyRatio(resolver, address(USDC), 1, 9891); // ratio after the 1.1% difference + rounding is 98,91 %
    }

    function test_operate_StorageUpdateBecauseOfBorrowRatioAboveUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup
        // supply again to have enough liquidity present for DEFAULT_BORROW_AMOUNT a huge amount
        // so that utilization could not be the cause for the update
        _supply(mockProtocolInterestFree, address(USDC), alice, 1_000_000 ether);

        // borrow 1 ether with interest (important to do this first so the ratio bit doesnt change)
        _borrow(mockProtocol, address(USDC), alice, 1 ether);
        // borrow 1 ether without interest
        _borrow(mockProtocolInterestFree, address(USDC), alice, 1 ether);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now borrow 0.011 ether as with interest, which causes ratio to change by 1.1%
        _borrow(mockProtocol, address(USDC), alice, 0.011 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertBorrowRatio(resolver, address(USDC), 0, 9891); // ratio after the 1.1% difference + rounding is 98,91 %
    }

    function test_operate_NoStorageUpdateBelowUpdateThresholdBorrowRatio() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup
        // supply again to have enough liquidity present for DEFAULT_BORROW_AMOUNT a huge amount
        // so that utilization could not be the cause for the update
        _supply(mockProtocolInterestFree, address(USDC), alice, 1_000_000 ether);

        // borrow 1 ether with interest (important to do this first so the ratio bit doesnt change)
        _borrow(mockProtocol, address(USDC), alice, 1 ether);
        // borrow 1 ether without interest
        _borrow(mockProtocolInterestFree, address(USDC), alice, 1 ether);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now borrow 0.0099 ether as with interest, which causes ratio to change by 0.99%
        _borrow(mockProtocol, address(USDC), alice, 0.0099 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocol), address(USDC)));

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));
    }

    function test_operate_StorageUpdateBecauseOfBorrowRatioModeChangeBelowUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup
        // supply again to have enough liquidity present for DEFAULT_BORROW_AMOUNT a huge amount
        // so that utilization could not be the cause for the update
        _supply(mockProtocolInterestFree, address(USDC), alice, 1_000_000 ether);

        // borrow 1 ether with interest (important to do this first so the ratio bit doesnt change)
        _borrow(mockProtocol, address(USDC), alice, 1 ether);
        // borrow 1 ether without interest -> mode bit is still 0
        _borrow(mockProtocolInterestFree, address(USDC), alice, 1 ether);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocolInterestFree), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now borrow interest free again a tiny amount 0.001 ether which causes ratio to flip as
        // borrow interest free is > borrow with interest for the first time
        _borrow(mockProtocolInterestFree, address(USDC), alice, 0.001 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocolInterestFree), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertBorrowRatio(resolver, address(USDC), 1, 9990); // ratio is at 99.90% after the tiny borrow amount
    }

    function test_operate_StorageUpdateBecauseOfBorrowRatioModeChangeAboveUpdateThreshold() public {
        // mockprotocol supplied DEFAULT_SUPPLY_AMOUNT with interest (1 ether) in setup
        // supply again to have enough liquidity present for DEFAULT_BORROW_AMOUNT a huge amount
        // so that utilization could not be the cause for the update
        _supply(mockProtocolInterestFree, address(USDC), alice, 1_000_000 ether);

        // borrow 1 ether with interest (important to do this first so the ratio bit doesnt change)
        _borrow(mockProtocol, address(USDC), alice, 1 ether);
        // borrow 1 ether without interest -> mode bit is still 0
        _borrow(mockProtocolInterestFree, address(USDC), alice, 1 ether);

        uint256 totalAmountsBefore = resolver.getTotalAmounts(address(USDC));
        uint256 userBorrowDataBefore = resolver.getUserBorrow(address(mockProtocolInterestFree), address(USDC));
        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        // now borrow interest free again an amount that would also affect ratio but main cause for update is
        // borrow interest free is > borrow with interest for the first time
        _borrow(mockProtocolInterestFree, address(USDC), alice, 0.011 ether);

        // make sure total amounts and userData has updated normally
        assertNotEq(totalAmountsBefore, resolver.getTotalAmounts(address(USDC)));
        assertNotEq(userBorrowDataBefore, resolver.getUserBorrow(address(mockProtocolInterestFree), address(USDC)));

        // assert exchangePricesAndConfig had storage update
        assertNotEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        _assertBorrowRatio(resolver, address(USDC), 1, 9891); // ratio after the 1.1% difference + rounding is 98,91 %
    }

    function test_operate_RevertValueOverflowUtilization() public {
        // borrow to 100% utilization, with very high borrow rate APR + 100% fee
        // meaning increase in borrow exchange price happens fast but supply exchange price
        // stays the same, so utilization will grow and grow until it reaches > 16_383 max value

        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(
            address(USDC),
            DEFAULT_KINK,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE
        );
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: DEFAULT_100_PERCENT, // 100%
            threshold: DEFAULT_STORAGE_UPDATE_THRESHOLD, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // borrow full available supply amount to get to 100% utilization
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        _borrow(
            mockProtocol,
            address(USDC),
            alice,
            overallTokenData.supplyRawInterest + overallTokenData.supplyInterestFree
        );

        // expect utilization to be 100%
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 100 * DEFAULT_PERCENT_PRECISION);

        // warp until utilization would overflow above 16_383. For this case utilization would be 19363
        vm.warp(block.timestamp + 160 days);

        // execute supply (borrow more would revert anyway as sending is not possible).
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__UTILIZATION
            )
        );
        _supply(mockProtocol, address(USDC), alice, 1 ether);
    }

    function test_operate_RevertValueOverflowSupplyExchangePrice() public {
        // borrow to 100% utilization, with very high borrow rate APR and 0% fee.
        // warp for a long time until exchange price would overflow the 64 bits at 1e12 precision
        // (18_446_744,073709551615)

        // there is no way for supply exchange price to ever grow faster than borrow exchange price.
        // so we use vm.store to simulate that case

        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(
            address(USDC),
            DEFAULT_KINK,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE
        );
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        // token config fee is 0 by default

        _supply(mockProtocol, address(USDC), alice, 5 ether);
        _borrow(mockProtocol, address(USDC), alice, 5 ether);

        // warp until borrow exchange price would overflow above 18_446_744,073709551615.
        // for this test it would be    41_422_281,760414423659
        // (comparison overflow at      18_446_744,073709551615)
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        _warpWithExchangePriceUpdates(address(liquidity), admin, tokens, PASS_1YEAR_TIME * 3);
        // warp without updates in exchangePrices to trigger the expected revert in operate()
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // simulate set borrowExchangePrice lower again to make sure that would not be the cause for the revert
        uint256 simulatedExchangePrices = _simulateExchangePrices(resolver, address(USDC), 18446744073709551612, 1e12);

        vm.warp(block.timestamp + 10 days);

        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedExchangePrices));

        // execute supply (borrow more would revert anyway as sending is not possible).
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__EXCHANGE_PRICES
            )
        );
        _supply(mockProtocol, address(USDC), alice, 20_000_000_000 ether); // enough to trigger storage update
    }

    function test_operate_RevertValueOverflowBorrowExchangePrice() public {
        // borrow, with very high borrow rate APR and some fee so borrow exchange price
        // grows faster than supply exchange Price.
        // use a huge supply amount + low borrow amount so utilization does not change too much
        // even with max borrow exchange price.
        // warp for a long time (max until 16 March 2242 -> max value 8589934591) until exchange price
        // would overflow the 64 bits at 1e12 precision (18_446_744,073709551615)

        _supply(mockProtocol, address(USDC), alice, 1 ether);

        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(
            address(USDC),
            DEFAULT_KINK,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE
        );
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 10 * DEFAULT_PERCENT_PRECISION, // 10%
            threshold: DEFAULT_STORAGE_UPDATE_THRESHOLD, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        _supply(mockProtocol, address(USDC), alice, 100_000_000 ether);
        _borrow(mockProtocol, address(USDC), alice, 1 ether);

        // warp until borrow exchange price would overflow above 18_446_744,073709551615.
        // for this test it would be    52_322_881,960523481183
        // (comparison overflow at      18_446_744,073709551615)
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        _warpWithExchangePriceUpdates(address(liquidity), admin, tokens, PASS_1YEAR_TIME * 3);
        // warp without updates in exchangePrices to trigger the expected revert in operate()
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.UserModule__ValueOverflow__EXCHANGE_PRICES
            )
        );
        _borrow(mockProtocol, address(USDC), alice, 1_500_000 ether); // enough to trigger storage update
    }
}

contract LiquidityUserModuleOperateAmountInsufficientTests is LiquidityUserModuleBaseTest {
    function test_operate_RevertOperateAmountInsufficientWhenUserSupply() public {
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e28), int256(0), address(0), address(0), abi.encode(alice));

        // simulate total amounts to be smaller so we can catch revert because of user amount
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(1e15, 0, 0, 0);
        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        // expect deposit to revert if user operate amount is too small.
        // 1e28 - big math precision ~1e17 -> 1e11 will be too small
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountInsufficient)
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e11), int256(0), address(0), address(0), abi.encode(alice));

        // expect deposit from other user (protocol) to work
        vm.prank(alice);
        mockProtocolWithInterest.operate(
            address(USDC),
            int256(1e11),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_OperateAmountWorksForWithdraw() public {
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e28), int256(0), address(0), address(0), abi.encode(alice));

        // for withdrawals, it always works, as the rounding down actually has an effect if the amount changes even by just 1
        vm.prank(alice);
        mockProtocol.operate(address(USDC), -int256(1), int256(0), alice, address(0), abi.encode(alice));

        vm.prank(alice);
        mockProtocol.operate(address(USDC), -int256(1e2), int256(0), alice, address(0), abi.encode(alice));
    }

    function test_operate_RevertOperateAmountInsufficientWhenTotalSupply() public {
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e28), int256(0), address(0), address(0), abi.encode(alice));

        // expect deposit to revert if operate amount is too small.
        // 1e28 - big math precision ~1e17 -> 1e11 will be too small
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountInsufficient)
        );
        vm.prank(alice);
        mockProtocolWithInterest.operate(
            address(USDC),
            int256(1e11),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );

        // bigger amount will work
        vm.prank(alice);
        mockProtocolWithInterest.operate(
            address(USDC),
            int256(1e12),
            int256(0),
            address(0),
            address(0),
            abi.encode(alice)
        );
    }

    function test_operate_OperateAmountWorksForBorrow() public {
        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](2);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocolWithInterest),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e32,
            maxDebtCeiling: 1e33
        });
        userBorrowConfigs_[1] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e32,
            maxDebtCeiling: 1e33
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e30), int256(0), address(0), address(0), abi.encode(alice));
        // borrow
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));

        // borrow is always rounded up so it ALWAYS triggers a change in user borrow amount even if operate amount
        // is only 1
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1), address(0), alice, abi.encode(alice));

        // expect borrow from other user (protocol) to work
        vm.prank(alice);
        mockProtocolWithInterest.operate(address(USDC), int256(0), int256(1e11), address(0), alice, abi.encode(alice));
    }

    function test_operate_RevertOperateAmountInsufficientWhenUserPayback() public {
        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e32,
            maxDebtCeiling: 1e33
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e30), int256(0), address(0), address(0), abi.encode(alice));
        // borrow
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));

        // simulate total amounts to be smaller so we can catch revert because of user amount
        uint256 simulatedTotalAmounts = _simulateTotalAmounts(1e15, 1e30, 1e15, 0);
        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            address(USDC)
        );
        vm.store(address(liquidity), slot, bytes32(simulatedTotalAmounts));

        // expect payback to revert if operate amount is too small.
        // 1e28 - big math precision ~1e17 -> 1e11 will be too small
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountInsufficient)
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), -int256(1e11), address(0), alice, abi.encode(alice));

        // bigger amount will work
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), -int256(1e12), address(0), alice, abi.encode(alice));
    }

    function test_operate_RevertOperateAmountInsufficientWhenTotalBorrow() public {
        // increase borrow limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](2);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e32,
            maxDebtCeiling: 1e33
        });
        userBorrowConfigs_[1] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocolWithInterest),
            token: address(USDC),
            mode: 1,
            expandPercent: 0,
            expandDuration: 1,
            baseDebtCeiling: 1e32,
            maxDebtCeiling: 1e33
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1e30), int256(0), address(0), address(0), abi.encode(alice));
        // borrow
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));
        vm.prank(alice);
        mockProtocolWithInterest.operate(address(USDC), int256(0), int256(1e28), address(0), alice, abi.encode(alice));

        // expect borrow to revert if operate amount is too small.
        // 1e28 - big math precision ~1e17 -> 1e11 will be too small
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountInsufficient)
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), -int256(1e11), address(0), alice, abi.encode(alice));
        // same for other user (protocol)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountInsufficient)
        );
        vm.prank(alice);
        mockProtocolWithInterest.operate(address(USDC), int256(0), -int256(1e11), address(0), alice, abi.encode(alice));

        // bigger amount will work
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(0), -int256(1e12), address(0), alice, abi.encode(alice));
    }
}

// ---- Todo tests later:

// todo: Tests for if limits change in between (changed via AdminModule)! See commented out in liquidityUserModule.t.sol

// - Todo: huge multi test with 2-3 mock protocols, at least 1 interestFree and others withInterest, playthrough scenario of multiple
//   operations incl. yield etc. Could also use lending protocol and vaults instead of mock protocol. Would be good to have before
//   going live. Use reserve contract for triggering rebalance etc.

// todo: Fuzz tests, invariant tests, think about any other edge cases? ----------

// add fuzz tests -> exclude cases for is in out balanced out with assumes
// assume at least one of supply amount & borrow amount are not 0. both 0 is special case that reverts

// default invariant checks to run after each test ? or in general invariants.
// e.g. exchange prices always up, reentrancy status always reset afterwards etc.
// invariant rounding tests -> supply should always be >= actual amount accredited at Liquidity
// withdraw should always be <= actual amount taken at Liquidity
// borrow should always be <= actual amount counted at Liquidity
// payback should always be >= actual amount deducted at Liquidity
