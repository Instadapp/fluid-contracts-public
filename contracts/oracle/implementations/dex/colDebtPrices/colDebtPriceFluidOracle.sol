// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../../../interfaces/iFluidOracle.sol";
import { ErrorTypes } from "../../../errorTypes.sol";
import { OracleUtils } from "../../../libraries/oracleUtils.sol";
import { DexColDebtPriceGetter } from "./dexColDebtPriceGetter.sol";

/// @notice reads the col debt Oracle Price from a separately deployed FluidOracle
/// @dev used to plug result of DexSmartColOracleImpl into any existing FluidOracle.
/// result of DexSmartColOracleImpl is e.g. for WSTETH/ETH smart col, WSTETH amount per 1 share.
/// we need 1 share in relation to debt. so e.g. wstETH/ETH smart col w.r.t. USDC debt.
/// so plug result into wstETH/USDC oracle then we get USDC per 1 share.
abstract contract DexColDebtPriceFluidOracle is DexColDebtPriceGetter {
    /// @dev external IFluidOracle used to convert from col or debt shares to a Fluid vault debt token.
    /// can be address zero if no conversion needed.
    /// IFluidOracle always returns 1e27 scaled price (DEX_COL_DEBT_ORACLE_PRECISION).
    IFluidOracle internal immutable COL_DEBT_ORACLE;
    bool internal immutable COL_DEBT_INVERT;

    constructor(IFluidOracle colDebtOracle_, bool colDebtInvert_) {
        COL_DEBT_ORACLE = colDebtOracle_;
        COL_DEBT_INVERT = colDebtInvert_;
    }

    function _getDexColDebtPriceOperate() internal view override returns (uint256 colDebtPrice_) {
        if (address(COL_DEBT_ORACLE) == address(0)) {
            return DEX_COL_DEBT_ORACLE_PRECISION;
        }
        colDebtPrice_ = COL_DEBT_ORACLE.getExchangeRateOperate();
        if (COL_DEBT_INVERT) {
            colDebtPrice_ = 1e54 / colDebtPrice_;
        }
    }

    function _getDexColDebtPriceLiquidate() internal view override returns (uint256 colDebtPrice_) {
        if (address(COL_DEBT_ORACLE) == address(0)) {
            return DEX_COL_DEBT_ORACLE_PRECISION;
        }
        colDebtPrice_ = COL_DEBT_ORACLE.getExchangeRateLiquidate();
        if (COL_DEBT_INVERT) {
            colDebtPrice_ = 1e54 / colDebtPrice_;
        }
    }

    /// @notice Returns Col/Debt Oracle data
    function getDexColDebtOracleData() public view returns (address colDebtOracle_, bool colDebtInvert_) {
        return (address(COL_DEBT_ORACLE), COL_DEBT_INVERT);
    }
}
