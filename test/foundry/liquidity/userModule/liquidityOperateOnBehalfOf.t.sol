//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";
import { FluidLiquidityUserModule } from "../../../../contracts/liquidity/userModule/main.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error as LiquidityError } from "../../../../contracts/liquidity/error.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

/// @notice Mock contract that attempts reentrancy during liquidityCallback
contract ReentrantOnBehalfCaller {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable LIQUIDITY;

    constructor(address liquidity_) {
        LIQUIDITY = liquidity_;
    }

    receive() external payable {}

    function liquidityCallback(address token_, uint256 amount_, bytes calldata) external {
        require(msg.sender == LIQUIDITY, "only liquidity");
        IFluidLiquidity(LIQUIDITY).operateOnBehalfOf(address(this), token_, int256(amount_), int256(0), new bytes(0));
        IERC20(token_).transfer(LIQUIDITY, amount_);
    }

    function operateOnBehalfOf(
        address onBehalf_,
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        bytes calldata callbackData_
    ) external payable returns (uint256, uint256) {
        return
            IFluidLiquidity(LIQUIDITY).operateOnBehalfOf{ value: msg.value }(
                onBehalf_,
                token_,
                supplyAmount_,
                borrowAmount_,
                callbackData_
            );
    }
}

/// @notice Mock contract that calls operateOnBehalfOf and implements liquidityCallback
contract MockOnBehalfCaller {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable LIQUIDITY;
    bool internal transferInsufficientMode;
    bool internal transferExcessMode;

    constructor(address liquidity_) {
        LIQUIDITY = liquidity_;
    }

    receive() external payable {}

    function setTransferInsufficientMode(bool transferInsufficientMode_) external {
        transferInsufficientMode = transferInsufficientMode_;
    }

    function setTransferExcessMode(bool transferExcessMode_) external {
        transferExcessMode = transferExcessMode_;
    }

    function liquidityCallback(address token_, uint256 amount_, bytes calldata) external {
        require(msg.sender == LIQUIDITY, "only liquidity");
        if (amount_ > 0) {
            if (transferExcessMode) {
                amount_ += (amount_ * 10101) / 10000;
            } else if (transferInsufficientMode) {
                amount_ -= 1;
            }
        }
        IERC20(token_).transfer(LIQUIDITY, amount_);
    }

    function operateOnBehalfOf(
        address onBehalf_,
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        bytes calldata callbackData_
    ) external payable returns (uint256, uint256) {
        return
            IFluidLiquidity(LIQUIDITY).operateOnBehalfOf{ value: msg.value }(
                onBehalf_,
                token_,
                supplyAmount_,
                borrowAmount_,
                callbackData_
            );
    }
}

/// To test run: forge test -vvv --match-path test/foundry/liquidity/userModule/liquidityOperateOnBehalfOf.t.sol
contract LiquidityOperateOnBehalfOfTest is LiquidityUserModuleBaseTest {
    MockOnBehalfCaller internal authCaller;
    MockOnBehalfCaller internal unauthorizedCaller;
    MockProtocol internal borrower;
    bytes32 internal constant LOG_OPERATE_TOPIC =
        keccak256("LogOperate(address,address,int256,int256,address,address,uint256,uint256)");

    function setUp() public virtual override {
        super.setUp();

        authCaller = new MockOnBehalfCaller(address(liquidity));
        unauthorizedCaller = new MockOnBehalfCaller(address(liquidity));
        borrower = new MockProtocol(address(liquidity));

        // re-register user module with operateOnBehalfOf selector
        vm.prank(admin);
        liquidity.removeImplementation(address(userModule));
        bytes4[] memory newUserSigs = new bytes4[](2);
        newUserSigs[0] = FluidLiquidityUserModule.operate.selector;
        newUserSigs[1] = FluidLiquidityUserModule.operateOnBehalfOf.selector;
        vm.prank(admin);
        liquidity.addImplementation(address(userModule), newUserSigs);

        // set authCaller as an auth on liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(authCaller), true);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // set up borrower with supply+borrow allowances
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(borrower));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(borrower));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(borrower));

        // set up authCaller (onBehalf position) with supply+borrow allowances
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(authCaller));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(authCaller));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(authCaller));

        // fund authCaller with tokens for payback/deposit
        vm.prank(alice);
        USDC.transfer(address(authCaller), 1e40);
        vm.prank(alice);
        IERC20(address(DAI)).transfer(address(authCaller), 1e40);
        vm.deal(address(authCaller), 1e40);

        // fund borrower
        vm.prank(alice);
        USDC.transfer(address(borrower), 1e40);
        vm.prank(alice);
        IERC20(address(DAI)).transfer(address(borrower), 1e40);
        vm.deal(address(borrower), 1e40);
    }

    // ======== Auth tests ========

    function test_operateOnBehalfOf_RevertIfUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfUnauthorized
            )
        );
        unauthorizedCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_RevertIfEOAUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfUnauthorized
            )
        );
        IFluidLiquidity(address(liquidity)).operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_GovernanceCanDepositNativeOnBehalf() public {
        uint256 depositAmount = 1 ether;
        address onBehalf = address(borrower);
        uint256 supplyBefore = resolver.getUserSupply(onBehalf, NATIVE_TOKEN_ADDRESS);

        vm.deal(admin, depositAmount);
        vm.prank(admin);
        IFluidLiquidity(address(liquidity)).operateOnBehalfOf{ value: depositAmount }(
            onBehalf,
            NATIVE_TOKEN_ADDRESS,
            int256(depositAmount),
            int256(0),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(onBehalf, NATIVE_TOKEN_ADDRESS);
        assertTrue(supplyAfter != supplyBefore, "governance should be able to deposit on behalf");
    }

    function test_operateOnBehalfOf_RevertIfGovernanceUsesERC20WithoutCallback() public {
        vm.prank(admin);
        // Governance is an EOA in this test setup, so the ERC20 callback path reverts before returning structured data.
        vm.expectRevert();
        IFluidLiquidity(address(liquidity)).operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    // ======== Revert: withdraw/borrow not allowed ========

    function test_operateOnBehalfOf_RevertIfSupplyNegative() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfDepositOrPaybackOnly
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(-1 ether), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfBorrowPositive() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfDepositOrPaybackOnly
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), int256(1 ether), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfBothWithdrawAndBorrow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfDepositOrPaybackOnly
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(-1 ether), int256(1 ether), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfSupplyNegativeWithPayback() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfDepositOrPaybackOnly
            )
        );
        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(-1 ether),
            int256(-1 ether),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_RevertIfBorrowPositiveWithDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfDepositOrPaybackOnly
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(1 ether), int256(1 ether), new bytes(0));
    }

    // ======== Revert: zero amounts ========

    function test_operateOnBehalfOf_RevertIfBothAmountsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateAmountsZero
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(type(int128).max) + 1,
            int256(0),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_RevertIfBorrowAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(0),
            int256(type(int128).min) - 1,
            new bytes(0)
        );
    }

    // ======== Revert: msg.value for non-native token ========

    function test_operateOnBehalfOf_RevertIfMsgValueForNonNativeToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__MsgValueForNonNativeToken
            )
        );
        authCaller.operateOnBehalfOf{ value: 1 ether }(
            address(authCaller),
            address(USDC),
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_RevertIfNativeMsgValueTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf{ value: 0.9 ether }(
            address(authCaller),
            NATIVE_TOKEN_ADDRESS,
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    function test_operateOnBehalfOf_RevertIfNativeMsgValueTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf{ value: 1.1 ether }(
            address(authCaller),
            NATIVE_TOKEN_ADDRESS,
            int256(1 ether),
            int256(0),
            new bytes(0)
        );
    }

    // ======== Revert: onBehalf address(0) ========

    function test_operateOnBehalfOf_RevertIfOnBehalfAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfAddressZero
            )
        );
        authCaller.operateOnBehalfOf(address(0), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    // ======== Revert: onBehalf must be configured ========

    function test_operateOnBehalfOf_RevertIfOnBehalfSupplyNotDefined() public {
        address undefinedOnBehalf = makeAddr("undefinedOnBehalf");

        vm.expectRevert(
            abi.encodeWithSelector(LiquidityError.FluidLiquidityError.selector, ErrorTypes.UserModule__UserNotDefined)
        );
        authCaller.operateOnBehalfOf(undefinedOnBehalf, address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfOnBehalfBorrowNotDefined() public {
        address undefinedOnBehalf = makeAddr("undefinedOnBehalf");

        vm.expectRevert(
            abi.encodeWithSelector(LiquidityError.FluidLiquidityError.selector, ErrorTypes.UserModule__UserNotDefined)
        );
        authCaller.operateOnBehalfOf(undefinedOnBehalf, address(USDC), int256(0), -int256(1 ether), new bytes(0));
    }

    function test_operateOnBehalfOf_DepositSucceedsEvenWhenTokenPaused() public {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(tokens_);

        uint256 supplyBefore = resolver.getUserSupply(address(borrower), address(USDC));

        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(1 ether), int256(0), new bytes(0));

        uint256 supplyAfter = resolver.getUserSupply(address(borrower), address(USDC));
        assertTrue(supplyAfter != supplyBefore, "deposit on behalf should succeed even when token is paused");
    }

    function test_operateOnBehalfOf_PaybackSucceedsEvenWhenTokenPaused() public {
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 10 ether);
        _borrow(borrower, address(USDC), bob, 1 ether);

        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(tokens_);

        uint256 borrowBefore = resolver.getUserBorrow(address(borrower), address(USDC));

        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), -int256(0.5 ether), new bytes(0));

        uint256 borrowAfter = resolver.getUserBorrow(address(borrower), address(USDC));
        assertTrue(borrowAfter != borrowBefore, "payback on behalf should succeed even when token is paused");
    }

    function test_operateOnBehalfOf_DepositAndPaybackSucceedEvenWhenTokenPaused() public {
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 100 ether);
        _borrow(borrower, address(USDC), bob, 10 ether);

        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(tokens_);

        uint256 supplyBefore = resolver.getUserSupply(address(borrower), address(USDC));
        uint256 borrowBefore = resolver.getUserBorrow(address(borrower), address(USDC));

        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(2 ether), -int256(5 ether), new bytes(0));

        uint256 supplyAfter = resolver.getUserSupply(address(borrower), address(USDC));
        uint256 borrowAfter = resolver.getUserBorrow(address(borrower), address(USDC));
        assertTrue(supplyAfter != supplyBefore, "supply position should change for onBehalf even when token paused");
        assertTrue(borrowAfter != borrowBefore, "borrow position should change for onBehalf even when token paused");
    }

    function test_operateOnBehalfOf_DepositNativeSucceedsEvenWhenTokenPaused() public {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = NATIVE_TOKEN_ADDRESS;

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(tokens_);

        uint256 supplyBefore = resolver.getUserSupply(address(borrower), NATIVE_TOKEN_ADDRESS);

        authCaller.operateOnBehalfOf{ value: 1 ether }(
            address(borrower),
            NATIVE_TOKEN_ADDRESS,
            int256(1 ether),
            int256(0),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(address(borrower), NATIVE_TOKEN_ADDRESS);
        assertTrue(supplyAfter != supplyBefore, "native deposit on behalf should succeed even when token is paused");
    }

    function test_operate_RevertIfTokenPaused() public {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).pauseTokens(tokens_);

        vm.expectRevert(
            abi.encodeWithSelector(LiquidityError.FluidLiquidityError.selector, ErrorTypes.UserModule__TokenPaused)
        );
        vm.prank(alice);
        mockProtocol.operate(address(USDC), int256(1 ether), int256(0), address(0), address(0), abi.encode(alice));
    }

    function test_operateOnBehalfOf_DepositSucceedsEvenWhenSupplyPaused() public {
        _pauseUser(address(liquidity), admin, address(borrower), address(USDC), address(0));

        // deposit on behalf should succeed even when user is paused
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_PaybackSucceedsEvenWhenBorrowPaused() public {
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 10 ether);
        _borrow(borrower, address(USDC), bob, 1 ether);
        _pauseUser(address(liquidity), admin, address(borrower), address(0), address(USDC));

        // payback on behalf should succeed even when user is paused
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), -int256(0.5 ether), new bytes(0));
    }

    // ======== Deposit on behalf (ERC20) ========

    function test_operateOnBehalfOf_DepositERC20() public {
        uint256 depositAmount = 1 ether;

        uint256 liquidityBalanceBefore = USDC.balanceOf(address(liquidity));
        uint256 callerBalanceBefore = USDC.balanceOf(address(authCaller));

        (uint256 supplyExPrice, uint256 borrowExPrice) = authCaller.operateOnBehalfOf(
            address(authCaller),
            address(USDC),
            int256(depositAmount),
            int256(0),
            new bytes(0)
        );

        assertGt(supplyExPrice, 0, "supply exchange price should be > 0");
        assertGt(borrowExPrice, 0, "borrow exchange price should be > 0");
        assertEq(
            USDC.balanceOf(address(liquidity)),
            liquidityBalanceBefore + depositAmount,
            "liquidity balance mismatch"
        );
        assertEq(USDC.balanceOf(address(authCaller)), callerBalanceBefore - depositAmount, "caller balance mismatch");
    }

    function test_operateOnBehalfOf_DepositERC20_PositionUpdatedForOnBehalf() public {
        uint256 depositAmount = 1 ether;

        uint256 supplyBefore = resolver.getUserSupply(address(authCaller), address(USDC));

        authCaller.operateOnBehalfOf(
            address(authCaller),
            address(USDC),
            int256(depositAmount),
            int256(0),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(address(authCaller), address(USDC));
        assertTrue(supplyAfter != supplyBefore, "supply data should have changed for onBehalf");
    }

    function test_operateOnBehalfOf_DepositERC20_OnBehalfOfDifferentAddress() public {
        uint256 depositAmount = 1 ether;

        uint256 callerSupplyBefore = resolver.getUserSupply(address(authCaller), address(USDC));
        uint256 supplyBefore = resolver.getUserSupply(address(borrower), address(USDC));

        // authCaller deposits, but position is for borrower
        // need supply config for borrower (already set in setUp)
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(depositAmount), int256(0), new bytes(0));

        uint256 callerSupplyAfter = resolver.getUserSupply(address(authCaller), address(USDC));
        uint256 supplyAfter = resolver.getUserSupply(address(borrower), address(USDC));
        assertEq(callerSupplyAfter, callerSupplyBefore, "caller position should not change");
        assertTrue(supplyAfter != supplyBefore, "supply data should have changed for borrower (onBehalf)");
    }

    // ======== Deposit on behalf (Native) ========

    function test_operateOnBehalfOf_DepositNative() public {
        uint256 depositAmount = 1 ether;

        uint256 liquidityBalanceBefore = address(liquidity).balance;

        authCaller.operateOnBehalfOf{ value: depositAmount }(
            address(authCaller),
            NATIVE_TOKEN_ADDRESS,
            int256(depositAmount),
            int256(0),
            new bytes(0)
        );

        assertEq(
            address(liquidity).balance,
            liquidityBalanceBefore + depositAmount,
            "liquidity native balance mismatch"
        );
    }

    function test_operateOnBehalfOf_DepositNative_OnBehalfOfDifferentAddress() public {
        uint256 depositAmount = 1 ether;

        uint256 supplyBefore = resolver.getUserSupply(address(borrower), NATIVE_TOKEN_ADDRESS);

        authCaller.operateOnBehalfOf{ value: depositAmount }(
            address(borrower),
            NATIVE_TOKEN_ADDRESS,
            int256(depositAmount),
            int256(0),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(address(borrower), NATIVE_TOKEN_ADDRESS);
        assertTrue(supplyAfter != supplyBefore, "supply data should have changed for borrower (onBehalf)");
    }

    // ======== Payback on behalf (ERC20) ========

    function test_operateOnBehalfOf_PaybackERC20() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        uint256 callerBalanceBefore = USDC.balanceOf(address(authCaller));

        (uint256 supplyExPrice, uint256 borrowExPrice) = authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(0),
            -int256(paybackAmount),
            new bytes(0)
        );

        assertGt(supplyExPrice, 0, "supply exchange price should be > 0");
        assertGt(borrowExPrice, 0, "borrow exchange price should be > 0");
        assertEq(
            USDC.balanceOf(address(authCaller)),
            callerBalanceBefore - paybackAmount,
            "caller balance should decrease"
        );
    }

    function test_operateOnBehalfOf_PaybackERC20_PositionUpdatedOnlyForOnBehalf() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        uint256 callerBorrowBefore = resolver.getUserBorrow(address(authCaller), address(USDC));
        uint256 borrowerBorrowBefore = resolver.getUserBorrow(address(borrower), address(USDC));

        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), -int256(paybackAmount), new bytes(0));

        uint256 callerBorrowAfter = resolver.getUserBorrow(address(authCaller), address(USDC));
        uint256 borrowerBorrowAfter = resolver.getUserBorrow(address(borrower), address(USDC));

        assertEq(callerBorrowAfter, callerBorrowBefore, "caller borrow position should not change");
        assertTrue(borrowerBorrowAfter != borrowerBorrowBefore, "borrower debt should change");
    }

    function test_operateOnBehalfOf_PaybackERC20_DAI() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supply(address(liquidity), mockProtocol, address(DAI), alice, supplyAmount);
        _borrow(borrower, address(DAI), bob, borrowAmount);

        uint256 callerBalanceBefore = IERC20(address(DAI)).balanceOf(address(authCaller));

        authCaller.operateOnBehalfOf(address(borrower), address(DAI), int256(0), -int256(paybackAmount), new bytes(0));

        assertEq(
            IERC20(address(DAI)).balanceOf(address(authCaller)),
            callerBalanceBefore - paybackAmount,
            "caller DAI balance should decrease"
        );
    }

    // ======== Payback on behalf (Native) ========

    function test_operateOnBehalfOf_PaybackNative() public {
        uint256 supplyAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 paybackAmount = 0.5 ether;

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        uint256 liquidityBalanceBefore = address(liquidity).balance;

        authCaller.operateOnBehalfOf{ value: paybackAmount }(
            address(borrower),
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            -int256(paybackAmount),
            new bytes(0)
        );

        assertEq(
            address(liquidity).balance,
            liquidityBalanceBefore + paybackAmount,
            "liquidity native balance mismatch after payback"
        );
    }

    function test_operateOnBehalfOf_RevertIfPaybackWithoutDebt() public {
        vm.expectRevert(stdError.arithmeticError);
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), -int256(1 ether), new bytes(0));
    }

    // ======== Deposit + Payback combined on behalf (ERC20) ========

    function test_operateOnBehalfOf_DepositAndPaybackERC20() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 10 ether;
        uint256 depositAmount = 2 ether;
        uint256 paybackAmount = 5 ether;

        // create supply pool
        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);

        // create debt for authCaller position via its own supply+borrow
        // first, authCaller needs to supply so it can borrow (but for operateOnBehalfOf the
        // onBehalf address needs the position). We use borrower which has configs.
        _borrow(borrower, address(USDC), bob, borrowAmount);

        uint256 callerBalanceBefore = USDC.balanceOf(address(authCaller));

        // combined: deposit supply + payback borrow, both on behalf of borrower
        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(depositAmount),
            -int256(paybackAmount),
            new bytes(0)
        );

        // tokens moved from authCaller
        assertEq(
            USDC.balanceOf(address(authCaller)),
            callerBalanceBefore - depositAmount - paybackAmount,
            "caller balance should decrease by deposit + payback"
        );
    }

    function test_operateOnBehalfOf_RevertIfTransferInTooLow() public {
        authCaller.setTransferInsufficientMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfTransferInTooHigh() public {
        authCaller.setTransferExcessMode(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__TransferAmountOutOfBounds
            )
        );
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    function test_operateOnBehalfOf_RevertIfCallbackDataNotEmpty() public {
        bytes memory callbackData = abi.encode(address(authCaller));

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfCallbackDataNotEmpty
            )
        );
        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(1 ether),
            -int256(0.5 ether),
            callbackData
        );
    }

    function test_operateOnBehalfOf_LogOperateUsesOnBehalfAsIndexedUser() public {
        uint256 depositAmount = 1 ether;

        vm.recordLogs();
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(depositAmount), int256(0), new bytes(0));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        // LogOperate is no longer the last event (LogOperateOnBehalfOf comes after), find it by topic
        Vm.Log memory log;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == LOG_OPERATE_TOPIC) {
                log = entries[i];
                break;
            }
        }

        assertEq(log.emitter, address(liquidity), "log should be emitted by liquidity");
        assertEq(address(uint160(uint256(log.topics[1]))), address(borrower), "indexed user should be onBehalf");
        assertEq(address(uint160(uint256(log.topics[2]))), address(USDC), "indexed token should match");

        (int256 supplyAmount, int256 borrowAmount, address withdrawTo, address borrowTo, , ) = abi.decode(
            log.data,
            (int256, int256, address, address, uint256, uint256)
        );

        assertEq(supplyAmount, int256(depositAmount), "event supply amount mismatch");
        assertEq(borrowAmount, int256(0), "event borrow amount mismatch");
        assertEq(withdrawTo, address(0), "withdraw receiver should be zero");
        assertEq(borrowTo, address(0), "borrow receiver should be zero");
    }

    function test_operateOnBehalfOf_EmitsLogOperateOnBehalfOf() public {
        uint256 depositAmount = 1 ether;

        bytes32 logOnBehalfTopic = keccak256(
            "LogOperateOnBehalfOf(address,address,address,int256,int256,uint256,uint256)"
        );

        vm.recordLogs();
        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(depositAmount), int256(0), new bytes(0));

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == logOnBehalfTopic) {
                found = true;
                assertEq(entries[i].emitter, address(liquidity), "LogOperateOnBehalfOf emitter mismatch");
                assertEq(
                    address(uint160(uint256(entries[i].topics[1]))),
                    address(authCaller),
                    "operator should be authCaller"
                );
                assertEq(
                    address(uint160(uint256(entries[i].topics[2]))),
                    address(borrower),
                    "onBehalf should be borrower"
                );
                assertEq(address(uint160(uint256(entries[i].topics[3]))), address(USDC), "token should match");
                (int256 supplyAmt, int256 borrowAmt, uint256 supplyExPrice, uint256 borrowExPrice) = abi.decode(
                    entries[i].data,
                    (int256, int256, uint256, uint256)
                );
                assertEq(supplyAmt, int256(depositAmount), "supply amount mismatch in LogOperateOnBehalfOf");
                assertEq(borrowAmt, int256(0), "borrow amount mismatch in LogOperateOnBehalfOf");
                assertGt(supplyExPrice, 0, "supply exchange price should be > 0");
                assertGt(borrowExPrice, 0, "borrow exchange price should be > 0");
                break;
            }
        }
        assertTrue(found, "LogOperateOnBehalfOf event should be emitted");
    }

    // ======== Supply only with zero borrow works ========

    function test_operateOnBehalfOf_DepositOnlyWithZeroBorrow() public {
        authCaller.operateOnBehalfOf(address(authCaller), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    // ======== Payback only with zero supply works ========

    function test_operateOnBehalfOf_PaybackOnlyWithZeroSupply() public {
        _supply(address(liquidity), mockProtocol, address(USDC), alice, 10 ether);
        _borrow(borrower, address(USDC), bob, 1 ether);

        authCaller.operateOnBehalfOf(address(borrower), address(USDC), int256(0), -int256(0.3 ether), new bytes(0));
    }

    // ======== Auth removal ========

    function test_operateOnBehalfOf_RevertAfterAuthRemoved() public {
        // confirm authCaller can operate before removal
        authCaller.operateOnBehalfOf(address(authCaller), address(USDC), int256(1 ether), int256(0), new bytes(0));

        // remove auth
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(authCaller), false);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // should revert now
        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                ErrorTypes.UserModule__OperateOnBehalfUnauthorized
            )
        );
        authCaller.operateOnBehalfOf(address(authCaller), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }

    // ======== Combined deposit+payback: both positions updated ========

    function test_operateOnBehalfOf_DepositAndPayback_BothPositionsUpdated() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 10 ether;
        uint256 depositAmount = 2 ether;
        uint256 paybackAmount = 5 ether;

        _supply(address(liquidity), mockProtocol, address(USDC), alice, supplyAmount);
        _borrow(borrower, address(USDC), bob, borrowAmount);

        uint256 supplyBefore = resolver.getUserSupply(address(borrower), address(USDC));
        uint256 borrowBefore = resolver.getUserBorrow(address(borrower), address(USDC));

        authCaller.operateOnBehalfOf(
            address(borrower),
            address(USDC),
            int256(depositAmount),
            -int256(paybackAmount),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(address(borrower), address(USDC));
        uint256 borrowAfter = resolver.getUserBorrow(address(borrower), address(USDC));

        assertTrue(supplyAfter != supplyBefore, "supply position should change for onBehalf");
        assertTrue(borrowAfter != borrowBefore, "borrow position should change for onBehalf");
    }

    function test_operateOnBehalfOf_DepositAndPaybackNative() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 10 ether;
        uint256 depositAmount = 2 ether;
        uint256 paybackAmount = 5 ether;
        address onBehalf = address(borrower);

        _supplyNative(address(liquidity), mockProtocol, alice, supplyAmount);
        _borrowNative(borrower, bob, borrowAmount);

        uint256 supplyBefore = resolver.getUserSupply(onBehalf, NATIVE_TOKEN_ADDRESS);
        uint256 liquidityBalanceBefore = address(liquidity).balance;

        authCaller.operateOnBehalfOf{ value: depositAmount + paybackAmount }(
            onBehalf,
            NATIVE_TOKEN_ADDRESS,
            int256(depositAmount),
            -int256(paybackAmount),
            new bytes(0)
        );

        uint256 supplyAfter = resolver.getUserSupply(onBehalf, NATIVE_TOKEN_ADDRESS);

        assertTrue(supplyAfter > supplyBefore, "native supply position should increase");
        assertEq(
            address(liquidity).balance,
            liquidityBalanceBefore + depositAmount + paybackAmount,
            "native combined operation should transfer the full input amount"
        );
    }

    // ======== Reentrancy protection ========

    function test_operateOnBehalfOf_RevertOnReentrancy() public {
        ReentrantOnBehalfCaller reentrant = new ReentrantOnBehalfCaller(address(liquidity));

        // set reentrant as auth
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(reentrant), true);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // set up supply allowances for reentrant
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(reentrant));

        // fund reentrant with tokens
        vm.prank(alice);
        USDC.transfer(address(reentrant), 1e40);

        // the callback will attempt to re-enter operateOnBehalfOf; reentrancy guard reverts the whole tx
        vm.expectRevert(
            abi.encodeWithSelector(LiquidityError.FluidLiquidityError.selector, ErrorTypes.LiquidityHelpers__Reentrancy)
        );
        reentrant.operateOnBehalfOf(address(reentrant), address(USDC), int256(1 ether), int256(0), new bytes(0));
    }
}
