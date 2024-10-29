// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFToken } from "../../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { Events } from "../../../../contracts/protocols/lending/fToken/events.sol";

contract Handler is Test, Events {
    using FixedPointMathLib for uint256;

    IFToken token;
    MockERC20 underlying;

    address[] public actors;
    address public admin;
    address public rateModel;

    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useAdminActor() {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    constructor(IFToken token_, address underlying_, address[] memory actors_, address admin_) {
        token = token_;
        underlying = MockERC20(underlying_);
        actors = actors_;
        admin = admin_;
    }

    function deposit(
        uint256 assets,
        address receiver,
        uint256 actorIndexSeed
    ) external useActor(actorIndexSeed) returns (uint256 shares) {
        assets = bound(assets, 1e4, 1e18);

        underlying.mint(currentActor, assets);
        underlying.approve(address(token), type(uint256).max);

        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        // solidity rounds down by default
        uint256 expectedShares = (assets * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / currentTokenExchangePrice;

        uint256 assetsBefore = underlying.balanceOf(currentActor);
        uint256 sharesBefore = token.balanceOf(currentActor);
        token.deposit(assets, currentActor);
        uint256 assetsAfter = underlying.balanceOf(currentActor);
        uint256 sharesAfter = token.balanceOf(currentActor);

        // equal because expectedAssetsReceived is already rounded down as default in Solidity
        assertEq(sharesAfter - sharesBefore, expectedShares);
        assertEq(assetsBefore - assetsAfter, assets);
    }

    function mint(uint256 shares, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        shares = bound(shares, 1e4, 1e18);

        uint256 consumeAssets = token.previewMint(shares);

        underlying.mint(currentActor, consumeAssets);
        underlying.approve(address(token), type(uint256).max);

        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();

        uint256 expectedAssets = (shares * currentTokenExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        uint256 assetsBefore = underlying.balanceOf(currentActor);
        uint256 sharesBefore = token.balanceOf(currentActor);
        token.mint(shares, currentActor);
        uint256 assetsAfter = underlying.balanceOf(currentActor);
        uint256 sharesAfter = token.balanceOf(currentActor);

        assertEq(sharesAfter - sharesBefore, shares);
        assertTrue(assetsBefore - assetsAfter >= expectedAssets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 actorIndexSeed
    ) external useActor(actorIndexSeed) {
        assets = bound(assets, 1e4, 1e18);
        underlying.mint(currentActor, assets);
        underlying.approve(address(token), type(uint256).max);

        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();

        uint256 sharesToBurn_ = assets.mulDivUp(LiquidityCalcs.EXCHANGE_PRICES_PRECISION, currentTokenExchangePrice);

        if (token.balanceOf(currentActor) < sharesToBurn_) return;

        uint256 expectedBurnedShares = (assets * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / currentTokenExchangePrice;

        uint256 assetsBefore = underlying.balanceOf(currentActor);
        uint256 sharesBefore = token.balanceOf(currentActor);
        token.withdraw(assets, currentActor, currentActor);
        uint256 assetsAfter = underlying.balanceOf(currentActor);
        uint256 sharesAfter = token.balanceOf(currentActor);

        // assert that the actual burned shares are greater than or equal to the expected amount, confirming rounding up
        assertTrue(sharesBefore - sharesAfter >= expectedBurnedShares);
        assertEq(assetsAfter - assetsBefore, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 actorIndexSeed
    ) external useActor(actorIndexSeed) {
        shares = bound(shares, 1e4, 1e18);
        uint256 sharesBalance = token.balanceOf(currentActor);

        if (shares > sharesBalance) {
            shares = sharesBalance;
        }

        if (token.previewRedeem(sharesBalance) == 0) return;

        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();

        uint256 assetsBefore = underlying.balanceOf(currentActor);
        uint256 sharesBefore = token.balanceOf(currentActor);
        token.redeem(shares, currentActor, currentActor);
        uint256 assetsAfter = underlying.balanceOf(currentActor);
        uint256 sharesAfter = token.balanceOf(currentActor);

        uint256 expectedAssetsReceived = (shares * currentTokenExchangePrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // equal because expectedAssetsReceived is already rounded down as default in Solidity
        assertEq(assetsAfter - assetsBefore, expectedAssetsReceived);
        // the combination of rounding down in previewRedeem and rounding up in executeWithdraw does not lead to a situation where the amount of burned shares is higher than the input shares.
        assertEq(sharesBefore - sharesAfter, shares);
    }

    function updateRewards() external useAdminActor {
        //NOTE: function changes rateModel address to zero address in order to get the lowest rewards in this case 0 .
        vm.expectEmit(true, true, true, true);
        emit LogUpdateRewards(IFluidLendingRewardsRateModel(address(0)));
        token.updateRewards(IFluidLendingRewardsRateModel(address(0)));
    }

    function initialDeposit(uint256 assets_) external useAdminActor {
        assets_ = bound(assets_, 1e4, 2e18);
        underlying.mint(admin, assets_);
        underlying.approve(address(token), type(uint256).max);

        token.deposit(assets_, admin);
    }

    function updateRates() public {
        vm.expectEmit(true, false, false, false);
        emit LogUpdateRates(0, 0);
        token.updateRates();
    }
}
