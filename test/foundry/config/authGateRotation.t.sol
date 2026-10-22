// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidPauseAuth } from "contracts/config/pauseAuth/main.sol";
import { IFluidAuthGate, FluidAuthLevels } from "contracts/config/authGate/interfaces/iAuthGate.sol";

interface IFluidLiquidityGovernance {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

// the gate is 0.8.36 and the consumer 0.8.21, so the gate is deployed by artifact and upgraded through this
interface IFluidAuthGateUpgradeable {
    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

error Access__Unauthorized();

// To test run:
// forge test -vvv --match-path test/foundry/config/authGateRotation.t.sol
contract AuthGateRotationTest is Test, FluidAuthLevels {
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal liquidity;
    address internal governance;
    address internal stranger;
    address internal teamTimelock;
    address internal highMultisigA;
    address internal highMultisigB;
    address internal midMultisigA;
    address internal midMultisigB;

    address internal gateProxy;

    FluidPauseAuth internal pauseAuth;

    function setUp() public {
        liquidity = makeAddr("liquidity");
        governance = makeAddr("governance");
        stranger = makeAddr("stranger");
        teamTimelock = makeAddr("teamTimelock");
        highMultisigA = makeAddr("highMultisigA");
        highMultisigB = makeAddr("highMultisigB");
        midMultisigA = makeAddr("midMultisigA");
        midMultisigB = makeAddr("midMultisigB");
        _mockGovernance(governance);

        address implementationV1_ = _deployGate(highMultisigA, midMultisigA);
        gateProxy = deployCode(
            "contracts/config/authGate/proxy.sol:FluidAuthGateProxy",
            abi.encode(implementationV1_, abi.encodeWithSignature("initialize()"))
        );

        pauseAuth = new FluidPauseAuth(
            liquidity,
            makeAddr("vaultFactory"),
            makeAddr("dexFactory"),
            makeAddr("pauseAuthLiquidity"),
            makeAddr("pauseAuthDex"),
            makeAddr("pauseAuthOracleV2"),
            gateProxy
        );
    }

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            liquidity,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    function _deployGate(address teamMultisig_, address teamMultisig2_) internal returns (address) {
        return
            deployCode(
                "contracts/config/authGate/main.sol:FluidAuthGate",
                abi.encode(liquidity, teamMultisig_, teamMultisig2_, teamTimelock)
            );
    }

    function test_rotation_newMultisigTakesOverWithoutRedeploy() public {
        address botAuth_ = makeAddr("botAuth");

        vm.prank(highMultisigA);
        pauseAuth.setPauseAuth(botAuth_, 1);
        assertEq(pauseAuth.pauseAuths(botAuth_), 1);

        vm.prank(highMultisigB);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setPauseAuth(botAuth_, 2);

        address implementationV2_ = _deployGate(highMultisigB, midMultisigA);

        vm.prank(governance);
        IFluidAuthGateUpgradeable(gateProxy).upgradeTo(implementationV2_);

        vm.prank(highMultisigB);
        pauseAuth.setPauseAuth(botAuth_, 2);
        assertEq(pauseAuth.pauseAuths(botAuth_), 2);

        vm.prank(highMultisigA);
        vm.expectRevert(Access__Unauthorized.selector);
        pauseAuth.setPauseAuth(botAuth_, 3);
    }

    function test_rotation_midTierFollowsUpgrade() public {
        assertEq(IFluidAuthGate(gateProxy).authLevel(midMultisigA), SECURITY_LEVEL_MID);
        assertEq(IFluidAuthGate(gateProxy).authLevel(midMultisigB), 0);

        address implementationV2_ = _deployGate(highMultisigA, midMultisigB);

        vm.prank(governance);
        IFluidAuthGateUpgradeable(gateProxy).upgradeTo(implementationV2_);

        assertEq(IFluidAuthGate(gateProxy).authLevel(midMultisigB), SECURITY_LEVEL_MID);
        assertEq(IFluidAuthGate(gateProxy).authLevel(midMultisigA), 0);
    }

    function test_upgrade_RevertIfNotGovernance() public {
        address implementationV2_ = _deployGate(highMultisigB, midMultisigA);

        vm.prank(stranger);
        vm.expectRevert(Access__Unauthorized.selector);
        IFluidAuthGateUpgradeable(gateProxy).upgradeTo(implementationV2_);

        vm.prank(highMultisigA);
        vm.expectRevert(Access__Unauthorized.selector);
        IFluidAuthGateUpgradeable(gateProxy).upgradeTo(implementationV2_);
    }

    function test_upgradeToAndCall_RevertIfReinitialize() public {
        address implementationV2_ = _deployGate(highMultisigB, midMultisigA);
        bytes32 slotBefore_ = vm.load(gateProxy, bytes32(0));

        vm.prank(governance);
        vm.expectRevert("Initializable: contract is already initialized");
        IFluidAuthGateUpgradeable(gateProxy).upgradeToAndCall(
            implementationV2_,
            abi.encodeWithSignature("initialize()")
        );

        vm.prank(governance);
        IFluidAuthGateUpgradeable(gateProxy).upgradeTo(implementationV2_);

        assertEq(vm.load(gateProxy, bytes32(0)), slotBefore_);
        assertEq(IFluidAuthGate(gateProxy).authLevel(highMultisigB), SECURITY_LEVEL_HIGH);
    }
}
