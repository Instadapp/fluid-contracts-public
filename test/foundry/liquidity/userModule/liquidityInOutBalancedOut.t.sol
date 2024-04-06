//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";

contract LiquidityUserModuleInOutBalancedOutTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // create liquidity
        _supply(mockProtocol, address(USDC), alice, 10 * DEFAULT_SUPPLY_AMOUNT);
        _supplyNative(mockProtocol, alice, 10 * DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_NotInOutBalancedOutIfInFromIsNotBorrowTo() public {
        USDC.mint(address(mockProtocol), 1e50 ether);

        uint256 mockProtocolBalanceBefore = USDC.balanceOf(address(mockProtocol));
        uint256 aliceBalanceBefore = USDC.balanceOf(alice);

        // expect transfer of USDC to happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 1); // incoming
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 1); // outgoing

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(alice), // to != from -> should lead to normal transfer triggers
            abi.encode(address(mockProtocol))
        );

        uint256 mockProtocolBalanceAfter = USDC.balanceOf(address(mockProtocol));
        uint256 aliceBalanceAfter = USDC.balanceOf(alice);

        // balance of alice should have increased as receiver of borrowTo
        assertEq(aliceBalanceAfter, aliceBalanceBefore + DEFAULT_SUPPLY_AMOUNT);
        // balance of mockProtocol should have decreased as source for inFrom
        assertEq(mockProtocolBalanceAfter, mockProtocolBalanceBefore - DEFAULT_SUPPLY_AMOUNT);

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }

    function test_operate_NotInOutBalancedOutIfInFromIsNotWithdrawTo() public {
        USDC.mint(address(mockProtocol), 1e50 ether);

        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        uint256 mockProtocolBalanceBefore = USDC.balanceOf(address(mockProtocol));
        uint256 aliceBalanceBefore = USDC.balanceOf(alice);

        // expect transfer of USDC to happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 1); // incoming
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 1); // outgoing

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // withdraw and payback exact same amounts
            -int256(DEFAULT_BORROW_AMOUNT),
            -int256(DEFAULT_BORROW_AMOUNT),
            address(alice), // to != from -> should lead to normal transfer triggers
            address(0),
            abi.encode(address(mockProtocol))
        );

        uint256 mockProtocolBalanceAfter = USDC.balanceOf(address(mockProtocol));
        uint256 aliceBalanceAfter = USDC.balanceOf(alice);

        // balance of alice should have increased as receiver of withdrawTo
        assertEq(aliceBalanceAfter, aliceBalanceBefore + DEFAULT_BORROW_AMOUNT);
        // balance of mockProtocol should have decreased as source for inFrom
        assertEq(mockProtocolBalanceAfter, mockProtocolBalanceBefore - DEFAULT_BORROW_AMOUNT);

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 10 - DEFAULT_BORROW_AMOUNT);

        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userBorrowData_.borrow, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_NotInOutBalancedOutIfInFromIsNotMsgSenderForBorrowTo() public {
        uint256 balanceBefore = USDC.balanceOf(alice);

        // expect transfer of USDC to happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 1); // incoming
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 1); // outgoing

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(alice), // to == from but not msg.sender (mockProtocol) -> should lead to normal transfer triggers
            abi.encode(address(alice))
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }

    function test_operate_NotInOutBalancedOutIfInFromIsNotMsgSenderForWithdrawTo() public {
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        uint256 balanceBefore = USDC.balanceOf(alice);

        // expect transfer of USDC to happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 1); // incoming
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 1); // outgoing

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // withdraw and payback exact same amounts
            -int256(DEFAULT_BORROW_AMOUNT),
            -int256(DEFAULT_BORROW_AMOUNT),
            address(alice), // to == from but not msg.sender (mockProtocol) -> should lead to normal transfer triggers
            address(0),
            abi.encode(address(alice))
        );

        uint256 balanceAfter = USDC.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 10 - DEFAULT_BORROW_AMOUNT);

        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userBorrowData_.borrow, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_InOutBalancedOutSupplyAndBorrow() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encode(address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }

    function test_operate_InOutBalancedOutWithdrawAndPayback() public {
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // withdraw and payback exact same amounts
            -int256(DEFAULT_BORROW_AMOUNT),
            -int256(DEFAULT_BORROW_AMOUNT),
            address(mockProtocol), // to == from
            address(0),
            abi.encode(address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 10 - DEFAULT_BORROW_AMOUNT);

        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userBorrowData_.borrow, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_InOutBalancedOutSupplyAndBorrowNative() public {
        uint256 balanceBefore = address(mockProtocol).balance;

        // if this operation passes then it means inOutBalancedOut optimization was active because no msg.value is sent along
        // = NO transfers happened
        vm.prank(alice);
        mockProtocol.operate(
            NATIVE_TOKEN_ADDRESS,
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encode(address(mockProtocol))
        );

        uint256 balanceAfter = address(mockProtocol).balance;
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }

    function test_operate_InOutBalancedOutWithdrawAndPaybackNative() public {
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        uint256 balanceBefore = address(mockProtocol).balance;

        // if this operation passes then it means inOutBalancedOut optimization was active because no msg.value is sent along
        // = NO transfers happened
        vm.prank(alice);
        mockProtocol.operate(
            NATIVE_TOKEN_ADDRESS,
            // withdraw and payback exact same amounts
            -int256(DEFAULT_BORROW_AMOUNT),
            -int256(DEFAULT_BORROW_AMOUNT),
            address(mockProtocol), // to == from
            address(0),
            abi.encode(address(mockProtocol))
        );

        uint256 balanceAfter = address(mockProtocol).balance;
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 10 - DEFAULT_BORROW_AMOUNT);

        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS
        );

        assertEq(userBorrowData_.borrow, DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_BORROW_AMOUNT);
    }

    function test_operate_NotInOutBalancedOutIfWithMsgValueNative() public {
        uint256 mockProtocolBalanceBefore = address(mockProtocol).balance;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        // send along msg.value: -> should lead to normal transfer triggers
        mockProtocol.operate{ value: DEFAULT_SUPPLY_AMOUNT }(
            NATIVE_TOKEN_ADDRESS,
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from (mockProtocol)
            abi.encode(address(mockProtocol)) // ignored in Liquidity as we never get to isInOutBalancedOut because of msg.value > 0
        );

        uint256 mockProtocolBalanceAfter = address(mockProtocol).balance;
        uint256 aliceBalanceAfter = alice.balance;

        // alice sent the DEFAULT_SUPPLY_AMOUNT along as value so inFrom is ignored from Liquidity
        assertEq(aliceBalanceAfter, aliceBalanceBefore - DEFAULT_SUPPLY_AMOUNT);
        // balance of mockProtocol should have increased as receiver for borrow amount
        assertEq(mockProtocolBalanceAfter, mockProtocolBalanceBefore + DEFAULT_SUPPLY_AMOUNT);

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }
}

contract LiquidityUserModuleInOutBalancedOutEncodingTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        _supply(mockProtocol, address(USDC), alice, 10 * DEFAULT_SUPPLY_AMOUNT); // create liquidity
    }

    function test_operate_NotInOutBalancedOutCallbackDataTooShort() public {
        mockProtocol.setTransferFromAddress(address(mockProtocol));

        USDC.mint(address(mockProtocol), 1e50 ether);

        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to happen normally
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 1); // incoming
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 1); // outgoing

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            new bytes(0) // transfer in will happen normally from mockProtocol thanks to mockProtocol.setTransferFromAddress above
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same

        (ResolverStructs.UserSupplyData memory userSupplyData_, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(userSupplyData_.supply, DEFAULT_SUPPLY_AMOUNT * 11);
    }

    function test_operate_InOutBalancedOutPacked() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encodePacked(address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }

    function test_operate_InOutBalancedOutPackedWithBool() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encodePacked(true, address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }

    function test_operate_InOutBalancedOutPackedWithDynamicTypes() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encodePacked(true, "someString", uint256(1), address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }

    function test_operate_InOutBalancedOutEncodedWithBool() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encode(true, address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }

    function test_operate_InOutBalancedOutCombineEncodedWithDynamicData() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // expect transfer of USDC to NOT happen
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transfer.selector), 0);
        vm.expectCall(address(USDC), abi.encodeWithSelector(USDC.transferFrom.selector), 0);

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            // abi.encode simple types, combined with abi.encodePacked to put dynamic types at front
            abi.encodePacked("someString", abi.encode(true, uint256(1), address(mockProtocol)))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }

    function test_operate_RevertIfInOutBalancedOutEncodedWithDynamicData() public {
        uint256 balanceBefore = USDC.balanceOf(address(mockProtocol));

        // operate fails because abi.encode with dynamic types ends up with the from address not at the end
        // of the calldata bytes. Would have to use abi.encodePacked for that and then manually decode.
        vm.expectRevert();
        // leads to USDC transfer from being called for the zero address
        vm.expectCall(
            address(USDC),
            abi.encodeCall(USDC.transferFrom, (address(0), address(liquidity), DEFAULT_SUPPLY_AMOUNT))
        );

        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            // supply and borrow exact same amounts
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_SUPPLY_AMOUNT),
            address(0),
            address(mockProtocol), // to == from
            abi.encode(true, "someString", uint256(1), address(mockProtocol))
        );

        uint256 balanceAfter = USDC.balanceOf(address(mockProtocol));
        assertEq(balanceAfter, balanceBefore); // balance should be the same
    }
}
