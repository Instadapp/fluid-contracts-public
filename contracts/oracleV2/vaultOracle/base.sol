// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IFluidOracle } from "../interfaces/iFluidOracle.sol";
import { IUSDOracle } from "../interfaces/iUSDOracle.sol";
import { DexShareResolver } from "../common/dexShareResolver.sol";
import { TokenSymbolResolver } from "../common/tokenSymbolResolver.sol";
import { Error as VaultError } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

/// @title VaultOracleBase
/// @notice Abstract base for vault oracles. Inherits DexShareResolver for share pricing,
///         TokenSymbolResolver for `_tokenSymbol`, and adds normal token resolution + exchange rate computation.
///
///         USD Oracle reads use immutable supply/borrow eModes (per deployment).
///         Exchange rate = debt-per-collateral in 1e27 precision adjusted for token decimals.
///
///         `_resolveNormalWrite` serves `IFluidOracleWrite` vault types (T1 only; smart vaults T2–T4 stay
///         view-only — Write there is planned for later, once actually needed).
abstract contract VaultOracleBase is DexShareResolver, TokenSymbolResolver, VaultError, IFluidOracle {
    /// @notice eMode passed to `FluidUsdOracle` for collateral-side price reads from this vault oracle.
    uint256 internal immutable SUPPLY_E_MODE;
    /// @notice eMode passed to `FluidUsdOracle` for debt-side price reads from this vault oracle.
    uint256 internal immutable BORROW_E_MODE;

    /// @notice Reserve adjustment (ppm on `PEG_BUFFER_SCALE`) applied to DEX share legs on the operate path.
    uint256 internal immutable PEG_BUFFER_PPM_OPERATE;
    /// @notice Reserve adjustment (ppm on `PEG_BUFFER_SCALE`) applied to DEX share legs on the liquidate path.
    uint256 internal immutable PEG_BUFFER_PPM_LIQUIDATE;

    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev Fluid protocol rate / USD price fixed-point scale (1e27).
    uint256 internal constant FLUID_RATE_DECIMALS = 27;

    /// @param pegBufferPpmOperate_ Operate-path DEX share reserve adjustment.
    /// @param pegBufferPpmLiquidate_ Liquidate-path DEX share reserve adjustment.
    /// @dev Bounds on both values are enforced by `VaultOracleFactory` at registration. Checking here as well
    ///      would only surface as the deployer factory's own generic error, since the revert would happen
    ///      inside `deployContract`.
    constructor(
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) {
        SUPPLY_E_MODE = supplyEMode_;
        BORROW_E_MODE = borrowEMode_;
        PEG_BUFFER_PPM_OPERATE = pegBufferPpmOperate_;
        PEG_BUFFER_PPM_LIQUIDATE = pegBufferPpmLiquidate_;
    }

    function infoName() public view returns (string memory) {
        return string.concat(_debtName(), " / 1 ", _collateralName());
    }

    /// @notice Returns canonical vault-oracle config fields across T1-T4.
    /// @dev Non-applicable fields are returned as address(0) depending on vault type.
    function getOracleConfig()
        external
        view
        returns (
            address usdOracle_,
            address supplyToken0_,
            address supplyToken1_,
            address borrowToken0_,
            address borrowToken1_,
            address supplyDexPool_,
            address borrowDexPool_,
            uint256 supplyEMode_,
            uint256 borrowEMode_
        )
    {
        (
            usdOracle_,
            supplyToken0_,
            supplyToken1_,
            borrowToken0_,
            borrowToken1_,
            supplyDexPool_,
            borrowDexPool_
        ) = _oracleConfigAddresses();
        supplyEMode_ = SUPPLY_E_MODE;
        borrowEMode_ = BORROW_E_MODE;
    }

    function targetDecimals() public view returns (uint8 targetDecimals_) {
        targetDecimals_ = uint8(FLUID_RATE_DECIMALS + _debtDecimals() - _collateralDecimals());
    }

    /// @notice Get the exchange rate for operate mode.
    function getExchangeRateOperate() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(true, false);
    }

    /// @notice Get the exchange rate for liquidate mode.
    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(false, false);
    }

    /// @dev Deprecated. Same as operate.
    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(true, false);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperateRaw() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(true, true);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidateRaw() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(false, true);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateRaw() external view returns (uint256 exchangeRate_) {
        return _getExchangeRate(true, true);
    }

    /// @notice Resolves USD price and decimals of a normal (non-share) token.
    function _resolveNormal(
        address usdOracle_,
        address token_,
        bool isOperate_,
        bool isCollateral_,
        bool isRaw_
    ) internal view returns (uint256 priceUsd_, uint256 decimals_) {
        uint256 eMode_ = isCollateral_ ? SUPPLY_E_MODE : BORROW_E_MODE;
        uint8 dec_;
        if (isRaw_) {
            (priceUsd_, dec_, ) = IUSDOracle(usdOracle_).getPriceDetailedViewRaw(
                token_,
                eMode_,
                isOperate_,
                isCollateral_
            );
        } else {
            (priceUsd_, dec_, ) = IUSDOracle(usdOracle_).getPriceDetailedView(
                token_,
                eMode_,
                isOperate_,
                isCollateral_
            );
        }
        decimals_ = uint256(dec_);
        if (priceUsd_ == 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__PriceZero);
        }
    }

    /// @notice Write variant of `_resolveNormal` via UsdOracle `getPriceDetailed` (persists source state).
    function _resolveNormalWrite(
        address usdOracle_,
        address token_,
        bool isOperate_,
        bool isCollateral_
    ) internal returns (uint256 priceUsd_, uint256 decimals_) {
        uint8 dec_;
        (priceUsd_, dec_, ) = IUSDOracle(usdOracle_).getPriceDetailed(
            token_,
            isCollateral_ ? SUPPLY_E_MODE : BORROW_E_MODE,
            isOperate_,
            isCollateral_
        );
        decimals_ = uint256(dec_);
        if (priceUsd_ == 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__PriceZero);
        }
    }

    /// @dev Peg buffer for T2–T4 DEX share legs, set per deployment. T1 has no DEX leg and never calls this.
    function _dexSharePegBufferPpm(bool isOperate_) internal view returns (uint256 pegBufferPpm_) {
        pegBufferPpm_ = isOperate_ ? PEG_BUFFER_PPM_OPERATE : PEG_BUFFER_PPM_LIQUIDATE;
    }

    /// @dev Computes the exchange rate between collateral and debt.
    ///      rate = colPriceUsd * 10^(27 + debtDecimals - colDecimals) / debtPriceUsd
    ///
    ///      Example: ETH (18 dec) / USDC (6 dec) at $2000/$1:
    ///        2000e27 * 10^(27+6-18) / 1e27 = 2000e27 * 1e15 / 1e27 = 2000 * 1e15 = 2e18
    ///        targetDecimals = 15, so 2e18 represents 2000 USDC per ETH.
    function _computeExchangeRate(
        uint256 colPriceUsd_,
        uint256 colDecimals_,
        uint256 debtPriceUsd_,
        uint256 debtDecimals_
    ) internal pure returns (uint256 exchangeRate_) {
        exchangeRate_ = (colPriceUsd_ * (10 ** (FLUID_RATE_DECIMALS + debtDecimals_ - colDecimals_))) / debtPriceUsd_;
    }

    function _tokenDecimals(address token_) internal view returns (uint256 decimals_) {
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            return DEX_SHARE_DECIMALS;
        }
        decimals_ = uint256(IERC20Metadata(token_).decimals());
    }

    function _dexPairName(address token0_, address token1_) internal view returns (string memory) {
        return string.concat(_tokenSymbol(token0_), "-", _tokenSymbol(token1_));
    }

    function _oracleConfigAddresses()
        internal
        view
        virtual
        returns (
            address usdOracle_,
            address supplyToken0_,
            address supplyToken1_,
            address borrowToken0_,
            address borrowToken1_,
            address supplyDexPool_,
            address borrowDexPool_
        );

    /// @dev Each vault oracle implements this to wire its specific collateral/debt resolution.
    /// @param isRaw_ When true, use raw oracle reads (`getPriceDetailedViewRaw`, etc.) that may bypass guarded checks (e.g. L2 sequencer uptime today).
    function _getExchangeRate(bool isOperate_, bool isRaw_) internal view virtual returns (uint256 exchangeRate_);

    function _collateralName() internal view virtual returns (string memory);

    function _debtName() internal view virtual returns (string memory);

    function _collateralDecimals() internal view virtual returns (uint256);

    function _debtDecimals() internal view virtual returns (uint256);
}
