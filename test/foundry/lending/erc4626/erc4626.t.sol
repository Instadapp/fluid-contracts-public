// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { FluidLendingFactory } from "../../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { IFToken } from "../../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";

import { Structs as FluidLiquidityResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { Handler } from "./handler.sol";
import { TestERC20 } from "../../testERC20.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "../../liquidity/userModule/liquidityOperate.t.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquidityUserModuleBaseTest } from "../../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";

import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { SafeTransfer } from "../../../../contracts/libraries/safeTransfer.sol";
import { LibsErrorTypes } from "../../../../contracts/libraries/errorTypes.sol";

import { MockERC20 } from "solady-test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

abstract contract ERC4626fTokenHelperTest is LiquidityBaseTest, LiquidityUserModuleBaseTest {
    MockERC20 asset;
    IFToken token;
    IFluidLiquidity liquidityProxy;
    FluidLendingFactory factory;
    FluidLendingRewardsRateModel rateModel;
    uint256 endTime_;
    uint256 startTime_;
    uint256 sharesAmountFrominitialDeposit;

    function setUp() public virtual override(LiquidityBaseTest, LiquidityUserModuleBaseTest) {
        LiquidityBaseTest.setUp();
        liquidityProxy = IFluidLiquidity(address(liquidity));
        factory = new FluidLendingFactory(liquidityProxy, address(admin));
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        // Add factory to the list of auths so it can enable fTokens to provide liquidity
        vm.prank(admin);
        AdminModuleStructs.AddressBool[] memory auths = new AdminModuleStructs.AddressBool[](1);
        auths[0] = AdminModuleStructs.AddressBool(address(factory), true);
        liquidityProxy.updateAuths(auths);
        vm.prank(admin);
        token = IFToken(factory.createToken(address(USDC), "fToken", false));
        asset = MockERC20(address(USDC));
        _setDefaultRateDataV1(address(liquidityProxy), admin, address(asset));

        _setApproval(IERC20(address(asset)), address(token), alice);

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(token));
    }

    function activateRewardRateModel() internal returns (FluidLendingRewardsRateModel, uint256, uint256) {
        // TODO: (Optional to improve) take default settings of rate model from TestSuite from rateModel tests
        (, , , , , , , uint256 liquidityExchangePriceBefore, uint256 tokenExchangePriceBefore) = IFToken(address(token))
            .getData();

        startTime_ = block.timestamp + 3153600; // 10% of 1 year = 36.5 days
        endTime_ = startTime_ + 365 days;

        FluidLendingRewardsRateModel rateModel = new FluidLendingRewardsRateModel(
            alice,
            address(token),
            address(0),
            address(0),
            1,
            1500,
            365 days,
            startTime_
        );

        vm.prank(admin);
        IFToken(address(token)).updateRewards(IFluidLendingRewardsRateModel(address(rateModel)));

        FluidLiquidityResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(
            address(USDC)
        );

        // Move time to startTime_
        vm.warp(startTime_);
        vm.prank(alice);

        (, , , , , , , uint256 liquidityExchangePriceAfter, uint256 tokenExchangePriceAfter) = IFToken(address(token))
            .getData();

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 20000000000000 * (34689601 - 34689601) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 20000000000000 * 0 / 31536000
        // rewards return in percentage = 0

        /*
        How to calculate borrow and supply exchange prices explanation:
        taking the same example and amounts
        DEFAULT_SUPPLY_AMOUNT = 1 ether and
        DEFAULT_BORROW_AMOUNT = 0.5 ether
        after the 1 year update the total supply will be
        1 ether * 103.875% = 1,03875 ether
        and total borrow will be
        0.5 ether * 107.75% = 0,53875 ether
        so from that we can get the new utilization
        which is total borrow / total supply. =  0,53875 / 1,03875 = ~51.865%. Note how this went up from previous 50%
        and borrow rate is a result of utilization so with higher utilization there is a higher borrow rate.
        borrow rate is depending on the following config (when leaving the default values, defined in liquidityTestHelpers.sol):
        uint256 constant DEFAULT_KINK = 80 * DEFAULT_PERCENT_PRECISION; // 80%
        uint256 constant DEFAULT_RATE_AT_ZERO = 4 * DEFAULT_PERCENT_PRECISION; // 4%
        uint256 constant DEFAULT_RATE_AT_KINK = 10 * DEFAULT_PERCENT_PRECISION; // 10%
        uint256 constant DEFAULT_RATE_AT_MAX = 150 * DEFAULT_PERCENT_PRECISION; // 150%
        borrow rate is y = mx +b where b = DEFAULT_RATE_AT_ZERO
        and for m*x , we can simply think if 80% is the total length from 0 to kink and over this period it increases from 4% at 0 to 10% at kink we can find out:
        how much of the total length we passed with utilization being at 51%: utilization / length = 51.86% / 80% = 64,825%
        so borrow rate will be: 64,825%  of the total 6% growth (4 at 0 to 10 at kink) + 4%. -> 64,825% * 0.6 + 4% = 3,8895% + 4% = 7.8895%
        so over 1 year the borrow rate is 7.8895% or for 36.5 days 10% of that so 0.78895%
        new borrow exchange price = oldBorrowExchangePrice * 100.78895% = 1077500000000 * 100,78895% = 1086000936250.
        For the supply exchange price, previously it was half of the increase of borrow exchange price because we were at exactly 50% utilization. But now it is 51.86% utilization so it will be that increase :
        0.78895% * 51.86% = 0,40914947%.
        new supply exchange price = oldSupplyExchangePrice * 100.40914947 = 1038750000000 * 100,40914947% = 1043000040119
        and to get to new total amounts afterwards simply multiply previous total amounts with new exchange prices again
        */

        return (rateModel, endTime_, startTime_);
    }

    function activateYieldWithDefaultValuesAndWarpTime(uint256 time) internal {
        activateYieldAndWarpTime(time, DEFAULT_SUPPLY_AMOUNT, DEFAULT_BORROW_AMOUNT);
    }

    function activateYieldAndWarpTime(uint256 time, uint256 supplyAmount, uint256 borrowAmount) internal {
        // alice supplies asset liquidity
        asset.mint(address(liquidity), 100 * 1e6);
        _setUserAllowancesDefault(address(liquidity), admin, address(asset), address(mockProtocol));
        address alice = address(0xB0FF);
        // alice supplies asset liquidity
        asset.mint(alice, supplyAmount);
        vm.prank(alice);
        asset.approve(address(mockProtocol), type(uint256).max);
        _supply(address(liquidity), mockProtocol, address(asset), alice, supplyAmount);

        // alice borrows asset liquidity
        _borrow(mockProtocol, address(asset), alice, borrowAmount);

        // simulate passing time to accrue yield
        vm.warp(block.timestamp + time);

        address[] memory tokens = new address[](1);
        tokens[0] = address(asset);
        // update exchange prices at liquidity (open method)
        FluidLiquidityAdminModule(address(liquidity)).updateExchangePrices(tokens);
    }

    function initialDeposit(uint256 amount) internal {
        asset.mint(admin, amount);
        vm.prank(admin);
        asset.approve(address(token), amount);
        vm.prank(admin);
        uint256 shares = IFToken(address(token)).deposit(amount, admin);
        sharesAmountFrominitialDeposit += shares;
    }
}

contract ERC4626fTokenTest is ERC4626fTokenHelperTest {
    function test_metadata() public {
        assertEq(token.name(), string.concat("Fluid ", asset.symbol()));
        assertEq(token.symbol(), string.concat("f", asset.symbol()));
        assertEq(token.decimals(), asset.decimals());
        assertEq(token.asset(), address(asset));
    }

    function test_fuzz_deposit_RedeemReturnsAtMostDeposited(uint256 assets) public {
        assets = bound(assets, 1_000, 1e14);

        uint256 expectedShares = token.previewDeposit(assets);
        vm.prank(alice);
        uint256 shares = token.deposit(assets, alice);
        assertEq(shares, expectedShares);

        uint256 expectedAssets = token.previewRedeem(shares);
        vm.prank(alice);
        uint256 redeemed = token.redeem(shares, alice, alice);

        assertEq(redeemed, expectedAssets);
        assertLe(redeemed, assets);
        assertEq(token.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(token)), 0);
    }

    function test_fuzz_mint_WithdrawBurnsAtMostMinted(uint256 shares) public {
        shares = bound(shares, 1_000, 1e14);

        uint256 expectedAssets = token.previewMint(shares);
        vm.prank(alice);
        uint256 assetsIn = token.mint(shares, alice);
        assertEq(assetsIn, expectedAssets);

        uint256 withdrawAssets = token.maxWithdraw(alice);
        uint256 expectedBurn = token.previewWithdraw(withdrawAssets);
        vm.prank(alice);
        uint256 burned = token.withdraw(withdrawAssets, alice, alice);

        assertEq(burned, expectedBurn);
        assertLe(burned, shares);
    }

    function test_previews_RoundInProtocolFavor() public {
        initialDeposit(1_000_000 * 1e6);
        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME);

        uint256[5] memory amounts = [uint256(1), 7, 1_000, 123_456, 987_654_321];

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amt = amounts[i];
            assertLe(token.previewDeposit(amt), token.convertToShares(amt));
            assertLe(token.previewRedeem(amt), token.convertToAssets(amt));
            assertGe(token.previewMint(amt), token.convertToAssets(amt));
            assertGe(token.previewWithdraw(amt), token.convertToShares(amt));
        }
    }

    function test_deposit_ReceiverGetsShares() public {
        uint256 aliceAssetBefore = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = token.deposit(1_000 * 1e6, bob);

        assertEq(token.balanceOf(bob), shares);
        assertEq(token.balanceOf(alice), 0);
        assertEq(aliceAssetBefore - asset.balanceOf(alice), 1_000 * 1e6);
    }

    function test_withdraw_SpenderWithAllowance() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        uint256 aliceSharesBefore = token.balanceOf(alice);
        vm.prank(alice);
        token.approve(bob, aliceSharesBefore);

        uint256 withdrawAssets = token.convertToAssets(aliceSharesBefore) / 2;
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 allowanceBefore = token.allowance(alice, bob);

        vm.prank(bob);
        uint256 burnedShares = token.withdraw(withdrawAssets, bob, alice);

        assertEq(aliceSharesBefore - token.balanceOf(alice), burnedShares);
        assertEq(allowanceBefore - token.allowance(alice, bob), burnedShares);
        assertEq(asset.balanceOf(bob) - bobAssetBefore, withdrawAssets);
    }

    function test_redeem_SpenderWithAllowance() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        uint256 aliceSharesBefore = token.balanceOf(alice);
        vm.prank(alice);
        token.approve(bob, aliceSharesBefore);

        uint256 redeemShares = aliceSharesBefore / 2;
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 allowanceBefore = token.allowance(alice, bob);

        vm.prank(bob);
        uint256 assetsOut = token.redeem(redeemShares, bob, alice);

        uint256 burnedShares = aliceSharesBefore - token.balanceOf(alice);
        assertEq(allowanceBefore - token.allowance(alice, bob), burnedShares);
        assertEq(asset.balanceOf(bob) - bobAssetBefore, assetsOut);
    }

    function test_withdraw_RevertIfSpenderNotApproved() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        vm.prank(bob);
        token.withdraw(1, bob, alice);
    }

    function test_redeem_RevertIfSpenderNotApproved() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        vm.prank(bob);
        token.redeem(1, bob, alice);
    }

    function test_deposit_RevertIfAssetNotApproved() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTransfer.FluidSafeTransferError.selector,
                LibsErrorTypes.SafeTransfer__TransferFromFailed
            )
        );
        vm.prank(bob);
        token.deposit(1_000 * 1e6, bob);
    }

    function test_mint_RevertIfAssetNotApproved() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTransfer.FluidSafeTransferError.selector,
                LibsErrorTypes.SafeTransfer__TransferFromFailed
            )
        );
        vm.prank(bob);
        token.mint(1_000 * 1e6, bob);
    }

    function test_withdraw_RevertIfAboveMaxWithdraw() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        uint256 maxWithdrawAmount = token.maxWithdraw(alice);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        vm.prank(alice);
        token.withdraw(maxWithdrawAmount + 1, alice, alice);
    }

    function test_redeem_RevertIfAboveBalance() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        uint256 balance = token.balanceOf(alice);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        vm.prank(alice);
        token.redeem(balance + 1, alice, alice);
    }

    function test_deposit_RevertIfZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        vm.prank(alice);
        token.deposit(0, alice);
    }

    function test_mint_RevertIfZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        vm.prank(alice);
        token.mint(0, alice);
    }

    function test_withdraw_RevertIfZero() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        vm.prank(alice);
        token.withdraw(0, alice, alice);
    }

    function test_redeem_RevertIfZero() public {
        vm.prank(alice);
        token.deposit(1_000 * 1e6, alice);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountsZero)
        );
        vm.prank(alice);
        token.redeem(0, alice, alice);
    }

    function test_redeem_EarlierDepositorEarnsMoreYield() public {
        uint256 depositAmount = 1_000 * 1e6;

        vm.prank(alice);
        token.deposit(depositAmount, alice);

        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME);

        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);
        vm.prank(bob);
        token.deposit(depositAmount, bob);

        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME);

        uint256 aliceShares = token.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceAssets = token.redeem(aliceShares, alice, alice);

        uint256 bobShares = token.balanceOf(bob);
        vm.prank(bob);
        uint256 bobAssets = token.redeem(bobShares, bob, bob);

        assertGt(aliceAssets, depositAmount);
        assertGt(bobAssets, depositAmount);
        assertGt(aliceAssets, bobAssets);
        assertEq(asset.balanceOf(address(token)), 0);
    }

    function test_maxWithdrawAndMaxRedeem_AreExecutable() public {
        uint256 depositAmount = 1_000 * 1e6;
        vm.prank(alice);
        token.deposit(depositAmount, alice);

        activateYieldWithDefaultValuesAndWarpTime(PASS_1YEAR_TIME);

        assertLe(token.maxRedeem(alice), token.balanceOf(alice));

        uint256 snapshotId = vm.snapshot();

        uint256 withdrawAssets = token.maxWithdraw(alice);
        vm.prank(alice);
        token.withdraw(withdrawAssets, alice, alice);

        vm.revertTo(snapshotId);

        uint256 redeemShares = token.maxRedeem(alice);
        vm.prank(alice);
        token.redeem(redeemShares, alice, alice);
    }
}

contract ERC4626fTokenCustomCasesTest is ERC4626fTokenHelperTest {
    address john = address(0x123F);

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        IFToken(address(token)).updateRebalancer(admin);
    }

    //  if lendingRewardsRateModel says rewards are active and distributes rewards but admin did not fund enough rewards via "rebalance".
    // Liquidity balance would simply be insufficient if all users would want to withdraw so would revert.
    // But can once verify this with a test and verify that once admin funds rewards all users can withdraw normally.
    function test_AllUsersWantToWithdrawRewardsActiveButInsufficientLiquidityBalance() public {
        vm.prank(alice);
        asset.burn(address(liquidity), asset.balanceOf(address(liquidity)));
        (rateModel, endTime_, startTime_) = activateRewardRateModel();

        assertEq(asset.balanceOf(address(liquidity)), 0);

        uint256 fundAmount = 2000;
        vm.prank(alice);
        asset.mint(alice, fundAmount);
        vm.prank(alice);
        token.deposit(fundAmount, alice);
        vm.prank(bob);
        asset.mint(bob, fundAmount);
        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);
        vm.prank(bob);
        token.deposit(fundAmount, bob);

        vm.warp(block.timestamp + (PASS_1YEAR_TIME * 3) / 4);

        uint256 aliceSharesConvertedToAssets = token.convertToAssets(token.balanceOf(alice));
        vm.prank(alice);
        token.withdraw(aliceSharesConvertedToAssets - 10, alice, alice); //alice withraws ALMOST all assets (alice and bob deposited assets) from token

        uint256 aliceAndBobAssetsAfterAliceWithdraw = token.convertToAssets(token.balanceOf(alice)) +
            token.convertToAssets(token.balanceOf(bob)); // rest of the assets

        //bob
        uint256 bobSharesConvertedToAssets = token.convertToAssets(token.balanceOf(bob));
        // should revert because there is no enough assets in liquidity
        vm.expectRevert();
        vm.prank(bob);
        token.withdraw(bobSharesConvertedToAssets, bob, bob);

        asset.mint(admin, aliceAndBobAssetsAfterAliceWithdraw);
        _setApproval(IERC20(address(asset)), address(token), admin);
        vm.prank(admin);
        IFToken(address(token)).rebalance();

        //now bob can withdraw rest of his  assets
        uint256 restBobBalance = token.convertToAssets(token.balanceOf(bob));
        vm.prank(bob);
        token.withdraw(restBobBalance, bob, bob);

        //alice as well
        uint256 restAliceBalance = token.convertToAssets(token.balanceOf(alice));
        vm.prank(alice);
        token.withdraw(restAliceBalance, alice, alice);

        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    // Special case of all depositors fully withdraw and then deposits start again. Does yield accrue as expected for new depositors?
    // We can assume liquidity balance is present thanks to initial initialDeposit call.
    function test_DepositorsFullyWithdrawAndStartAgain() public {
        // A = Alice, B = Bob, B = Jon
        //  _______________________________________________________________________________________
        // | Vault shares | A share | A assets | B share | B assets  | C share | C assets |       |
        // |======================================================================================|
        // | 0. Initial state after initial deposit                                               |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |         0 |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 1. Warp time to 10% of whole period (exchange token price goes up because of rewards)|
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 2. All deposit 2000 tokens (1990 shares)                     |           |           |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35970 |      1990 |    2000   |      1990 |        2000 |      1990 |      2000 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 3. All users withdraw                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |        0  |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 4. Warp time to 75% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 5. Deactivate rewards                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 6. Warp time to 80% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 7. Activate rewards                                                                  |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 8. Warp time to 90% of the whole period                                              |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 9. All deposits 2000 tokens                                                          |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35751 |      1918 |     2000  |      1918 |        2000 |      1918 |      2000 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 10. Warp time to 100% of the whole period                                            |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      35751 |      1918 |     2007  |      1918 |        2007 |      1918 |      2007 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // | 9. All users withdraw                                                                |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|
        // |      30000 |         0 |        0  |         0 |           0 |         0 |         0 |
        // |------------|-----------|-----------|-----------|-------------|-----------|-----------|

        (rateModel, endTime_, startTime_) = activateRewardRateModel();
        initialDeposit();

        assertEq(block.timestamp, 3153601);
        // 1. Warp time to 10% of whole period (exchange token price goes up because of rewards)
        vm.warp(block.timestamp + (PASS_1YEAR_TIME) / 10);
        assertEq(block.timestamp, 6307201); // 3153601 + (31536000 * 1 / 10) = 6307201

        // 2. All deposit 2000 tokens (costs 1990 tokens)
        // all deposit 2000 assets (1990 shares)
        depositForUsers(alice, bob, john);
        assertsAfterFirstDeposit(IFToken(address(token)));
        // 3. All users withdraw
        withdrawForUsers(alice, bob, john, IFToken(address(token)));
        // 4. Warp time to 75% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 65) / 100));
        assertEq(block.timestamp, 26805601); // 3153601 + (31536000 * 3 / 4) = 26805601
        assertsAfterSecondWarp(IFToken(address(token)));

        // 5. Deactivate rewards
        deactivateRewards(IFToken(address(token)));

        // 6. Warp time to 80% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 5) / 100));
        assertEq(block.timestamp, 28382401); // 3153601 + (31536000 * 4 / 5) = 28382401
        assertsAfterThirdWarp(IFToken(address(token)));

        // 7. Activate rewards
        activateRewards(IFToken(address(token)));

        // 8. Warp time to 90% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 1) / 10));
        assertEq(block.timestamp, 31536001); // 3153601 + (31536000 * 9 / 10) = 31536001
        assertsAfterFourthWarp(IFToken(address(token)));

        // 9. All deposits 2000 tokens
        secondRoundOfDeposits(alice, bob, john);
        // 10. Warp time to 100% of the whole period
        vm.warp(block.timestamp + (((PASS_1YEAR_TIME) * 1) / 10));

        assertEq(block.timestamp, 34689601); // 3153601 + 31536000 = 34689601
        assertsAfterFinalWarp(IFToken(address(token)));
        // 9. All users withdraw
        finalWithdrawForUsers(alice, bob, john, IFToken(address(token)));
    }

    function initialDeposit() private {
        uint256 assetsAmount = 30_000;
        asset.mint(admin, assetsAmount);
        vm.prank(admin);
        asset.approve(address(token), assetsAmount);
        vm.prank(admin);
        IFToken(address(token)).deposit(assetsAmount, admin);
    }

    function depositForUsers(address alice, address bob, address john) private {
        uint256 fundAmount = 2000;
        // shares = assets / token exchnage price
        // shares = 2000 / 1.005 = 1990.0497512437810945273631840796019900497512437810945273631840796 and down = 1990
        // will mint 1990 shares
        // Alice's deposit
        makeDeposit(alice, fundAmount);
        // Bob's deposit
        makeDeposit(bob, fundAmount);
        // John's deposit
        makeDeposit(john, fundAmount);
    }

    function assertsAfterFirstDeposit(IFToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();
        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 5000000000000 * (6307201 - 3153601) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 5000000000000 * 3153600 / 31536000
        // rewards return in percentage = 500000000000

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1 + 1 * 500000000000 / 1e14
        // token exchange price_ = 1.005
        assertEq(tokenExchangePrice, 1005000000000);

        // each has 1990 shares
        assertEq(token.balanceOf(alice), 1990);
        assertEq(token.balanceOf(bob), 1990);
        assertEq(token.balanceOf(john), 1990);

        // 1990 * 1.005 = 1999.95 and down 1999
        assertEq(token.convertToAssets(token.balanceOf(alice)), 1999);
        assertEq(token.convertToAssets(token.balanceOf(bob)), 1999);
        assertEq(token.convertToAssets(token.balanceOf(john)), 1999);
    }

    function withdrawForUsers(address alice, address bob, address john, IFToken token) private {
        // Alice's withdrawal
        makeWithdrawal(alice, token);
        // Bob's withdrawal
        makeWithdrawal(bob, token);
        // John's withdrawal
        makeWithdrawal(john, token);
    }

    function assertsAfterSecondWarp(IFToken token) private {
        (, , IFluidLendingRewardsRateModel rateModel_, , , , , , uint256 tokenExchangePrice) = token.getData();

        // reward rate based on totalAssets with oldTokenExchangePrice -> 30000 * 1.005 = 30150.
        // yearly 1500 rewards per 30150 tvl -> 0,0497512437810945273631840796
        (uint256 rate, , ) = rateModel_.getRate(30150);
        assertEq(rate, 4975124378109);

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4975124378109 * (26805601 - 6307201) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4975124378109 * 20498400 / 31536000
        // rewards return in percentage = 3233830845770

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1.005 + 1.005 * 3233830845770 / 1e14
        // token exchange price_ = 1,037499999999

        assertEq(tokenExchangePrice, 1037499999999);

        assertEq(token.totalAssets(), 31124); // 75% of rewards accrued (1500 so 1125, rounded down to 1124)

        // all have 0 shares
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    function deactivateRewards(IFToken token) private {
        vm.prank(admin);
        token.updateRewards(IFluidLendingRewardsRateModel(address(0)));
    }

    function assertsAfterThirdWarp(IFToken token) private {
        (, , , , , , , , uint256 tokenExchangePrice) = token.getData();

        // rewards return in percentage = 0 is because rewards are not active

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e12
        // token exchange price_ = 1.037499999999 + 1.037499999999  * 0 / 1e12
        // token exchange price_ = 1.037499999999

        assertEq(tokenExchangePrice, 1037499999999);

        // all have 0 shares
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    function activateRewards(IFToken token) private {
        vm.prank(admin);
        token.updateRewards(IFluidLendingRewardsRateModel(address(rateModel)));
    }

    function assertsAfterFourthWarp(IFToken token) private {
        (, , IFluidLendingRewardsRateModel rateModel_, , , , , , uint256 tokenExchangePrice) = token.getData();

        // reward rate based on totalAssets with oldTokenExchangePrice -> 30000 * 1037499999999 / 1e12 = 31124.
        // yearly 1500 rewards per 31124 tvl ->0.0481943194962087135329649145354067600
        (uint256 rate, , ) = rateModel_.getRate(31124);
        assertEq(rate, 4819431949620);

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4819431949620 * (31536001 - 28382401) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4819431949620 * 3153600 / 31536000
        // rewards return in percentage = 481943194962

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1037499999999 + 1037499999999  * 481943194962 / 1e14
        // token exchange price_ = 1.04250016064672593056805038

        assertEq(tokenExchangePrice, 1042500160646);

        // 90% of rewards accrued but rewards model was not enabled on fToken for 5% of the time so only 85%
        // (1500 * 0.85 = 1275)
        assertEq(token.totalAssets(), 31275);
    }

    function secondRoundOfDeposits(address alice, address bob, address john) private {
        uint256 fundAmount = 2000;

        //  shares = assets / token exchange price
        //  shares = 2000 * 1e12 / 1042500160646
        //  shares = 1918.464 and down 1918

        // Alice's second deposit
        makeDeposit(alice, fundAmount);
        // Bob's second deposit
        makeDeposit(bob, fundAmount);
        // John's second deposit
        makeDeposit(john, fundAmount);

        assertEq(token.totalAssets(), 37273); // 31275 + 6000 in deposits, rounded down difference from shares
    }

    function assertsAfterFinalWarp(IFToken token) private {
        (, , IFluidLendingRewardsRateModel rateModel_, , , , , , uint256 tokenExchangePrice) = token.getData();

        // reward rate based on totalAssets with oldTokenExchangePrice -> 30000 * 1042500160646 / 1e12 = 31275.
        // but also 6000 in deposits are added  so tvl = 37273
        // yearly 1500 rewards per 37273 tvl -> 0.4024360797360019316931827328
        (uint256 rate, , ) = rateModel_.getRate(37273);
        assertEq(rate, 4024360797360);

        // rewards return in percentage = rewardsRate * timeElapsed / SECONDS_PER_YEAR
        // rewards return in percentage = 4024360797360 * (34689601 - 31536001) / 31536000 (rewardRate proper calculation confirmed in lendingRewardsRateModel.t.sol)
        // rewards return in percentage = 4024360797360 * 3153600 / 31536000
        // rewards return in percentage = 402436079736

        // token exchange price_ = oldTokenExchangePrice_ + oldTokenExchangePrice_ * totalReturnInPercent_ / 1e14
        // token exchange price_ = 1042500160646 + 1042500160646 * 402436079736 / 1e14
        // token exchange price_ = 1.04669555742374526465269456

        assertEq(tokenExchangePrice, 1046695557423);

        // each has 1918 shares (2000×1e12÷1042500160646)
        assertEq(token.balanceOf(alice), 1918);
        assertEq(token.balanceOf(bob), 1918);
        assertEq(token.balanceOf(john), 1918);

        // 1918 * 1046695557423 / 1e12 = 2007.562
        assertEq(token.convertToAssets(token.balanceOf(alice)), 2007);
        assertEq(token.convertToAssets(token.balanceOf(bob)), 2007);
        assertEq(token.convertToAssets(token.balanceOf(john)), 2007);

        // 100% of rewards accrued but rewards model was not enabled on fToken for 5% of the time so only 95%
        // (1500 * 0.85 = 1425)
        assertEq(token.totalAssets(), 37423); // rounded down from shares diff, + 6000 assets
    }

    function finalWithdrawForUsers(address alice, address bob, address john, IFToken token) private {
        // Alice's final withdrawal
        makeWithdrawal(alice, token);
        // Bob's final withdrawal
        makeWithdrawal(bob, token);
        // John's final withdrawal
        makeWithdrawal(john, token);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(john), 0);
    }

    // Helper functions for deposit and withdrawal
    function makeDeposit(address user, uint256 amount) private {
        vm.prank(user);
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(token), amount);
        vm.prank(user);
        token.deposit(amount, user);
    }

    function makeWithdrawal(address user, IFToken token) private {
        uint256 userBalance = token.convertToAssets(token.balanceOf(user));
        vm.prank(user);
        token.withdraw(userBalance, user, user);
    }
}

contract ERC4626fToken_Invariants_Handler_Test is ERC4626fTokenHelperTest {
    Handler handler;
    address john = address(0xABFF);

    address[] users = new address[](3);
    uint256 lastTokenExchangePrice;

    function setUp() public virtual override(ERC4626fTokenHelperTest) {
        ERC4626fTokenHelperTest.setUp();
        (rateModel, endTime_, startTime_) = activateRewardRateModel();
        users[0] = address(alice);
        users[1] = address(bob);
        users[2] = address(john);
        handler = new Handler(IFToken(address(token)), address(asset), users, admin);

        vm.prank(alice);
        asset.approve(address(token), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);

        vm.prank(john);
        asset.approve(address(token), type(uint256).max);

        vm.prank(alice);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(john);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(alice);
        token.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        token.approve(address(handler), type(uint256).max);

        vm.prank(john);
        token.approve(address(handler), type(uint256).max);

        targetContract(address(handler));

        // address[] memory senders = [alice, bob];
        targetSender(alice);
        targetSender(bob);

        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(admin);
        factory.setAuth(bob, true);
        vm.prank(admin);
        factory.setAuth(john, true);

        (, , , , , , , , lastTokenExchangePrice) = IFToken(address(token)).getData();

        asset.mint(bob, 5e18);
        vm.prank(bob);
        token.deposit(5e18, bob);

        asset.mint(alice, 5e18);
        vm.prank(alice);
        token.deposit(5e18, alice);

        asset.mint(john, 5e18);
        vm.prank(john);
        token.deposit(5e18, john);
    }

    function invariant_TokenExchangePriceShouldOnlyGoUp() public {
        // exchange price should only ever go up
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        assertGe(currentTokenExchangePrice, lastTokenExchangePrice, "Token exchange price should not decrease");
    }

    function invariant_UndelyingBalanceOfFTokenShouldNeverBeGreaterThanZero() public {
        // with normal interactions (supply, withdraw) ERC20 underlying balanceOf fToken should never be > 0.
        assertEq(asset.balanceOf(address(token)), 0, "Token exchange price should not decrease");
    }

    function invariant_SharesShouldAlwaysBeSumOfAllDepositorsShares() public {
        // shares should always be sum of all depositors shares

        uint256 sum;
        for (uint256 i = 0; i > users.length; i++) {
            sum += IFToken(address(token)).balanceOf(users[i]);
        }
        assertGe(IFToken(address(token)).totalAssets(), sum, "Token exchange price should not decrease");
    }

    function invariant_Metadata() public {
        assertEq(token.name(), string.concat("Fluid ", asset.symbol()));
        assertEq(token.symbol(), string.concat("f", asset.symbol()));
        assertEq(token.decimals(), token.decimals());
    }
}
