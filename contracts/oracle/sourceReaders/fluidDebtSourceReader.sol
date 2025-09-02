// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidCappedRate } from "../interfaces/iFluidCappedRate.sol";

abstract contract FluidDebtSourceReader {
    function _readFluidDebtSource(address oracle_, bool isOperate_) internal view returns (uint256 rate_) {
        if (isOperate_) {
            try IFluidCappedRate(oracle_).getExchangeRateOperateDebt() returns (uint256 exchangeRate_) {
                return exchangeRate_;
            } catch {}
        } else {
            try IFluidCappedRate(oracle_).getExchangeRateLiquidateDebt() returns (uint256 exchangeRate_) {
                return exchangeRate_;
            } catch {}
        }
    }
}
