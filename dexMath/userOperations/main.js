const helpers = require('./helpers');

/**
 * Calculates the shares to be minted for a deposit operation.
 * @param {number} token0Amt - The amount of token0 to deposit.
 * @param {number} token1Amt - The amount of token1 to deposit.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalSupplyShares - The total supply of shares before the deposit.
 * @param {Object} colReserves - The current collateral reserves.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function deposit(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, dexFee, totalSupplyShares, colReserves) {
    // Adjust token amounts to 12 decimal places for internal calculations
    const token0AmtAdjusted = token0Amt * 10 ** (12 - token0Decimals);
    const token1AmtAdjusted = token1Amt * 10 ** (12 - token1Decimals);

    // Call depositAdjusted with the adjusted token amounts
    return helpers._depositAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalSupplyShares, colReserves);
}

/**
 * Calculates the shares to be burned for a withdraw operation.
 * @param {number} token0Amt - The amount of token0 to withdraw.
 * @param {number} token1Amt - The amount of token1 to withdraw.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} pex - The current price exponent.
 * @param {number} pex.geometricMean - The geometric mean price.
 * @param {number} pex.upperRange - The upper range price.
 * @param {number} pex.lowerRange - The lower range price.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function withdraw(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, dexFee, totalSupplyShares, colReserves, pex) {
    // Adjust token amounts to 12 decimal places for internal calculations
    const token0AmtAdjusted = token0Amt * 10 ** (12 - token0Decimals);
    const token1AmtAdjusted = token1Amt * 10 ** (12 - token1Decimals);

    return helpers._withdrawAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalSupplyShares, colReserves, pex);
}

/**
 * Calculates the output amount for a given input amount and reserves
 * @param {number} shares - The number of shares to withdraw.
 * @param {number} withdrawToken0Or1 - The token to withdraw in (0 for token0, 1 for token1).
 * @param {number} decimals0Or1 - The decimals of the token to withdraw.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @param {number} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {number} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {number} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @returns {Object} An object containing {tokenAmount, tokenAmountWithSlippage, success}.
 */
function withdrawMax(shares, withdrawToken0Or1, decimals0Or1, slippage, dexFee, totalSupplyShares, colReserves) {
    return helpers._withdrawPerfectInOneToken(shares, withdrawToken0Or1, decimals0Or1, slippage, dexFee, totalSupplyShares, colReserves);
}

/**
 * Calculates the shares to be minted for a borrow operation.
 * @param {number} token0Amt - The amount of token0 to borrow.
 * @param {number} token1Amt - The amount of token1 to borrow.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalBorrowShares - The total supply of shares before the borrow.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {number} debtReserves.token0Debt - Debt of token0 in the debt pool.
 * @param {number} debtReserves.token1Debt - Debt of token1 in the debt pool.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @param {Object} pex - The current price exponent.
 * @param {number} pex.geometricMean - The geometric mean price.
 * @param {number} pex.upperRange - The upper range price.
 * @param {number} pex.lowerRange - The lower range price.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function borrow(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, dexFee, totalBorrowShares, debtReserves, pex) {
    // Adjust token amounts to 12 decimal places for internal calculations
    const token0AmtAdjusted = token0Amt * 10 ** (12 - token0Decimals);
    const token1AmtAdjusted = token1Amt * 10 ** (12 - token1Decimals);

    return helpers._borrowAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalBorrowShares, debtReserves, pex);
}

/**
 * Calculates the shares to be burned for a payback operation.
 * @param {number} token0Amt - The amount of token0 to payback.
 * @param {number} token1Amt - The amount of token1 to payback.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {number} debtReserves.token0Debt - Debt of token0 in the debt pool.
 * @param {number} debtReserves.token1Debt - Debt of token1 in the debt pool.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function payback(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, dexFee, totalBorrowShares, debtReserves) {
    // Adjust token amounts to 12 decimal places for internal calculations
    const token0AmtAdjusted = token0Amt * 10 ** (12 - token0Decimals);
    const token1AmtAdjusted = token1Amt * 10 ** (12 - token1Decimals);

    return helpers._paybackAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalBorrowShares, debtReserves);
}

/**
 * Calculates the token amount to be paid back for a payback operation.
 * @param {number} shares - The amount of shares to burn.
 * @param {number} paybackToken0Or1 - The token to payback in (0 for token0, 1 for token1).
 * @param {number} decimals0Or1 - The decimals of the token to payback.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} dexFee - The DEX fee as a decimal (e.g., 0.003 for 0.3% fee).
 * @param {number} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {number} debtReserves.token0Debt - Debt of token0 in the debt pool.
 * @param {number} debtReserves.token1Debt - Debt of token1 in the debt pool.
 * @param {number} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {number} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {number} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @returns {Object} An object containing {tokenAmount, tokenAmountWithSlippage, success}.
 */
function paybackMax(shares, paybackToken0Or1, decimals0Or1, slippage, dexFee, totalBorrowShares, debtReserves) {
    return helpers._paybackPerfectInOneToken(shares, paybackToken0Or1, decimals0Or1, slippage, dexFee, totalBorrowShares, debtReserves);
}



/**
 * Calculates the shares to be minted for a deposit operation without slippage.
 * @param {number} token0Amt - The amount of token0 to deposit. If > 0, token1Amt must be 0.
 * @param {number} token1Amt - The amount of token1 to deposit. If > 0, token0Amt must be 0.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalSupplyShares - The total supply of shares before the deposit.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing:
 * @returns {number} shares - The amount of shares to be minted for the deposit.
 * @returns {number} token0Amt - The actual amount of token0 needed for the deposit to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the deposit to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function depositPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves) {
    let r_ = helpers._depositOrWithdrawPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves);

    let shares = r_.shares.toFixed(0);
    token0Amt = r_.token0Amt.toFixed(0);
    token1Amt = r_.token1Amt.toFixed(0);
    let token0AmtWithSlippage = (token0Amt * (1 + slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 + slippage)).toFixed(0);

    return {
        shares,
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }

}

/**
 * Calculates the shares to be burned for a withdraw operation without slippage.
 * @param {number} token0Amt - The amount of token0 to withdraw. If > 0, token1Amt must be 0.
 * @param {number} token1Amt - The amount of token1 to withdraw. If > 0, token0Amt must be 0.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing:
 * @returns {number} shares - The amount of shares to be burned for the withdraw.
 * @returns {number} token0Amt - The actual amount of token0 needed for the withdraw to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the withdraw to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function withdrawPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves) {
    let r_ = helpers._depositOrWithdrawPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves);

    let shares = r_.shares.toFixed(0);
    token0Amt = r_.token0Amt.toFixed(0);
    token1Amt = r_.token1Amt.toFixed(0);
    let token0AmtWithSlippage = (token0Amt * (1 - slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 - slippage)).toFixed(0);

    return {
        shares,
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }
}

/**
 * Calculates the token amount to be withdrawn for a withdraw operation without slippage.
 * @param {number} shares - The amount of shares to burn.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing:
 * @returns {number} token0Amt - The actual amount of token0 needed for the withdraw to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the withdraw to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function withdrawPerfectMax(shares, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves) {
    let token0AmtAdjusted = shares * colReserves.token0RealReserves / totalSupplyShares;
    let token1AmtAdjusted = shares * colReserves.token1RealReserves / totalSupplyShares;

    let token0Amt = (token0AmtAdjusted * 10 ** (token0Decimals - 12)).toFixed(0);
    let token1Amt = (token1AmtAdjusted * 10 ** (token1Decimals - 12)).toFixed(0);

    let token0AmtWithSlippage = (token0Amt * (1 - slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 - slippage)).toFixed(0);

    return {
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }
}

/**
 * Calculates the shares to be minted for a borrow operation without slippage.
 * @param {number} token0Amt - The amount of token0 to borrow. If > 0, token1Amt must be 0.
 * @param {number} token1Amt - The amount of token1 to borrow. If > 0, token0Amt must be 0.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalBorrowShares - The total supply of shares before the borrow.
 * @param {Object} debtReserves - The current debt reserves.
 * @returns {Object} An object containing:
 * @returns {number} shares - The amount of shares to be minted for the borrow.
 * @returns {number} token0Amt - The actual amount of token0 needed for the borrow to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the borrow to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function borrowPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalBorrowShares, debtReserves) {
    let r_ = helpers._borrowOrPaybackPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, totalBorrowShares, debtReserves);

    let shares = r_.shares.toFixed(0);
    token0Amt = r_.token0Amt.toFixed(0);
    token1Amt = r_.token1Amt.toFixed(0);
    let token0AmtWithSlippage = (token0Amt * (1 - slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 - slippage)).toFixed(0);

    return {
        shares,
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }
}

/**
 * Calculates the shares to be burned for a payback operation without slippage.
 * @param {number} token0Amt - The amount of token0 to payback. If > 0, token1Amt must be 0.
 * @param {number} token1Amt - The amount of token1 to payback. If > 0, token0Amt must be 0.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @returns {Object} An object containing:
 * @returns {number} shares - The amount of shares to be burned for the payback.
 * @returns {number} token0Amt - The actual amount of token0 needed for the payback to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the payback to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function paybackPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, slippage, totalBorrowShares, debtReserves) {
    let r_ = helpers._borrowOrPaybackPerfect(token0Amt, token1Amt, token0Decimals, token1Decimals, totalBorrowShares, debtReserves);

    let shares = r_.shares.toFixed(0);
    token0Amt = r_.token0Amt.toFixed(0);
    token1Amt = r_.token1Amt.toFixed(0);
    let token0AmtWithSlippage = (token0Amt * (1 + slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 + slippage)).toFixed(0);

    return {
        shares,
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }
}

/**
 * Calculates the token amount to be paid back for a payback operation without slippage.
 * @param {number} shares - The amount of shares to burn.
 * @param {number} token0Decimals - The decimals of token0.
 * @param {number} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 0.01 for 1%).
 * @param {number} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @returns {Object} An object containing:
 * @returns {number} token0Amt - The actual amount of token0 needed for the payback to maintain the pool ratio.
 * @returns {number} token1Amt - The actual amount of token1 needed for the payback to maintain the pool ratio.
 * @returns {number} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {number} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function paybackPerfectMax(shares, token0Decimals, token1Decimals, slippage, totalBorrowShares, debtReserves) {
    let token0AmtAdjusted = shares * debtReserves.token0Debt / totalBorrowShares;
    let token1AmtAdjusted = shares * debtReserves.token1Debt / totalBorrowShares;

    let token0Amt = (token0AmtAdjusted * 10 ** (token0Decimals - 12)).toFixed(0);
    let token1Amt = (token1AmtAdjusted * 10 ** (token1Decimals - 12)).toFixed(0);

    let token0AmtWithSlippage = (token0Amt * (1 + slippage)).toFixed(0);
    let token1AmtWithSlippage = (token1Amt * (1 + slippage)).toFixed(0);

    return {
        token0Amt,
        token1Amt,
        token0AmtWithSlippage,
        token1AmtWithSlippage
    }
}


module.exports = {
    deposit,
    withdraw,
    withdrawMax,
    borrow,
    payback,
    paybackMax,
    depositPerfect,
    withdrawPerfect,
    withdrawPerfectMax,
    borrowPerfect,
    paybackPerfect,
    paybackPerfectMax
};