// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { DexOracleBase } from "./dexOracleBase.sol";

abstract contract DexSmartColOracleImpl is DexOracleBase {
    uint256 private constant X128 = 0xffffffffffffffffffffffffffffffff;

    uint256 private immutable RESERVES_SCALER;

    constructor() {
        // need to invert decimals from reserves / shares to shares / reserves.
        // Can derive from token scaler consts targeting 1e12 + knowing shares decimals = 1e18:
        // e.g. for USDC 1e6 / 1e18 shares: 1e18 / (1e12 * 1 / 1e6) = 1e12
        // e.g. for WBTC 1e8 / 1e18 shares: 1e18 / (1e12 * 1 / 1e4) = 1e10
        RESERVES_SCALER = QUOTE_IN_TOKEN0
            ? 1e18 / ((1e12 * TOKEN_0_DENOMINATOR_PRECISION) / TOKEN_0_NUMERATOR_PRECISION)
            : 1e18 / ((1e12 * TOKEN_1_DENOMINATOR_PRECISION) / TOKEN_1_NUMERATOR_PRECISION);
    }

    /// @dev returns price per 1 col share (quoteToken / colShare) in token decimals scaled to 1e27
    function _getDexSmartColExchangeRate(
        uint256 conversionPrice_,
        uint256 token0Reserves_,
        uint256 token1Reserves_
    ) internal view returns (uint256 rate_) {
        uint256 totalSupplyShares_ = IFluidDexT1(DEX_).readFromStorage(
            bytes32(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)
        ) & X128;

        if (totalSupplyShares_ == 0) {
            // should never happen after Dex is initialized. until then -> revert
            revert FluidOracleError(ErrorTypes.DexSmartColOracle__SmartColNotEnabled);
        }

        uint256 reserves_ = _getDexReservesCombinedInQuoteToken(conversionPrice_, token0Reserves_, token1Reserves_);

        // here: all reserves_ are in either token0 or token1 in token decimals, and we have total shares.
        // so we know token0 or token1 per 1e18 share. => return price per 1 share (1e18), scaled to 1e27.
        // shares are in 1e18
        return (reserves_ * RESERVES_SCALER * 1e27) / totalSupplyShares_;
    }

    /// @notice Returns the rates of shares (totalReserves/totalShares)
    function dexSmartColSharesRates() public view virtual returns (uint256 operate_, uint256 liquidate_);
}
