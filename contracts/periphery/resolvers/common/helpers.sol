//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { IFluidOracle } from "../../../oracleV2/interfaces/iFluidOracle.sol";

abstract contract ResolverHelpers {
    /// @notice Returns the Liquidity Layer's balance of the given token currently sitting externally.
    /// @return The total external balance of the contract.
    function _getLiquidityExternalBalances(
        address /** token_ **/,
        address /** liquidity_ **/
    ) internal pure returns (uint256) {
        return 0;
    }

    /// @dev Fetches oracle prices for resolver/UI reads. Falls back to `*Raw` getters when guarded getters revert (e.g. L2 sequencer grace today).
    function _fetchOraclePrices(
        address oracle_
    ) internal view returns (uint256 oraclePriceOperate_, uint256 oraclePriceLiquidate_) {
        if (oracle_ == address(0)) {
            return (0, 0);
        }

        try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
            oraclePriceOperate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 liquidateRate_) {
                oraclePriceLiquidate_ = liquidateRate_;
            } catch {
                oraclePriceLiquidate_ = exchangeRate_;
            }
            return (oraclePriceOperate_, oraclePriceLiquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRateOperateRaw() returns (uint256 exchangeRate_) {
            oraclePriceOperate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidateRaw() returns (uint256 liquidateRate_) {
                oraclePriceLiquidate_ = liquidateRate_;
            } catch {
                oraclePriceLiquidate_ = exchangeRate_;
            }
            return (oraclePriceOperate_, oraclePriceLiquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRate() returns (uint256 exchangeRate_) {
            return (exchangeRate_, exchangeRate_);
        } catch {}

        return (0, 0);
    }
}
