// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { IFluidLendingFactory } from "../../../protocols/lending/interfaces/iLendingFactory.sol";
import { IFluidLendingRewardsRateModel } from "../../../protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { IAllowanceTransfer } from "../../../protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { IFToken, IFTokenNativeUnderlying } from "../../../protocols/lending/interfaces/iFToken.sol";
import { IFluidLiquidityResolver } from "../../../periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { Structs as LiquidityStructs } from "../../../periphery/resolvers/liquidity/structs.sol";
import { IFluidLendingResolver } from "./iLendingResolver.sol";
import { Structs } from "./structs.sol";

/// @notice Fluid Lending protocol (fTokens) resolver
/// Implements various view-only methods to give easy access to Lending protocol data.
contract FluidLendingResolver is IFluidLendingResolver, Structs {
    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @inheritdoc IFluidLendingResolver
    IFluidLendingFactory public immutable LENDING_FACTORY;

    /// @inheritdoc IFluidLendingResolver
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;

    /// @notice thrown if an input param address is zero
    error FluidLendingResolver__AddressZero();

    /// @notice constructor sets the immutable `LENDING_FACTORY` and `LIQUIDITY_RESOLVER` address
    constructor(IFluidLendingFactory lendingFactory_, IFluidLiquidityResolver liquidityResolver_) {
        if (address(lendingFactory_) == address(0) || address(liquidityResolver_) == address(0)) {
            revert FluidLendingResolver__AddressZero();
        }
        LENDING_FACTORY = lendingFactory_;
        LIQUIDITY_RESOLVER = liquidityResolver_;
    }

    /// @inheritdoc IFluidLendingResolver
    function isLendingFactoryAuth(address auth_) external view returns (bool) {
        return LENDING_FACTORY.isAuth(auth_);
    }

    /// @inheritdoc IFluidLendingResolver
    function isLendingFactoryDeployer(address deployer_) external view returns (bool) {
        return LENDING_FACTORY.isDeployer(deployer_);
    }

    /// @inheritdoc IFluidLendingResolver
    function getAllFTokenTypes() public view returns (string[] memory) {
        return LENDING_FACTORY.fTokenTypes();
    }

    /// @inheritdoc IFluidLendingResolver
    function getAllFTokens() public view returns (address[] memory) {
        return LENDING_FACTORY.allTokens();
    }

    /// @inheritdoc IFluidLendingResolver
    function computeFToken(address asset_, string calldata fTokenType_) external view returns (address) {
        return LENDING_FACTORY.computeToken(asset_, fTokenType_);
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokenDetails(IFToken fToken_) public view returns (FTokenDetails memory fTokenDetails_) {
        address underlying_ = fToken_.asset();

        bool isNativeUnderlying_ = false;
        try IFTokenNativeUnderlying(address(fToken_)).NATIVE_TOKEN_ADDRESS() {
            // if NATIVE_TOKEN_ADDRESS is defined, fTokenType must be NativeUnderlying.
            isNativeUnderlying_ = true;
        } catch {}

        bool supportsEIP2612Deposits_ = false;
        try IERC20Permit(underlying_).DOMAIN_SEPARATOR() {
            // if DOMAIN_SEPARATOR is defined, we assume underlying supports EIP2612. Not a 100% guarantee
            supportsEIP2612Deposits_ = true;
        } catch {}

        (, uint256 rewardsRate_) = getFTokenRewards(fToken_);
        (
            LiquidityStructs.UserSupplyData memory userSupplyData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(
                address(fToken_),
                isNativeUnderlying_ ? _NATIVE_TOKEN_ADDRESS : underlying_
            );

        uint256 totalAssets_ = fToken_.totalAssets();

        fTokenDetails_ = FTokenDetails(
            address(fToken_),
            supportsEIP2612Deposits_,
            isNativeUnderlying_,
            fToken_.name(),
            fToken_.symbol(),
            fToken_.decimals(),
            underlying_,
            totalAssets_,
            fToken_.totalSupply(),
            fToken_.convertToShares(10 ** fToken_.decimals()), // example convertToShares for 10 ** decimals
            fToken_.convertToAssets(10 ** fToken_.decimals()), // example convertToAssets for 10 ** decimals
            rewardsRate_,
            overallTokenData_.supplyRate,
            int256(userSupplyData_.supply) - int256(totalAssets_), // rebalanceDifference
            userSupplyData_
        );

        return fTokenDetails_;
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokenInternalData(
        IFToken fToken_
    )
        public
        view
        returns (
            IFluidLiquidity liquidity_,
            IFluidLendingFactory lendingFactory_,
            IFluidLendingRewardsRateModel lendingRewardsRateModel_,
            IAllowanceTransfer permit2_,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            uint256 liquidityExchangePrice_,
            uint256 tokenExchangePrice_
        )
    {
        return fToken_.getData();
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokensEntireData() public view returns (FTokenDetails[] memory) {
        address[] memory allTokens = getAllFTokens();
        FTokenDetails[] memory fTokenDetailsArr_ = new FTokenDetails[](allTokens.length);
        for (uint256 i = 0; i < allTokens.length; ) {
            fTokenDetailsArr_[i] = getFTokenDetails(IFToken(allTokens[i]));
            unchecked {
                i++;
            }
        }
        return fTokenDetailsArr_;
    }

    /// @inheritdoc IFluidLendingResolver
    function getUserPositions(address user_) external view returns (FTokenDetailsUserPosition[] memory) {
        FTokenDetails[] memory fTokensEntireData_ = getFTokensEntireData();
        FTokenDetailsUserPosition[] memory userPositionArr_ = new FTokenDetailsUserPosition[](
            fTokensEntireData_.length
        );
        for (uint256 i = 0; i < fTokensEntireData_.length; ) {
            userPositionArr_[i].fTokenDetails = fTokensEntireData_[i];
            userPositionArr_[i].userPosition = getUserPosition(IFToken(fTokensEntireData_[i].tokenAddress), user_);
            unchecked {
                i++;
            }
        }
        return userPositionArr_;
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokenRewards(
        IFToken fToken_
    ) public view returns (IFluidLendingRewardsRateModel rewardsRateModel_, uint256 rewardsRate_) {
        bool rewardsActive_;
        (, , rewardsRateModel_, , , rewardsActive_, , , ) = fToken_.getData();

        if (rewardsActive_ && address(rewardsRateModel_) != address(0)) {
            (rewardsRate_, , ) = rewardsRateModel_.getRate(fToken_.totalAssets());
        }
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokenRewardsRateModelConfig(
        IFToken fToken_
    )
        public
        view
        returns (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            uint256 maxRate_,
            uint256 rewardAmount_,
            address initiator_
        )
    {
        IFluidLendingRewardsRateModel rewardsRateModel_;
        (, , rewardsRateModel_, , , , , , ) = fToken_.getData();

        if (address(rewardsRateModel_) != address(0)) {
            (duration_, startTime_, endTime_, startTvl_, maxRate_, rewardAmount_, initiator_) = rewardsRateModel_
                .getConfig();
        }
    }

    /// @inheritdoc IFluidLendingResolver
    function getUserPosition(IFToken fToken_, address user_) public view returns (UserPosition memory userPosition) {
        IERC20 underlying_ = IERC20(fToken_.asset());

        userPosition.fTokenShares = fToken_.balanceOf(user_);
        userPosition.underlyingAssets = fToken_.convertToAssets(userPosition.fTokenShares);
        userPosition.underlyingBalance = underlying_.balanceOf(user_);
        userPosition.allowance = underlying_.allowance(user_, address(fToken_));
    }

    /// @inheritdoc IFluidLendingResolver
    function getPreviews(
        IFToken fToken_,
        uint256 assets_,
        uint256 shares_
    )
        public
        view
        returns (uint256 previewDeposit_, uint256 previewMint_, uint256 previewWithdraw_, uint256 previewRedeem_)
    {
        previewDeposit_ = fToken_.previewDeposit(assets_);
        previewMint_ = fToken_.previewMint(shares_);
        previewWithdraw_ = fToken_.previewWithdraw(assets_);
        previewRedeem_ = fToken_.previewRedeem(shares_);
    }
}
