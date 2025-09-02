pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFToken } from "../../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";

import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { Structs as FluidLiquidityResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";

import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";

import { ErrorTypes as LendingErrorTypes } from "../../../../contracts/protocols/lending/errorTypes.sol";
import { Error as LendingError } from "../../../../contracts/protocols/lending/error.sol";

contract FTokenHandler is Test {
    using FixedPointMathLib for uint256;

    IFToken token;
    MockERC20 underlying;

    address[] public actors;
    address public rateModel;
    address public admin;
    address public liquidity;
    MockProtocol mockProtocol;
    FluidLiquidityResolver resolver;

    address internal currentActor;

    uint256 internal liquidityExchangePrice;
    uint256 internal tokenExchangePrice;
    uint256 internal borrowExchangePrice;
    uint256 internal supplyExchangePrice;

    uint256 public ghost_sumBalanceOf;

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

    // function randomly warps time between 0 and 10 days
    modifier randomTimeWarp() {
        uint256 randomSeconds = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % (10 days);
        vm.warp(block.timestamp + randomSeconds);

        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);
        // update exchange prices at liquidity (open method)
        FluidLiquidityAdminModule(address(liquidity)).updateExchangePrices(tokens);
        _;
    }

    // random supply
    modifier randomSupplyAndBorrow() {
        underlying.mint(address(liquidity), 100 * 1e6);
        // actor supplies asset liquidity
        uint256 randomSupplyAmount = (uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, currentActor))
        ) & (0.8 ether)) + 0.2 ether;
        underlying.mint(currentActor, randomSupplyAmount);
        underlying.approve(address(mockProtocol), type(uint256).max);
        // _supply
        mockProtocol.operate(
            address(underlying),
            int256(randomSupplyAmount),
            0,
            address(0),
            address(0),
            abi.encode(currentActor)
        );
        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(underlying)
        );
        uint256 randomBorrowAmount = randomSupplyAmount > 0
            ? uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, currentActor))) % randomSupplyAmount
            : 0;
        if (randomBorrowAmount > userBorrowData_.borrowable) randomBorrowAmount = userBorrowData_.borrowable;
        mockProtocol.operate(
            address(underlying),
            0,
            int256(randomBorrowAmount),
            address(0),
            currentActor,
            new bytes(0)
        );
        _;
    }

    constructor(
        IFToken token_,
        address underlying_,
        address[] memory actors_,
        address admin_,
        address liquidity_,
        MockProtocol mockProtocol_
    ) {
        token = token_;
        underlying = MockERC20(underlying_);
        actors = actors_;
        admin = admin_;
        liquidity = liquidity_;
        mockProtocol = mockProtocol_;
        resolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity_)));
    }

    function _assertLiquidityExchangePrices() internal {
        (, , , , , , , uint256 newLiquidityExchangePrice, uint256 newTokenExchangePrice) = IFToken(address(token))
            .getData();
        FluidLiquidityResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(
            address(underlying)
        );

        assertGe(overallTokenData.borrowExchangePrice, borrowExchangePrice); // new borrow exchange price >= borrow exchange price
        assertGe(overallTokenData.supplyExchangePrice, supplyExchangePrice); // new borrow exchange price >= borrow exchange price
        assertGe(newLiquidityExchangePrice, liquidityExchangePrice);
        assertGe(newTokenExchangePrice, tokenExchangePrice);

        borrowExchangePrice = overallTokenData.borrowExchangePrice;
        supplyExchangePrice = overallTokenData.supplyExchangePrice;
        liquidityExchangePrice = newLiquidityExchangePrice;
        tokenExchangePrice = newTokenExchangePrice;
    }

    struct DepositState {
        uint256 assetsBefore;
        uint256 sharesBefore;
        uint256 assetsAfter;
        uint256 sharesAfter;
        uint256 currentTokenExchangePrice;
        uint256 expectedShares;
    }

    function deposit(
        uint256 assets,
        address receiver,
        uint256 actorIndexSeed
    ) external randomTimeWarp useActor(actorIndexSeed) randomSupplyAndBorrow returns (uint256 shares) {
        assets = bound(assets, 1e4, 1e18);
        underlying.mint(currentActor, assets);
        underlying.approve(address(token), type(uint256).max);

        DepositState memory state;
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        state.currentTokenExchangePrice = currentTokenExchangePrice;
        // solidity rounds down by default
        state.expectedShares = (assets * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) / state.currentTokenExchangePrice;

        state.assetsBefore = underlying.balanceOf(currentActor);
        state.sharesBefore = token.balanceOf(currentActor);

        shares = _executeDeposit(assets, state);

        ghost_sumBalanceOf += shares;

        _assertLiquidityExchangePrices();

        return shares;
    }

    function _executeDeposit(uint256 assets, DepositState memory state) internal returns (uint256 shares) {
        shares = token.deposit(assets, currentActor);

        state.assetsAfter = underlying.balanceOf(currentActor);
        state.sharesAfter = token.balanceOf(currentActor);

        // equal because expectedAssetsReceived is already rounded down as default in Solidity
        assertEq(state.sharesAfter - state.sharesBefore, state.expectedShares);
        assertEq(state.assetsBefore - state.assetsAfter, assets);

        // shares * tokenExchangePrice / 1e12
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        uint256 maxWithdrawAmount = token.maxWithdraw(currentActor);
        assertLe(maxWithdrawAmount, ((token.balanceOf(currentActor) * currentTokenExchangePrice) / 1e12));

        uint256 maxRedeemAmount = token.maxRedeem(currentActor);
        assertLe(maxRedeemAmount, token.balanceOf(currentActor));

        return shares;
    }

    struct MintState {
        uint256 assetsBefore;
        uint256 sharesBefore;
        uint256 assetsAfter;
        uint256 sharesAfter;
        uint256 currentTokenExchangePrice;
        uint256 expectedAssets;
    }

    function mint(
        uint256 shares,
        uint256 actorIndexSeed
    ) external randomTimeWarp useActor(actorIndexSeed) randomSupplyAndBorrow {
        shares = bound(shares, 1e4, 1e18);

        uint256 consumeAssets = token.previewMint(shares);

        underlying.mint(currentActor, consumeAssets);
        underlying.approve(address(token), type(uint256).max);

        MintState memory state;
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        state.currentTokenExchangePrice = currentTokenExchangePrice;
        state.expectedAssets = (shares * state.currentTokenExchangePrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        state.assetsBefore = underlying.balanceOf(currentActor);
        state.sharesBefore = token.balanceOf(currentActor);

        _executeMint(shares, state);

        ghost_sumBalanceOf += shares;

        _assertLiquidityExchangePrices();
    }

    function _executeMint(uint256 shares, MintState memory state) internal {
        try token.mint(shares, currentActor) {} catch (bytes memory lowLevelData) {
            // we ignore cases when there is arithmetic error or withdrawal limit is reached
            if (keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError))) {
                assertEq(true, false);
            }
        }

        state.assetsAfter = underlying.balanceOf(currentActor);
        state.sharesAfter = token.balanceOf(currentActor);

        assertEq(state.sharesAfter - state.sharesBefore, shares);
        assertTrue(state.assetsBefore - state.assetsAfter >= state.expectedAssets);

        // shares * tokenExchangePrice / 1e12
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        uint256 maxWithdrawAmount = token.maxWithdraw(currentActor);

        assertLe(maxWithdrawAmount, ((token.balanceOf(currentActor) * currentTokenExchangePrice) / 1e12));

        uint256 maxRedeemAmount = token.maxRedeem(currentActor);
        assertLe(maxRedeemAmount, token.balanceOf(currentActor));
    }

    struct WithdrawState {
        uint256 assetsBefore;
        uint256 sharesBefore;
        uint256 assetsAfter;
        uint256 sharesAfter;
        uint256 currentTokenExchangePrice;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 actorIndexSeed
    ) external randomTimeWarp useActor(actorIndexSeed) randomSupplyAndBorrow {
        assets = bound(assets, 1e4, 1e18);
        underlying.mint(currentActor, assets);
        underlying.approve(address(token), type(uint256).max);

        WithdrawState memory state;
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        state.currentTokenExchangePrice = currentTokenExchangePrice;

        uint256 sharesToBurn_ = assets.mulDivUp(
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION,
            state.currentTokenExchangePrice
        );
        if (token.balanceOf(currentActor) < sharesToBurn_) return;

        state.assetsBefore = underlying.balanceOf(currentActor);
        state.sharesBefore = token.balanceOf(currentActor);

        _executeWithdraw(assets, state);

        _assertLiquidityExchangePrices();
    }

    function _executeWithdraw(uint256 assets, WithdrawState memory state) internal {
        try token.withdraw(assets, currentActor, currentActor) returns (uint256 shares) {
            ghost_sumBalanceOf -= shares;

            state.assetsAfter = underlying.balanceOf(currentActor);
            state.sharesAfter = token.balanceOf(currentActor);

            uint256 expectedBurnedShares = (assets * LiquidityCalcs.EXCHANGE_PRICES_PRECISION) /
                state.currentTokenExchangePrice;

            // assert that the actual burned shares are greater than or equal to the expected amount, confirming rounding up
            assertTrue(state.sharesBefore - state.sharesAfter >= expectedBurnedShares);
            assertEq(state.assetsAfter - state.assetsBefore, assets);

            // shares * tokenExchangePrice / 1e12
            (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
            uint256 maxWithdrawAmount = token.maxWithdraw(currentActor);

            assertLe(maxWithdrawAmount, ((token.balanceOf(currentActor) * currentTokenExchangePrice) / 1e12));

            uint256 maxRedeemAmount = token.maxRedeem(currentActor);
            assertLe(maxRedeemAmount, token.balanceOf(currentActor));
        } catch (bytes memory lowLevelData) {
            // we ignore cases when there is arithmetic error or withdrawal limit is reached
            if (keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError))) {
                assertEq(true, false);
            }
        }
    }

    struct RedeemState {
        uint256 assetsBefore;
        uint256 sharesBefore;
        uint256 assetsAfter;
        uint256 sharesAfter;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 actorIndexSeed
    ) external randomTimeWarp useActor(actorIndexSeed) randomSupplyAndBorrow {
        shares = bound(shares, 1e4, 1e18);
        uint256 sharesBalance = token.balanceOf(currentActor);

        if (shares > sharesBalance) {
            shares = sharesBalance;
        }

        if (token.previewRedeem(sharesBalance) == 0) return;

        RedeemState memory state;
        state.assetsBefore = underlying.balanceOf(currentActor);
        state.sharesBefore = token.balanceOf(currentActor);

        _executeRedeem(shares, state);

        _assertLiquidityExchangePrices();
    }

    function _executeRedeem(uint256 shares, RedeemState memory state) internal {
        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();

        try token.redeem(shares, currentActor, currentActor) {
            ghost_sumBalanceOf -= shares;
            state.assetsAfter = underlying.balanceOf(currentActor);
            state.sharesAfter = token.balanceOf(currentActor);

            uint256 expectedAssetsReceived = (shares * currentTokenExchangePrice) /
                LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

            // equal because expectedAssetsReceived is already rounded down as default in Solidity
            assertEq(state.assetsAfter - state.assetsBefore, expectedAssetsReceived);
            // the combination of rounding down in previewRedeem and rounding up in executeWithdraw does not lead to a situation where the amount of burned shares is higher than the input shares.
            assertEq(state.sharesBefore - state.sharesAfter, shares);

            // shares * tokenExchangePrice / 1e12
            (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
            uint256 maxWithdrawAmount = token.maxWithdraw(currentActor);

            assertLe(maxWithdrawAmount, ((token.balanceOf(currentActor) * currentTokenExchangePrice) / 1e12));

            uint256 maxRedeemAmount = token.maxRedeem(currentActor);
            assertLe(maxRedeemAmount, token.balanceOf(currentActor));
        } catch (bytes memory lowLevelData) {
            // we ignore cases when there is arithmetic error or withdrawal limit is reached
            if (keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError))) {
                assertEq(true, false);
            }
        }
    }

    function updateRewards() external randomTimeWarp useAdminActor {
        //NOTE: function changes rateModel address to zero address in order to get the lowest rewards in this case 0 .
        token.updateRewards(IFluidLendingRewardsRateModel(address(0)));
        _assertLiquidityExchangePrices();
    }

    function updateRates()
        public
        randomTimeWarp
        returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_)
    {
        token.updateRates();
        _assertLiquidityExchangePrices();
    }

    function rebalance()
        public
        randomTimeWarp
        useAdminActor
        returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_)
    {
        underlying.mint(admin, 1e70); // assume rebalancer owns and approves enough for executing rebalance
        underlying.approve(address(token), 1e70);
        IFToken(address(token)).updateRebalancer(admin); //giving access to rebalance
        try IFToken(address(token)).rebalance() {
            _assertLiquidityExchangePrices();
        } catch (bytes memory lowLevelData) {
            if (
                keccak256(abi.encodePacked(lowLevelData)) != keccak256(abi.encodePacked(stdError.arithmeticError)) &&
                keccak256(abi.encodePacked(lowLevelData)) !=
                keccak256(
                    abi.encodeWithSelector(
                        Error.FluidLiquidityError.selector,
                        ErrorTypes.UserModule__OperateAmountsZero
                    )
                ) &&
                keccak256(abi.encodePacked(lowLevelData)) !=
                keccak256(
                    abi.encodeWithSelector(
                        Error.FluidLiquidityError.selector,
                        ErrorTypes.UserModule__OperateAmountInsufficient
                    )
                )
            ) {
                assertEq(true, false);
            }
        }
    }
}
