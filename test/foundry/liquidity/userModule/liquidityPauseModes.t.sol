//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";

contract LiquidityPauseModesTest is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT * 10);
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);
    }

    function _tokens(address token_) internal pure returns (address[] memory tokens_) {
        tokens_ = new address[](1);
        tokens_[0] = token_;
    }

    function _pauseUserSupply(bool pauseSupply_, bool pauseWithdraw_) internal {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseUserSupply(
            address(mockProtocol),
            _tokens(address(USDC)),
            pauseSupply_,
            pauseWithdraw_
        );
    }

    function _pauseUserBorrow(bool pauseBorrow_, bool pausePayback_) internal {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseUserBorrow(
            address(mockProtocol),
            _tokens(address(USDC)),
            pauseBorrow_,
            pausePayback_
        );
    }

    function _pauseTokens(bool supply_, bool withdraw_, bool borrow_, bool payback_) internal {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(
            _tokens(address(USDC)),
            supply_,
            withdraw_,
            borrow_,
            payback_
        );
    }

    function _unpauseTokens(bool supply_, bool withdraw_, bool borrow_, bool payback_) internal {
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).unpauseTokens(
            _tokens(address(USDC)),
            supply_,
            withdraw_,
            borrow_,
            payback_
        );
    }

    function _setProtocolClass(uint256 class_) internal {
        AdminModuleStructs.AddressUint256[] memory classes_ = new AdminModuleStructs.AddressUint256[](1);
        classes_[0] = AdminModuleStructs.AddressUint256(address(mockProtocol), class_);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserClasses(classes_);
    }

    function test_operate_SupplyPauseOnly_BlocksDepositAllowsWithdraw() public {
        _pauseUserSupply(true, false);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);

        uint256 balBefore_ = USDC.balanceOf(alice);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
        assertGt(USDC.balanceOf(alice), balBefore_);
    }

    function test_operate_WithdrawPauseOnly_BlocksWithdrawAllowsDeposit() public {
        _pauseUserSupply(false, true);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);

        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);
    }

    function test_operate_SupplyAndWithdrawPause_BlocksBoth() public {
        _pauseUserSupply(true, true);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
    }

    function test_operate_BorrowPauseOnly_BlocksBorrowAllowsPayback() public {
        _pauseUserBorrow(true, false);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);

        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);
    }

    function test_operate_PaybackPauseOnly_BlocksPaybackAllowsBorrow() public {
        _pauseUserBorrow(false, true);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);

        uint256 balBefore_ = USDC.balanceOf(alice);
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);
        assertGt(USDC.balanceOf(alice), balBefore_);
    }

    function test_operate_TokenSupplyPause_BlocksDepositThenUnpauseAllows() public {
        _pauseTokens(true, false, false, false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);

        _unpauseTokens(true, false, false, false);
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);
    }

    function test_operate_TokenWithdrawPause_BlocksWithdrawThenUnpauseAllows() public {
        _pauseTokens(false, true, false, false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);

        _unpauseTokens(false, true, false, false);
        uint256 balBefore_ = USDC.balanceOf(alice);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
        assertGt(USDC.balanceOf(alice), balBefore_);
    }

    function test_operate_TokenBorrowPause_BlocksBorrowThenUnpauseAllows() public {
        _pauseTokens(false, false, true, false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);

        _unpauseTokens(false, false, true, false);
        uint256 balBefore_ = USDC.balanceOf(alice);
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);
        assertGt(USDC.balanceOf(alice), balBefore_);
    }

    function test_operate_TokenPaybackPause_BlocksPaybackThenUnpauseAllows() public {
        _pauseTokens(false, false, false, true);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);

        _unpauseTokens(false, false, false, true);
        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);
    }

    function test_operate_Class1_IgnoresTokenWithdrawAndPaybackPause() public {
        _setProtocolClass(1);
        _pauseTokens(false, true, false, true);

        uint256 balBefore_ = USDC.balanceOf(alice);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
        assertGt(USDC.balanceOf(alice), balBefore_);

        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);
    }

    function test_operate_Class1_RevertIfTokenSupplyOrBorrowPaused() public {
        _setProtocolClass(1);
        _pauseTokens(true, false, true, false);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);
    }

    function test_operate_Class2_IgnoresAllTokenPauses() public {
        _setProtocolClass(2);
        _pauseTokens(true, true, true, true);

        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);
        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);
    }

    function test_pauseUserSupply_RevertIfClass1PausesWithdraw() public {
        _setProtocolClass(1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserSupply(false, true);

        _pauseUserSupply(true, false);
    }

    function test_pauseUserBorrow_RevertIfClass1PausesPayback() public {
        _setProtocolClass(1);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserBorrow(false, true);

        _pauseUserBorrow(true, false);
    }

    function test_pauseUserSupply_RevertIfClass2() public {
        _setProtocolClass(2);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserSupply(true, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserSupply(false, true);
    }

    function test_pauseUserBorrow_RevertIfClass2() public {
        _setProtocolClass(2);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserBorrow(true, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotPausable)
        );
        _pauseUserBorrow(false, true);
    }

    function test_unpauseUserSupply_AllowedAfterClass2Promotion() public {
        _pauseUserSupply(true, true);
        _setProtocolClass(2);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).unpauseUserSupply(
            address(mockProtocol),
            _tokens(address(USDC)),
            true,
            true
        );

        (ResolverStructs.UserSupplyData memory resolvedSupply_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertFalse(resolvedSupply_.isSupplyPaused);
        assertFalse(resolvedSupply_.isWithdrawPaused);
        assertFalse(resolvedSupply_.isPaused);
    }

    function test_operate_LegacyUserSupplyPauseBit_PausesDepositAndWithdraw() public {
        bytes32 slot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            address(mockProtocol),
            address(USDC)
        );
        uint256 userSupplyData_ = IFluidLiquidity(address(liquidity)).readFromStorage(slot_);
        // legacy pause only ever set bit 255; bit 254 left at 0 decodes to USER_PAUSE_MODE_ALL, not a partial mode
        vm.store(address(liquidity), slot_, bytes32(userSupplyData_ | (1 << 255)));

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__UserPaused));
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
    }

    function test_operate_LegacyTokenPauseBit_PausesPaybackOnly() public {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            address(USDC)
        );
        uint256 exchangePricesAndConfig_ = IFluidLiquidity(address(liquidity)).readFromStorage(slot_);
        // legacy token pause only ever set bit 255, which lands on the payback bit of the 4-bit mask
        vm.store(address(liquidity), slot_, bytes32(exchangePricesAndConfig_ | (1 << 255)));

        _supply(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT / 100);
        _withdraw(address(liquidity), mockProtocol, address(USDC), alice, DEFAULT_WITHDRAW_AMOUNT);
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 10);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        _payback(mockProtocol, address(USDC), alice, DEFAULT_PAYBACK_AMOUNT / 10);
    }

    function test_operate_MixedDepositAndBorrow_RevertsIfEitherLegPaused() public {
        uint256 depositAmount_ = DEFAULT_SUPPLY_AMOUNT / 100;
        uint256 borrowAmount_ = DEFAULT_BORROW_AMOUNT / 10;

        _pauseTokens(true, false, false, false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(depositAmount_),
            int256(borrowAmount_),
            address(0),
            alice,
            abi.encode(alice)
        );
        _unpauseTokens(true, false, false, false);

        _pauseTokens(false, false, true, false);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused));
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(depositAmount_),
            int256(borrowAmount_),
            address(0),
            alice,
            abi.encode(alice)
        );
        _unpauseTokens(false, false, true, false);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(depositAmount_),
            int256(borrowAmount_),
            address(0),
            alice,
            abi.encode(alice)
        );
    }
}
