//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "../testERC20.sol";
import { TestHelpers } from "../liquidity/liquidityTestHelpers.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";

import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { fTokenBaseActionsTest, fTokenBasePermitTest, fTokenBaseSetUp, fTokenGasTestFirstDeposit, fTokenGasTestSecondDeposit } from "./fToken.t.sol";
// import { fTokenBaseInvariantTestRewards, fTokenBaseInvariantTestRewardsNoBorrowers, fTokenBaseInvariantTestCore, fTokenBaseInvariantTestWithRepay } from "./fTokenInvariant.t.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { Error as LiquidityError } from "../../../contracts/liquidity/error.sol";
import { ErrorTypes as LiquidityErrorTypes } from "../../../contracts/liquidity/errorTypes.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

abstract contract fTokenWithInterestTestBase is fTokenBaseSetUp {
    function _createToken(
        FluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) internal virtual override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(asset_), "fToken", false));
    }
}

contract fTokenWithInterestGasTestFirstDeposit is fTokenWithInterestTestBase, fTokenGasTestFirstDeposit {}

contract fTokenWithInterestGasTestSecondDeposit is fTokenWithInterestTestBase, fTokenGasTestSecondDeposit {
    function setUp() public virtual override(fTokenGasTestSecondDeposit, fTokenBaseSetUp) {
        super.setUp();
    }
}

contract fTokenWithInterestActionsTest is fTokenWithInterestTestBase, fTokenBaseActionsTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function testMetadata(string calldata name, string calldata symbol) public {
        TestERC20 underlying = new TestERC20(name, symbol);

        // config for token must exist fur the underlying asset at liquidity before creating the fToken
        // 1. Setup rate data for USDC and DAI, must happen before token configs
        _setDefaultRateDataV1(address(liquidity), admin, address(underlying));

        // 2. Add a token configuration for USDC and DAI
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(underlying),
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        IFluidLiquidity(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        lendingFToken = fToken(address(_createToken(factory, IERC20(address(underlying)))));
        assertEq(lendingFToken.name(), string(abi.encodePacked("Fluid ", name)));
        assertEq(lendingFToken.symbol(), string(abi.encodePacked("f", symbol)));
        assertEq(address(lendingFToken.asset()), address(underlying));
    }

    function test_deposit_WithMaxAssetAmount() public override {
        // send out some balance of alice to get to more realistic test amunts
        // (alternatively asserts below would have to be adjusted for some minor inaccuracy)
        uint256 underlyingBalanceBeforeTransfer = underlying.balanceOf(alice);
        vm.prank(alice);
        underlying.transfer(admin, underlyingBalanceBeforeTransfer - DEFAULT_AMOUNT * 10);
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 balance = lendingFToken.deposit(UINT256_MAX, alice);

        assertEqDecimal(balance, underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), underlyingBalanceBefore);
    }

    function test_mint_WithMaxAssetAmount() public override {
        // send out some balance of alice to get to more realistic test amunts
        // (alternatively asserts below would have to be adjusted for some minor inaccuracy)
        uint256 underlyingBalanceBeforeTransfer = underlying.balanceOf(alice);
        vm.prank(alice);
        underlying.transfer(admin, underlyingBalanceBeforeTransfer - DEFAULT_AMOUNT * 10);
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 balance = lendingFToken.mint(UINT256_MAX, alice);

        assertEqDecimal(balance, underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), underlyingBalanceBefore);
    }

    function test_minDeposit_MinBigMathRounding() public override {
        uint256 minDeposit = lendingFToken.minDeposit();
        vm.prank(alice);
        underlying.approve(address(lendingFToken), type(uint256).max);
        vm.prank(alice);
        lendingFToken.deposit(1e22, alice);
        minDeposit = lendingFToken.minDeposit();

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityError.FluidLiquidityError.selector,
                LiquidityErrorTypes.UserModule__OperateAmountInsufficient
            )
        );
        vm.prank(alice);
        lendingFToken.deposit(minDeposit - 1, alice);
        vm.prank(alice);
        lendingFToken.deposit(minDeposit, alice);
    }
}

// contract fTokenWithInterestPermitTest is fTokenWithInterestTestBase, fTokenBasePermitTest {
//     function setUp() public virtual override(fTokenBaseSetUp, fTokenBasePermitTest) {
//         super.setUp();
//     }
// }

// contract fTokenWithInterestInvariantTestCore is fTokenWithInterestTestBase, fTokenBaseInvariantTestCore {
//     function setUp() public virtual override(fTokenBaseSetUp, fTokenBaseInvariantTestCore) {
//         super.setUp();
//     }
// }

// contract fTokenWithInterestInvariantTestRewards is fTokenWithInterestTestBase, fTokenBaseInvariantTestRewards {
//     function setUp() public virtual override(fTokenBaseSetUp, fTokenBaseInvariantTestRewards) {
//         super.setUp();
//     }
// }

// contract fTokenWithInterestInvariantTestRewardsNoBorrowers is
//     fTokenWithInterestTestBase,
//     fTokenBaseInvariantTestRewardsNoBorrowers
// {
//     function setUp() public virtual override(fTokenBaseSetUp, fTokenBaseInvariantTestRewardsNoBorrowers) {
//         super.setUp();
//     }
// }

// contract fTokenWithInterestInvariantTestRepay is fTokenWithInterestTestBase, fTokenBaseInvariantTestWithRepay {
//     function setUp() public virtual override(fTokenBaseSetUp, fTokenBaseInvariantTestWithRepay) {
//         super.setUp();
//     }
// }
