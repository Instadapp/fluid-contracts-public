// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../fluidOracle.sol";
import { DexSmartDebtPegOracleImpl } from "../implementations/dexSmartDebtPegOracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";

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

    constructor(
        string memory infoName_,
        address dexPool_,
        address reservesConversionOracle_,
        bool quoteInToken0_,
        bool reservesConversionInvert_,
        uint256 reservesPegBufferPercent_,
        IFluidOracle colDebtOracle_,
        bool colDebtInvert_
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
    }

    function _getExternalPrice(uint256 externalPrice_) private view returns (uint256) {
        if (_COL_DEBT_INVERT) {
            externalPrice_ = 1e54 / externalPrice_;
        }
        return externalPrice_;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        // to get debt/col rate of col per 1 debt share (SHARE/COL_TOKEN) :
        // _getDexSmartDebtOperate() = debt token0 or debt token1 per 1 share (DEBT_TOKEN/SHARE).
        // _getExternalPrice() = debt token per 1 col token = DEBT_TOKEN/COL_TOKEN.
        // so (1 / DEBT_TOKEN/SHARE) * DEBT_TOKEN/COL_TOKEN =
        // SHARE/DEBT_TOKEN * DEBT_TOKEN/COL_TOKEN = SHARE/COL_TOKEN
        return
            ((1e54 / _getDexSmartDebtOperate()) * _getExternalPrice(_COL_DEBT_ORACLE.getExchangeRateOperate())) / 1e27;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        return
            (_getDexSmartDebtLiquidate() * (1e54 / _getExternalPrice(_COL_DEBT_ORACLE.getExchangeRateLiquidate()))) /
            1e27;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @notice Returns the address and inversion status of the COL DEBT ORACLE
    /// @return The address and inversion status of the COL DEBT ORACLE
    function getDexSmartDebtOracleData() public view returns (address, bool) {
        return (address(_COL_DEBT_ORACLE), _COL_DEBT_INVERT);
    }
}
