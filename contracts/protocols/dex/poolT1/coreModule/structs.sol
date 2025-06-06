// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Structs {
    struct PricesAndExchangePrice {
        uint lastStoredPrice; // last stored price in 1e27 decimals
        uint centerPrice; // last stored price in 1e27 decimals
        uint upperRange; // price at upper range in 1e27 decimals
        uint lowerRange; // price at lower range in 1e27 decimals
        uint geometricMean; // geometric mean of upper range & lower range in 1e27 decimals
        uint supplyToken0ExchangePrice;
        uint borrowToken0ExchangePrice;
        uint supplyToken1ExchangePrice;
        uint borrowToken1ExchangePrice;
    }

    struct ExchangePrices {
        uint supplyToken0ExchangePrice;
        uint borrowToken0ExchangePrice;
        uint supplyToken1ExchangePrice;
        uint borrowToken1ExchangePrice;
    }

    struct CollateralReserves {
        uint token0RealReserves;
        uint token1RealReserves;
        uint token0ImaginaryReserves;
        uint token1ImaginaryReserves;
    }

    struct CollateralReservesSwap {
        uint tokenInRealReserves;
        uint tokenOutRealReserves;
        uint tokenInImaginaryReserves;
        uint tokenOutImaginaryReserves;
    }

    struct DebtReserves {
        uint token0Debt;
        uint token1Debt;
        uint token0RealReserves;
        uint token1RealReserves;
        uint token0ImaginaryReserves;
        uint token1ImaginaryReserves;
    }

    struct DebtReservesSwap {
        uint tokenInDebt;
        uint tokenOutDebt;
        uint tokenInRealReserves;
        uint tokenOutRealReserves;
        uint tokenInImaginaryReserves;
        uint tokenOutImaginaryReserves;
    }

    struct SwapInMemory {
        address tokenIn;
        address tokenOut;
        uint256 amtInAdjusted;
        address withdrawTo;
        address borrowTo;
        uint price; // price of pool after swap
        uint fee; // fee of pool
        uint revenueCut; // revenue cut of pool
        bool swap0to1;
        int swapRoutingAmt;
        bytes data; // just added to avoid stack-too-deep error
    }

    struct SwapOutMemory {
        address tokenIn;
        address tokenOut;
        uint256 amtOutAdjusted;
        address withdrawTo;
        address borrowTo;
        uint price; // price of pool after swap
        uint fee;
        uint revenueCut; // revenue cut of pool
        bool swap0to1;
        int swapRoutingAmt;
        bytes data; // just added to avoid stack-too-deep error
        uint msgValue;
    }

    struct DepositColMemory {
        uint256 token0AmtAdjusted;
        uint256 token1AmtAdjusted;
        uint256 token0ReservesInitial;
        uint256 token1ReservesInitial;
    }

    struct WithdrawColMemory {
        uint256 token0AmtAdjusted;
        uint256 token1AmtAdjusted;
        uint256 token0ReservesInitial;
        uint256 token1ReservesInitial;
        address to;
    }

    struct BorrowDebtMemory {
        uint256 token0AmtAdjusted;
        uint256 token1AmtAdjusted;
        uint256 token0DebtInitial;
        uint256 token1DebtInitial;
        address to;
    }

    struct PaybackDebtMemory {
        uint256 token0AmtAdjusted;
        uint256 token1AmtAdjusted;
        uint256 token0DebtInitial;
        uint256 token1DebtInitial;
    }

    struct OraclePriceMemory {
        uint lowestPrice1by0;
        uint highestPrice1by0;
        uint oracleSlot;
        uint oracleMap;
        uint oracle;
    }

    struct Oracle {
        uint twap1by0; // TWAP price
        uint lowestPrice1by0; // lowest price point
        uint highestPrice1by0; // highest price point
        uint twap0by1; // TWAP price
        uint lowestPrice0by1; // lowest price point
        uint highestPrice0by1; // highest price point
    }

    struct Implementations {
        address shift;
        address admin;
        address colOperations;
        address debtOperations;
        address perfectOperationsAndSwapOut;
    }

    struct ConstantViews {
        uint256 dexId;
        address liquidity;
        address factory;
        Implementations implementations;
        address deployerContract;
        address token0;
        address token1;
        bytes32 supplyToken0Slot;
        bytes32 borrowToken0Slot;
        bytes32 supplyToken1Slot;
        bytes32 borrowToken1Slot;
        bytes32 exchangePriceToken0Slot;
        bytes32 exchangePriceToken1Slot;
        uint256 oracleMapping;
    }

    struct ConstantViews2 {
        uint token0NumeratorPrecision;
        uint token0DenominatorPrecision;
        uint token1NumeratorPrecision;
        uint token1DenominatorPrecision;
    }
}
