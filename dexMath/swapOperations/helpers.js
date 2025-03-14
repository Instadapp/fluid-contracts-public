/**
 * Given an input amount of asset and pair reserves, returns the maximum output amount of the other asset.
 * @param {number} amountIn - The amount of input asset.
 * @param {number} iReserveIn - Imaginary token reserve with input amount.
 * @param {number} iReserveOut - Imaginary token reserve of output amount.
 * @returns {number} - The maximum output amount of the other asset.
 */
function getAmountOut(amountIn, iReserveIn, iReserveOut) {
    // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
    const numerator = amountIn * iReserveOut;
    const denominator = iReserveIn + amountIn;

    // Using the swap formula: (AmountIn * iReserveY) / (iReserveX + AmountIn)
    return numerator / denominator;
}

/**
 * Given an output amount of asset and pair reserves, returns the input amount of the other asset
 * @param {number} amountOut - Desired output amount of the asset.
 * @param {number} iReserveIn - Imaginary token reserve of input amount.
 * @param {number} iReserveOut - Imaginary token reserve of output amount.
 * @returns {number} - The input amount of the other asset.
 */
function getAmountIn(amountOut, iReserveIn, iReserveOut) {
    // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
    const numerator = amountOut * iReserveIn;
    const denominator = iReserveOut - amountOut;

    // Using the swap formula: (AmountOut * iReserveX) / (iReserveY - AmountOut)
    return numerator / denominator;
}

/**
 * Calculates how much of a swap should go through the collateral pool.
 * @param {number} t - Total amount in.
 * @param {number} x - Imaginary reserves of token out of collateral.
 * @param {number} y - Imaginary reserves of token in of collateral.
 * @param {number} x2 - Imaginary reserves of token out of debt.
 * @param {number} y2 - Imaginary reserves of token in of debt.
 * @returns {number} a - How much swap should go through collateral pool. Remaining will go from debt.
 * @note If a < 0 then entire trade route through debt pool and debt pool arbitrage with col pool.
 * @note If a > t then entire trade route through col pool and col pool arbitrage with debt pool.
 * @note If a > 0 & a < t then swap will route through both pools.
 */
function swapRoutingIn(t, x, y, x2, y2) {
    // Adding 1e18 precision
    var xyRoot = Math.sqrt(x * y * 1e18);
    var x2y2Root = Math.sqrt(x2 * y2 * 1e18);
    // Calculating 'a' using the given formula
    var a = (y2 * xyRoot + t * xyRoot - y * x2y2Root) / (xyRoot + x2y2Root);
    return a;
}

/**
 * Calculates how much of a swap should go through the collateral pool for output amount.
 * @param {number} t - Total amount out.
 * @param {number} x - Imaginary reserves of token in of collateral.
 * @param {number} y - Imaginary reserves of token out of collateral.
 * @param {number} x2 - Imaginary reserves of token in of debt.
 * @param {number} y2 - Imaginary reserves of token out of debt.
 * @returns {number} a - How much swap should go through collateral pool. Remaining will go from debt.
 * @note If a < 0 then entire trade route through debt pool and debt pool arbitrage with col pool.
 * @note If a > t then entire trade route through col pool and col pool arbitrage with debt pool.
 * @note If a > 0 & a < t then swap will route through both pools.
 */
function swapRoutingOut(t, x, y, x2, y2) {
    // Adding 1e18 precision
    const xyRoot = Math.sqrt(x * y * 1e18);
    const x2y2Root = Math.sqrt(x2 * y2 * 1e18);

    // 1e18 precision gets cancelled out in division
    const a = (t * xyRoot + y * x2y2Root - y2 * xyRoot) / (xyRoot + x2y2Root);

    return a;
}

/**
 * Calculates the currently available swappable amount for a token limit considering expansion since last syncTime.
 * @param {number} syncTime - timestamp in seconds when the limits were synced
 * @param {Object} limit - token limit object
 * @param {number} limit.available - available amount at `syncTime` 
 * @param {number} limit.expandsTo - maximum amount that available expands to over the duration of `expandDuration` seconds
 * @param {number} limit.expandDuration - duration in seconds for available to grow to expandsTo
 * @returns {number} availableAmount - The calculated available swappable amount (borrowable or withdrawable).
*/
function getExpandedLimit(syncTime, limit) {
    const currentTime = Date.now() / 1000;  // convert milliseconds to seconds
    const elapsedTime = (currentTime - syncTime);

    if(elapsedTime < 10){
        // if almost no time has elapsed, return available amount
        return limit.available;
    }

    if (elapsedTime >= limit.expandDuration) {
        // if duration has passed, return max amount
        return limit.expandsTo;
    }

    const expandedAmount = limit.available + (limit.expandsTo - limit.available) * (elapsedTime / limit.expandDuration);
    return Math.floor(expandedAmount);
}

const MIN_SWAP_LIQUIDITY = 0.85e4; // on-chain we use 1e4 but use extra buffer to avoid reverts

/**
 * Checks if token0 reserves are sufficient compared to token1 reserves.
 * This helps prevent edge cases and ensures high precision in calculations.
 * @param {number} token0Reserves - The reserves of token0.
 * @param {number} token1Reserves - The reserves of token1.
 * @param {number} price - The current price used for calculation.
 * @returns {boolean} - Returns false if token0 reserves are too low, true otherwise.
 */
function verifyToken0Reserves(token0Reserves, token1Reserves, price) {
  return token0Reserves >= (token1Reserves * 1e27) / (price * MIN_SWAP_LIQUIDITY);
}

/**
 * Checks if token1 reserves are sufficient compared to token0 reserves.
 * This helps prevent edge cases and ensures high precision in calculations.
 * @param {number} token0Reserves - The reserves of token0.
 * @param {number} token1Reserves - The reserves of token1.
 * @param {number} price - The current price used for calculation.
 * @returns {boolean} - Returns false if token1 reserves are too low, true otherwise.
 */
function verifyToken1Reserves(token0Reserves, token1Reserves, price) {
  return token1Reserves >= (token0Reserves * price) / (1e27 * MIN_SWAP_LIQUIDITY);
}

module.exports = {
    getAmountOut,
    getAmountIn,
    swapRoutingIn,
    swapRoutingOut,
    getExpandedLimit,
    verifyToken0Reserves,
    verifyToken1Reserves
};