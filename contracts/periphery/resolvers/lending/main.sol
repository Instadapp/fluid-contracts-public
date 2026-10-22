// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { IFluidLendingFactory } from "../../../protocols/lending/interfaces/iLendingFactory.sol";
import { IFluidLendingRewardsRateModel } from "../../../protocols/lending/interfaces/iLendingRewardsRateModel.sol";
import { IFluidLendingStaticRateModel } from "../../../protocols/lending/interfaces/iLendingStaticRateModel.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { IAllowanceTransfer } from "../../../protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";
import { IFToken, IFTokenNativeUnderlying } from "../../../protocols/lending/interfaces/iFToken.sol";
import { IFluidLiquidityResolver } from "../../../periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { Structs as LiquidityStructs } from "../../../periphery/resolvers/liquidity/structs.sol";
import { IFluidLendingResolver } from "./iLendingResolver.sol";
import { Structs } from "./structs.sol";
import { IFluidAccessTypeView, IFluidDeploymentNameView } from "../../../libraries/utils/minimalInterfaces.sol";
import { FluidAccessType } from "../../../libraries/fluidAccessType.sol";

/// @notice Fluid Lending protocol (fTokens) resolver
/// Implements various view-only methods to give easy access to Lending protocol data.
contract FluidLendingResolver is IFluidLendingResolver, Structs {
    /// @dev address that is mapped to the chain native token
    address internal constant _NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev On-chain model rates use `1e12` = 1%; resolver APR fields use Liquidity scale (`100` = 1%).
    uint256 internal constant MODEL_RATE_SCALE_FACTOR = 1e10;

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
    /// @dev Permissioned-stack factories expose `deploymentName()`; production factories do not → empty string.
    function getDeploymentName() external view returns (string memory deploymentName_) {
        try IFluidDeploymentNameView(address(LENDING_FACTORY)).deploymentName() returns (string memory name_) {
            deploymentName_ = name_;
        } catch {}
    }

    /// @inheritdoc IFluidLendingResolver
    function getFTokenDetails(IFToken fToken_) public view virtual returns (FTokenDetails memory fTokenDetails_) {
        address underlying_ = fToken_.asset();
        bool isNativeUnderlying_ = _isNativeUnderlyingFToken(fToken_);
        bool supportsEIP2612Deposits_ = _supportsEIP2612Deposits(fToken_, underlying_);

        (, int256 rawModelRate_, bool isStaticRate_, bool rewardsActive_) = _getFTokenRewardsData(fToken_);

        fTokenDetails_ = _buildFTokenDetails(
            fToken_,
            underlying_,
            isNativeUnderlying_,
            supportsEIP2612Deposits_,
            rawModelRate_,
            isStaticRate_,
            rewardsActive_
        );
        fTokenDetails_.accessType = _getAccessType(address(fToken_));
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
    )
        public
        view
        virtual
        returns (
            IFluidLendingRewardsRateModel rewardsRateModel_,
            uint256 relativeModelRate_,
            int256 staticModelRate_,
            bool isStaticRate_,
            uint256 liquidityRate_,
            uint256 totalRate_,
            bool rewardsActive_
        )
    {
        bool isNativeUnderlying_ = _isNativeUnderlyingFToken(fToken_);
        address underlying_ = fToken_.asset();

        int256 rawModelRate_;
        (rewardsRateModel_, rawModelRate_, isStaticRate_, rewardsActive_) = _getFTokenRewardsData(fToken_);

        (, LiquidityStructs.OverallTokenData memory overallTokenData_) = LIQUIDITY_RESOLVER.getUserSupplyData(
            address(fToken_),
            isNativeUnderlying_ ? _NATIVE_TOKEN_ADDRESS : underlying_
        );

        liquidityRate_ = overallTokenData_.supplyRate;
        (relativeModelRate_, staticModelRate_, totalRate_) = _computeHolderRates(
            _scaleModelRate(rawModelRate_),
            isStaticRate_,
            rewardsActive_,
            liquidityRate_
        );
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
            int256 maxRateOrStaticRate_,
            uint256 rewardAmount_,
            address configurator_
        )
    {
        IFluidLendingRewardsRateModel rewardsRateModel_;
        (, , rewardsRateModel_, , , , , , ) = fToken_.getData();

        if (address(rewardsRateModel_) != address(0)) {
            bool isStaticRate_;
            try fToken_.isStaticRateModelActive() returns (bool staticActive_) {
                isStaticRate_ = staticActive_;
            } catch {}

            if (isStaticRate_) {
                (maxRateOrStaticRate_, duration_, startTime_, configurator_, ) = IFluidLendingStaticRateModel(
                    address(rewardsRateModel_)
                ).getStaticConfig();
                endTime_ = startTime_ + duration_;
            } else {
                // `getConfig().maxRate` is uint256 — cast via helper to avoid stack-too-deep on the signed return.
                (
                    duration_,
                    startTime_,
                    endTime_,
                    startTvl_,
                    maxRateOrStaticRate_,
                    rewardAmount_,
                    configurator_
                ) = _streamingRateModelConfig(rewardsRateModel_);
            }
        }
    }

    /// @dev Maps streaming `getConfig()` into the signed config tuple (`maxRate` is always >= 0).
    function _streamingRateModelConfig(
        IFluidLendingRewardsRateModel model_
    )
        private
        view
        returns (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            int256 maxRateOrStaticRate_,
            uint256 rewardAmount_,
            address configurator_
        )
    {
        uint256 maxRate_;
        (duration_, startTime_, endTime_, startTvl_, maxRate_, rewardAmount_, configurator_) = model_.getConfig();
        maxRateOrStaticRate_ = int256(maxRate_);
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

    // ----------------------------- internal ---------------------------------

    function _isNativeUnderlyingFToken(IFToken fToken_) internal view returns (bool isNativeUnderlying_) {
        try IFTokenNativeUnderlying(address(fToken_)).NATIVE_TOKEN_ADDRESS() {
            isNativeUnderlying_ = true;
        } catch {}
    }

    /// @dev a permit-capable underlying is not sufficient: the fToken must also be able to consume a signature.
    ///      Beacon-proxy fTokens (permissioned stack) revert the whole ERC20Permit surface with `DisabledSelector`
    ///      and expose no `*WithSignature*` entrypoint, so `nonces` reverting rules them out.
    function _supportsEIP2612Deposits(
        IFToken fToken_,
        address underlying_
    ) internal view returns (bool supportsEIP2612Deposits_) {
        try IERC20Permit(underlying_).DOMAIN_SEPARATOR() {
            try IERC20Permit(address(fToken_)).nonces(address(0)) {
                supportsEIP2612Deposits_ = true;
            } catch {}
        } catch {}
    }

    function _buildFTokenDetails(
        IFToken fToken_,
        address underlying_,
        bool isNativeUnderlying_,
        bool supportsEIP2612Deposits_,
        int256 rawModelRate_,
        bool isStaticRate_,
        bool rewardsActive_
    ) internal view returns (FTokenDetails memory fTokenDetails_) {
        (
            LiquidityStructs.UserSupplyData memory userSupplyData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(
                address(fToken_),
                isNativeUnderlying_ ? _NATIVE_TOKEN_ADDRESS : underlying_
            );

        uint256 liquidityRate_ = overallTokenData_.supplyRate;
        (uint256 relativeModelRate_, int256 staticModelRate_, uint256 totalRate_) = _computeHolderRates(
            _scaleModelRate(rawModelRate_),
            isStaticRate_,
            rewardsActive_,
            liquidityRate_
        );

        uint256 decimals_ = fToken_.decimals();
        uint256 oneUnit_ = 10 ** decimals_;

        fTokenDetails_.tokenAddress = address(fToken_);
        fTokenDetails_.eip2612Deposits = supportsEIP2612Deposits_;
        fTokenDetails_.isNativeUnderlying = isNativeUnderlying_;
        fTokenDetails_.name = fToken_.name();
        fTokenDetails_.symbol = fToken_.symbol();
        fTokenDetails_.decimals = decimals_;
        fTokenDetails_.asset = underlying_;
        fTokenDetails_.totalAssets = fToken_.totalAssets();
        fTokenDetails_.totalSupply = fToken_.totalSupply();
        fTokenDetails_.convertToShares = fToken_.convertToShares(oneUnit_);
        fTokenDetails_.convertToAssets = fToken_.convertToAssets(oneUnit_);
        fTokenDetails_.relativeModelRate = relativeModelRate_;
        fTokenDetails_.staticModelRate = staticModelRate_;
        fTokenDetails_.isStaticRate = isStaticRate_;
        fTokenDetails_.rewardsActive = rewardsActive_;
        fTokenDetails_.liquidityRate = liquidityRate_;
        fTokenDetails_.totalRate = totalRate_;
        fTokenDetails_.rebalanceDifference = int256(userSupplyData_.supply) - int256(fTokenDetails_.totalAssets);
        fTokenDetails_.liquidityUserSupplyData = userSupplyData_;
    }

    function _getAccessType(address target_) internal view returns (uint8 accessType_) {
        accessType_ = FluidAccessType.PUBLIC;
        try IFluidAccessTypeView(target_).ACCESS_TYPE() returns (uint8 type_) {
            accessType_ = type_;
        } catch {}
    }

    function _getFTokenRewardsData(
        IFToken fToken_
    )
        internal
        view
        returns (
            IFluidLendingRewardsRateModel rewardsRateModel_,
            int256 rawModelRate_,
            bool isStaticRate_,
            bool rewardsActive_
        )
    {
        (, , rewardsRateModel_, , , rewardsActive_, , , ) = fToken_.getData();

        if (address(rewardsRateModel_) != address(0)) {
            // `isStaticRateModelActive` only exists on newer fToken versions; older deployed fTokens
            // must fall back to the streaming rewards rate model path.
            try fToken_.isStaticRateModelActive() returns (bool staticActive_) {
                isStaticRate_ = staticActive_;
            } catch {}
        }

        if (rewardsActive_ && address(rewardsRateModel_) != address(0)) {
            if (isStaticRate_) {
                (rawModelRate_, , , ) = IFluidLendingStaticRateModel(address(rewardsRateModel_)).getRateV2(0);
            } else {
                uint256 streamingRate_;
                (streamingRate_, , ) = rewardsRateModel_.getRate(fToken_.totalAssets());
                rawModelRate_ = int256(streamingRate_);
            }
        }
    }

    /// @dev Converts on-chain model APR (`1e12` = 1%) to resolver APR scale (`100` = 1%, same as Liquidity `supplyRate`).
    function _scaleModelRate(int256 modelRate_) internal pure returns (int256) {
        return modelRate_ / int256(MODEL_RATE_SCALE_FACTOR);
    }

    /// @dev All returned APR fields use Liquidity resolver scale (`100` = 1%, divide by 100 for % display).
    /// Streaming / static are both **additive** on Liquidity yield in the fToken share price.
    /// `staticModelRate_` is the signed offset directly (not derived from `totalRate_`).
    function _computeHolderRates(
        int256 scaledModelRate_,
        bool isStaticRate_,
        bool rewardsActive_,
        uint256 liquidityRate_
    ) internal pure returns (uint256 relativeModelRate_, int256 staticModelRate_, uint256 totalRate_) {
        if (isStaticRate_) {
            relativeModelRate_ = 0;
            if (rewardsActive_) {
                staticModelRate_ = scaledModelRate_;
                int256 total_ = int256(liquidityRate_) + staticModelRate_;
                totalRate_ = total_ > 0 ? uint256(total_) : 0;
            } else {
                staticModelRate_ = 0;
                totalRate_ = liquidityRate_;
            }
        } else {
            staticModelRate_ = 0;
            if (rewardsActive_) {
                relativeModelRate_ = uint256(scaledModelRate_); // streaming rates are non-negative
                totalRate_ = liquidityRate_ + relativeModelRate_;
            } else {
                relativeModelRate_ = 0;
                totalRate_ = liquidityRate_;
            }
        }
    }
}
