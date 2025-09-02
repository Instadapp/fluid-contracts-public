// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";

// @dev Amounts are always in token amount for normal col / normal debt or in
// shares for Dex smart col / smart debt.
contract Structs {
    struct Configs {
        // can be supplyRate instead if Vault Type is smart col. in that case if 1st bit == 1 then positive else negative
        uint16 supplyRateMagnifier;
        // can be borrowRate instead if Vault Type is smart debt. in that case if 1st bit == 1 then positive else negative
        uint16 borrowRateMagnifier;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationMaxLimit;
        uint16 withdrawalGap;
        uint16 liquidationPenalty;
        uint16 borrowFee;
        address oracle;
        // Oracle price is always debt per col, i.e. amount of debt for 1 col.
        // In case of Dex this price can be used to resolve shares values w.r.t. token0 or token1:
        // - T2: debt token per 1 col share
        // - T3: debt shares per 1 col token
        // - T4: debt shares per 1 col share
        uint oraclePriceOperate;
        uint oraclePriceLiquidate;
        address rebalancer;
        uint lastUpdateTimestamp;
    }

    struct ExchangePricesAndRates {
        uint lastStoredLiquiditySupplyExchangePrice; // 0 in case of smart col
        uint lastStoredLiquidityBorrowExchangePrice; // 0 in case of smart debt
        uint lastStoredVaultSupplyExchangePrice;
        uint lastStoredVaultBorrowExchangePrice;
        uint liquiditySupplyExchangePrice; // set to 1e12 in case of smart col
        uint liquidityBorrowExchangePrice; // set to 1e12 in case of smart debt
        uint vaultSupplyExchangePrice;
        uint vaultBorrowExchangePrice;
        uint supplyRateLiquidity; // set to 0 in case of smart col. Must get per token through DexEntireData
        uint borrowRateLiquidity; // set to 0 in case of smart debt. Must get per token through DexEntireData
        // supplyRateVault or borrowRateVault:
        // - when normal col / debt: rate at liquidity + diff rewards or fee through magnifier (rewardsOrFeeRate below)
        // - when smart col / debt: rewards or fee rate at the vault itself. always == rewardsOrFeeRate below.
        // to get the full rates for vault when smart col / debt, combine with data from DexResolver:
        // - rateAtLiquidity for token0 or token1 (DexResolver)
        // - the rewards or fee rate at the vault (VaultResolver)
        // - the Dex APR (currently off-chain compiled through tracking swap events at the DEX)
        int supplyRateVault; // can be negative in case of smart col (meaning pay to supply)
        int borrowRateVault; // can be negative in case of smart debt (meaning get paid to borrow)
        // rewardsOrFeeRateSupply: rewards or fee rate in percent 1e2 precision (1% = 100, 100% = 10000).
        // positive rewards, negative fee.
        // for smart col vaults: absolute percent, supplyRateVault == rewardsOrFeeRateSupply.
        // for normal col vaults: relative percent to supplyRateLiquidity, e.g.:
        // when rewards: supplyRateLiquidity = 4%, rewardsOrFeeRateSupply = 20%, supplyRateVault = 4.8%.
        // when fee: supplyRateLiquidity = 4%, rewardsOrFeeRateSupply = -30%, supplyRateVault = 2.8%.
        int rewardsOrFeeRateSupply;
        // rewardsOrFeeRateBorrow: rewards or fee rate in percent 1e2 precision (1% = 100, 100% = 10000).
        // negative rewards, positive fee.
        // for smart debt vaults: absolute percent, borrowRateVault == rewardsOrFeeRateBorrow.
        // for normal debt vaults: relative percent to borrowRateLiquidity, e.g.:
        // when rewards: borrowRateLiquidity = 4%, rewardsOrFeeRateBorrow = -20%, borrowRateVault = 3.2%.
        // when fee: borrowRateLiquidity = 4%, rewardsOrFeeRateBorrow = 30%, borrowRateVault = 5.2%.
        int rewardsOrFeeRateBorrow;
    }

    struct TotalSupplyAndBorrow {
        uint totalSupplyVault;
        uint totalBorrowVault;
        uint totalSupplyLiquidityOrDex;
        uint totalBorrowLiquidityOrDex;
        uint absorbedSupply;
        uint absorbedBorrow;
    }

    struct LimitsAndAvailability {
        // in case of DEX: withdrawable / borrowable amount of vault at DEX, BUT there could be that DEX can not withdraw
        // that much at Liquidity! So for DEX this must be combined with returned data in DexResolver.
        uint withdrawLimit;
        uint withdrawableUntilLimit;
        uint withdrawable;
        uint borrowLimit;
        uint borrowableUntilLimit; // borrowable amount until any borrow limit (incl. max utilization limit)
        uint borrowable; // actual currently borrowable amount (borrow limit - already borrowed) & considering balance, max utilization
        uint borrowLimitUtilization; // borrow limit for `maxUtilization` config at Liquidity
        uint minimumBorrowing;
    }

    struct CurrentBranchState {
        uint status; // if 0 then not liquidated, if 1 then liquidated, if 2 then merged, if 3 then closed
        int minimaTick;
        uint debtFactor;
        uint partials;
        uint debtLiquidity;
        uint baseBranchId;
        int baseBranchMinima;
    }

    struct VaultState {
        uint totalPositions;
        int topTick;
        uint currentBranch;
        uint totalBranch;
        uint totalBorrow;
        uint totalSupply;
        CurrentBranchState currentBranchState;
    }

    struct VaultEntireData {
        address vault;
        bool isSmartCol; // true if col token is a Fluid Dex
        bool isSmartDebt; // true if debt token is a Fluid Dex
        IFluidVault.ConstantViews constantVariables;
        Configs configs;
        ExchangePricesAndRates exchangePricesAndRates;
        TotalSupplyAndBorrow totalSupplyAndBorrow;
        LimitsAndAvailability limitsAndAvailability;
        VaultState vaultState;
        // liquidity related data such as supply amount, limits, expansion etc.
        // Also set for Dex, limits are in shares and same things apply as noted for LimitsAndAvailability above!
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyData;
        // liquidity related data such as borrow amount, limits, expansion etc.
        // Also set for Dex, limits are in shares and same things apply as noted for LimitsAndAvailability above!
        FluidLiquidityResolverStructs.UserBorrowData liquidityUserBorrowData;
    }

    struct UserPosition {
        uint nftId;
        address owner;
        bool isLiquidated;
        bool isSupplyPosition; // if true that means borrowing is 0
        int tick;
        uint tickId;
        uint beforeSupply;
        uint beforeBorrow;
        uint beforeDustBorrow;
        uint supply;
        uint borrow;
        uint dustBorrow;
    }

    /// @dev liquidation related data
    /// @param vault address of vault
    /// @param token0In address of token in
    /// @param token0Out address of token out
    /// @param token1In address of token in (if smart debt)
    /// @param token1Out address of token out (if smart col)
    /// @param inAmt (without absorb liquidity) minimum of available liquidation
    /// @param outAmt (without absorb liquidity) expected token out, collateral to withdraw
    /// @param inAmtWithAbsorb (absorb liquidity included) minimum of available liquidation. In most cases it'll be same as inAmt but sometimes can be bigger.
    /// @param outAmtWithAbsorb (absorb liquidity included) expected token out, collateral to withdraw. In most cases it'll be same as outAmt but sometimes can be bigger.
    /// @param absorbAvailable true if absorb is available
    /// @dev Liquidity in with absirb will always be >= without asborb. Sometimes without asborb can provide better swaps,
    ///      sometimes with absirb can provide better swaps. But available in with absirb will always be >= One
    struct LiquidationStruct {
        address vault;
        address token0In;
        address token0Out;
        address token1In;
        address token1Out;
        // amounts in case of smart debt are in shares, otherwise token amounts.
        // smart col can not be liquidated so to exchange inAmt always use DexResolver DexState.tokenPerDebtShare
        // and tokenPerColShare for outAmt when Vault is smart col.
        uint inAmt;
        uint outAmt;
        uint inAmtWithAbsorb;
        uint outAmtWithAbsorb;
        bool absorbAvailable;
    }

    struct AbsorbStruct {
        address vault;
        bool absorbAvailable;
    }
}
