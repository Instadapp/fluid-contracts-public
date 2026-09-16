// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";

import { BasicAuth } from "../../../../../contracts/libraries/access/basicAuth.sol";
import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "../../../../../contracts/libraries/access/liquidityGovernanceAuth.sol";

contract BasicAuthHarness is BasicAuth {
    mapping(address => uint256) internal _auths;

    constructor(address liquidity_) LiquidityGovernanceAuth(liquidity_) {}

    function _authClass(address auth_) internal view override returns (uint256) {
        return _auths[auth_];
    }

    function _setAuthClass(address auth_, uint256 authClass_) internal override {
        _auths[auth_] = authClass_;
    }

    function governance() external view returns (address) {
        return _governance();
    }

    function onlyAuthAction() external onlyAuth returns (bool) {
        return true;
    }

    function onlyAuthClassAction(uint256 class_) external onlyAuthClass(class_) returns (bool) {
        return true;
    }

    function onlyAuthClassAboveAction(uint256 class_) external onlyAuthClassAbove(class_) returns (bool) {
        return true;
    }
}

contract BasicAuthTest is Test {
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    BasicAuthHarness internal harness;
    address internal governance;
    address internal auth;
    address internal stranger;

    event LogUpdateAuth(address indexed auth, uint256 authClass);

    function setUp() public {
        governance = makeAddr("governance");
        auth = makeAddr("auth");
        stranger = makeAddr("stranger");
        harness = new BasicAuthHarness(LIQUIDITY);
        _mockGovernance(governance);
    }

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                isAuth / authClass
    //////////////////////////////////////////////////////////////*/

    function test_IsAuth_FalseByDefault() public {
        assertFalse(harness.isAuth(auth));
        assertFalse(harness.isAuth(stranger));
        assertFalse(harness.isAuth(governance));
        assertEq(harness.authClass(auth), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              updateAuth
    //////////////////////////////////////////////////////////////*/

    function test_UpdateAuth_GovernanceCanGrantAndRevoke() public {
        vm.prank(governance);
        vm.expectEmit(true, false, false, true, address(harness));
        emit LogUpdateAuth(auth, 1);
        harness.updateAuth(auth, 1);
        assertTrue(harness.isAuth(auth));
        assertEq(harness.authClass(auth), 1);

        vm.prank(governance);
        vm.expectEmit(true, false, false, true, address(harness));
        emit LogUpdateAuth(auth, 0);
        harness.updateAuth(auth, 0);
        assertFalse(harness.isAuth(auth));
        assertEq(harness.authClass(auth), 0);
    }

    function test_UpdateAuth_RevertsForNonGovernance() public {
        vm.prank(stranger);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.updateAuth(auth, 1);

        vm.prank(auth);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.updateAuth(auth, 1);

        assertFalse(harness.isAuth(auth));
    }

    function test_UpdateAuth_RevertsForZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.updateAuth(address(0), 1);
    }

    function test_UpdateAuth_AuthCannotUpdateEvenIfListed() public {
        vm.prank(governance);
        harness.updateAuth(auth, 1);

        vm.prank(auth);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.updateAuth(stranger, 1);
    }

    /*//////////////////////////////////////////////////////////////
                               onlyAuth
    //////////////////////////////////////////////////////////////*/

    function test_OnlyAuth_AllowsGovernanceWithoutListing() public {
        assertFalse(harness.isAuth(governance));
        vm.prank(governance);
        assertTrue(harness.onlyAuthAction());
    }

    function test_OnlyAuth_AllowsListedAuth() public {
        vm.prank(governance);
        harness.updateAuth(auth, 2);

        vm.prank(auth);
        assertTrue(harness.onlyAuthAction());
    }

    function test_OnlyAuth_RevertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyAuthAction();
    }

    function test_OnlyAuth_RevertsAfterAuthRevoked() public {
        vm.startPrank(governance);
        harness.updateAuth(auth, 1);
        harness.updateAuth(auth, 0);
        vm.stopPrank();

        vm.prank(auth);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyAuthAction();
    }

    /*//////////////////////////////////////////////////////////////
                          onlyAuthClass / onlyAuthClassAbove
    //////////////////////////////////////////////////////////////*/

    function test_OnlyAuthClass_AllowsExactClass() public {
        vm.prank(governance);
        harness.updateAuth(auth, 2);

        vm.prank(auth);
        assertTrue(harness.onlyAuthClassAction(2));

        vm.prank(auth);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyAuthClassAction(1);
    }

    function test_OnlyAuthClass_AllowsGovernance() public {
        vm.prank(governance);
        assertTrue(harness.onlyAuthClassAction(99));
    }

    function test_OnlyAuthClassAbove_AllowsEqualOrHigher() public {
        vm.prank(governance);
        harness.updateAuth(auth, 2);

        vm.prank(auth);
        assertTrue(harness.onlyAuthClassAboveAction(1));
        vm.prank(auth);
        assertTrue(harness.onlyAuthClassAboveAction(2));

        vm.prank(auth);
        vm.expectRevert(LiquidityGovernanceAuth.Access__Unauthorized.selector);
        harness.onlyAuthClassAboveAction(3);
    }

    function test_OnlyAuthClassAbove_AllowsGovernance() public {
        vm.prank(governance);
        assertTrue(harness.onlyAuthClassAboveAction(99));
    }
}
