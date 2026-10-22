// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../interfaces/iFluidOracle.sol";

abstract contract FluidSourceReader {
    function _readFluidSource(address oracle_, bool isOperate_) internal view returns (uint256 rate_) {
        if (isOperate_) {
            try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
                return exchangeRate_;
            } catch {}
        } else {
            try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 exchangeRate_) {
                return exchangeRate_;
            } catch {}
        }
    }
}
