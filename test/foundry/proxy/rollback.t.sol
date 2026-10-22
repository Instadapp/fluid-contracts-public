// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { Proxy } from "../../../contracts/infiniteProxy/proxy.sol";
import { InfiniteProxyRollbackModule, RollbackCoreInternals } from "../../../contracts/infiniteProxy/rollbackModule/main.sol";
import { ErrorTypes } from "../../../contracts/infiniteProxy/errorTypes.sol";
import { Error } from "../../../contracts/infiniteProxy/error.sol";

contract InfiniteProxyRollbackTest is LiquidityBaseTest {
    event LogCleanupExpiredRollbackImplementation(address implementation);

    // Constants defined in RollbackCoreInternals
    address constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    uint256 constant ROLLBACK_PERIOD = 7 days;

    InfiniteProxyRollbackModule rollbackModule;
    bytes4[] rollbackSigs;

    InfiniteProxyRollbackModule rollbackProxy;

    function setUp() public virtual override {
        super.setUp();
        // Add the rollback module implementation to the proxy (like liquidityBaseTest.t.sol line 109-110)
        rollbackModule = new InfiniteProxyRollbackModule();
        // Register rollback module selectors, like adminSigs but for all external methods (including getters)
        rollbackSigs = [
            InfiniteProxyRollbackModule.registerRollbackDummyImplementation.selector,
            InfiniteProxyRollbackModule.rollbackDummyImplementation.selector,
            InfiniteProxyRollbackModule.registerRollbackImplementation.selector,
            InfiniteProxyRollbackModule.rollbackImplementation.selector,
            InfiniteProxyRollbackModule.cleanupExpiredRollbackImplementation.selector,
            InfiniteProxyRollbackModule.getRollbackForImplementation.selector,
            InfiniteProxyRollbackModule.getRollbackDummyImplementation.selector
        ];
        vm.prank(admin);
        liquidity.addImplementation(address(rollbackModule), rollbackSigs);
        rollbackProxy = InfiniteProxyRollbackModule(address(liquidity));

        vm.prank(admin);
        Proxy(payable(liquidity)).setDummyImplementation(address(0x1111));

        vm.warp(1);
    }

    /// @dev Tests registration and execution of dummy implementation rollback
    function test_DummyImplementationRollback() public {
        address oldDummy = Proxy(payable(liquidity)).getDummyImplementation();

        // 1. Admin registers the current dummy for potential rollback
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();

        // Read the currently registered rollback dummy implementation and its timestamp
        (address registeredRollbackDummy, uint256 rollbackTimestamp) = rollbackProxy.getRollbackDummyImplementation();
        // Confirm that the registered dummy implementation is the "oldDummy"
        assertEq(registeredRollbackDummy, oldDummy);
        // The registered timestamp should be approximately equal to block.timestamp (or at least nonzero)
        assertGt(rollbackTimestamp, 0);

        // 2. Simulate an upgrade to a new dummy implementation
        address newDummy = address(0x1234);
        vm.prank(admin);
        Proxy(payable(liquidity)).setDummyImplementation(newDummy);
        assertEq(Proxy(payable(liquidity)).getDummyImplementation(), newDummy);

        // 3. Team Multisig triggers the rollback
        vm.prank(TEAM_MULTISIG);
        rollbackProxy.rollbackDummyImplementation();

        // 4. Verify restoration
        assertEq(Proxy(payable(liquidity)).getDummyImplementation(), oldDummy);
        // Also verify that getRollbackDummyImplementation got cleared
        (address rollbackAddress, uint256 rollbackTime) = rollbackProxy.getRollbackDummyImplementation();
        assertEq(rollbackAddress, address(0));
        assertEq(rollbackTime, 0);
    }

    /// @dev Tests setDummyImplementation reverts when setting zero address (prevents sig-slot collision)
    function test_setDummyImplementation_revertsWhenZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("ERC1967: new implementation is the zero address");
        Proxy(payable(liquidity)).setDummyImplementation(address(0));
    }

    /// @dev Tests registerRollbackDummyImplementation reverts when current dummy is zero (prevents sig-slot collision)
    function test_registerRollbackDummyImplementation_revertsWhenZeroDummy() public {
        // EIP1967 implementation slot (same as _DUMMY_IMPLEMENTATION_SLOT in proxy.sol)
        bytes32 dummySlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(liquidity), dummySlot, bytes32(uint256(0)));
        assertEq(Proxy(payable(liquidity)).getDummyImplementation(), address(0));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__ZeroDummyImplementation
            )
        );
        rollbackProxy.registerRollbackDummyImplementation();
    }

    /// @dev Tests registerRollbackDummyImplementation reverts when called by non-admin
    function test_registerRollbackDummyImplementation_revertsWhenUnauthorized() public {
        // Try with a non-admin (TEAM_MULTISIG)
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.registerRollbackDummyImplementation();

        // Try with another random address
        address notAdmin = address(0x7aCe);
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.registerRollbackDummyImplementation();
    }

    /// @dev Tests registerRollbackDummyImplementation reverts when rollback already registered (within period)
    function test_registerRollbackDummyImplementation_revertsWhenAlreadyExists() public {
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();

        // Still within ROLLBACK_PERIOD — must revert
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__AlreadyExists
            )
        );
        rollbackProxy.registerRollbackDummyImplementation();
    }

    /// @dev Tests registerRollbackDummyImplementation allows re-registration after period expired
    function test_registerRollbackDummyImplementation_allowsReRegisterAfterExpired() public {
        address oldDummy = Proxy(payable(liquidity)).getDummyImplementation();
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();
        (address regDummy, uint256 regTs) = rollbackProxy.getRollbackDummyImplementation();
        assertEq(regDummy, oldDummy);
        assertEq(regTs, 1); // vm.warp(1) in setUp

        skip(ROLLBACK_PERIOD + 1);
        // Re-register should succeed (expired entry is cleared then overwritten)
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();
        (address regDummy2, uint256 regTs2) = rollbackProxy.getRollbackDummyImplementation();
        assertEq(regDummy2, oldDummy);
        assertGt(regTs2, regTs);
    }

    /// @dev Tests rollbackDummyImplementation reverts when called by non-multisig
    function test_rollbackDummyImplementation_revertsWhenUnauthorized() public {
        // Register dummy implementation via admin first
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();

        // Try with admin (should fail: onlyMultisig)
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.rollbackDummyImplementation();

        // Try with a random non-multisig address
        address notMultisig = address(0xDEAD);
        vm.prank(notMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.rollbackDummyImplementation();
    }

    /// @dev Tests rollbackDummyImplementation reverts when not registered
    function test_rollbackDummyImplementation_revertsWhenNotRegistered() public {
        // Ensure dummy implementation slot is empty
        (address registeredDummy, ) = rollbackProxy.getRollbackDummyImplementation();
        assertEq(registeredDummy, address(0));

        // Only multisig can call, but nothing registered
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__NotRegistered
            )
        );
        rollbackProxy.rollbackDummyImplementation();
    }

    /// @dev Tests rollbackDummyImplementation reverts when expired
    function test_rollbackDummyImplementation_revertsWhenExpired() public {
        // Register dummy implementation
        vm.prank(admin);
        rollbackProxy.registerRollbackDummyImplementation();

        // Fast-forward beyond ROLLBACK_PERIOD
        skip(ROLLBACK_PERIOD + 100);

        // Try to rollback (should revert with Expired)
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidInfiniteProxyError.selector, ErrorTypes.InfiniteProxyRollback__Expired)
        );
        rollbackProxy.rollbackDummyImplementation();
    }

    /// @dev Tests full happy path of registering and rolling back implementation sigs
    function test_registerAndRollbackImplementation_success() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);

        // Old implementation uses one sig
        bytes4[] memory oldSigs = new bytes4[](1);
        oldSigs[0] = bytes4(keccak256("testFunction()"));

        // New implementation uses two different sigs
        bytes4[] memory newSigs = new bytes4[](2);
        newSigs[0] = bytes4(keccak256("otherFunctionA()"));
        newSigs[1] = bytes4(keccak256("otherFunctionB()"));

        // 1. Setup: register oldImpl with its sigs
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, oldSigs);

        // 2. Register rollback (captures sigs on oldImpl)
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);

        // Check data stored correctly in rollback
        RollbackCoreInternals.RollbackSigsSlot memory slotData = rollbackProxy.getRollbackForImplementation(oldImpl);
        bytes4[] memory regSigs = slotData.sigs;
        uint40 regTs = slotData.rollbackRegisterTimestamp;
        address replacesImpl = slotData.replacesImplementation;

        assertEq(regSigs.length, 1);
        assertEq(regSigs[0], oldSigs[0]);
        assertGt(regTs, 0);
        assertEq(replacesImpl, newImpl);

        // 3. Upgrade happens: remove old, add new for new sigs
        vm.startPrank(admin);
        Proxy(payable(liquidity)).removeImplementation(oldImpl);
        Proxy(payable(liquidity)).addImplementation(newImpl, newSigs);
        vm.stopPrank();

        // At this point, old sig has no mapping, new sigs map to newImpl
        assertEq(Proxy(payable(liquidity)).getSigsImplementation(newSigs[0]), newImpl);
        assertEq(Proxy(payable(liquidity)).getSigsImplementation(newSigs[1]), newImpl);

        // 4. Multisig triggers rollback
        vm.prank(TEAM_MULTISIG);
        rollbackProxy.rollbackImplementation(oldImpl, newImpl);

        // 5. Old sig now points back to oldImpl; new sigs should be removed,
        // as they are not supposed to remain mapped after a rollback
        assertEq(Proxy(payable(liquidity)).getSigsImplementation(oldSigs[0]), oldImpl);
        assertEq(Proxy(payable(liquidity)).getSigsImplementation(newSigs[0]), address(0));
        assertEq(Proxy(payable(liquidity)).getSigsImplementation(newSigs[1]), address(0));

        // After rollback, storage for rollback should be deleted
        RollbackCoreInternals.RollbackSigsSlot memory afterSlotData = rollbackProxy.getRollbackForImplementation(
            oldImpl
        );
        bytes4[] memory afterSigs = afterSlotData.sigs;
        uint40 afterTs = afterSlotData.rollbackRegisterTimestamp;
        address afterReplacesImpl = afterSlotData.replacesImplementation;
        assertEq(afterSigs.length, 0);
        assertEq(afterTs, 0);
        assertEq(afterReplacesImpl, address(0));
    }

    /// @dev Reverts when implementation has a sig whose rollback slot collides with dummy impl slot (0x4910fdfa)
    function test_registerRollbackImplementation_revertsWhenSigSlotCollidesWithDummySlot() public {
        // Selector 0x4910fdfa makes or(_ROLLBACK_SIG_SLOT_BASE, sig) == _ROLLBACK_DUMMY_IMPLEMENTATION_SLOT
        address collidingImpl = address(0xCCC);
        address otherImpl = address(0xDDD);
        bytes4[] memory collidingSigs = new bytes4[](1);
        collidingSigs[0] = bytes4(0x4910fdfa);

        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(collidingImpl, collidingSigs);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__SigSlotCollision
            )
        );
        rollbackProxy.registerRollbackImplementation(collidingImpl, otherImpl);
    }

    /// @dev Only admin can register rollback for implementation
    function test_registerRollbackImplementation_revertsWhenUnauthorized() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);

        // Try with a random account
        address notAdmin = address(0x2);
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Only multisig can trigger function-level rollback
    function test_rollbackImplementation_revertsWhenUnauthorized() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        // Setup by admin: register oldImpl and rollback data
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        // Simulate upgrade
        vm.prank(admin);
        Proxy(payable(liquidity)).removeImplementation(oldImpl);
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(newImpl, sigs);

        // Fail with unauthorized caller
        address notMultisig = address(0x31337);
        vm.prank(notMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__Unauthorized
            )
        );
        rollbackProxy.rollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Reverts if multisig tries to rollback an implementation not registered for rollback
    function test_rollbackImplementation_revertsWhenNotRegistered() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);

        // No rollback registered, so should revert
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__NotRegistered
            )
        );
        rollbackProxy.rollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Reverts if trying to rollback after expiration
    function test_rollbackImplementation_revertsWhenExpired() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        // Setup by admin: register oldImpl, set rollback
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        // Simulate upgrade
        vm.prank(admin);
        Proxy(payable(liquidity)).removeImplementation(oldImpl);
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(newImpl, sigs);

        // Fast-forward beyond ROLLBACK_PERIOD
        skip(ROLLBACK_PERIOD + 5);

        // Should revert with Expired
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidInfiniteProxyError.selector, ErrorTypes.InfiniteProxyRollback__Expired)
        );
        rollbackProxy.rollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Reverts if multisig tries to rollback for wrong (not replaced) implementation
    function test_rollbackImplementation_revertsWhenWrongNewImplementation() public {
        address oldImpl = address(0xAAA);
        address correctNewImpl = address(0xBBB);
        address wrongNewImpl = address(0xCCC);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        // Setup and register rollback for correctNewImpl
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, correctNewImpl);
        // Upgrade to correctNewImpl
        vm.prank(admin);
        Proxy(payable(liquidity)).removeImplementation(oldImpl);
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(correctNewImpl, sigs);

        // Attempt rollback with wrong newImpl
        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__NotRegistered
            )
        );
        rollbackProxy.rollbackImplementation(oldImpl, wrongNewImpl);
    }

    /// @dev Reverts to register rollback with empty sigs
    function test_registerRollbackImplementation_revertsWhenNoRollbackSigs() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);

        // Try to register rollback without any registered sigs
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__NoRollbackSigs
            )
        );
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Reverts to register rollback if already registered
    function test_registerRollbackImplementation_revertsWhenAlreadyExists() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        // Setup, register initial rollback
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);

        // Try to register again for the same implementation
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__AlreadyExists
            )
        );
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
    }

    /// @dev Reverts when registering rollback for an impl whose sig is already in rollback namespace (stale from expired rollback)
    function test_registerRollbackImplementation_revertsWhenSigAlreadyExists() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4 sigX = bytes4(keccak256("testFunction()"));
        bytes4 sigY = bytes4(keccak256("otherFunction()"));
        bytes4[] memory oldSigs = new bytes4[](1);
        oldSigs[0] = sigX;
        bytes4[] memory newSigs = new bytes4[](1);
        newSigs[0] = sigY;

        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, oldSigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        // Rollback namespace: sigX -> oldImpl. Upgrade so main no longer uses sigX.
        vm.prank(admin);
        Proxy(payable(liquidity)).removeImplementation(oldImpl);
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(newImpl, newSigs);
        // Main: sigY -> newImpl. Rollback still has sigX -> oldImpl (stale).
        address thirdImpl = address(0xCCC);
        bytes4[] memory thirdSigs = new bytes4[](1);
        thirdSigs[0] = sigX;
        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(thirdImpl, thirdSigs);
        // Registering rollback for thirdImpl would set sigX -> thirdImpl in rollback, but sigX is already oldImpl.
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__SigAlreadyExists
            )
        );
        rollbackProxy.registerRollbackImplementation(thirdImpl, address(0xDDD));
    }

    // ------------------------- cleanupExpiredRollbackImplementation -------------------------

    /// @dev Cleanup expired rollback storage succeeds and allows re-registration; callable by anyone
    function test_cleanupExpiredRollbackImplementation_success() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        assertGt(rollbackProxy.getRollbackForImplementation(oldImpl).sigs.length, 0);

        skip(ROLLBACK_PERIOD + 1);
        address anyCaller = address(0x999);
        vm.prank(anyCaller);
        vm.expectEmit(true, true, true, true);
        emit LogCleanupExpiredRollbackImplementation(oldImpl);
        rollbackProxy.cleanupExpiredRollbackImplementation(oldImpl);

        RollbackCoreInternals.RollbackSigsSlot memory after_ = rollbackProxy.getRollbackForImplementation(oldImpl);
        assertEq(after_.sigs.length, 0);
        assertEq(after_.rollbackRegisterTimestamp, 0);
        assertEq(after_.replacesImplementation, address(0));

        // Re-register rollback for same impl (previously blocked by SigAlreadyExists) now possible
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        assertGt(rollbackProxy.getRollbackForImplementation(oldImpl).sigs.length, 0);
    }

    /// @dev Cleanup reverts when no rollback registered for implementation
    function test_cleanupExpiredRollbackImplementation_revertsWhenNotRegistered() public {
        address randomImpl = address(0xDEF);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidInfiniteProxyError.selector,
                ErrorTypes.InfiniteProxyRollback__NotRegistered
            )
        );
        rollbackProxy.cleanupExpiredRollbackImplementation(randomImpl);
    }

    /// @dev Cleanup reverts when rollback period has not elapsed
    function test_cleanupExpiredRollbackImplementation_revertsWhenNotExpired() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        skip(ROLLBACK_PERIOD - 1); // still within period
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidInfiniteProxyError.selector, ErrorTypes.InfiniteProxyRollback__NotExpired)
        );
        rollbackProxy.cleanupExpiredRollbackImplementation(oldImpl);
    }

    /// @dev Cleanup is callable by non-admin (e.g. random user)
    function test_cleanupExpiredRollbackImplementation_callableByNonAdmin() public {
        address oldImpl = address(0xAAA);
        address newImpl = address(0xBBB);
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = bytes4(keccak256("testFunction()"));

        vm.prank(admin);
        Proxy(payable(liquidity)).addImplementation(oldImpl, sigs);
        vm.prank(admin);
        rollbackProxy.registerRollbackImplementation(oldImpl, newImpl);
        skip(ROLLBACK_PERIOD + 1);

        vm.prank(alice);
        rollbackProxy.cleanupExpiredRollbackImplementation(oldImpl);
        assertEq(rollbackProxy.getRollbackForImplementation(oldImpl).sigs.length, 0);
    }
}
