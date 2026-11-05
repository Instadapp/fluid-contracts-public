// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";

import { FluidAuthGate } from "contracts/config/authGate/main.sol";
import { FluidAuthLevels } from "contracts/config/authGate/interfaces/iAuthGate.sol";
import { FluidAuthGateProxy } from "contracts/config/authGate/proxy.sol";
import { BasicValidations } from "contracts/libraries/utils/basicValidations.sol";
import { LibsErrorTypes } from "contracts/libraries/errorTypes.sol";
import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "contracts/libraries/access/liquidityGovernanceAuth.sol";

// To test run:
// forge test -vvv --match-path test/foundry/config/authGate.t.sol
contract AuthGateTest is Test, FluidAuthLevels {
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address internal constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    FluidAuthGate internal authGate; // the proxy, typed as implementation
    FluidAuthGate internal implementation;
    address internal governance;
    address internal stranger;
    address internal teamTimelock;

    function setUp() public {
        governance = makeAddr("governance");
        stranger = makeAddr("stranger");
        teamTimelock = makeAddr("teamTimelock");
        _mockGovernance(governance);

        implementation = new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, teamTimelock);
        authGate = FluidAuthGate(
            address(new FluidAuthGateProxy(address(implementation), abi.encodeCall(implementation.initialize, ())))
        );
    }

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    function test_deployment() public view {
        assertEq(authGate.LIQUIDITY(), LIQUIDITY);
        assertEq(authGate.TEAM_MULTISIG(), TEAM_MULTISIG);
        assertEq(authGate.TEAM_MULTISIG2(), TEAM_MULTISIG2);
        assertEq(authGate.TEAM_MULTISIG_TIMELOCK(), teamTimelock);
    }

    function test_constructor_RevertIfZeroLiquidity() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        new FluidAuthGate(address(0), TEAM_MULTISIG, TEAM_MULTISIG2, teamTimelock);
    }

    function test_constructor_RevertIfZeroIdentity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidAuthGate(LIQUIDITY, address(0), TEAM_MULTISIG2, teamTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, address(0), teamTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                BasicValidations.FluidBasicValidationsError.selector,
                LibsErrorTypes.BasicValidations__AddressZero
            )
        );
        new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, address(0));
    }

    function test_constructor_RevertIfEqualIdentities() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG, teamTimelock);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, TEAM_MULTISIG);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, TEAM_MULTISIG2);
    }

    function test_governanceOverlapResolvesToMax() public {
        FluidAuthGate gate_ = new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, governance);
        assertEq(gate_.authLevel(governance), SECURITY_LEVEL_MAX);
        gate_.requireAuthLevelMax(governance);

        gate_ = new FluidAuthGate(LIQUIDITY, governance, TEAM_MULTISIG2, teamTimelock);
        assertEq(gate_.authLevel(governance), SECURITY_LEVEL_MAX);
    }

    function test_initialize_RevertIfCalledTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        authGate.initialize();
    }

    function test_initialize_RevertOnImplementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize();
    }

    // ==================== governance ====================

    function test_governance() public view {
        assertEq(authGate.governance(), governance);
    }

    function test_isGovernance() public view {
        assertTrue(authGate.isGovernance(governance));
        assertFalse(authGate.isGovernance(stranger));
        assertFalse(authGate.isGovernance(TEAM_MULTISIG));
        assertFalse(authGate.isGovernance(address(0)));
    }

    function test_isGovernance_TracksLiquidityAdminChange() public {
        address newGovernance_ = makeAddr("newGovernance");
        _mockGovernance(newGovernance_);
        assertTrue(authGate.isGovernance(newGovernance_));
        assertFalse(authGate.isGovernance(governance));
    }

    // ==================== auth levels ====================

    function test_authLevel() public view {
        assertEq(authGate.authLevel(governance), SECURITY_LEVEL_MAX);
        assertEq(authGate.authLevel(teamTimelock), SECURITY_LEVEL_CRITICAL);
        assertEq(authGate.authLevel(TEAM_MULTISIG), SECURITY_LEVEL_HIGH);
        assertEq(authGate.authLevel(TEAM_MULTISIG2), SECURITY_LEVEL_MID);
        assertEq(authGate.authLevel(stranger), 0);
        assertEq(authGate.authLevel(address(0)), 0);
    }

    // ==================== requireAuthLevel ====================

    function test_requireAuthLevel_GovernanceOnlyAtMax() public {
        authGate.requireAuthLevel(governance, 0);
        authGate.requireAuthLevel(governance, SECURITY_LEVEL_MAX);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(governance, SECURITY_LEVEL_MAX + 1);
    }

    function test_requireAuthLevel_MultisigsPassByLevel() public view {
        authGate.requireAuthLevel(TEAM_MULTISIG, SECURITY_LEVEL_HIGH);
        authGate.requireAuthLevel(TEAM_MULTISIG2, SECURITY_LEVEL_MID);
        authGate.requireAuthLevel(teamTimelock, SECURITY_LEVEL_CRITICAL);
        authGate.requireAuthLevel(teamTimelock, SECURITY_LEVEL_HIGH);
    }

    function test_requireAuthLevel_RevertIfLevelTooLow() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(TEAM_MULTISIG2, SECURITY_LEVEL_HIGH);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(TEAM_MULTISIG, SECURITY_LEVEL_CRITICAL);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(teamTimelock, SECURITY_LEVEL_MAX);
    }

    function test_requireAuthLevel_RevertIfStranger() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(stranger, 0);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevel(address(0), SECURITY_LEVEL_LOW);
    }

    function test_requireAuthLevelHelpers() public view {
        authGate.requireAuthLevelLow(TEAM_MULTISIG2);
        authGate.requireAuthLevelMid(TEAM_MULTISIG2);
        authGate.requireAuthLevelHigh(TEAM_MULTISIG);
        authGate.requireAuthLevelCritical(teamTimelock);
        authGate.requireAuthLevelMax(governance);
    }

    function test_requireAuthLevelHelpers_RevertIfLevelTooLow() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevelHigh(TEAM_MULTISIG2);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevelCritical(TEAM_MULTISIG);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevelMax(teamTimelock);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevelLow(stranger);

        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.requireAuthLevelMid(stranger);
    }

    // ==================== upgrades ====================

    function test_upgradeTo_ByGovernance() public {
        FluidAuthGate newImplementation_ = new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, teamTimelock);

        vm.prank(governance);
        authGate.upgradeTo(address(newImplementation_));

        assertEq(
            address(uint160(uint256(vm.load(address(authGate), IMPLEMENTATION_SLOT)))),
            address(newImplementation_)
        );
        assertEq(authGate.authLevel(TEAM_MULTISIG), SECURITY_LEVEL_HIGH);
    }

    function test_upgradeTo_RevertIfNotGovernance() public {
        FluidAuthGate newImplementation_ = new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, teamTimelock);

        vm.prank(stranger);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.upgradeTo(address(newImplementation_));

        vm.prank(TEAM_MULTISIG);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        authGate.upgradeTo(address(newImplementation_));
    }

    /// @dev an implementation bound to another Liquidity would move governance with it and lock the gate
    function test_upgradeTo_RevertIfImplementationLiquidityMismatch() public {
        FluidAuthGate foreign_ = new FluidAuthGate(
            makeAddr("otherLiquidity"),
            TEAM_MULTISIG,
            TEAM_MULTISIG2,
            teamTimelock
        );

        vm.prank(governance);
        vm.expectRevert(FluidAuthGate.AuthGate__ImplementationLiquidityMismatch.selector);
        authGate.upgradeTo(address(foreign_));

        // the same upgrade with a matching Liquidity goes through, so the assert above is not vacuous
        FluidAuthGate matching_ = new FluidAuthGate(LIQUIDITY, TEAM_MULTISIG, TEAM_MULTISIG2, teamTimelock);
        vm.prank(governance);
        authGate.upgradeTo(address(matching_));
        assertEq(address(uint160(uint256(vm.load(address(authGate), IMPLEMENTATION_SLOT)))), address(matching_));
    }
}
