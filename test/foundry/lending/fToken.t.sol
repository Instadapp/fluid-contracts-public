//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { FluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { Events as fTokenEvents } from "../../../contracts/protocols/lending/fToken/events.sol";
import { Error as fTokenError } from "../../../contracts/protocols/lending/error.sol";
import { IFluidLendingRewardsRateModel } from "../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidLiquidityProxy } from "../../../contracts/liquidity/proxy.sol";
import { Error as LiquidityError } from "../../../contracts/liquidity/error.sol";
import { ErrorTypes as LiquidityErrorTypes } from "../../../contracts/liquidity/errorTypes.sol";
import { IAllowanceTransfer } from "../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { TestERC20 } from "../testERC20.sol";
import { LendingRewardsRateMockModel } from "./mocks/rewardsMock.sol";
import { ReentrantAttacker } from "./mocks/fTokenReentrantAttacker.sol";
import { SigUtils } from "./helper/sigUtils.sol";

import { Error } from "../../../contracts/protocols/lending/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/lending/errorTypes.sol";
import { IERC2612 } from "../../../contracts/protocols/lending/interfaces/permit2/IERC2612.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";

import { fTokenHarness } from "./harness/fTokenHarness.sol";

import "forge-std/console2.sol";

// todo: test LogUpdateRates exact topics.

abstract contract fTokenBaseSetUp is LiquidityBaseTest {
    uint256 constant PRECISION = 1e4;
    uint256 constant DEFAULT_UNIT = 1e6;
    uint256 constant DEFAULT_AMOUNT = 1000 * DEFAULT_UNIT;
    uint256 constant DEFAULT_DECIMALS = 6;

    fToken lendingFToken;
    LendingRewardsRateMockModel rewards;
    FluidLendingFactory factory;

    TestERC20 underlying;

    IFluidLiquidity liquidityProxy;

    function setUp() public virtual override {
        super.setUp();
        liquidityProxy = IFluidLiquidity(address(liquidity));

        factory = new FluidLendingFactory(liquidityProxy, admin);

        underlying = TestERC20(_createUnderlying());

        // make sure token is set up at Liquidity
        _setDefaultRateDataV1(address(liquidity), admin, address(underlying));
        // add a token configuration for underyling
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(underlying),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        lendingFToken = fToken(address(_createToken(factory, underlying)));
        // reset all fTokenType creation codes for clean tests state
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", new bytes(0));
        vm.prank(admin);
        factory.setFTokenCreationCode("NativeUnderlying", new bytes(0));

        // set 20% a year rewards rate (max accepted at fToken is 25%)
        rewards = new LendingRewardsRateMockModel();
        rewards.setRate(20 * 1e12); // 20%
        rewards.setStartTime(block.timestamp);
        vm.prank(admin);
        lendingFToken.updateRewards(IFluidLendingRewardsRateModel(address(rewards)));
        vm.prank(admin);
        lendingFToken.updateRebalancer(admin);

        vm.label(address(underlying), "underlying");
        underlying.mint(admin, 1e50 ether);
        underlying.mint(alice, 1e50 ether);
        underlying.mint(bob, 1e50 ether);

        // approve underlying to fToken
        _setApproval(underlying, address(lendingFToken), admin);
        _setApproval(underlying, address(lendingFToken), alice);
        _setApproval(underlying, address(lendingFToken), bob);
        // approve underlying to mockProtocol
        _setApproval(underlying, address(mockProtocol), admin);
        _setApproval(underlying, address(mockProtocol), alice);
        _setApproval(underlying, address(mockProtocol), bob);

        // enable fToken to supply tokens
        _setUserAllowancesDefault(address(liquidity), admin, address(underlying), address(lendingFToken));

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(underlying), address(mockProtocol));

        // supply as alice to init protocol for gas report reasons
        _supply(mockProtocol, address(underlying), alice, DEFAULT_AMOUNT);
    }

    function _createUnderlying() internal virtual returns (address) {
        return address(USDC);
    }

    function _createToken(FluidLendingFactory lendingFactory_, IERC20 asset_) internal virtual returns (IERC4626);
}

abstract contract fTokenGasTestFirstDeposit is fTokenBaseSetUp {
    function test_deposit_GasFirstDeposit() public {
        uint256 snap = gasleft();

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 firstDepositGas = snap - gasleft();
        console2.logString("Lending fToken: first deposit gas cost");
        console2.logUint(firstDepositGas);
    }
}

abstract contract fTokenGasTestSecondDeposit is fTokenBaseSetUp {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
    }

    function test_deposit_GasSecondDeposit() public {
        uint256 snap = gasleft();

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 secondDepositGas = snap - gasleft();
        console2.logString("Lending fToken: second deposit gas cost");
        console2.logUint(secondDepositGas);
    }
}

abstract contract fTokenBaseActionsTest is fTokenBaseSetUp, fTokenEvents {
    using SignedMath for int256;

    function test_deposit() public {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    }

    function test_deposit_DepositWithMinSharesAmountOut() public {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT);
        assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    }

    function test_deposit_RevertIfLessThanMinSharesAmountOut() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MinAmountOut));
        lendingFToken.deposit(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT + 1);
    }

    function test_deposit_WithMaxAssetAmount() public virtual {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 balance = lendingFToken.deposit(UINT256_MAX, alice);

        assertEqDecimal(balance, underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), underlyingBalanceBefore);
    }

    function test_deposit_RevertIfDepositInsignificant() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        vm.warp(block.timestamp + PASS_1YEAR_TIME);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__DepositInsignificant)
        );
        vm.prank(alice);
        lendingFToken.deposit(1, alice);
    }

    function test_mint() public {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = lendingFToken.mint(DEFAULT_AMOUNT, alice);

        assertEqDecimal(assets, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    }

    function test_mint_WithMaxAssetAmount() public virtual {
        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 balance = lendingFToken.mint(UINT256_MAX, alice);

        assertEqDecimal(balance, underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEqDecimal(lendingFToken.balanceOf(alice), underlyingBalanceBefore, DEFAULT_DECIMALS);
        assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), underlyingBalanceBefore);
    }

    function test_mint_WithMaxAssets() public {
        vm.prank(alice);
        lendingFToken.mint(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT);
    }

    function test_mint_RevertIfMaxAssetsIsSurpassed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        lendingFToken.mint(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT - 1);
    }

    function test_withdraw() public {
        vm.startPrank(alice);

        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        uint256 shares = lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice);

        assertEq(shares, DEFAULT_AMOUNT);
        assertEq(lendingFToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);

        vm.stopPrank();
    }

    function test_withdraw_WithMaxAssetAmount() public {
        vm.startPrank(alice);

        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        uint256 shares = lendingFToken.withdraw(UINT256_MAX, alice, alice);

        assertEq(shares, DEFAULT_AMOUNT);
        assertEq(lendingFToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);

        vm.stopPrank();
    }

    function test_withdraw_WithWithdrawableResolver() public virtual {
        vm.startPrank(alice);

        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(lendingFToken),
            address(USDC)
        );

        lendingFToken.withdraw(userSupplyData.withdrawable, alice, alice);

        (userSupplyData, ) = resolver.getUserSupplyData(address(lendingFToken), address(USDC));
        assertEq(userSupplyData.withdrawable, 0);
        vm.stopPrank();
    }

    function test_withdraw_SenderIsNotOwnerCase() public {
        uint256 aliceBalanceBeforeDeposit = lendingFToken.balanceOf(alice);
        uint256 bobBalanceBeforeDeposit = lendingFToken.balanceOf(bob);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        vm.prank(bob);
        lendingFToken.deposit(DEFAULT_AMOUNT, bob);

        uint256 aliceBalanceAfterDeposit = lendingFToken.balanceOf(alice);
        uint256 bobBalanceAfterDeposit = lendingFToken.balanceOf(bob);

        assertEq(aliceBalanceBeforeDeposit, aliceBalanceAfterDeposit - DEFAULT_AMOUNT);
        assertEq(bobBalanceBeforeDeposit, bobBalanceAfterDeposit - DEFAULT_AMOUNT);

        vm.prank(bob);
        lendingFToken.approve(alice, DEFAULT_AMOUNT);
        vm.prank(alice);
        lendingFToken.withdraw(DEFAULT_AMOUNT, alice, bob);

        assertEq(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT);
        assertEq(lendingFToken.balanceOf(bob), bobBalanceAfterDeposit - DEFAULT_AMOUNT);
    }

    function test_withdraw_WithMaxSharesBurn() public {
        vm.startPrank(alice);
        uint256 aliceBalanceBeforeDeposit = lendingFToken.balanceOf(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        uint256 aliceBalanceAfterDeposit = lendingFToken.balanceOf(alice);
        assertEq(aliceBalanceBeforeDeposit, aliceBalanceAfterDeposit - DEFAULT_AMOUNT);

        lendingFToken.withdraw(UINT256_MAX, alice, alice, DEFAULT_AMOUNT);
        uint256 aliceBalanceAfterWithdraw = lendingFToken.balanceOf(alice);
        vm.stopPrank();

        assertEq(aliceBalanceBeforeDeposit, aliceBalanceAfterWithdraw);
    }

    function test_withdraw_RevertIfMaxSharesBurnIsSurpassed() public {
        vm.startPrank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice, DEFAULT_AMOUNT - 1);
        vm.stopPrank();
    }

    function test_redeem() public {
        vm.startPrank(alice);

        lendingFToken.mint(DEFAULT_AMOUNT, alice);

        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        uint256 assets = lendingFToken.redeem(lendingFToken.balanceOf(alice), alice, alice);
        vm.stopPrank();

        assertEq(lendingFToken.balanceOf(alice), 0);
        assertEq(DEFAULT_AMOUNT, assets);
        assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);
    }

    function test_redeem_WithMaxAssetAmount() public {
        vm.startPrank(alice);

        lendingFToken.mint(DEFAULT_AMOUNT, alice);

        uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
        uint256 assets = lendingFToken.redeem(UINT256_MAX, alice, alice);
        vm.stopPrank();

        assertEq(lendingFToken.balanceOf(alice), 0);
        assertEq(DEFAULT_AMOUNT, assets);
        assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);
    }

    function test_redeem_WithMinSharesAmountOut() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBeforeDeposit = lendingFToken.balanceOf(alice);

        lendingFToken.mint(DEFAULT_AMOUNT, alice);

        uint256 aliceBalanceAfterDeposit = lendingFToken.balanceOf(alice);

        assertEq(aliceBalanceBeforeDeposit, aliceBalanceAfterDeposit - DEFAULT_AMOUNT);

        lendingFToken.redeem(UINT256_MAX, alice, alice, DEFAULT_AMOUNT);

        assertEq(lendingFToken.balanceOf(alice), aliceBalanceBeforeDeposit);

        vm.stopPrank();
    }

    function test_redeem_SenderIsNotOwnerCase() public {
        uint256 aliceBalanceBeforeDeposit = lendingFToken.balanceOf(alice);
        uint256 bobBalanceBeforeDeposit = lendingFToken.balanceOf(bob);

        vm.prank(alice);
        lendingFToken.mint(DEFAULT_AMOUNT, alice);
        vm.prank(bob);
        lendingFToken.mint(DEFAULT_AMOUNT, bob);

        uint256 aliceBalanceAfterDeposit = lendingFToken.balanceOf(alice);
        uint256 bobBalanceAfterDeposit = lendingFToken.balanceOf(bob);

        assertEq(aliceBalanceBeforeDeposit, aliceBalanceAfterDeposit - DEFAULT_AMOUNT);
        assertEq(bobBalanceBeforeDeposit, bobBalanceAfterDeposit - DEFAULT_AMOUNT);
        vm.prank(bob);
        lendingFToken.approve(alice, DEFAULT_AMOUNT);
        vm.prank(alice);
        lendingFToken.redeem(DEFAULT_AMOUNT, alice, bob);

        assertEq(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT);
        assertEq(lendingFToken.balanceOf(bob), bobBalanceAfterDeposit - DEFAULT_AMOUNT);
    }

    function test_redeem_RevertIfLessThanMinSharesAmountOut() public {
        vm.startPrank(alice);
        lendingFToken.mint(DEFAULT_AMOUNT, alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MinAmountOut));
        lendingFToken.redeem(UINT256_MAX, alice, alice, DEFAULT_AMOUNT + 1);
        vm.stopPrank();
    }

    function test_withdrawWithSignature_RevertIfOwner() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__PermitFromOwnerCall)
        );
        lendingFToken.withdrawWithSignature(1, 1, alice, admin, 1, block.timestamp, new bytes(0));
    }

    function test_withdrawWithSignature_RevertIfMaxSharesBurnIsSurpassed() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(lendingFToken)),
                alice,
                bob,
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MaxAmount));
        lendingFToken.withdrawWithSignature(
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            alice,
            alice,
            DEFAULT_AMOUNT - 1,
            deadline,
            signature
        );
    }

    function test_withdrawWithSignature() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(lendingFToken)),
                alice,
                admin,
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 aliceBalanceBefore = IERC20(address(lendingFToken)).balanceOf(alice);
        uint256 aliceUnderlyingBalanceBefore = IERC20(address(underlying)).balanceOf(alice);

        vm.prank(admin);
        lendingFToken.withdrawWithSignature(
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            alice,
            alice,
            DEFAULT_AMOUNT,
            deadline,
            signature
        );

        uint256 aliceBalanceAfter = IERC20(address(lendingFToken)).balanceOf(alice);
        uint256 aliceUnderlyingBalanceAfter = IERC20(address(underlying)).balanceOf(alice);

        assertEq(aliceBalanceAfter, aliceBalanceBefore - DEFAULT_AMOUNT);
        assertEq(aliceUnderlyingBalanceAfter, aliceUnderlyingBalanceBefore + DEFAULT_AMOUNT);
    }

    function test_redeemWithSignature_RevertIfOwner() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__PermitFromOwnerCall)
        );
        lendingFToken.redeemWithSignature(1, alice, admin, 1, block.timestamp, new bytes(0));
    }

    function test_redeemWithSignature_RevertWhenSharesAmountDontMeetMinAmountOut() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(lendingFToken)),
                alice,
                bob,
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__MinAmountOut));
        lendingFToken.redeemWithSignature(DEFAULT_AMOUNT, alice, alice, DEFAULT_AMOUNT + 1, deadline, signature);
    }

    function test_redeemWithSignatureNative() public {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(lendingFToken)),
                alice,
                admin,
                DEFAULT_AMOUNT,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 aliceBalanceBefore = IERC20(address(lendingFToken)).balanceOf(alice);
        uint256 aliceUnderlyingBalanceBefore = IERC20(address(underlying)).balanceOf(alice);

        vm.prank(admin);
        lendingFToken.redeemWithSignature(DEFAULT_AMOUNT, alice, alice, DEFAULT_AMOUNT, deadline, signature);

        uint256 aliceBalanceAfter = IERC20(address(lendingFToken)).balanceOf(alice);
        uint256 aliceUnderlyingBalanceAfter = IERC20(address(underlying)).balanceOf(alice);

        assertEq(aliceBalanceAfter, aliceBalanceBefore - DEFAULT_AMOUNT);
        assertEq(aliceUnderlyingBalanceAfter, aliceUnderlyingBalanceBefore + DEFAULT_AMOUNT);
    }

    function test_convertToShares() public {
        assertEq(lendingFToken.convertToShares(DEFAULT_AMOUNT), DEFAULT_AMOUNT);
    }

    // function test_supplyYield() public virtual {
    //     // set 0% rate in rewards
    //     rewards.setRate(0);
    //     // withdraw direct supply into liquidity from alice executed in setUp()
    //     _withdraw(mockProtocol, address(underlying), alice, DEFAULT_AMOUNT);
    //     // assert everything is at 0
    //     assertEq(lendingFToken.getLiquidityBalance(), 0);

    //     // deposit as alice through fToken vault
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // borrow to kink as bob (default rate at kink 80% utilization is 10%)
    //     _borrow(mockProtocol, address(underlying), bob, (DEFAULT_AMOUNT * DEFAULT_KINK) / DEFAULT_100_PERCENT);

    //     // jump into future to accrue yield
    //     // bob pays 10% APR on borrow amount (80% of DEFAULT_AMOUNT)
    //     // -> the new exchange price in liquidity is 1.08
    //     // each fToken share is now worth 1.08 assets. so 1000 shares = 1080 assets
    //     vm.warp(block.timestamp + PASS_1YEAR_TIME);

    //     assertEq(
    //         lendingFToken.getLiquidityExchangePrice(),
    //         EXCHANGE_PRICES_PRECISION + ((EXCHANGE_PRICES_PRECISION / 100) * 8)
    //     );

    //     // simulate enough funds in liquidity present
    //     underlying.mint(address(liquidityProxy), DEFAULT_AMOUNT);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
    //     uint256 balanceBefore = lendingFToken.balanceOf(alice);
    //     uint256 yield = 80 * DEFAULT_UNIT;
    //     vm.prank(alice);
    //     // withdrawing yield of 80 assets. alice should have less shares but DEFAULT_AMOUNT of assets still afterwards
    //     uint256 shares = lendingFToken.withdraw(yield, alice, alice);

    //     // assert withdrawn shares 80 assets at 1.08 assets per share => 80 / 1.08 =  74,0740740740...
    //     // rounded up + 1
    //     assertEq(shares, 74074075);
    //     // assert shares balance 1000 assets at 1.08 assets per share => 1000 / 1.08 = 925,925925925...
    //     assertEq(balanceBefore - shares, 925925925);

    //     // assert alice has received yield
    //     assertEqDecimal(underlying.balanceOf(alice), underlyingBalanceBefore + yield, DEFAULT_DECIMALS);

    //     // assert rest of shares still make up for DEFAULT_AMOUNT (with tolerance for rounding up)
    //     assertApproxEqAbs(lendingFToken.previewRedeem(lendingFToken.balanceOf(alice)), DEFAULT_AMOUNT, 1);
    // }

    function test_updateRewards_RevertUnauthorized() public {
        vm.startPrank(alice);
        uint256 startTime_ = block.timestamp + 10 days;
        uint256 endTime_ = startTime_ + 365 days;

        // create rewards contract
        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            alice,
            address(lendingFToken),
            address(0),
            address(0),
            1,
            1 ether,
            365 days,
            startTime_
        );
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.updateRewards(rateModel);

        vm.stopPrank();
    }

    function test_updateRewards() public {
        uint256 startTime_ = block.timestamp + 10 days;
        uint256 endTime_ = startTime_ + 365 days;

        // create rewards contract
        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            alice,
            address(lendingFToken),
            address(0),
            address(0),
            1,
            1 ether,
            365 days,
            startTime_
        );
        vm.warp(startTime_);

        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRewards(rateModel);
        // vm.expectEmit(true, false, false, false);
        // emit LogUpdateRates(0, 0);

        vm.prank(alice);
        lendingFToken.updateRewards(rateModel);

        (, , IFluidLendingRewardsRateModel rewardsRateModel_, , , bool rewardsActive_, , , ) = lendingFToken.getData();
        assertEq(address(rewardsRateModel_), address(rateModel));
        assertEq(rewardsActive_, true);
    }

    function test_updateRebalancer_RevertIfNotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.updateRebalancer(alice);
    }

    function test_updateRebalancer_AsAuthorized() public {
        vm.prank(admin);
        lendingFToken.updateRebalancer(alice);

        (, , , , address newRebalancer_, , , , ) = lendingFToken.getData();

        assertEq(newRebalancer_, alice);
    }

    function test_updateRebalancer_EmitLogUpdateRebalancer() public {
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRebalancer(alice);

        vm.prank(admin);
        lendingFToken.updateRebalancer(alice);
    }

    function test_rebalance_RevertIfNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__NotRebalancer));
        vm.prank(alice);
        lendingFToken.rebalance();
    }

    function test_rebalance_RevertIfMsgValueSent() public virtual {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__NotNativeUnderlying)
        );
        vm.deal(admin, 1e10);
        vm.prank(admin);
        lendingFToken.rebalance{ value: 1 }();
    }

    function test_rebalance() public virtual {
        // make alice the rebalancer
        vm.prank(admin);
        lendingFToken.updateRebalancer(alice);
        // supply as alice to have some initial deposit
        vm.startPrank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        // get balance of alice before rebalance
        uint256 balanceBefore = underlying.balanceOf(address(alice));
        // create a difference between Liquidity supply and totalAssets() by warping time so rewards accrue
        //  rewards rate is 20% per year.
        vm.warp(block.timestamp + 365 days);
        // expect total assets to be 1.2x DEFAULT_AMOUNT now.
        assertEq(lendingFToken.totalAssets(), (DEFAULT_AMOUNT * 12) / 10);
        // expect liquidityBalance still to be only DEFAULT_AMOUNT
        (, , , , , , uint256 liquidityBalance, , ) = lendingFToken.getData();
        assertEq(liquidityBalance, DEFAULT_AMOUNT);

        // execute rebalance
        lendingFToken.rebalance();

        // balance should be before - 20% of DEFAULT_AMOUNT as 20% of DEFAULT_AMOUNT got used to fund rewards
        uint256 balanceAfter = underlying.balanceOf(address(alice));
        assertEq(balanceAfter, balanceBefore - DEFAULT_AMOUNT / 5);
        // expect total assets should still be 1.2x DEFAULT_AMOUNT now.
        assertEq(lendingFToken.totalAssets(), (DEFAULT_AMOUNT * 12) / 10);
        // expect liquidityBalance should now also be 1.2x DEFAULT_AMOUNT
        (, , , , , , liquidityBalance, , ) = lendingFToken.getData();
        assertEq(liquidityBalance, (DEFAULT_AMOUNT * 12) / 10);

        vm.stopPrank();
    }

    function test_rebalance_EmitLogRebalance() public virtual {
        // make alice the rebalancer
        vm.prank(admin);
        lendingFToken.updateRebalancer(alice);
        // supply as alice to have some initial deposit
        vm.startPrank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        // create a difference between Liquidity supply and totalAssets() by warping time so rewards accrue
        // rewards rate is 20% per year.
        vm.warp(block.timestamp + 365 days);

        //check event
        vm.expectEmit(true, true, true, true);
        emit LogRebalance((DEFAULT_AMOUNT / 5));

        // execute rebalance
        lendingFToken.rebalance();
        vm.stopPrank();
    }

    function test_updateRates_RevertIfNewLiquidityExchangePriceSmallerThanOld() public {
        // create fTokenHarness in order to test updateRates function
        fTokenHarness fTokenHarness_ = new fTokenHarness(liquidityProxy, factory, USDC);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLendingError.selector,
                ErrorTypes.fToken__LiquidityExchangePriceUnexpected
            )
        );
        fTokenHarness_.exposed_updateRates(1e12 - 1);
    }

    function test_updateRates_RevertIfExchangePriceOverflow() public {
        fTokenHarness fTokenHarness_ = new fTokenHarness(liquidityProxy, factory, USDC);
        vm.warp(block.timestamp + PASS_1YEAR_TIME);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__ExchangePriceOverflow)
        );
        fTokenHarness_.exposed_updateRates(1e32);
    }

    function test_updateRates_CaseWhenRewardsEnded() public virtual {
        // rewards ended which means that it should update fields: _tokenExchangePrice, _liquidityExchangePrice, _lastUpdateTimestamp
        vm.warp(1704578099);
        uint256 startTime_ = block.timestamp + 10 days;
        uint256 endTime_ = startTime_ + PASS_1YEAR_TIME;

        // create rewards contract
        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            alice,
            address(lendingFToken),
            address(0),
            address(0),
            1,
            1 ether,
            365 days,
            startTime_
        );
        vm.warp(startTime_);

        // create fTokenHarness in order to test updateRates function
        fTokenHarness fTokenHarness_ = new fTokenHarness(liquidityProxy, factory, USDC);
        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(alice);
        fTokenHarness_.updateRewards(rateModel);
        assertEq(fTokenHarness_.exposed_tokenExchangePrice(), 1e12);
        assertEq(fTokenHarness_.exposed_liquidityExchangePrice(), 1e12);
        assertEq(fTokenHarness_.exposed_lastUpdateTimestamp(), 1705442099);

        vm.warp(endTime_ - 1); // warp until shortly before end time and update rates
        fTokenHarness_.exposed_updateRates(2e12); // also update liquidityExchangePrice, doubling it.
        assertEq(fTokenHarness_.exposed_rewardsActive(), true);

        // exposed_tokenExchangePrice -> 100% yield from rewards (in reality would also have 100% from liquidityExchangePrice
        // but uses actually calculated data not as passed in in harness).
        assertEq(fTokenHarness_.exposed_tokenExchangePrice(), 2e12);
        assertEq(fTokenHarness_.exposed_liquidityExchangePrice(), 2e12);
        assertEq(fTokenHarness_.exposed_lastUpdateTimestamp(), 1736978098);

        // make rewards ended
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        fTokenHarness_.exposed_updateRates(2e12);
        assertEq(fTokenHarness_.exposed_tokenExchangePrice(), 2e12); // should stay the same if liquidity price is the same
        assertEq(fTokenHarness_.exposed_liquidityExchangePrice(), 2e12);
        assertEq(fTokenHarness_.exposed_lastUpdateTimestamp(), block.timestamp); // written to storage
        assertEq(fTokenHarness_.exposed_rewardsActive(), false);
    }

    function test_rescueFunds_NonReentrantCheck() public {
        ReentrantAttacker attacker = new ReentrantAttacker(lendingFToken);
        vm.prank(admin);
        factory.setAuth(address(attacker), true);
        attacker.attack();
    }

    function test_rescueFunds_Unauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLendingError.selector, ErrorTypes.fToken__Unauthorized));
        lendingFToken.rescueFunds(address(underlying));
    }

    function test_rescueFunds() public virtual {
        uint256 liquidityBalanceBefore = underlying.balanceOf(address(liquidity));
        uint256 amount = 2000;
        underlying.mint(address(lendingFToken), amount);
        vm.prank(admin);
        factory.setAuth(alice, true);

        vm.expectEmit(true, true, true, true);
        emit LogRescueFunds(address(underlying));

        vm.prank(alice);
        lendingFToken.rescueFunds(address(underlying));
        uint256 liquidityBalanceAfter = underlying.balanceOf(address(liquidity));
        assertEq(liquidityBalanceAfter - liquidityBalanceBefore, amount);
    }

    function test_getLiquidityBalance() public {
        vm.startPrank(alice);

        (, , , , , , uint256 balanceBefore, , ) = lendingFToken.getData();
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        (, , , , , , uint256 balanceAfter, , ) = lendingFToken.getData();
        assertEq(balanceAfter, balanceBefore + DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_maxDeposit_NoDeposits() public virtual {
        // withdraw seed deposit from mockProtocol as alice down to 0
        _withdraw(mockProtocol, address(underlying), alice, DEFAULT_AMOUNT);
        (, , , , , , uint256 liquidityBalance, , ) = lendingFToken.getData();
        assertEq(liquidityBalance, 0);

        uint256 maxDeposit = lendingFToken.maxDeposit(address(0));
        assertEq(maxDeposit, uint256(uint128(type(int128).max)));
    }

    function test_maxMint_NoDeposits() public virtual {
        // withdraw seed deposit from mockProtocol as alice down to 0
        _withdraw(mockProtocol, address(underlying), alice, DEFAULT_AMOUNT);
        (, , , , , , uint256 liquidityBalance, , ) = lendingFToken.getData();
        assertEq(liquidityBalance, 0);

        uint256 maxMint = lendingFToken.maxMint(address(0));
        assertEq(maxMint, uint256(uint128(type(int128).max)));
    }

    function test_maxDeposit_WithDeposits() public virtual {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 maxDeposit = lendingFToken.maxDeposit(address(0));
        assertEq(maxDeposit, uint256(uint128(type(int128).max)) - DEFAULT_AMOUNT * 2);

        uint256 maxDepositAmount = lendingFToken.maxDeposit(address(0));

        vm.prank(alice);
        lendingFToken.deposit(maxDepositAmount, alice);

        maxDeposit = lendingFToken.maxDeposit(address(0));
        assertEq(maxDeposit, 0);
    }

    function test_maxMint_WithDeposits() public virtual {
        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);

        uint256 maxMint = lendingFToken.maxMint(address(0));
        uint256 expectedMaxMint = uint256(uint128(type(int128).max)) - DEFAULT_AMOUNT * 2;
        assertEq(maxMint, expectedMaxMint);

        vm.prank(alice);
        lendingFToken.mint(expectedMaxMint, alice);
        vm.warp(block.timestamp + 10);
        maxMint = lendingFToken.maxMint(address(0));
        assertEq(maxMint, 0);
    }

    function test_maxWithdraw_NoWithdrawalLimit() public {
        vm.startPrank(alice);
        uint256 maxWithdrawBefore = lendingFToken.maxWithdraw(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        uint256 maxWithdrawAfter = lendingFToken.maxWithdraw(alice);
        assertEq(maxWithdrawAfter, maxWithdrawBefore + DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_maxRedeem_NoWithdrawalLimit() public {
        vm.startPrank(alice);
        uint256 maxRedeemBefore = lendingFToken.maxRedeem(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        uint256 maxRedeemAfter = lendingFToken.maxRedeem(alice);
        assertEq(maxRedeemAfter, maxRedeemBefore + DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_maxWithdraw_WithWithdrawalLimit() public virtual {
        // set withdrawal limit of 10% expanded at liquidity. This should then be the reported max amount.
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(lendingFToken),
            token: address(underlying),
            mode: 1,
            expandPercent: 10 * DEFAULT_PERCENT_PRECISION, // 10%
            expandDuration: 1,
            baseWithdrawalLimit: 1e5 // low base withdrawal limit so not full amount is withdrawable
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        vm.warp(block.timestamp + 10); // get to full expansion

        assertEq(lendingFToken.maxWithdraw(alice), DEFAULT_AMOUNT / 10);

        uint256 maxWithdrawAmount = lendingFToken.maxWithdraw(alice);
        vm.prank(alice);
        lendingFToken.withdraw(maxWithdrawAmount, alice, alice);
        assertEq(lendingFToken.maxWithdraw(alice), 0);
    }

    function test_maxRedeem_WithWithdrawalLimit() public virtual {
        // set no rewards for this test
        rewards.setRate(0);

        // set withdrawal limit of 10% expanded at liquidity. This should then be the reported max amount.
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(lendingFToken),
            token: address(underlying),
            mode: 1,
            expandPercent: 10 * DEFAULT_PERCENT_PRECISION, // 10%
            expandDuration: 1,
            baseWithdrawalLimit: 1e5 // low base withdrawal limit so not full amount is withdrawable
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        vm.prank(alice);
        lendingFToken.deposit(DEFAULT_AMOUNT, alice);
        vm.warp(block.timestamp + 10); // get to full expansion

        assertEq(lendingFToken.maxRedeem(alice), DEFAULT_AMOUNT / 10);

        uint256 maxRedeemAmount = lendingFToken.maxRedeem(alice);
        vm.prank(alice);
        lendingFToken.redeem(maxRedeemAmount, alice, alice);
        assertEq(lendingFToken.maxRedeem(alice), 0);
    }

    function test_minDeposit_MinBigMathRounding() public virtual {
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
        lendingFToken.deposit(minDeposit, alice);
    }

    function test_minDeposit() public {
        uint256 minDeposit = lendingFToken.minDeposit();
        assertEq(minDeposit, 1);
    }

    // // No rewards but supply yield from liquidity
    // function testRedeemWithSupplyYield() public {
    //     // set 0% rate in rewards
    //     rewards.setRate(0);
    //     // withdraw direct supply into liquidity from alice executed in setUp()
    //     vm.prank(alice);
    //     liquidityProxy.operate(
    //              address(underlying),
    //              -int256(DEFAULT_AMOUNT),
    //              0,
    //              alice,
    //              address(0),
    //              abi.encode(alice)
    //     );

    //     // assert everything is at 0
    //     assertEq(liquidityProxy.totalSupply(address(underlying)), 0);
    //     assertEq(liquidityProxy.totalBorrow(address(underlying)), 0);

    //     _setDefaultRateDataV1(address(liquidityProxy), admin, address(USDC));
    //     _setUserAllowancesDefault(address(liquidityProxy), admin, address(USDC), bob);

    //     // deposit as alice through fToken vault
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // borrow to kink as bob (default rate at kink 80% utilization is 10%)
    //     vm.prank(bob);
    //     liquidityProxy.borrow(address(USDC), (DEFAULT_AMOUNT * DEFAULT_KINK) / 1e8, bob);

    //     (, , uint256 borrowPrice) = liquidityProxy.exchangePrice(address(underlying));
    //     assertEq(borrowPrice, EXCHANGE_PRICES_PRECISION);

    //     // jump into future to accrue yield
    //     // bob pays 10% APR on 0.8 ether (80% of default amount) = 0.08 ether
    //     // the new exchange price for safe / risky in liquidity is 1.08
    //     // each fToken share is now worth 1.08 assets. so 1000 shares = 1080 assets
    //     vm.warp(block.timestamp + 365 days);

    //     (, , borrowPrice) = liquidityProxy.exchangePrice(address(underlying));
    //     assertEq(borrowPrice, EXCHANGE_PRICES_PRECISION + (EXCHANGE_PRICES_PRECISION / 10));

    //     // simulate enough funds in liquidity present
    //     underlying.mint(address(liquidityProxy), DEFAULT_AMOUNT);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
    //     uint256 balanceBefore = lendingFToken.balanceOf(alice);
    //     uint256 yield = 80 * DEFAULT_UNIT;
    //     // redeem yield of 80 assets. alice should have less shares but DEFAULT_AMOUNT of assets still afterwards
    //     uint256 withdrawShares = lendingFToken.previewWithdraw(yield);
    //     assertEq(withdrawShares, 74074075); // 80 assets at 1.08 assets per share => 80 / 1.08 =  74,0740740740...; rounding up
    //     vm.prank(alice);
    //     uint256 assets = lendingFToken.redeem(withdrawShares, alice, alice);

    //     // assert shares, ignoring rounding errors
    //     assertApproxEqAbs(assets, yield, 1);
    //     assertEq(balanceBefore - lendingFToken.balanceOf(alice), withdrawShares);

    //     // assert alice has received yield, ignoring rounding errors
    //     assertApproxEqAbs(underlying.balanceOf(alice), underlyingBalanceBefore + yield, 1);

    //     // assert rest of shares still make up for DEFAULT_AMOUNT, ignoring rounding errors
    //     assertApproxEqAbs(lendingFToken.previewRedeem(lendingFToken.balanceOf(alice)), DEFAULT_AMOUNT, 1);
    // }

    // // No rewards by supply yield from liquidity
    // function testWithdrawWithSupplyYield() public {
    //     // set 0% rate in rewards
    //     rewards.setRate(0);
    //     // withdraw direct supply into liquidity from alice executed in setUp()
    //     vm.prank(alice);
    //     liquidityProxy.withdrawSafe(address(underlying), DEFAULT_AMOUNT, alice);
    //     // assert everything is at 0
    //     assertEq(liquidityProxy.totalSupply(address(underlying)), 0);
    //     assertEq(liquidityProxy.totalBorrow(address(underlying)), 0);

    //     _setDefaultRateDataV1(address(liquidityProxy), admin, address(USDC));
    //     _setUserAllowancesDefault(address(liquidityProxy), admin, address(USDC), bob);

    //     // deposit as alice through fToken vault
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // borrow to kink as bob (default rate at kink 80% utilization is 10%)
    //     vm.prank(bob);
    //     liquidityProxy.borrow(address(USDC), (DEFAULT_AMOUNT * DEFAULT_KINK) / 1e8, bob);

    //     (, , uint256 borrowPrice) = liquidityProxy.exchangePrice(address(underlying));
    //     assertEq(borrowPrice, EXCHANGE_PRICES_PRECISION);

    //     // jump into future to accrue yield
    //     // bob pays 10% APR on 0.8 ether (80% of default amount) = 0.08 ether
    //     // the new exchange price for safe / risky in liquidity is 1.08
    //     // each fToken share is now worth 1.08 assets. so 1000 shares = 1080 assets
    //     vm.warp(block.timestamp + 365 days);

    //     (, , borrowPrice) = liquidityProxy.exchangePrice(address(underlying));
    //     assertEq(borrowPrice, EXCHANGE_PRICES_PRECISION + (EXCHANGE_PRICES_PRECISION / 10));

    //     // simulate enough funds in liquidity present
    //     underlying.mint(address(liquidityProxy), DEFAULT_AMOUNT);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);
    //     uint256 balanceBefore = lendingFToken.balanceOf(alice);
    //     uint256 yield = 80 * DEFAULT_UNIT;
    //     vm.prank(alice);
    //     // withdrawing yield of 80 assets. alice should have less shares but DEFAULT_AMOUNT of assets still afterwards
    //     uint256 shares = lendingFToken.withdraw(yield, alice, alice);

    //     // assert shares
    //     assertEq(shares, 74074074); // 80 assets at 1.08 assets per share => 80 / 1.08 =  74,0740740740...
    //     assertEq(balanceBefore - shares, 925925926); // 1000 assets at 1.08 assets per share => 1000 / 1.08 = 925,925925925...

    //     // assert alice has received yield
    //     assertEqDecimal(underlying.balanceOf(alice), underlyingBalanceBefore + yield, DEFAULT_DECIMALS);

    //     // assert rest of shares still make up for DEFAULT_AMOUNT
    //     assertEq(lendingFToken.previewRedeem(lendingFToken.balanceOf(alice)), DEFAULT_AMOUNT);
    // }

    // function testWithdrawWithAllowance() public {
    //     // deposit as alice
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);
    //     // add allowance bob for alice
    //     vm.prank(alice);
    //     lendingFToken.approve(bob, DEFAULT_AMOUNT);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

    //     // execute withdraw bob for alice
    //     vm.prank(bob);
    //     uint256 shares = lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice);

    //     // assert results
    //     assertEq(shares, DEFAULT_AMOUNT);
    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);
    // }

    // function testRewardsTotalAssetsBiggerThanLiquiditySupply() public {
    //     vm.startPrank(alice);

    //     // withdraw direct supply into liquidity from alice executed in setUp()
    //     liquidityProxy.withdrawSafe(address(underlying), DEFAULT_AMOUNT, alice);
    //     // assert everything is at 0
    //     assertEq(liquidityProxy.totalSupply(address(underlying)), 0);
    //     assertEq(liquidityProxy.totalBorrow(address(underlying)), 0);

    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // jump into future to accrue rewards
    //     vm.warp(block.timestamp + 365 days);

    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     vm.stopPrank();

    //     uint256 liquidityTotalSupply = liquidityProxy.totalSupply(address(underlying)) + 1; // rounding up
    //     // tolerance for expected 1e12 inaccuracy
    //     liquidityTotalSupply += (liquidityTotalSupply / 1e12);

    //     // because of rewards, totalAssets in fToken vault will be more than amount supplied in liquidity
    //     assertGe(lendingFToken.totalAssets(), liquidityTotalSupply);

    //     // fund rewards to cover amount accrued as rewards
    //     vm.prank(admin);
    //     lendingFToken.rebalance(); // DEFAULT_AMOUNT * 2

    //     liquidityTotalSupply = liquidityProxy.totalSupply(address(underlying)) + 1; // rounding up
    //     // tolerance for expected 1e12 inaccuracy
    //     liquidityTotalSupply += (liquidityTotalSupply / 1e12);

    //     // supplied in liquidity should now be more than totalAssets in fToken vault
    //     assertLe(lendingFToken.totalAssets(), liquidityTotalSupply);
    // }

    // // No supply yield but 100% rewards a year
    // function testWithdrawWithRewards() public {
    //     vm.startPrank(alice);

    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // jump into future to accrue rewards
    //     vm.warp(block.timestamp + 365 days);

    //     uint256 balanceBefore = lendingFToken.balanceOf(alice);
    //     uint256 shares = lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice);

    //     vm.stopPrank();

    //     // because we have 100% rewards a year user's balance should double, so
    //     // we should have still 50% of shares left
    //     assertLtDecimal((int256(balanceBefore - shares) - 500 * 1e6).abs(), PRECISION, DEFAULT_DECIMALS);
    // }

    // function testSingleDepositWithdraw(uint120 amount) public {
    //     vm.assume(amount > lendingFToken.minDeposit());

    //     uint256 expectedInaccuracy = (amount / 1e12) + 1;

    //     uint256 aliceUnderlyingAmount = amount;

    //     underlying.mint(alice, aliceUnderlyingAmount);

    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), aliceUnderlyingAmount);
    //     assertEq(underlying.allowance(alice, address(lendingFToken)), aliceUnderlyingAmount);

    //     uint256 alicePreDepositBal = underlying.balanceOf(alice);

    //     vm.prank(alice);
    //     uint256 aliceShareAmount = lendingFToken.deposit(aliceUnderlyingAmount, alice);
    //     assertApproxEqAbs(aliceUnderlyingAmount, aliceShareAmount, expectedInaccuracy);
    //     uint256 aliceDepositedAmount = lendingFToken.convertToAssets(aliceShareAmount);
    //     assertApproxEqAbs(aliceUnderlyingAmount, aliceDepositedAmount, expectedInaccuracy);
    //     // Expect exchange rate to be 1:1 on initial deposit.
    //     assertEq(aliceDepositedAmount, aliceShareAmount);

    //     assertEq(lendingFToken.previewWithdraw(aliceShareAmount), aliceDepositedAmount);
    //     assertEq(lendingFToken.previewDeposit(aliceDepositedAmount), aliceShareAmount);

    //     assertEq(lendingFToken.totalSupply(), aliceShareAmount);
    //     assertEq(lendingFToken.totalAssets(), aliceDepositedAmount);

    //     assertEq(lendingFToken.convertToAssets(aliceShareAmount), aliceDepositedAmount);

    //     assertEq(underlying.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    //     vm.prank(alice);
    //     lendingFToken.withdraw(aliceDepositedAmount, alice, alice);

    //     assertEq(lendingFToken.totalAssets(), 0);
    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(lendingFToken.convertToAssets(lendingFToken.balanceOf(alice)), 0);
    //     assertApproxEqAbs(underlying.balanceOf(alice), alicePreDepositBal, expectedInaccuracy);
    // }

    // function testSingleMintRedeem(uint120 amount) public {
    //     vm.assume(amount > lendingFToken.minMint());

    //     uint256 expectedInaccuracy = (amount / 1e12) + 1;

    //     uint256 aliceShareAmount = amount;

    //     underlying.mint(alice, aliceShareAmount);

    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), aliceShareAmount);
    //     assertEq(underlying.allowance(alice, address(lendingFToken)), aliceShareAmount);

    //     uint256 alicePreDepositBal = underlying.balanceOf(alice);

    //     vm.prank(alice);
    //     uint256 alicePaidAmount = lendingFToken.mint(aliceShareAmount, alice);

    //     // get actual alice received shares
    //     uint256 aliceReceivedShares = lendingFToken.balanceOf(alice);
    //     assertApproxEqAbs(aliceShareAmount, aliceReceivedShares, expectedInaccuracy);

    //     // get actual alice deposit amount
    //     uint256 aliceDepositAmount = lendingFToken.convertToAssets(aliceReceivedShares);
    //     assertApproxEqAbs(aliceDepositAmount, aliceShareAmount, expectedInaccuracy);
    //     assertApproxEqAbs(alicePaidAmount, aliceDepositAmount, expectedInaccuracy);

    //     // Expect exchange rate to be 1:1 on initial mint.
    //     assertEq(aliceDepositAmount, aliceReceivedShares);

    //     assertEq(lendingFToken.previewWithdraw(aliceReceivedShares), aliceDepositAmount);
    //     assertEq(lendingFToken.previewDeposit(aliceDepositAmount), aliceReceivedShares);

    //     assertEq(lendingFToken.totalSupply(), aliceReceivedShares);
    //     assertEq(lendingFToken.totalAssets(), aliceDepositAmount);
    //     assertEq(underlying.balanceOf(alice), alicePreDepositBal - alicePaidAmount);

    //     vm.prank(alice);
    //     lendingFToken.redeem(aliceReceivedShares, alice, alice);

    //     assertEq(lendingFToken.totalAssets(), 0);
    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(lendingFToken.convertToAssets(lendingFToken.balanceOf(alice)), 0);
    //     assertApproxEqAbs(underlying.balanceOf(alice), alicePreDepositBal, expectedInaccuracy);
    // }

    // function testFailDepositWithNotEnoughApproval() public {
    //     underlying.mint(address(this), 0.5e18);
    //     underlying.approve(address(lendingFToken), 0.5e18);
    //     assertEq(underlying.allowance(address(this), address(lendingFToken)), 0.5e18);

    //     lendingFToken.deposit(1e18, address(this));
    // }

    // function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
    //     underlying.mint(address(this), 0.5e18);
    //     underlying.approve(address(lendingFToken), 0.5e18);

    //     lendingFToken.deposit(0.5e18, address(this));

    //     lendingFToken.withdraw(1e18, address(this), address(this));
    // }

    // function testFailRedeemWithNotEnoughShareAmount() public {
    //     underlying.mint(address(this), 0.5e18);
    //     underlying.approve(address(lendingFToken), 0.5e18);

    //     lendingFToken.deposit(0.5e18, address(this));

    //     lendingFToken.redeem(1e18, address(this), address(this));
    // }

    // function testFailWithdrawWithNoUnderlyingAmount() public {
    //     lendingFToken.withdraw(1e18, address(this), address(this));
    // }

    // function testFailRedeemWithNoShareAmount() public {
    //     lendingFToken.redeem(1e18, address(this), address(this));
    // }

    // function testFailDepositWithNoApproval() public {
    //     lendingFToken.deposit(1e18, address(this));
    // }

    // function testFailMintWithNoApproval() public {
    //     lendingFToken.mint(1e18, address(this));
    // }

    // function testRevertDepositLessThanMin() public {
    //     uint256 minDeposit = lendingFToken.minDeposit();
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), minDeposit - 1);

    //     vm.expectRevert(fTokenError.fToken__DepositInsignificant.selector);
    //     vm.prank(alice);
    //     lendingFToken.deposit(minDeposit - 1, alice);
    // }

    // function testRevertMintLessThanMin() public {
    //     uint256 minMint = lendingFToken.minMint();
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), minMint - 1);

    //     vm.expectRevert(fTokenError.fToken__DepositInsignificant.selector);
    //     vm.prank(alice);
    //     lendingFToken.mint(minMint - 1, alice);
    // }

    // function testRevertRedeemZero() public {
    //     vm.expectRevert(fTokenError.fToken__RoundingError.selector);
    //     lendingFToken.redeem(0, address(this), address(this));
    // }

    // function testRevertWithdrawZero() public {
    //     vm.expectRevert(fTokenError.fToken__RoundingError.selector);
    //     lendingFToken.withdraw(0, address(this), address(this));

    //     assertEq(lendingFToken.balanceOf(address(this)), 0);
    //     assertEq(lendingFToken.convertToAssets(lendingFToken.balanceOf(address(this))), 0);
    //     assertEq(lendingFToken.totalSupply(), 0);
    //     assertEq(lendingFToken.totalAssets(), 0);
    // }

    // function testVaultInteractionsForSomeoneElse() public {
    //     // init 2 users with a 1e18 balance
    //     address alice = address(0xABCD);
    //     address bob = address(0xDCBA);
    //     underlying.mint(alice, 1e18);
    //     underlying.mint(bob, 1e18);

    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), 1e18);

    //     vm.prank(bob);
    //     underlying.approve(address(lendingFToken), 1e18);

    //     // alice deposits 1e18 for bob
    //     vm.prank(alice);
    //     lendingFToken.deposit(1e18, bob);

    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(lendingFToken.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(alice), 0);

    //     // bob mint 1e18 for alice
    //     vm.prank(bob);
    //     lendingFToken.mint(1e18, alice);
    //     assertEq(lendingFToken.balanceOf(alice), 1e18);
    //     assertEq(lendingFToken.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(bob), 0);

    //     // alice redeem 1e18 for bob
    //     vm.prank(alice);
    //     lendingFToken.redeem(1e18, bob, alice);

    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(lendingFToken.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(bob), 1e18);

    //     // bob withdraw 1e18 for alice
    //     vm.prank(bob);
    //     lendingFToken.withdraw(1e18, alice, bob);

    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(lendingFToken.balanceOf(bob), 0);
    //     assertEq(underlying.balanceOf(alice), 1e18);
    // }

    function _getPermitHash(
        IERC2612 token,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32 h) {
        bytes32 domainHash = token.DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));
    }
}

abstract contract fTokenBasePermitTest is fTokenBaseSetUp {
    SigUtils sigUtils;

    // from https://github.com/Uniswap/permit2/blob/main/src/libraries/PermitHash.sol
    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    // function setUp() public virtual override {
    //     // permit tests must run in fork for Permit2 contract
    //     vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

    //     super.setUp();

    //     sigUtils = new SigUtils(address(lendingFToken.PERMIT2()), lendingFToken.DOMAIN_SEPARATOR());

    //     // approve permit2 contract for alice
    //     _setApproval(underlying, address(lendingFToken.PERMIT2()), alice);
    // }

    // function testDepositWithPermit2() public {
    //     // reset direct token approval
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), 0);
    //     // make sure deposit without permit would fail
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

    //     // create permit2 message
    //     ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
    //         permitted: ISignatureTransfer.TokenPermissions({
    //             token: address(underlying), // ERC20 token address
    //             // the maximum amount that can be spent
    //             amount: DEFAULT_AMOUNT
    //         }),
    //         nonce: 1,
    //         deadline: block.timestamp + 10 minutes
    //     });

    //     // create permit2 signature
    //     bytes32 digest = sigUtils.permit2TypedDataHash(permit, address(lendingFToken));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // deposit with permit2
    //     vm.prank(alice);
    //     uint256 shares = lendingFToken.deposit(DEFAULT_AMOUNT, alice, 0, permit, signature);

    //     // assert results
    //     assertEqDecimal(shares, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
    //     assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
    //     assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    // }

    // function testDepositMinAmountOutWithPermit2Revert() public {
    //     // reset direct token approval
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), 0);
    //     // make sure deposit without permit would fail
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // create permit2 message
    //     ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
    //         permitted: ISignatureTransfer.TokenPermissions({
    //             token: address(underlying), // ERC20 token address
    //             // the maximum amount that can be spent
    //             amount: DEFAULT_AMOUNT
    //         }),
    //         nonce: 1,
    //         deadline: block.timestamp + 10 minutes
    //     });

    //     // create permit2 signature
    //     bytes32 digest = sigUtils.permit2TypedDataHash(permit, address(lendingFToken));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // deposit with permit2
    //     vm.expectRevert(fTokenError.fToken__MinAmountOut.selector);
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT + 10, permit, signature);
    // }

    // function testMintWithPermit2() public {
    //     // reset direct token approval
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), 0);
    //     // make sure deposit without permit would fail
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

    //     // create permit2 message
    //     ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
    //         permitted: ISignatureTransfer.TokenPermissions({
    //             token: address(underlying), // ERC20 token address
    //             // the maximum amount that can be spent
    //             amount: DEFAULT_AMOUNT
    //         }),
    //         nonce: 1,
    //         deadline: block.timestamp + 10 minutes
    //     });

    //     // create permit2 signature
    //     bytes32 digest = sigUtils.permit2TypedDataHash(permit, address(lendingFToken));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // mint with permit2
    //     vm.prank(alice);
    //     uint256 assets = lendingFToken.mint(DEFAULT_AMOUNT, alice, 0, permit, signature);

    //     // assert results
    //     assertEqDecimal(assets, DEFAULT_AMOUNT, DEFAULT_DECIMALS);
    //     assertEqDecimal(lendingFToken.balanceOf(alice), DEFAULT_AMOUNT, DEFAULT_DECIMALS);
    //     assertEq(underlyingBalanceBefore - underlying.balanceOf(alice), DEFAULT_AMOUNT);
    // }

    // function testMintMinAmountOutWithPermit2Revert() public {
    //     // reset direct token approval
    //     vm.prank(alice);
    //     underlying.approve(address(lendingFToken), 0);
    //     // make sure deposit without permit would fail
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);

    //     // create permit2 message
    //     ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
    //         permitted: ISignatureTransfer.TokenPermissions({
    //             token: address(underlying), // ERC20 token address
    //             // the maximum amount that can be spent
    //             amount: DEFAULT_AMOUNT
    //         }),
    //         nonce: 1,
    //         deadline: block.timestamp + 10 minutes
    //     });

    //     // create permit2 signature
    //     bytes32 digest = sigUtils.permit2TypedDataHash(permit, address(lendingFToken));
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // mint with permit2
    //     vm.expectRevert(fTokenError.fToken__MinAmountOut.selector);
    //     vm.prank(alice);
    //     lendingFToken.mint(DEFAULT_AMOUNT, alice, DEFAULT_AMOUNT + 10, permit, signature);
    // // }

    // function testWithdrawWithPermit() public {
    //     // deposit as alice
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);
    //     // make sure bob has no allowance for alice
    //     vm.prank(alice);
    //     lendingFToken.approve(bob, 0);
    //     // make sure withdraw without permit would fail -> bob withdraws for alice
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(bob);
    //     lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

    //     uint256 deadline = block.timestamp + 10 minutes;

    //     // create permit message
    //     SigUtils.Permit memory permit = SigUtils.Permit({
    //         owner: alice,
    //         spender: bob,
    //         value: DEFAULT_AMOUNT,
    //         nonce: lendingFToken.nonces(alice),
    //         deadline: deadline
    //     });

    //     // create permit signature
    //     bytes32 digest = sigUtils.permitTypedDataHash(permit);
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // execute withdraw bob for alice
    //     vm.prank(bob);
    //     uint256 shares = lendingFToken.withdraw(DEFAULT_AMOUNT, alice, alice, DEFAULT_AMOUNT, deadline, signature);

    //     // assert results
    //     assertEq(shares, DEFAULT_AMOUNT);
    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);

    //     assertEq(lendingFToken.allowance(alice, bob), 0);
    // }

    // function testRedeemWithPermit() public {
    //     // deposit as alice
    //     vm.prank(alice);
    //     lendingFToken.deposit(DEFAULT_AMOUNT, alice);
    //     // make sure bob has no allowance for alice
    //     vm.prank(alice);
    //     lendingFToken.approve(bob, 0);
    //     // make sure withdraw without permit would fail -> bob withdraws for alice
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     vm.prank(bob);
    //     lendingFToken.redeem(DEFAULT_AMOUNT, alice, alice);

    //     uint256 underlyingBalanceBefore = underlying.balanceOf(alice);

    //     uint256 deadline = block.timestamp + 10 minutes;

    //     // create permit message
    //     SigUtils.Permit memory permit = SigUtils.Permit({
    //         owner: alice,
    //         spender: bob,
    //         value: DEFAULT_AMOUNT,
    //         nonce: lendingFToken.nonces(alice),
    //         deadline: deadline
    //     });

    //     // create permit signature
    //     bytes32 digest = sigUtils.permitTypedDataHash(permit);
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     // execute withdraw bob for alice
    //     vm.prank(bob);
    //     uint256 assets = lendingFToken.redeem(DEFAULT_AMOUNT, alice, alice, DEFAULT_AMOUNT, deadline, signature);

    //     // assert results
    //     assertEq(assets, DEFAULT_AMOUNT);
    //     assertEq(lendingFToken.balanceOf(alice), 0);
    //     assertEq(underlying.balanceOf(alice) - underlyingBalanceBefore, DEFAULT_AMOUNT);

    //     assertEq(lendingFToken.allowance(alice, bob), 0);
    // }
}
