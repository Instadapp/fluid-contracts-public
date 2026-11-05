// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";

import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "../../../../../contracts/libraries/access/liquidityGovernanceAuth.sol";

contract LiquidityGovernanceAuthHarness is LiquidityGovernanceAuth {
    constructor(address liquidity_) LiquidityGovernanceAuth(liquidity_) {}

    function governance() external view returns (address) {
        return _governance();
    }

    function governanceSlot() external pure returns (bytes32) {
        return _LIQUIDITY_GOVERNANCE_SLOT;
    }

    function onlyGovernanceAction() external onlyGovernance returns (bool) {
        return true;
    }
}

contract LiquidityGovernanceAuthTest is Test {
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    LiquidityGovernanceAuthHarness internal harness;
    address internal governance;
    address internal stranger;

    function setUp() public {
        governance = makeAddr("governance");
        stranger = makeAddr("stranger");
        harness = new LiquidityGovernanceAuthHarness(LIQUIDITY);
        _mockGovernance(governance);
    }

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    function test_Constructor_SetsLiquidity() public {
        assertEq(harness.LIQUIDITY(), LIQUIDITY);
        assertEq(harness.governanceSlot(), GOVERNANCE_SLOT);
    }

    function test_Constructor_RevertsOnZeroLiquidity() public {
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        new LiquidityGovernanceAuthHarness(address(0));
    }

    function test_Governance_ReadsBoundLiquiditySlot() public {
        assertEq(harness.governance(), governance);

        address other_ = makeAddr("otherGov");
        _mockGovernance(other_);
        assertEq(harness.governance(), other_);
    }

    function test_Governance_UsesConstructorLiquidityNotHardcoded() public {
        address otherLiquidity_ = makeAddr("otherLiquidity");
        LiquidityGovernanceAuthHarness other_ = new LiquidityGovernanceAuthHarness(otherLiquidity_);
        address otherGov_ = makeAddr("otherGov");
        vm.mockCall(
            otherLiquidity_,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(otherGov_)))
        );
        assertEq(other_.governance(), otherGov_);
        assertEq(other_.LIQUIDITY(), otherLiquidity_);
    }

    function test_OnlyGovernance_AllowsGovernance() public {
        vm.prank(governance);
        assertTrue(harness.onlyGovernanceAction());
    }

    function test_OnlyGovernance_RevertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyGovernanceAction();
    }

    function test_OnlyGovernance_RevertsWhenGovernanceIsZero() public {
        _mockGovernance(address(0));
        vm.prank(stranger);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyGovernanceAction();
    }
}
