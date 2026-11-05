const helpers = require('./helpers');

const FEE_100_PERCENT = 1e6;
const MAX_PRICE_DIFF = 5; // 5%

/**
 * Calculates the output amount for a given input amount in a swap operation.
 * @param {boolean} swap0To1 - Direction of the swap. True if swapping token0 for token1, false otherwise.
 * @param {number} amountToSwap - The amount of input token to be swapped. in 1e12 decimals.
 * @param {Object} colReserves - The reserves of the collateral pool. in 1e12 decimals.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} debtReserves - The reserves of the debt pool. in 1e12 decimals.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @param {number} outDecimals - The number of decimals for the output token.
 * @param {Object} currentLimits - current borrowable & withdrawable of the pool. in token decimals.
 * @param {Object} currentLimits.borrowableToken0 - token0 borrow limit
 * @param {number} currentLimits.borrowableToken0.available - token0 instant borrowable available
 * @param {number} currentLimits.borrowableToken0.expandsTo - token0 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.borrowableToken1 - token1 borrow limit
 * @param {number} currentLimits.borrowableToken1.available - token1 instant borrowable available
 * @param {number} currentLimits.borrowableToken1.expandsTo - token1 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken0 - token0 withdraw limit
 * @param {number} currentLimits.withdrawableToken0.available - token0 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken0.expandsTo - token0 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken1 - token1 withdraw limit
 * @param {number} currentLimits.withdrawableToken1.available - token1 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken1.expandsTo - token1 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {number} centerPrice - current center price used to verify reserves ratio
 * @param {number} syncTime - timestamp in seconds when the limits were synced
 * @returns {number} amountOut - The calculated output amount. Returns 0 in case of no swap available or not enough liquidity.
 */
function swapInAdjusted(
    swap0To1,
    amountToSwap,
    colReserves,
    debtReserves,
    outDecimals,
    currentLimits,
    centerPrice,
    syncTime
) {
    const {
        token0RealReserves,
        token1RealReserves,
        token0ImaginaryReserves,
        token1ImaginaryReserves
    } = colReserves;

    const {
        token0RealReserves: debtToken0RealReserves,
        token1RealReserves: debtToken1RealReserves,
        token0ImaginaryReserves: debtToken0ImaginaryReserves,
        token1ImaginaryReserves: debtToken1ImaginaryReserves
    } = debtReserves;

    // Check if all reserves of collateral pool are greater than 0
    const colPoolEnabled = (
        token0RealReserves > 0 &&
        token1RealReserves > 0 &&
        token0ImaginaryReserves > 0 &&
        token1ImaginaryReserves > 0
    );

    // Check if all reserves of debt pool are greater than 0
    const debtPoolEnabled = (
        debtToken0RealReserves > 0 &&
        debtToken1RealReserves > 0 &&
        debtToken0ImaginaryReserves > 0 &&
        debtToken1ImaginaryReserves > 0
    );

    let colReserveIn, colReserveOut, debtReserveIn, debtReserveOut;
    let colIReserveIn, colIReserveOut, debtIReserveIn, debtIReserveOut;
    let borrowable, withdrawable;

    if (swap0To1) {
        colReserveIn = token0RealReserves;
        colReserveOut = token1RealReserves;
        colIReserveIn = token0ImaginaryReserves;
        colIReserveOut = token1ImaginaryReserves;
        debtReserveIn = debtToken0RealReserves;
        debtReserveOut = debtToken1RealReserves;
        debtIReserveIn = debtToken0ImaginaryReserves;
        debtIReserveOut = debtToken1ImaginaryReserves;
        borrowable = helpers.getExpandedLimit(syncTime, currentLimits.borrowableToken1);
        withdrawable = helpers.getExpandedLimit(syncTime, currentLimits.withdrawableToken1);
    } else {
        colReserveIn = token1RealReserves;
        colReserveOut = token0RealReserves;
        colIReserveIn = token1ImaginaryReserves;
        colIReserveOut = token0ImaginaryReserves;
        debtReserveIn = debtToken1RealReserves;
        debtReserveOut = debtToken0RealReserves;
        debtIReserveIn = debtToken1ImaginaryReserves;
        debtIReserveOut = debtToken0ImaginaryReserves;
        borrowable = helpers.getExpandedLimit(syncTime, currentLimits.borrowableToken0);
        withdrawable = helpers.getExpandedLimit(syncTime, currentLimits.withdrawableToken0);
    }

    // bring borrowable and withdrawable from token decimals to 1e12 decimals, same as amounts
    borrowable = borrowable * 10 ** (12 - outDecimals);
    withdrawable = withdrawable * 10 ** (12 - outDecimals);

    let a;
    if (colPoolEnabled && debtPoolEnabled) {
        a = helpers.swapRoutingIn(
            amountToSwap,
            colIReserveOut,
            colIReserveIn,
            debtIReserveOut,
            debtIReserveIn
        );
    } else if (debtPoolEnabled) {
        a = -1; // Route from debt pool
    } else if (colPoolEnabled) {
        a = amountToSwap + 1; // Route from collateral pool
    } else {
        throw new Error("No pools are enabled");
    }

    let amountOutCollateral = 0;
    let amountOutDebt = 0;
    let amountInCollateral = 0;
    let amountInDebt = 0;

    if (a <= 0) {
        // Entire trade routes through debt pool
        amountInDebt = amountToSwap;
        amountOutDebt = helpers.getAmountOut(amountToSwap, debtIReserveIn, debtIReserveOut);
    } else if (a >= amountToSwap) {
        // Entire trade routes through collateral pool
        amountInCollateral = amountToSwap;
        amountOutCollateral = helpers.getAmountOut(amountToSwap, colIReserveIn, colIReserveOut);
    } else {
        // Trade routes through both pools
        amountInCollateral = a;
        amountOutCollateral = helpers.getAmountOut(a, colIReserveIn, colIReserveOut);
        amountInDebt = amountToSwap - a;
        amountOutDebt = helpers.getAmountOut(amountInDebt, debtIReserveIn, debtIReserveOut);
    }

    if (amountOutDebt > debtReserveOut) {
        return 0;
    }

    if (amountOutDebt > borrowable) {
        return 0;
    }

    if (amountOutCollateral > colReserveOut) {
        return 0;
    }

    if (amountOutCollateral > withdrawable) {
        return 0;
    }

    if (amountInCollateral > 0) {
        let reservesRatioValid = swap0To1
          ? helpers.verifyToken1Reserves(colReserveIn + amountInCollateral, colReserveOut - amountOutCollateral, centerPrice)
          : helpers.verifyToken0Reserves(colReserveOut - amountOutCollateral, colReserveIn + amountInCollateral, centerPrice);
        if (!reservesRatioValid) {
          return 0;
        }
    }
    if (amountInDebt > 0) {
        let reservesRatioValid = swap0To1
            ? helpers.verifyToken1Reserves(debtReserveIn + amountInDebt, debtReserveOut - amountOutDebt, centerPrice)
            : helpers.verifyToken0Reserves(debtReserveOut - amountOutDebt, debtReserveIn + amountInDebt, centerPrice);
        if (!reservesRatioValid) {
            return 0;
        }
    }

    let oldPrice;
    let newPrice;
    // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
    if (amountInCollateral > amountInDebt) {
        // new pool price from col pool
        oldPrice = swap0To1 ? (colIReserveOut * 1e27) / (colIReserveIn) : (colIReserveIn * 1e27) / (colIReserveOut);
        newPrice = swap0To1
            ? ((colIReserveOut - amountOutCollateral) * 1e27) / (colIReserveIn + amountInCollateral)
            : ((colIReserveIn + amountInCollateral) * 1e27) / (colIReserveOut - amountOutCollateral);
    } else {
        // new pool price from debt pool
        oldPrice = swap0To1 ? (debtIReserveOut * 1e27) / (debtIReserveIn) : (debtIReserveIn * 1e27) / (debtIReserveOut);
        newPrice = swap0To1
            ? ((debtIReserveOut - amountOutDebt) * 1e27) / (debtIReserveIn + amountInDebt)
            : ((debtIReserveIn + amountInDebt) * 1e27) / (debtIReserveOut - amountOutDebt);
    }
    if (Math.abs(oldPrice - newPrice) > (oldPrice / 100 * MAX_PRICE_DIFF)) {
        // if price diff is > 5% then swap would revert.
        return 0;
    }

    const totalAmountOut = amountOutCollateral + amountOutDebt;

    return totalAmountOut;
}

/**
 * Calculates the output amount for a given input amount in a swap operation.
 * @param {boolean} swap0To1 - Direction of the swap. True if swapping token0 for token1, false otherwise.
 * @param {number} amountToSwap - The amount of input token to be swapped.
 * @param {Object} colReserves - The reserves of the collateral pool. in 1e12 decimals.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} debtReserves - The reserves of the debt pool. in 1e12 decimals.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @param {number} inDecimals - The number of decimals for the input token.
 * @param {number} outDecimals - The number of decimals for the output token.
 * @param {number} fee - The fee for the swap. 1e4 = 1%
 * @param {Object} currentLimits - current borrowable & withdrawable of the pool. in token decimals.
 * @param {Object} currentLimits.borrowableToken0 - token0 borrow limit
 * @param {number} currentLimits.borrowableToken0.available - token0 instant borrowable available
 * @param {number} currentLimits.borrowableToken0.expandsTo - token0 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.borrowableToken1 - token1 borrow limit
 * @param {number} currentLimits.borrowableToken1.available - token1 instant borrowable available
 * @param {number} currentLimits.borrowableToken1.expandsTo - token1 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken0 - token0 withdraw limit
 * @param {number} currentLimits.withdrawableToken0.available - token0 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken0.expandsTo - token0 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken1 - token1 withdraw limit
 * @param {number} currentLimits.withdrawableToken1.available - token1 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken1.expandsTo - token1 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {number} centerPrice - current center price used to verify reserves ratio
 * @param {number} syncTime - timestamp in seconds when the limits were synced
 * @returns {number} amountOut - The calculated output amount. Returns 0 in case of no swap available or not enough liquidity.
 */
function swapIn(
    swap0To1,
    amountIn,
    colReserves,
    debtReserves,
    inDecimals,
    outDecimals,
    fee,
    currentLimits,
    centerPrice,
    syncTime
) {
    const amountInAdjusted = (amountIn * (FEE_100_PERCENT - fee) / FEE_100_PERCENT) * 10 ** (12 - inDecimals);
    const amountOut = swapInAdjusted(swap0To1, amountInAdjusted, colReserves, debtReserves, outDecimals, currentLimits, centerPrice, syncTime);
    return amountOut * 10 ** (outDecimals - 12);
}

/**
 * Calculates the input amount for a given output amount in a swap operation.
 * @param {boolean} swap0To1 - Direction of the swap. True if swapping token0 for token1, false otherwise.
 * @param {number} amountOut - The amount of output token to be swapped. in 1e12 decimals.
 * @param {Object} colReserves - The reserves of the collateral pool. in 1e12 decimals.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} debtReserves - The reserves of the debt pool. in 1e12 decimals.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @param {number} outDecimals - The number of decimals for the output token.
 * @param {Object} currentLimits - current borrowable & withdrawable of the pool. in token decimals.
 * @param {Object} currentLimits.borrowableToken0 - token0 borrow limit
 * @param {number} currentLimits.borrowableToken0.available - token0 instant borrowable available
 * @param {number} currentLimits.borrowableToken0.expandsTo - token0 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.borrowableToken1 - token1 borrow limit
 * @param {number} currentLimits.borrowableToken1.available - token1 instant borrowable available
 * @param {number} currentLimits.borrowableToken1.expandsTo - token1 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken0 - token0 withdraw limit
 * @param {number} currentLimits.withdrawableToken0.available - token0 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken0.expandsTo - token0 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken1 - token1 withdraw limit
 * @param {number} currentLimits.withdrawableToken1.available - token1 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken1.expandsTo - token1 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {number} centerPrice - current center price used to verify reserves ratio
 * @param {number} syncTime - timestamp in seconds when the limits were synced
 * @returns {number} amountIn - The calculated input amount required for the swap. Returns Number.MAX_VALUE in case of no swap available or not enough liquidity.
 */
function swapOutAdjusted(
    swap0To1,
    amountOut,
    colReserves,
    debtReserves,
    outDecimals,
    currentLimits,
    centerPrice,
    syncTime
) {
    const {
        token0RealReserves,
        token1RealReserves,
        token0ImaginaryReserves,
        token1ImaginaryReserves
    } = colReserves;

    const {
        token0RealReserves: debtToken0RealReserves,
        token1RealReserves: debtToken1RealReserves,
        token0ImaginaryReserves: debtToken0ImaginaryReserves,
        token1ImaginaryReserves: debtToken1ImaginaryReserves
    } = debtReserves;

    // Check if all reserves of collateral pool are greater than 0
    const colPoolEnabled = (
        token0RealReserves > 0 &&
        token1RealReserves > 0 &&
        token0ImaginaryReserves > 0 &&
        token1ImaginaryReserves > 0
    );

    // Check if all reserves of debt pool are greater than 0
    const debtPoolEnabled = (
        debtToken0RealReserves > 0 &&
        debtToken1RealReserves > 0 &&
        debtToken0ImaginaryReserves > 0 &&
        debtToken1ImaginaryReserves > 0
    );

    let colReserveIn, colReserveOut, debtReserveIn, debtReserveOut;
    let colIReserveIn, colIReserveOut, debtIReserveIn, debtIReserveOut;
    let borrowable, withdrawable;

    if (swap0To1) {
        colReserveIn = token0RealReserves;
        colReserveOut = token1RealReserves;
        colIReserveIn = token0ImaginaryReserves;
        colIReserveOut = token1ImaginaryReserves;
        debtReserveIn = debtToken0RealReserves;
        debtReserveOut = debtToken1RealReserves;
        debtIReserveIn = debtToken0ImaginaryReserves;
        debtIReserveOut = debtToken1ImaginaryReserves;
        borrowable = helpers.getExpandedLimit(syncTime, currentLimits.borrowableToken1);
        withdrawable = helpers.getExpandedLimit(syncTime, currentLimits.withdrawableToken1);
    } else {
        colReserveIn = token1RealReserves;
        colReserveOut = token0RealReserves;
        colIReserveIn = token1ImaginaryReserves;
        colIReserveOut = token0ImaginaryReserves;
        debtReserveIn = debtToken1RealReserves;
        debtReserveOut = debtToken0RealReserves;
        debtIReserveIn = debtToken1ImaginaryReserves;
        debtIReserveOut = debtToken0ImaginaryReserves;
        borrowable = helpers.getExpandedLimit(syncTime, currentLimits.borrowableToken0);
        withdrawable = helpers.getExpandedLimit(syncTime, currentLimits.withdrawableToken0);
    }

    // bring borrowable and withdrawable from token decimals to 1e12 decimals, same as amounts
    borrowable = borrowable * 10 ** (12 - outDecimals);
    withdrawable = withdrawable * 10 ** (12 - outDecimals);

    let a;
    if (colPoolEnabled && debtPoolEnabled) {
        a = helpers.swapRoutingOut(
            amountOut,
            colIReserveIn,
            colIReserveOut,
            debtIReserveIn,
            debtIReserveOut
        );
    } else if (debtPoolEnabled) {
        a = -1; // Route from debt pool
    } else if (colPoolEnabled) {
        a = amountOut + 1; // Route from collateral pool
    } else {
        throw new Error("No pools are enabled");
    }

    let amountInCollateral = 0;
    let amountInDebt = 0;
    let amountOutCollateral = 0;
    let amountOutDebt = 0;

    if (a <= 0) {
        // Entire trade routes through debt pool
        amountOutDebt = amountOut;
        amountInDebt = helpers.getAmountIn(amountOut, debtIReserveIn, debtIReserveOut);
        if (amountOut > debtReserveOut) {
            return Number.MAX_VALUE;
        }
        if (amountOut > borrowable) {
            return Number.MAX_VALUE;
        }
    } else if (a >= amountOut) {
        // Entire trade routes through collateral pool
        amountOutCollateral = amountOut;
        amountInCollateral = helpers.getAmountIn(amountOut, colIReserveIn, colIReserveOut);
        if (amountOut > colReserveOut) {
            return Number.MAX_VALUE;
        }
        if (amountOut > withdrawable) {
            return Number.MAX_VALUE;
        }
    } else {
        // Trade routes through both pools
        amountOutCollateral = a;
        amountInCollateral = helpers.getAmountIn(a, colIReserveIn, colIReserveOut);
        amountOutDebt = amountOut - a;
        amountInDebt = helpers.getAmountIn(amountOutDebt, debtIReserveIn, debtIReserveOut);
        if (((amountOutDebt) > debtReserveOut) || (a > colReserveOut)) {
            return Number.MAX_VALUE;
        }
        if (((amountOutDebt) > borrowable) || (a > withdrawable)) {
            return Number.MAX_VALUE;
        }
    }

    if (amountInCollateral > 0) {
        let reservesRatioValid = swap0To1
          ? helpers.verifyToken1Reserves(colReserveIn + amountInCollateral, colReserveOut - amountOutCollateral, centerPrice)
          : helpers.verifyToken0Reserves(colReserveOut - amountOutCollateral, colReserveIn + amountInCollateral, centerPrice);
        if (!reservesRatioValid) {
            return Number.MAX_VALUE;
        }
    }
    if (amountInDebt > 0) {
        let reservesRatioValid = swap0To1
            ? helpers.verifyToken1Reserves(debtReserveIn + amountInDebt, debtReserveOut - amountOutDebt, centerPrice)
            : helpers.verifyToken0Reserves(debtReserveOut - amountOutDebt, debtReserveIn + amountInDebt, centerPrice);
        if (!reservesRatioValid) {
            return Number.MAX_VALUE;
        }
    }

    let oldPrice;
    let newPrice;
    // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
    if (amountOutCollateral > amountOutDebt) {
        // new pool price from col pool
        oldPrice = swap0To1 ? (colIReserveOut * 1e27) / (colIReserveIn) : (colIReserveIn * 1e27) / (colIReserveOut);
        newPrice = swap0To1
            ? ((colIReserveOut - amountOutCollateral) * 1e27) / (colIReserveIn + amountInCollateral)
            : ((colIReserveIn + amountInCollateral) * 1e27) / (colIReserveOut - amountOutCollateral);
    } else {
        // new pool price from debt pool
        oldPrice = swap0To1 ? (debtIReserveOut * 1e27) / (debtIReserveIn) : (debtIReserveIn * 1e27) / (debtIReserveOut);
        newPrice = swap0To1
            ? ((debtIReserveOut - amountOutDebt) * 1e27) / (debtIReserveIn + amountInDebt)
            : ((debtIReserveIn + amountInDebt) * 1e27) / (debtIReserveOut - amountOutDebt);
    }
    if (Math.abs(oldPrice - newPrice) > (oldPrice / 100 * MAX_PRICE_DIFF)) {
        // if price diff is > 5% then swap would revert.
        return Number.MAX_VALUE;
    }

    const totalAmountIn = amountInCollateral + amountInDebt;

    return totalAmountIn;
}

/**
 * Calculates the input amount for a given output amount in a swap operation.
 * @param {boolean} swap0To1 - Direction of the swap. True if swapping token0 for token1, false otherwise.
 * @param {number} amountOut - The amount of output token to be swapped.
 * @param {Object} colReserves - The reserves of the collateral pool. in 1e12 decimals.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} debtReserves - The reserves of the debt pool. in 1e12 decimals.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @param {number} inDecimals - The number of decimals for the input token.
 * @param {number} outDecimals - The number of decimals for the output token.
 * @param {number} fee - The fee for the swap. 1e4 = 1%
 * @param {Object} currentLimits - current borrowable & withdrawable of the pool. in token decimals.
 * @param {Object} currentLimits.borrowableToken0 - token0 borrow limit
 * @param {number} currentLimits.borrowableToken0.available - token0 instant borrowable available
 * @param {number} currentLimits.borrowableToken0.expandsTo - token0 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.borrowableToken1 - token1 borrow limit
 * @param {number} currentLimits.borrowableToken1.available - token1 instant borrowable available
 * @param {number} currentLimits.borrowableToken1.expandsTo - token1 maximum amount the available borrow amount expands to
 * @param {number} currentLimits.borrowableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken0 - token0 withdraw limit
 * @param {number} currentLimits.withdrawableToken0.available - token0 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken0.expandsTo - token0 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken0.expandDuration - duration for token0 available to grow to expandsTo
 * @param {Object} currentLimits.withdrawableToken1 - token1 withdraw limit
 * @param {number} currentLimits.withdrawableToken1.available - token1 instant withdrawable available
 * @param {number} currentLimits.withdrawableToken1.expandsTo - token1 maximum amount the available withdraw amount expands to
 * @param {number} currentLimits.withdrawableToken1.expandDuration - duration for token1 available to grow to expandsTo
 * @param {number} centerPrice - current center price used to verify reserves ratio
 * @param {number} syncTime - timestamp in seconds when the limits were synced
 * @returns {number} amountIn - The calculated input amount required for the swap. Returns Number.MAX_VALUE in case of no swap available or not enough liquidity.
 */
function swapOut(
    swap0To1,
    amountOut,
    colReserves,
    debtReserves,
    inDecimals,
    outDecimals,
    fee,
    currentLimits,
    centerPrice,
    syncTime
) {
    const amountOutAdjusted = amountOut * 10 ** (12 - outDecimals);
    const amountIn = swapOutAdjusted(swap0To1, amountOutAdjusted, colReserves, debtReserves, outDecimals, currentLimits, centerPrice, syncTime);
    return (amountIn * FEE_100_PERCENT / (FEE_100_PERCENT - fee)) * 10 ** (inDecimals - 12);
}

module.exports = {
    swapInAdjusted,
    swapOutAdjusted,
    swapIn,
    swapOut
};