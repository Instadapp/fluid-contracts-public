// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle, IFluidOracle } from "../fluidOracle.sol";
import { DexSmartColPegOracleImpl } from "../implementations/dexSmartColPegOracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   Fluid Dex Smart Col Pegged Oracle for assets ~1=~1
/// @notice  Gets the exchange rate between a Fluid Dex smart collateral shares and normal debt.
/// @dev plugs result of DexSmartColOracleImpl into any existing FluidOracle.
/// result of DexSmartColOracleImpl is e.g. for WSTETH/ETH smart col, WSTETH amount per 1 share.
/// we need 1 share in relation to debt. so e.g. wstETH/ETH smart col w.r.t. USDC debt.
/// so plug result into wstETH/USDC oracle then we get USDC per 1 share.
/// @dev can be paired with DexSmartDebtOracle to create an Oracle for type 4 smart col & smart debt.
contract DexSmartColPegOracle is FluidOracle, DexSmartColPegOracleImpl {
    /// @dev external IFluidOracle used to convert from col shares to a Fluid vault debt token
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
        DexSmartColPegOracleImpl(
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

        _COL_DEBT_DIVISOR = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + _DEX_SHARES_DECIMALS - colDebtDecimals_);
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
        // to get debt/col rate of debt token per 1 col share (DEBT_TOKEN/SHARE):
        // _getDexSmartColOperate() = col token0 or col token1 per 1 share (COL_TOKEN/SHARE).
        // _getExternalPrice() = debt token per 1 col token = DEBT_TOKEN/COL_TOKEN.
        // so COL_TOKEN/SHARE * DEBT_TOKEN/COL_TOKEN = DEBT_TOKEN/SHARE
        return (_getDexSmartColOperate() * _getExternalPrice(true)) / _COL_DEBT_DIVISOR;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        return (_getDexSmartColLiquidate() * _getExternalPrice(false)) / _COL_DEBT_DIVISOR;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @notice Returns Col/Debt Oracle data
    function getDexSmartColOracleData()
        public
        view
        returns (address colDebtOracle_, bool colDebtInvert_, uint8 colDebtDecimals_)
    {
        return (address(_COL_DEBT_ORACLE), _COL_DEBT_INVERT, _COL_DEBT_DECIMALS);
    }
}
