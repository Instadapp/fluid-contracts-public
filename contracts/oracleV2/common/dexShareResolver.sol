// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IUSDOracle } from "../interfaces/iUSDOracle.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { Error } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

interface IFluidStorageReadable {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

/// @title DexShareResolver
/// @notice Reusable abstract for resolving DEX LP shares to USD-denominated prices.
///         Intended for vault oracles, auth contracts, limit handlers, or any consumer
///         that needs to value DEX collateral/debt shares in USD.
///
///         Uses the USD Oracle as common denominator: each token's reserves are valued
///         in USD independently, eliminating the need for conversion price oracles,
///         colDebt bridge oracles, or result scaling.
///
/// @dev Peg buffer (`pegBufferPpm_`): optional, same semantics as V1 `DexReservesFromLiquidityPeg`.
///      Pass `0` for **unbuffered** reserves (true economic value) — use this for limit handlers
///      and any consumer that must not discount reserves.
///
///      **Vault oracles (T2–T4)** pass a protocol-fixed buffer from `VaultOracleBase`
///      (0.5% operate / 0.1% liquidate). Any other `pegBufferPpm_` must be `< 1e6`.
///
///      **`eMode_`:** forwarded to `IUSDOracle.getPriceDetailedView` when valuing reserves; vault oracles supply
///      immutable `E_MODE` from `VaultOracleBase`.
abstract contract DexShareResolver is Error {
    uint256 private constant X64 = 0xffffffffffffffff;
    uint256 private constant X128 = 0xffffffffffffffffffffffffffffffff;

    /// @dev Fluid DEX LP shares use 18 decimals; returned as `uint256` to avoid widening at every call site.
    uint256 internal constant DEX_SHARE_DECIMALS = 18;

    /// @dev Denominator for peg buffer (parts per million). `pegBufferPpm_` of 10_000 = 1%.
    uint256 internal constant PEG_BUFFER_SCALE = 1e6;

    /// @dev Converts pool total USD into per-share USD at oracle precision (1e27).
    ///      Reserves are normalized to 1e12; oracle prices are 1e27; `totalValueUsd_` is ~1e39.
    ///      DEX share amounts are 1e18. We want USD per 1e18 shares also at 1e27:
    ///      `totalValueUsd_ * SHARE_PRICE_USD_SCALE / totalShares_` → `1e39 * 1e6 / 1e18 = 1e27`.
    ///      Same numeric value as `PEG_BUFFER_SCALE` but a different semantic (not ppm).
    uint256 private constant SHARE_PRICE_USD_SCALE = 1e6;

    IFluidStorageReadable internal constant LIQUIDITY =
        IFluidStorageReadable(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    /// @dev Parameters for DEX share resolution. Passed by the vault oracle which caches them as immutables.
    struct DexParams {
        address dexPool;
        address token0;
        address token1;
        bytes32 supplyToken0Slot;
        bytes32 supplyToken1Slot;
        bytes32 borrowToken0Slot;
        bytes32 borrowToken1Slot;
        bytes32 exchangePriceToken0Slot;
        bytes32 exchangePriceToken1Slot;
        uint256 token0NumeratorPrecision;
        uint256 token0DenominatorPrecision;
        uint256 token1NumeratorPrecision;
        uint256 token1DenominatorPrecision;
    }

    /// @notice Resolves the USD price per one DEX collateral share (1e18).
    /// @param pegBufferPpm_ Peg buffer in parts per million; `0` = none. Collateral reserves are scaled by `(1e6 - pegBufferPpm_) / 1e6` before valuation.
    /// @dev Reads raw collateral reserves from Liquidity, values them in USD via the oracle,
    ///      divides by total supply shares. Returns price in 1e27 precision; second return is `DEX_SHARE_DECIMALS` (18) as `uint256`.
    function _resolveColShare(
        address usdOracle_,
        uint256 eMode_,
        bool isOperate_,
        DexParams memory d_,
        uint256 pegBufferPpm_,
        bool isRaw_
    ) internal view returns (uint256 priceUsd_, uint256 decimals_) {
        uint256 token0Reserves_ = _getLiquidityCollateral(
            d_.supplyToken0Slot,
            d_.exchangePriceToken0Slot,
            d_.token0NumeratorPrecision,
            d_.token0DenominatorPrecision
        );
        uint256 token1Reserves_ = _getLiquidityCollateral(
            d_.supplyToken1Slot,
            d_.exchangePriceToken1Slot,
            d_.token1NumeratorPrecision,
            d_.token1DenominatorPrecision
        );

        (token0Reserves_, token1Reserves_) = _applyPegBufferToReserves(
            token0Reserves_,
            token1Reserves_,
            pegBufferPpm_,
            true
        );

        uint256 totalValueUsd_ = _computeTotalValueUsd(
            usdOracle_,
            eMode_,
            isOperate_,
            true,
            d_.token0,
            d_.token1,
            token0Reserves_,
            token1Reserves_,
            isRaw_
        );

        uint256 totalSupplyShares_ = IFluidStorageReadable(d_.dexPool).readFromStorage(
            bytes32(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)
        ) & X128;

        if (totalSupplyShares_ == 0) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__SharesZero);
        }

        priceUsd_ = (totalValueUsd_ * SHARE_PRICE_USD_SCALE) / totalSupplyShares_;
        decimals_ = DEX_SHARE_DECIMALS;
    }

    /// @notice Resolves the USD price per one DEX debt share (1e18).
    /// @param pegBufferPpm_ Peg buffer in parts per million; `0` = none. Debt reserves are scaled by `(1e6 + pegBufferPpm_) / 1e6` before valuation.
    /// @dev Same approach as collateral shares but reads borrow reserves and total borrow shares. Second return is `DEX_SHARE_DECIMALS` (18) as `uint256`.
    function _resolveDebtShare(
        address usdOracle_,
        uint256 eMode_,
        bool isOperate_,
        DexParams memory d_,
        uint256 pegBufferPpm_,
        bool isRaw_
    ) internal view returns (uint256 priceUsd_, uint256 decimals_) {
        uint256 token0Reserves_ = _getLiquidityDebt(
            d_.borrowToken0Slot,
            d_.exchangePriceToken0Slot,
            d_.token0NumeratorPrecision,
            d_.token0DenominatorPrecision
        );
        uint256 token1Reserves_ = _getLiquidityDebt(
            d_.borrowToken1Slot,
            d_.exchangePriceToken1Slot,
            d_.token1NumeratorPrecision,
            d_.token1DenominatorPrecision
        );

        (token0Reserves_, token1Reserves_) = _applyPegBufferToReserves(
            token0Reserves_,
            token1Reserves_,
            pegBufferPpm_,
            false
        );

        uint256 totalValueUsd_ = _computeTotalValueUsd(
            usdOracle_,
            eMode_,
            isOperate_,
            false,
            d_.token0,
            d_.token1,
            token0Reserves_,
            token1Reserves_,
            isRaw_
        );

        uint256 totalBorrowShares_ = IFluidStorageReadable(d_.dexPool).readFromStorage(
            bytes32(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT)
        ) & X128;

        if (totalBorrowShares_ == 0) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__SharesZero);
        }

        priceUsd_ = (totalValueUsd_ * SHARE_PRICE_USD_SCALE) / totalBorrowShares_;
        decimals_ = DEX_SHARE_DECIMALS;
    }

    /// @dev V1 `DexReservesFromLiquidityPeg`: collateral reduces, debt increases by `pegBufferPpm_` / 1e6.
    function _applyPegBufferToReserves(
        uint256 token0Reserves_,
        uint256 token1Reserves_,
        uint256 pegBufferPpm_,
        bool isCollateralSide_
    ) internal pure returns (uint256 out0_, uint256 out1_) {
        if (pegBufferPpm_ == 0) {
            return (token0Reserves_, token1Reserves_);
        }
        if (pegBufferPpm_ >= PEG_BUFFER_SCALE) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__InvalidPegBuffer);
        }
        unchecked {
            if (isCollateralSide_) {
                uint256 f_ = PEG_BUFFER_SCALE - pegBufferPpm_;
                out0_ = (token0Reserves_ * f_) / PEG_BUFFER_SCALE;
                out1_ = (token1Reserves_ * f_) / PEG_BUFFER_SCALE;
            } else {
                uint256 f_ = PEG_BUFFER_SCALE + pegBufferPpm_;
                out0_ = (token0Reserves_ * f_) / PEG_BUFFER_SCALE;
                out1_ = (token1Reserves_ * f_) / PEG_BUFFER_SCALE;
            }
        }
    }

    /// @dev Computes total USD value of token0 + token1 reserves (each already at 1e12 precision).
    ///      Returns result in ~1e39 range (1e12 * 1e27).
    function _computeTotalValueUsd(
        address usdOracle_,
        uint256 eMode_,
        bool isOperate_,
        bool isCollateral_,
        address token0_,
        address token1_,
        uint256 token0Reserves_,
        uint256 token1Reserves_,
        bool isRaw_
    ) private view returns (uint256 totalValueUsd_) {
        (uint256 price0_, , ) = _usdPriceDetailedView(usdOracle_, token0_, eMode_, isOperate_, isCollateral_, isRaw_);
        (uint256 price1_, , ) = _usdPriceDetailedView(usdOracle_, token1_, eMode_, isOperate_, isCollateral_, isRaw_);

        if (price0_ == 0 || price1_ == 0) {
            revert OracleV2CommonError(ErrorTypes.OracleV2Common__PriceZero);
        }

        totalValueUsd_ = (token0Reserves_ * price0_) + (token1Reserves_ * price1_);
    }

    function _usdPriceDetailedView(
        address usdOracle_,
        address token_,
        uint256 eMode_,
        bool isOperate_,
        bool isCollateral_,
        bool isRaw_
    ) private view returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        if (isRaw_) {
            return IUSDOracle(usdOracle_).getPriceDetailedViewRaw(token_, eMode_, isOperate_, isCollateral_);
        }
        return IUSDOracle(usdOracle_).getPriceDetailedView(token_, eMode_, isOperate_, isCollateral_);
    }

    /// @dev Reads a token's collateral (supply) amount from Liquidity, adjusted for exchange price.
    ///      Normalized to 1e12 using the token's precision scalers.
    function _getLiquidityCollateral(
        bytes32 supplySlot_,
        bytes32 exchangePriceSlot_,
        uint256 numPrecision_,
        uint256 denPrecision_
    ) private view returns (uint256 tokenSupply_) {
        uint256 tokenSupplyData_ = LIQUIDITY.readFromStorage(supplySlot_);
        tokenSupply_ = (tokenSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        tokenSupply_ =
            (tokenSupply_ >> LiquidityCalcs.DEFAULT_EXPONENT_SIZE) <<
            (tokenSupply_ & LiquidityCalcs.DEFAULT_EXPONENT_MASK);

        (uint256 exchangePrice_, ) = LiquidityCalcs.calcExchangePrices(LIQUIDITY.readFromStorage(exchangePriceSlot_));

        if (tokenSupplyData_ & 1 == 1) {
            unchecked {
                tokenSupply_ = (tokenSupply_ * exchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        unchecked {
            tokenSupply_ = (tokenSupply_ * numPrecision_) / denPrecision_;
        }
    }

    /// @dev Reads a token's debt (borrow) amount from Liquidity, adjusted for exchange price.
    ///      Normalized to 1e12 using the token's precision scalers.
    function _getLiquidityDebt(
        bytes32 borrowSlot_,
        bytes32 exchangePriceSlot_,
        uint256 numPrecision_,
        uint256 denPrecision_
    ) private view returns (uint256 debtAmount_) {
        uint256 debtAmountData_ = LIQUIDITY.readFromStorage(borrowSlot_);
        debtAmount_ = (debtAmountData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        debtAmount_ =
            (debtAmount_ >> LiquidityCalcs.DEFAULT_EXPONENT_SIZE) <<
            (debtAmount_ & LiquidityCalcs.DEFAULT_EXPONENT_MASK);

        (, uint256 exchangePrice_) = LiquidityCalcs.calcExchangePrices(LIQUIDITY.readFromStorage(exchangePriceSlot_));

        if (debtAmountData_ & 1 == 1) {
            unchecked {
                debtAmount_ = (debtAmount_ * exchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        unchecked {
            debtAmount_ = (debtAmount_ * numPrecision_) / denPrecision_;
        }
    }
}
