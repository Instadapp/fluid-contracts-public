// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IFluidOracleWithDebt } from "../../interfaces/iFluidOracleWithDebt.sol";
import { IFluidOracleWrite } from "../../interfaces/iFluidOracleWrite.sol";

/// @dev Shared directional read path for `SOURCE_CAPPED_RATE` and `SOURCE_FLUID_ORACLE`
///      (same getters; capped-rate also requires `centerPrice()` at config time only).
abstract contract FluidSourceReader {
    /// @dev Reads the latest exchange rate from a Fluid oracle / capped rate (directional getters). Returns 0 on call failure.
    function _readFluidSource(
        address oracle_,
        bool isOperate_,
        bool isCollateral_
    ) internal view returns (uint256 rate_) {
        if (isOperate_) {
            if (isCollateral_) {
                try IFluidOracleWithDebt(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidOracleWithDebt(oracle_).getExchangeRateOperateDebt() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        } else {
            if (isCollateral_) {
                try IFluidOracleWithDebt(oracle_).getExchangeRateLiquidate() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidOracleWithDebt(oracle_).getExchangeRateLiquidateDebt() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        }
    }

    /// @dev Raw read via `getExchangeRate()` (uncapped, no directional distinction).
    function _readFluidSourceRaw(address oracle_) internal view returns (uint256 rate_) {
        try IFluidOracleWithDebt(oracle_).getExchangeRate() returns (uint256 price_) {
            rate_ = price_;
        } catch {}
    }

    /// @dev Like `_readFluidSource`, but tries the direction's Write getter first (e.g. CLX cache warm).
    ///      Any Write failure falls back to the view getter, keeping per-leg failure isolation.
    function _readFluidSourceWrite(
        address oracle_,
        bool isOperate_,
        bool isCollateral_
    ) internal returns (uint256 rate_) {
        if (isOperate_) {
            if (isCollateral_) {
                try IFluidOracleWrite(oracle_).getExchangeRateOperateWrite() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidOracleWrite(oracle_).getExchangeRateOperateDebtWrite() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        } else {
            if (isCollateral_) {
                try IFluidOracleWrite(oracle_).getExchangeRateLiquidateWrite() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            } else {
                try IFluidOracleWrite(oracle_).getExchangeRateLiquidateDebtWrite() returns (uint256 exchangeRate_) {
                    return exchangeRate_;
                } catch {}
            }
        }
        return _readFluidSource(oracle_, isOperate_, isCollateral_);
    }
}
