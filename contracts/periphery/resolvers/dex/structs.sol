// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";

abstract contract Structs {
    struct DexState {
        uint256 lastToLastStoredPrice;
        uint256 lastStoredPrice; // price of pool after the most recent swap
        uint256 centerPrice;
        uint256 lastUpdateTimestamp;
        uint256 lastPricesTimeDiff;
        uint256 oracleCheckPoint;
        uint256 oracleMapping;
        uint256 totalSupplyShares;
        uint256 totalBorrowShares;
        bool isSwapAndArbitragePaused; // if true, only perfect functions will be usable
        ShiftChanges shifts;
        // below values have to be combined with Oracle price data at the VaultResolver
        uint256 token0PerSupplyShare; // token0 amount per 1e18 supply shares
        uint256 token1PerSupplyShare; // token1 amount per 1e18 supply shares
        uint256 token0PerBorrowShare; // token0 amount per 1e18 borrow shares
        uint256 token1PerBorrowShare; // token1 amount per 1e18 borrow shares
    }

    struct ShiftData {
        uint256 oldUpper;
        uint256 oldLower;
        uint256 duration;
        uint256 startTimestamp;
        uint256 oldTime; // only for thresholdShift
    }

    struct CenterPriceShift {
        uint256 shiftPercentage;
        uint256 duration;
        uint256 startTimestamp;
    }

    struct ShiftChanges {
        bool isRangeChangeActive;
        bool isThresholdChangeActive;
        bool isCenterPriceShiftActive;
        ShiftData rangeShift;
        ShiftData thresholdShift;
        CenterPriceShift centerPriceShift;
    }

    struct Configs {
        bool isSmartCollateralEnabled;
        bool isSmartDebtEnabled;
        uint256 fee;
        uint256 revenueCut;
        uint256 upperRange;
        uint256 lowerRange;
        uint256 upperShiftThreshold;
        uint256 lowerShiftThreshold;
        uint256 shiftingTime;
        address centerPriceAddress;
        address hookAddress;
        uint256 maxCenterPrice;
        uint256 minCenterPrice;
        uint256 utilizationLimitToken0;
        uint256 utilizationLimitToken1;
        uint256 maxSupplyShares;
        uint256 maxBorrowShares;
    }

    // @dev note there might be other things that act as effective limits which are not fully considered here.
    // e.g. such as maximum 5% oracle shift in one swap, withdraws & borrowing together affecting each other,
    // shares being below max supply / borrow shares etc.
    struct SwapLimitsAndAvailability {
        // liquidity total amounts
        uint liquiditySupplyToken0;
        uint liquiditySupplyToken1;
        uint liquidityBorrowToken0;
        uint liquidityBorrowToken1;
        // liquidity limits
        uint liquidityWithdrawableToken0;
        uint liquidityWithdrawableToken1;
        uint liquidityBorrowableToken0;
        uint liquidityBorrowableToken1;
        // utilization limits based on config at Dex. (e.g. liquiditySupplyToken0 * Configs.utilizationLimitToken0 / 1e3)
        uint utilizationLimitToken0;
        uint utilizationLimitToken1;
        // swappable amounts until utilization limit.
        // In a swap that does both withdraw and borrow, the effective amounts might be less because withdraw / borrow affect each other
        // (both increase utilization).
        uint withdrawableUntilUtilizationLimitToken0; // x = totalSupply - totalBorrow / maxUtilizationPercentage
        uint withdrawableUntilUtilizationLimitToken1;
        uint borrowableUntilUtilizationLimitToken0; // x = maxUtilizationPercentage * totalSupply - totalBorrow.
        uint borrowableUntilUtilizationLimitToken1;
        // additional liquidity related data such as supply amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyDataToken0;
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyDataToken1;
        // additional liquidity related data such as borrow amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserBorrowData liquidityUserBorrowDataToken0;
        FluidLiquidityResolverStructs.UserBorrowData liquidityUserBorrowDataToken1;
        // liquidity token related data
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData0;
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData1;
    }

    struct DexEntireData {
        address dex;
        IFluidDexT1.ConstantViews constantViews;
        IFluidDexT1.ConstantViews2 constantViews2;
        Configs configs;
        IFluidDexT1.PricesAndExchangePrice pex;
        IFluidDexT1.CollateralReserves colReserves;
        IFluidDexT1.DebtReserves debtReserves;
        DexState dexState;
        SwapLimitsAndAvailability limitsAndAvailability;
    }

    // amounts are always in normal (for withInterest already multiplied with exchange price)
    struct UserSupplyData {
        bool isAllowed;
        uint256 supply; // user supply amount/shares
        // the withdrawal limit (e.g. if 10% is the limit, and 100M is supplied, it would be 90M)
        uint256 withdrawalLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent; // withdrawal limit expand percent in 1e2
        uint256 expandDuration; // withdrawal limit expand duration in seconds
        uint256 baseWithdrawalLimit;
        // the current actual max withdrawable amount (e.g. if 10% is the limit, and 100M is supplied, it would be 10M)
        uint256 withdrawableUntilLimit;
        uint256 withdrawable; // actual currently withdrawable amount (supply - withdrawal Limit) & considering balance
        // liquidity related data such as supply amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyDataToken0;
        FluidLiquidityResolverStructs.UserSupplyData liquidityUserSupplyDataToken1;
        // liquidity token related data
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData0;
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData1;
    }

    // amounts are always in normal (for withInterest already multiplied with exchange price)
    struct UserBorrowData {
        bool isAllowed;
        uint256 borrow; // user borrow amount/shares
        uint256 borrowLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseBorrowLimit;
        uint256 maxBorrowLimit;
        uint256 borrowableUntilLimit; // borrowable amount until any borrow limit (incl. max utilization limit)
        uint256 borrowable; // actual currently borrowable amount (borrow limit - already borrowed) & considering balance, max utilization
        // liquidity related data such as borrow amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserBorrowData liquidityUserBorrowDataToken0;
        FluidLiquidityResolverStructs.UserBorrowData liquidityUserBorrowDataToken1;
        // liquidity token related data
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData0;
        FluidLiquidityResolverStructs.OverallTokenData liquidityTokenData1;
    }
}
