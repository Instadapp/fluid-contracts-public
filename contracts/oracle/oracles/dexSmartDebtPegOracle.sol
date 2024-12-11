// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../fluidOracle.sol";
import { DexSmartDebtPegOracleImpl } from "../implementations/dexSmartDebtPegOracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   Fluid Dex Smart Debt Pegged Oracle for assets ~1=~1
/// @notice  Gets the exchange rate between a Fluid Dex normal collateral and smart debt.
/// @dev plugs result of DexSmartDebtOracleImpl into any existing FluidOracle.
/// result of DexSmartDebtOracleImpl is e.g. for USDC/USDT smart debt, USDC amount per 1 share.
/// we need share in relation to 1 col. so e.g. USDC/USDT debt w.r.t. ETH col.
/// so plug result into ETH/USDC oracle then we get shares per 1 ETH.
/// @dev can be paired with DexSmartColOracle to create an Oracle for type 4 smart col & smart debt.
contract DexSmartDebtPegOracle is FluidOracle, DexSmartDebtPegOracleImpl {
    /// @dev external IFluidOracle used to convert from debt shares to a Fluid vault debt token
    IFluidOracle internal immutable _COL_DEBT_ORACLE;
    bool internal immutable _COL_DEBT_INVERT;
    uint8 internal immutable _COL_DEBT_DECIMALS;

    uint256 internal immutable _COL_DEBT_DIVISOR; // helper for gas optimization

    constructor(
        string memory infoName_,
        address dexPool_,
        address reservesConversionOracle_,
        bool quoteInToken0_,
        bool reservesConversionInvert_,
        uint256 reservesPegBufferPercent_,
        IFluidOracle colDebtOracle_,
        bool colDebtInvert_,
        uint8 colDebtDecimals_
    )
        DexSmartDebtPegOracleImpl(
            dexPool_,
            reservesConversionOracle_,
            quoteInToken0_,
            reservesConversionInvert_,
            reservesPegBufferPercent_
        )
        FluidOracle(infoName_)
    {
        _COL_DEBT_ORACLE = colDebtOracle_;
        _COL_DEBT_INVERT = colDebtInvert_;
        _COL_DEBT_DECIMALS = colDebtDecimals_;

        _COL_DEBT_DIVISOR = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + colDebtDecimals_ - _DEX_SHARES_DECIMALS);
    }

    function _getExternalPrice(bool isOperate_) private view returns (uint256 externalPrice_) {
        if (address(_COL_DEBT_ORACLE) == address(0)) {
            return 1e27;
        }
        externalPrice_ = isOperate_
            ? _COL_DEBT_ORACLE.getExchangeRateOperate()
            : _COL_DEBT_ORACLE.getExchangeRateLiquidate();
        if (_COL_DEBT_INVERT) {
            externalPrice_ = 1e54 / externalPrice_;
        }
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        // to get debt/col rate of col per 1 debt share (SHARE/COL_TOKEN) :
        // _getDexSmartDebtOperate() = debt token0 or debt token1 per 1 share (DEBT_TOKEN/SHARE).
        // _getExternalPrice() = debt token per 1 col token = DEBT_TOKEN/COL_TOKEN.
        // so (1 / DEBT_TOKEN/SHARE) * DEBT_TOKEN/COL_TOKEN =
        // SHARE/DEBT_TOKEN * DEBT_TOKEN/COL_TOKEN = SHARE/COL_TOKEN
        return ((1e54 / _getDexSmartDebtOperate()) * _getExternalPrice(true)) / _COL_DEBT_DIVISOR;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        return ((1e54 / _getDexSmartDebtLiquidate()) * _getExternalPrice(false)) / _COL_DEBT_DIVISOR;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @notice Returns Col/Debt Oracle data
    function getDexSmartDebtOracleData()
        public
        view
        returns (address colDebtOracle_, bool colDebtInvert_, uint8 colDebtDecimals_)
    {
        return (address(_COL_DEBT_ORACLE), _COL_DEBT_INVERT, _COL_DEBT_DECIMALS);
    }
}
