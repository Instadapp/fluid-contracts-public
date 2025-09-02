const helpers = require("./helpers");
/**
 * Calculates the shares to be minted for a deposit operation.
 * @param {bigint} token0Amt - The amount of token0 to deposit.
 * @param {bigint} token1Amt - The amount of token1 to deposit.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a bigint representing a percentage (e.g., 1 for 100%).
 * @param {bigint} dexFee - The DEX fee as a bigint representing a percentage (1e6 for 100%)
 * @param {bigint} totalSupplyShares - The total supply of shares before the deposit.
 * @param {Object} colReserves - The current collateral reserves.
 * @param {bigint} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {bigint} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {bigint} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {bigint} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function deposit(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  dexFee,
  totalSupplyShares,
  colReserves
) {
  // Adjust token amounts to 12 decimal places for internal calculations
  const SCALE_FACTOR = 12n;
  const token0AmtAdjusted = (token0Amt * 10n ** SCALE_FACTOR) / 10n ** token0Decimals;
  const token1AmtAdjusted = (token1Amt * 10n ** SCALE_FACTOR) / 10n ** token1Decimals;

  // Call depositAdjusted with the adjusted token amounts
  return helpers._depositAdjusted(
    token0AmtAdjusted,
    token1AmtAdjusted,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves
  );
}

/**
 * Calculates the shares to be burned for a withdraw operation.
 * @param {bigint} token0Amt - The amount of token0 to withdraw.
 * @param {bigint} token1Amt - The amount of token1 to withdraw.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance as a bigint representing a percentage (e.g., 1 for 100%).
 * @param {bigint} dexFee - The DEX fee as a bigint representing a percentage (1e6 for 100%)
 * @param {bigint} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @param {bigint} colReserves.token0RealReserves - Real reserves of token0 in the collateral pool.
 * @param {bigint} colReserves.token1RealReserves - Real reserves of token1 in the collateral pool.
 * @param {bigint} colReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the collateral pool.
 * @param {bigint} colReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the collateral pool.
 * @param {Object} pex - The current price exponent.
 * @param {bigint} pex.geometricMean - The geometric mean price.
 * @param {bigint} pex.upperRange - The upper range price.
 * @param {bigint} pex.lowerRange - The lower range price.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function withdraw(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  dexFee,
  totalSupplyShares,
  colReserves,
  pex
) {
  // Adjust token amounts to 12 decimal places for internal calculations
  const SCALE_FACTOR = 12n;
  const token0AmtAdjusted = (token0Amt * 10n ** SCALE_FACTOR) / 10n ** token0Decimals;
  const token1AmtAdjusted = (token1Amt * 10n ** SCALE_FACTOR) / 10n ** token1Decimals;

  return helpers._withdrawAdjusted(
    token0AmtAdjusted,
    token1AmtAdjusted,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves,
    pex
  );
}

/**
 * Calculates the output amount for a given input amount and reserves
 * @param {bigint} shares - The number of shares to withdraw.
 * @param {bigint} withdrawToken0Or1 - The token to withdraw in (0 for token0, 1 for token1).
 * @param {bigint} decimals0Or1 - The decimals of the token to withdraw.
 * @param {number} slippage - The slippage tolerance. (e.g., 1n for 100%).
 * @param {bigint} dexFee - The DEX fee.(1e6 for 100%)
 * @param {bigint} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing {tokenAmount, tokenAmountWithSlippage, success}.
 */
function withdrawMax(shares, withdrawToken0Or1, decimals0Or1, slippage, dexFee, totalSupplyShares, colReserves) {
  return helpers._withdrawPerfectInOneToken(
    shares,
    withdrawToken0Or1,
    decimals0Or1,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves
  );
}

/**
 * Calculates the shares to be minted for a borrow operation.
 * @param {bigint} token0Amt - The amount of token0 to borrow.
 * @param {bigint} token1Amt - The amount of token1 to borrow.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance. (e.g., 1n for 100%).
 * @param {bigint} dexFee - The DEX fee.(1e6 for 100%)
 * @param {bigint} totalBorrowShares - The total supply of shares before the borrow.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {Object} pex - The current price exponent.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function borrow(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  dexFee,
  totalBorrowShares,
  debtReserves,
  pex
) {
  // Adjust token amounts to 12 decimal places for internal calculations
  const TWELVE_DECIMALS = 12n;
  const token0AmtAdjusted = (token0Amt * 10n ** TWELVE_DECIMALS) / 10n ** BigInt(token0Decimals);
  const token1AmtAdjusted = (token1Amt * 10n ** TWELVE_DECIMALS) / 10n ** BigInt(token1Decimals);

  return helpers._borrowAdjusted(
    token0AmtAdjusted,
    token1AmtAdjusted,
    slippage,
    dexFee,
    totalBorrowShares,
    debtReserves,
    pex
  );
}

/**
 * Calculates the shares to be burned for a payback operation.
 * @param {bigint} token0Amt - The amount of token0 to payback.
 * @param {bigint} token1Amt - The amount of token1 to payback.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance. (e.g., 1n for 100%).
 * @param {bigint} dexFee - The DEX fee.(1e6 for 100%)
 * @param {bigint} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @returns {Object} An object containing {shares, sharesWithSlippage, success}.
 */
function payback(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  dexFee,
  totalBorrowShares,
  debtReserves
) {
  // Adjust token amounts to 12 decimal places for internal calculations
  const TWELVE_DECIMALS = 12n;
  const token0AmtAdjusted = (token0Amt * 10n ** TWELVE_DECIMALS) / 10n ** BigInt(token0Decimals);
  const token1AmtAdjusted = (token1Amt * 10n ** TWELVE_DECIMALS) / 10n ** BigInt(token1Decimals);

  return helpers._paybackAdjusted(
    token0AmtAdjusted,
    token1AmtAdjusted,
    slippage,
    dexFee,
    totalBorrowShares,
    debtReserves
  );
}

/**
 * Calculates the token amount to be paid back for a payback operation.
 * @param {bigint} shares - The amount of shares to burn.
 * @param {bigint} paybackToken0Or1 - The token to payback in (0 for token0, 1 for token1).
 * @param {bigint} decimals0Or1 - The decimals of the token to payback.
 * @param {number} slippage - The slippage tolerance as a decimal (e.g., 1n for 100%).
 * @param {bigint} dexFee - The DEX fee as a decimal (1e6 for 100%)
 * @param {bigint} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {bigint} debtReserves.token0Debt - Debt of token0 in the debt pool.
 * @param {bigint} debtReserves.token1Debt - Debt of token1 in the debt pool.
 * @param {bigint} debtReserves.token0RealReserves - Real reserves of token0 in the debt pool.
 * @param {bigint} debtReserves.token1RealReserves - Real reserves of token1 in the debt pool.
 * @param {bigint} debtReserves.token0ImaginaryReserves - Imaginary reserves of token0 in the debt pool.
 * @param {bigint} debtReserves.token1ImaginaryReserves - Imaginary reserves of token1 in the debt pool.
 * @returns {Object} An object containing {tokenAmount, tokenAmountWithSlippage, success}.
 */
function paybackMax(shares, paybackToken0Or1, decimals0Or1, slippage, dexFee, totalBorrowShares, debtReserves) {
  return helpers._paybackPerfectInOneToken(
    shares,
    paybackToken0Or1,
    decimals0Or1,
    slippage,
    dexFee,
    totalBorrowShares,
    debtReserves
  );
}

/**
 * Calculates the shares to be minted for a deposit operation without slippage.
 * @param {bigint} token0Amt - The amount of token0 to deposit. If > 0, token1Amt must be 0.
 * @param {bigint} token1Amt - The amount of token1 to deposit. If > 0, token0Amt must be 0.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance in 12 decimal fixed point  (e.g., 1n for 100%).
 * @param {bigint} totalSupplyShares - The total supply of shares before the deposit.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing:
 * @returns {bigint} shares - The amount of shares to be minted for the deposit.
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the deposit to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the deposit to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function depositPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  totalSupplyShares,
  colReserves
) {
  let r_ = helpers._depositOrWithdrawPerfect(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    totalSupplyShares,
    colReserves
  );

  let shares = r_.shares;
  token0Amt = r_.token0Amt;
  token1Amt = r_.token1Amt;

  // Calculate amounts with slippage
  let token0AmtWithSlippage = BigInt(Math.floor(Number(token0Amt) * (1 + slippage)));
  let token1AmtWithSlippage = BigInt(Math.floor(Number(token1Amt) * (1 + slippage)));

  return {
    shares,
    token0Amt,
    token1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}

/**
 * Calculates the shares to be burned for a withdraw operation without slippage.
 * @param {bigint} token0Amt - The amount of token0 to withdraw. If > 0, token1Amt must be 0.
 * @param {bigint} token1Amt - The amount of token1 to withdraw. If > 0, token0Amt must be 0.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance in 12 decimal fixed point (e.g., 1n for 100%).
 * @param {bigint} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves.
 * @returns {Object} An object containing:
 * @returns {bigint} shares - The amount of shares to be burned for the withdraw.
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the withdraw to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the withdraw to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function withdrawPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  totalSupplyShares,
  colReserves
) {

  let r_ = helpers._depositOrWithdrawPerfect(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    totalSupplyShares,
    colReserves
  );

  let shares = r_.shares;
  token0Amt = r_.token0Amt;
  token1Amt = r_.token1Amt;

  // Calculate amounts with slippage
  let token0AmtWithSlippage = BigInt(Math.floor(Number(token0Amt) * (1 - slippage)));
  let token1AmtWithSlippage = BigInt(Math.floor(Number(token1Amt) * (1 - slippage)));

  return {
    shares,
    token0Amt,
    token1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}

/**
 * Calculates the token amount to be withdrawn for a withdraw operation without slippage.
 * @param {bigint} shares - The amount of shares to burn.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance in basis points (e.g., 1n for 100%).
 * @param {bigint} totalSupplyShares - The total supply of shares before the withdraw.
 * @param {Object} colReserves - The current collateral reserves containing BigInt values:
 * @param {bigint} colReserves.token0RealReserves - The actual reserves of token0
 * @param {bigint} colReserves.token1RealReserves - The actual reserves of token1
 * @returns {Object} An object containing BigInt values:
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the withdraw to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the withdraw to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function withdrawPerfectMax(shares, token0Decimals, token1Decimals, slippage, totalSupplyShares, colReserves) {
  const PRECISION = 12n; // Standard precision used in the original calculation

  // Calculate token amounts adjusted for share ratio
  // Multiply before division to maintain precision
  const token0AmtAdjusted = (shares * colReserves.token0RealReserves) / totalSupplyShares;
  const token1AmtAdjusted = (shares * colReserves.token1RealReserves) / totalSupplyShares;

  // Adjust for decimals difference
  // Using BigInt exponential calculation
  const token0Amt = (token0AmtAdjusted * 10n ** token0Decimals) / 10n ** PRECISION;
  const token1Amt = (token1AmtAdjusted * 10n ** token1Decimals) / 10n ** PRECISION;

  const token0AmtWithSlippage = BigInt(Math.floor(Number(token0Amt) * (1 - slippage)));
  const token1AmtWithSlippage = BigInt(Math.floor(Number(token1Amt) * (1 - slippage)));

  return {
    token0Amt,
    token1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}
/**
 * Calculates the shares to be minted for a borrow operation without slippage.
 * @param {bigint} token0Amt - The amount of token0 to borrow. If > 0n, token1Amt must be 0n.
 * @param {bigint} token1Amt - The amount of token1 to borrow. If > 0n, token0Amt must be 0n.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance in basis points (e.g., 1n for 100%).
 * @param {bigint} totalBorrowShares - The total supply of shares before the borrow.
 * @param {Object} debtReserves - The current debt reserves (assumed to contain BigInt values).
 * @returns {Object} An object containing BigInt values:
 * @returns {bigint} shares - The amount of shares to be minted for the borrow.
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the borrow to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the borrow to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The minimum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The minimum amount of token1 that could be needed accounting for slippage.
 */
function borrowPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  totalBorrowShares,
  debtReserves
) {
  // Call helper function (assumed to be updated to work with BigInt)
  const r_ = helpers._borrowOrPaybackPerfect(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    totalBorrowShares,
    debtReserves
  );

  // No need for toFixed() as we're working with BigInt
  const shares = r_.shares;
  const finalToken0Amt = r_.token0Amt;
  const finalToken1Amt = r_.token1Amt;

  // Calculate slippage amounts
  const token0AmtWithSlippage = BigInt(Math.floor(Number(finalToken0Amt) * (1 - slippage)));
  const token1AmtWithSlippage = BigInt(Math.floor(Number(finalToken1Amt) * (1 - slippage)));

  return {
    shares,
    token0Amt: finalToken0Amt,
    token1Amt: finalToken1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}
/**
 * Calculates the shares to be burned for a payback operation without slippage.
 * @param {bigint} token0Amt - The amount of token0 to payback. If > 0n, token1Amt must be 0n.
 * @param {bigint} token1Amt - The amount of token1 to payback. If > 0n, token0Amt must be 0n.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance in basis points (e.g., 1n for 100%).
 * @param {bigint} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves (assumed to contain BigInt values).
 * @returns {Object} An object containing BigInt values:
 * @returns {bigint} shares - The amount of shares to be burned for the payback.
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the payback to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the payback to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function paybackPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  totalBorrowShares,
  debtReserves
) {
  // Call helper function (assumed to be updated to work with BigInt)
  const r_ = helpers._borrowOrPaybackPerfect(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    totalBorrowShares,
    debtReserves
  );

  // No need for toFixed() as we're working with BigInt
  const shares = r_.shares;
  const finalToken0Amt = r_.token0Amt;
  const finalToken1Amt = r_.token1Amt;

  // Calculate slippage amounts
  const token0AmtWithSlippage = BigInt(Math.floor(Number(finalToken0Amt) * (1 + slippage)));
  const token1AmtWithSlippage = BigInt(Math.floor(Number(finalToken1Amt) * (1 + slippage)));

  return {
    shares,
    token0Amt: finalToken0Amt,
    token1Amt: finalToken1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}
/**
 * Calculates the token amount to be paid back for a payback operation without slippage.
 * All numeric inputs and outputs are BigInt.
 * @param {bigint} shares - The amount of shares to burn.
 * @param {bigint} token0Decimals - The decimals of token0.
 * @param {bigint} token1Decimals - The decimals of token1.
 * @param {number} slippage - The slippage tolerance (e.g., 1n for 100%)
 * @param {bigint} totalBorrowShares - The total supply of shares before the payback.
 * @param {Object} debtReserves - The current debt reserves.
 * @param {bigint} debtReserves.token0Debt - The current debt of token0.
 * @param {bigint} debtReserves.token1Debt - The current debt of token1.
 * @returns {Object} An object containing BigInt values:
 * @returns {bigint} token0Amt - The actual amount of token0 needed for the payback to maintain the pool ratio.
 * @returns {bigint} token1Amt - The actual amount of token1 needed for the payback to maintain the pool ratio.
 * @returns {bigint} token0AmtWithSlippage - The maximum amount of token0 that could be needed accounting for slippage.
 * @returns {bigint} token1AmtWithSlippage - The maximum amount of token1 that could be needed accounting for slippage.
 */
function paybackPerfectMax(shares, token0Decimals, token1Decimals, slippage, totalBorrowShares, debtReserves) {
  // Constants
  const PRECISION_DECIMALS = 12n;
  const PRECISION_SCALE = 10n ** PRECISION_DECIMALS;

  // Calculate base amounts with high precision
  const token0AmtAdjusted = (shares * debtReserves.token0Debt) / totalBorrowShares;
  const token1AmtAdjusted = (shares * debtReserves.token1Debt) / totalBorrowShares;

  // Scale to proper token decimals
  const token0Scale = 10n ** token0Decimals;
  const token1Scale = 10n ** token1Decimals;

  const token0Amt = (token0AmtAdjusted * token0Scale) / PRECISION_SCALE;
  const token1Amt = (token1AmtAdjusted * token1Scale) / PRECISION_SCALE;

  // Calculate amounts with slippage
  const token0AmtWithSlippage = BigInt(Math.floor(Number(token0Amt) * (1 + slippage)));
  const token1AmtWithSlippage = BigInt(Math.floor(Number(token1Amt) * (1 + slippage)));

  return {
    token0Amt,
    token1Amt,
    token0AmtWithSlippage,
    token1AmtWithSlippage,
  };
}

module.exports = {
  deposit,
  withdraw,
  borrow,
  payback,

  depositPerfect,
  withdrawPerfect,
  borrowPerfect,
  paybackPerfect,

  withdrawMax,
  paybackMax,

  withdrawPerfectMax,
  paybackPerfectMax,
};
