// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../../errorTypes.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { DexOracleBase } from "./dexOracleBase.sol";

abstract contract DexSmartDebtOracleImpl is DexOracleBase {
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

    /// @dev returns price per 1 quoteToken (debtShares / quoteToken) in token decimals scaled to 1e27
    function _getDexSmartDebtExchangeRate(
        uint256 conversionPrice_,
        uint256 token0Reserves_,
        uint256 token1Reserves_
    ) internal view returns (uint256 rate_) {
        uint256 totalBorrowShares_ = IFluidDexT1(DEX_).readFromStorage(
            bytes32(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT)
        ) & X128;

        if (totalBorrowShares_ == 0) {
            // should never happen after Dex is initialized. until then -> revert
            revert FluidOracleError(ErrorTypes.DexSmartDebtOracle__SmartDebtNotEnabled);
        }

        uint256 reserves_ = _getDexReservesCombinedInQuoteToken(conversionPrice_, token0Reserves_, token1Reserves_);

        // here: all reserves_ are in either token0 or token1 in token decimals, and we have total shares.
        // so we know token0 or token1 per 1e18 share. => return shares per 1 quote token, scaled to 1e27.

        return (totalBorrowShares_ * 1e27) / (reserves_ * RESERVES_SCALER);
    }

    /// @notice Returns the rates of shares (totalShares/totalReserves)
    function dexSmartDebtSharesRates() public view virtual returns (uint256 operate_, uint256 liquidate_);
}
