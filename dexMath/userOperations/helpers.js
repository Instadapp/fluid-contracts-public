function _getUpdatedColReserves(newShares, totalOldShares, colReserves, mintOrBurn) {
  let updatedReserves = {};

  if (mintOrBurn) {
    // If minting, increase reserves proportionally to new shares
    updatedReserves.token0RealReserves =
      colReserves.token0RealReserves + (colReserves.token0RealReserves * newShares) / totalOldShares;
    updatedReserves.token1RealReserves =
      colReserves.token1RealReserves + (colReserves.token1RealReserves * newShares) / totalOldShares;
    updatedReserves.token0ImaginaryReserves =
      colReserves.token0ImaginaryReserves + (colReserves.token0ImaginaryReserves * newShares) / totalOldShares;
    updatedReserves.token1ImaginaryReserves =
      colReserves.token1ImaginaryReserves + (colReserves.token1ImaginaryReserves * newShares) / totalOldShares;
  } else {
    // If burning, decrease reserves proportionally to burned shares
    updatedReserves.token0RealReserves =
      colReserves.token0RealReserves - (colReserves.token0RealReserves * newShares) / totalOldShares;
    updatedReserves.token1RealReserves =
      colReserves.token1RealReserves - (colReserves.token1RealReserves * newShares) / totalOldShares;
    updatedReserves.token0ImaginaryReserves =
      colReserves.token0ImaginaryReserves - (colReserves.token0ImaginaryReserves * newShares) / totalOldShares;
    updatedReserves.token1ImaginaryReserves =
      colReserves.token1ImaginaryReserves - (colReserves.token1ImaginaryReserves * newShares) / totalOldShares;
  }

  return updatedReserves;
}

// ##################### DEPOSIT #####################

/**
 * Calculates swap and deposit amounts
 * @param {bigint} c First input parameter
 * @param {bigint} d Second input parameter
 * @param {bigint} e Third input parameter
 * @param {bigint} f Fourth input parameter
 * @param {bigint} i Fifth input parameter
 * @returns {bigint} Calculated shares
 */
function _getSwapAndDeposit(c, d, e, f, i) {
  const SIX_DECIMALS = 1000000n; // 10^6 as BigInt

  // temp_ => B/i
  let temp = (c * d + d * f + e * i - c * i) / i;
  let temp2 = 4n * c * e;
  let amtToSwap = (calculateSquareRoot(temp2 + temp * temp) - temp) / 2n;

  // Ensure the amount to swap is within reasonable bounds
  if (amtToSwap > (c * (SIX_DECIMALS - 1n)) / SIX_DECIMALS || amtToSwap < c / SIX_DECIMALS) {
    throw new Error("SwapAndDepositTooLowOrTooHigh");
  }

  // temp_ => amt0ToDeposit
  temp = c - amtToSwap;
  // temp2_ => amt1ToDeposit_
  temp2 = (d * amtToSwap) / (e + amtToSwap);

  // temp_ => shares1
  temp = (temp * 10n ** 18n) / (f + amtToSwap);
  // temp2_ => shares1
  temp2 = (temp2 * 10n ** 18n) / (i - temp2);

  // Return the smaller of temp and temp2
  return temp > temp2 ? temp2 : temp;
}

function _depositAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalSupplyShares, colReserves) {
  const PRECISION = 10n ** 18n;
  let temp = 0n;
  let temp2 = 0n;
  let shares = 0n;
  let sharesWithSlippage = 0n;

  if (token0AmtAdjusted > 0n && token1AmtAdjusted > 0n) {
    // mint shares in equal proportion
    // temp_ => expected shares from token0 deposit
    temp = (token0AmtAdjusted * PRECISION) / colReserves.token0RealReserves;
    // temp2_ => expected shares from token1 deposit
    temp2 = (token1AmtAdjusted * PRECISION) / colReserves.token1RealReserves;

    if (temp > temp2) {
      // use temp2_ shares
      shares = (temp2 * totalSupplyShares) / PRECISION;
      // temp_ => token0 to swap
      temp = ((temp - temp2) * colReserves.token0RealReserves) / PRECISION;
      temp2 = 0n;
    } else if (temp2 > temp) {
      // use temp shares
      shares = (temp * totalSupplyShares) / PRECISION;
      // temp2 => token1 to swap
      temp2 = ((temp2 - temp) * colReserves.token1RealReserves) / PRECISION;
      temp = 0n;
    } else {
      // if equal then throw error as swap will not be needed anymore which can create some issue, better to use depositPerfect in this case
      return { shares: 0n, sharesWithSlippage: 0n, success: false };
    }

    // User deposited in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
    colReserves = _getUpdatedColReserves(shares, totalSupplyShares, colReserves, true);

    totalSupplyShares += shares;
  } else if (token0AmtAdjusted > 0n) {
    temp = token0AmtAdjusted;
    temp2 = 0n;
  } else if (token1AmtAdjusted > 0n) {
    temp = 0n;
    temp2 = token1AmtAdjusted;
  } else {
    // user sent both amounts as 0
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  if (temp > 0n) {
    // swap token0
    temp = _getSwapAndDeposit(
      temp, // token0 to divide and swap
      colReserves.token1ImaginaryReserves, // token1 imaginary reserves
      colReserves.token0ImaginaryReserves, // token0 imaginary reserves
      colReserves.token0RealReserves, // token0 real reserves
      colReserves.token1RealReserves // token1 real reserves
    );
  } else if (temp2 > 0n) {
    // swap token1
    temp = _getSwapAndDeposit(
      temp2, // token1 to divide and swap
      colReserves.token0ImaginaryReserves, // token0 imaginary reserves
      colReserves.token1ImaginaryReserves, // token1 imaginary reserves
      colReserves.token1RealReserves, // token1 real reserves
      colReserves.token0RealReserves // token0 real reserves
    );
  } else {
    // maybe possible to happen due to some precision issue that both are 0
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  // new shares minted from swap & deposit
  temp = (temp * totalSupplyShares) / PRECISION;

  // adding fee in case of swap & deposit
  // 1 - fee. If fee is 1% then without fee will be BigInt(1e6) - 1e4
  // temp => withdraw fee
  // const HUNDRED_PERCENT = 10n ** 6n;
  temp = (temp * (BigInt(1e6) - dexFee)) / BigInt(1e6);

  // final new shares to mint for user
  shares += temp;

  // Calculate shares with slippage 
  sharesWithSlippage = BigInt(Math.floor(Number(shares) * (1 - slippage)));

  return {
    shares: shares,
    sharesWithSlippage: sharesWithSlippage,
    success: true,
  };
}

// ##################### DEPOSIT END #####################

// ##################### WITHDRAW #####################

function _getWithdrawAndSwap(c_, d_, e_, f_, g_) {
  // Constants
  const SIX_DECIMALS = 1000000n;
  const EIGHTEEN_DECIMALS = 10n ** 18n;

  // temp_ = B/2A = (d * e + 2 * c * d + c * f) / (2 * d)
  const temp = (d_ * e_ + 2n * c_ * d_ + c_ * f_) / (2n * d_);

  // temp2_ = (((c * f) / d) + c) * g
  const temp2 = ((c_ * f_) / d_ + c_) * g_;

  // tokenAxa = temp - calculateSquareRoot((temp * temp) - temp2)
  const tempSquared = temp * temp;
  const tokenAxa = temp - calculateSquareRoot(tempSquared - temp2);

  // Ensure the amount to withdraw is within reasonable bounds
  const upperBound = (g_ * (SIX_DECIMALS - 1n)) / SIX_DECIMALS;
  const lowerBound = g_ / SIX_DECIMALS;

  if (tokenAxa > upperBound || tokenAxa < lowerBound) {
    throw new Error("WithdrawAndSwapTooLowOrTooHigh");
  }

  // shares_ = (tokenAxa * 1e18) / c
  const shares = (tokenAxa * EIGHTEEN_DECIMALS) / c_;

  return shares;
}

/**
 * Calculates reserves outside range for a liquidity pool
 * @param {bigint} geometricMeanPrice - Geometric mean of upper and lower price bounds
 * @param {bigint} priceAtRange - Price at range boundary (upper or lower)
 * @param {bigint} reserveX - Real reserves of token X
 * @param {bigint} reserveY - Real reserves of token Y
 * @returns {[bigint, bigint]} - [reserveXOutside, reserveYOutside]
 */
function _calculateReservesOutsideRange(geometricMeanPrice, priceAtRange, reserveX, reserveY) {
  // Scale factor for price precision (equivalent to 1e27 in Solidity)
  const SCALE = 10n ** 27n;

  // Calculate the three parts of the quadratic equation solution
  const part1 = priceAtRange - geometricMeanPrice;

  // Calculate part2 with BigInt division and multiplication
  const part2 = (geometricMeanPrice * reserveX + reserveY * SCALE) / (2n * part1);

  // Handle potential overflow like in Solidity
  let part3 = reserveX * reserveY;
  part3 = part3 < 10n ** 50n ? (part3 * SCALE) / part1 : (part3 / part1) * SCALE;

  // Calculate square root for BigInt
  // Note: This is an approximate integer square root

  // Calculate reserveXOutside
  const reserveXOutside = part2 + calculateSquareRoot(part3 + part2 * part2);

  // Calculate yb (reserveYOutside)
  const reserveYOutside = (reserveXOutside * geometricMeanPrice) / SCALE;

  return { reserveXOutside, reserveYOutside };
}
function _withdrawAdjusted(
  token0AmtAdjusted,
  token1AmtAdjusted,
  slippage,
  dexFee,
  totalSupplyShares,
  colReserves,
  pex
) {
  const PRECISION = 10n ** 18n;
  const HUNDRED_PERCENT = 10n ** 6n;

  let temp = 0n;
  let temp2 = 0n;
  let shares = 0n;
  let sharesWithSlippage = 0n;

  if (token0AmtAdjusted > 0n && token1AmtAdjusted > 0n) {
    // Calculate expected shares for each token
    temp = (token0AmtAdjusted * PRECISION) / colReserves.token0RealReserves;
    temp2 = (token1AmtAdjusted * PRECISION) / colReserves.token1RealReserves;

    if (temp > temp2) {
      shares = (temp2 * totalSupplyShares) / PRECISION;
      temp = ((temp - temp2) * colReserves.token0RealReserves) / PRECISION;
      temp2 = 0n;
    } else if (temp2 > temp) {
      shares = (temp * totalSupplyShares) / PRECISION;
      temp2 = ((temp2 - temp) * colReserves.token1RealReserves) / PRECISION;
      temp = 0n;
    } else {
      return { shares: 0n, sharesWithSlippage: 0n, success: false };
    }

    // Update reserves and total supply shares
    colReserves.token0RealReserves -= (colReserves.token0RealReserves * shares) / totalSupplyShares;
    colReserves.token1RealReserves -= (colReserves.token1RealReserves * shares) / totalSupplyShares;
    colReserves.token0ImaginaryReserves -= (colReserves.token0ImaginaryReserves * shares) / totalSupplyShares;
    colReserves.token1ImaginaryReserves -= (colReserves.token1ImaginaryReserves * shares) / totalSupplyShares;

    totalSupplyShares -= shares;
  } else if (token0AmtAdjusted > 0n) {
    temp = token0AmtAdjusted;
    temp2 = 0n;
  } else if (token1AmtAdjusted > 0n) {
    temp = 0n;
    temp2 = token1AmtAdjusted;
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  let token0ImaginaryReservesOutsideRange;
  let token1ImaginaryReservesOutsideRange;

  // Using BigInt-compatible large number representation
  const LARGE_PRECISION = 10n ** 54n;

  if (pex.geometricMean < LARGE_PRECISION) {
    const ob_ = _calculateReservesOutsideRange(
      pex.geometricMean,
      pex.upperRange,
      colReserves.token0RealReserves - temp,
      colReserves.token1RealReserves - temp2
    );
    token0ImaginaryReservesOutsideRange = ob_.reserveXOutside;
    token1ImaginaryReservesOutsideRange = ob_.reserveYOutside;
  } else {
    const ob_ = _calculateReservesOutsideRange(
      LARGE_PRECISION / pex.geometricMean,
      LARGE_PRECISION / pex.lowerRange,
      colReserves.token1RealReserves - temp2,
      colReserves.token0RealReserves - temp
    );
    token0ImaginaryReservesOutsideRange = ob_.reserveYOutside;
    token1ImaginaryReservesOutsideRange = ob_.reserveXOutside;
  }

  if (temp > 0n) {
    temp = _getWithdrawAndSwap(
      colReserves.token0RealReserves,
      colReserves.token1RealReserves,
      token0ImaginaryReservesOutsideRange,
      token1ImaginaryReservesOutsideRange,
      temp
    );
  } else if (temp2 > 0n) {
    temp = _getWithdrawAndSwap(
      colReserves.token1RealReserves,
      colReserves.token0RealReserves,
      token1ImaginaryReservesOutsideRange,
      token0ImaginaryReservesOutsideRange,
      temp2
    );
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  // Calculate shares to burn from withdraw & swap
  temp = (temp * totalSupplyShares) / PRECISION;

  // Add fee (using BigInt percentage calculation)
  temp = (temp * (BigInt(1e6) + dexFee)) / BigInt(1e6);

  // Update shares to burn for user
  shares += temp;

  // Calculate shares with slippage
  sharesWithSlippage = BigInt(Math.floor(Number(shares) * (1 + slippage)));

  return {
    shares: shares,
    sharesWithSlippage: sharesWithSlippage,
    success: true,
  };
}
// ##################### WITHDRAW END #####################

// ##################### WITHDRAW PERFECT IN ONE TOKEN #####################

/**
 * Calculates the output amount for a given input amount and reserves
 * @param {BigInt} amountIn - The amount of input asset
 * @param {BigInt} iReserveIn - Imaginary token reserve of input amount
 * @param {BigInt} iReserveOut - Imaginary token reserve of output amount
 * @returns {BigInt} The calculated output amount
 */
function _getAmountOut(amountIn, iReserveIn, iReserveOut) {
  // Calculate numerator and denominator
  const numerator = amountIn * iReserveOut;
  const denominator = iReserveIn + amountIn;

  // Calculate and return the output amount
  // Note: Using BigInt division to mimic Solidity's behavior
  return numerator / denominator;
}
function _withdrawPerfectInOneToken(
  shares,
  withdrawToken0Or1,
  decimals0Or1,
  slippage, // Expecting slippage as fixed point number with 12 decimals
  dexFee, // Expecting dexFee as fixed point number with 12 decimals
  totalSupplyShares,
  colReserves
) {
  let tokenAmount = 0n;
  let tokenAmountWithSlippage = 0n;

  // Constants for calculations
  const PRECISION = 12n;
  const BASE = 10n ** PRECISION;

  if (colReserves.token0RealReserves === 0n || colReserves.token1RealReserves === 0n) {
    return {
      tokenAmount: 0n,
      tokenAmountWithSlippage: 0n,
      success: false,
    };
  }

  const updatedReserves = _getUpdatedColReserves(shares, totalSupplyShares, colReserves, false);

  let token0Amount = colReserves.token0RealReserves - updatedReserves.token0RealReserves - 1n;
  let token1Amount = colReserves.token1RealReserves - updatedReserves.token1RealReserves - 1n;

  if (withdrawToken0Or1 === 0n) {
    // Withdraw in token0
    tokenAmount = token0Amount;
    tokenAmount += _getAmountOut(
      token1Amount,
      updatedReserves.token1ImaginaryReserves,
      updatedReserves.token0ImaginaryReserves
    );
  } else if (withdrawToken0Or1 === 1n) {
    // Withdraw in token1
    tokenAmount = token1Amount;
    tokenAmount += _getAmountOut(
      token0Amount,
      updatedReserves.token0ImaginaryReserves,
      updatedReserves.token1ImaginaryReserves
    );
  } else {
    return {
      tokenAmount: 0n,
      tokenAmountWithSlippage: 0n,
      success: false,
    };
  }

  // Apply DEX fee
  tokenAmount = (tokenAmount * (BigInt(1e6) - dexFee)) / BigInt(1e6);

  // Adjust decimals
  const decimalAdjustment = 10n ** decimals0Or1;
  tokenAmount = (tokenAmount * decimalAdjustment) / BASE;

  // Apply slippage
  tokenAmountWithSlippage = BigInt(Math.floor(Number(tokenAmount) * (1 - slippage)));

  return {
    tokenAmount,
    tokenAmountWithSlippage,
    success: true,
  };
}

// ##################### WITHDRAW PERFECT IN ONE TOKEN END #####################

// ##################### BORROW #####################

function _getBorrowAndSwap(c, d, e, f, g) {
  const E18 = 1n * 10n ** 18n;

  // Calculate temp_ = B/2A
  const temp = (c * f + d * e + d * g) / (2n * d);

  // Calculate temp2_ = C / A
  const temp2 = (c * f * g) / d;

  // Calculate square root using Newton's method
  const sqrtPart = calculateSquareRoot(temp * temp - temp2);

  // Calculate tokenAxa = (-B - (B^2 - 4AC)^0.5) / 2A
  const tokenAxa = temp - sqrtPart;

  // Rounding up borrow shares to mint for user
  const shares = ((tokenAxa + 1n) * E18) / c;

  return shares;
}

/**
 * Calculate square root for BigInt using Newton's method
 * @param {bigint} n - Number to calculate square root for
 * @returns {bigint} Integer square root
 */
function calculateSquareRoot(n) {
  if (n <= 1n) return n;

  let x = n;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + n / x) / 2n;
  }
  return x;
}

function _getUpdateDebtReserves(shares, totalShares, debtReserves, mintOrBurn) {
  let updatedDebtReserves = {
    token0Debt: 0,
    token1Debt: 0,
    token0RealReserves: 0,
    token1RealReserves: 0,
    token0ImaginaryReserves: 0,
    token1ImaginaryReserves: 0,
  };

  if (mintOrBurn) {
    updatedDebtReserves.token0Debt = debtReserves.token0Debt + (debtReserves.token0Debt * shares) / totalShares;
    updatedDebtReserves.token1Debt = debtReserves.token1Debt + (debtReserves.token1Debt * shares) / totalShares;
    updatedDebtReserves.token0RealReserves =
      debtReserves.token0RealReserves + (debtReserves.token0RealReserves * shares) / totalShares;
    updatedDebtReserves.token1RealReserves =
      debtReserves.token1RealReserves + (debtReserves.token1RealReserves * shares) / totalShares;
    updatedDebtReserves.token0ImaginaryReserves =
      debtReserves.token0ImaginaryReserves + (debtReserves.token0ImaginaryReserves * shares) / totalShares;
    updatedDebtReserves.token1ImaginaryReserves =
      debtReserves.token1ImaginaryReserves + (debtReserves.token1ImaginaryReserves * shares) / totalShares;
  } else {
    updatedDebtReserves.token0Debt = debtReserves.token0Debt - (debtReserves.token0Debt * shares) / totalShares;
    updatedDebtReserves.token1Debt = debtReserves.token1Debt - (debtReserves.token1Debt * shares) / totalShares;
    updatedDebtReserves.token0RealReserves =
      debtReserves.token0RealReserves - (debtReserves.token0RealReserves * shares) / totalShares;
    updatedDebtReserves.token1RealReserves =
      debtReserves.token1RealReserves - (debtReserves.token1RealReserves * shares) / totalShares;
    updatedDebtReserves.token0ImaginaryReserves =
      debtReserves.token0ImaginaryReserves - (debtReserves.token0ImaginaryReserves * shares) / totalShares;
    updatedDebtReserves.token1ImaginaryReserves =
      debtReserves.token1ImaginaryReserves - (debtReserves.token1ImaginaryReserves * shares) / totalShares;
  }

  return updatedDebtReserves;
}
/**
 * Calculates debt reserves for both tokens in a pool
 * @param {bigint} geometricMean - Geometric mean of upper and lower price ranges (in 1e27 decimals)
 * @param {bigint} lowerPrice - Lower price range (in 1e27 decimals)
 * @param {bigint} debtA - Debt amount of token A
 * @param {bigint} debtB - Debt amount of token B
 * @returns {Object} Object containing real and imaginary reserves for both tokens
 */
function _calculateDebtReserves(geometricMean, lowerPrice, debtA, debtB) {
  const E27 = 1n * 10n ** 27n;
  const SIX_DECIMALS = 1n * 10n ** 6n;
  const E25 = 1n * 10n ** 25n;
  const E50 = 1n * 10n ** 50n;

  // Calculate realDebtReserveB (ry_)
  // part1 = ((debtA * geometricMean) - (debtB * 1e27)) / (2 * 1e27)
  const part1 = (debtA * geometricMean - debtB * E27) / (2n * E27);

  // part2 = (debtA * debtB * lowerPrice) / 1e27
  let part2 = debtA * debtB;
  part2 = part2 < E50 ? (part2 * lowerPrice) / E27 : (part2 / E27) * lowerPrice;

  // Calculate square root of part2 + part1^2 using Newton's method
  const realDebtReserveB = calculateSquareRoot(part2 + part1 * part1) + part1;

  // Calculate imaginaryDebtReserveB (iry_)
  // iry_ = ((ry_ * 1e27) - (debtA * lowerPrice))
  let imaginaryDebtReserveB = realDebtReserveB * E27 - debtA * lowerPrice;

  if (imaginaryDebtReserveB < SIX_DECIMALS) {
    throw new Error("Debt reserves too low");
  }

  // Adjust imaginaryDebtReserveB based on realDebtReserveB size
  if (realDebtReserveB < E25) {
    imaginaryDebtReserveB = (realDebtReserveB * realDebtReserveB * E27) / imaginaryDebtReserveB;
  } else {
    imaginaryDebtReserveB = (realDebtReserveB * realDebtReserveB) / (imaginaryDebtReserveB / E27);
  }

  // Calculate imaginaryDebtReserveA (irx_)
  // irx_ = ((iry_ * debtA) / ry_) - debtA
  const imaginaryDebtReserveA = (imaginaryDebtReserveB * debtA) / realDebtReserveB - debtA;

  // Calculate realDebtReserveA (rx_)
  // rx_ = (irx_ * debtB) / (iry_ + debtB)
  const realDebtReserveA = (imaginaryDebtReserveA * debtB) / (imaginaryDebtReserveB + debtB);

  return {
    realDebtReserveA,
    realDebtReserveB,
    imaginaryDebtReserveA,
    imaginaryDebtReserveB,
  };
}

function _borrowAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalBorrowShares, debtReserves, pex) {
  const EIGHTEEN_DECIMALS = 10n ** 18n;
  const TWENTY_SEVEN_DECIMALS = 10n ** 27n;
  const FIFTY_FOUR_DECIMALS = 10n ** 54n;

  let temp;
  let temp2;
  let shares = 0n;
  let sharesWithSlippage = 0n;

  if (token0AmtAdjusted > 0n && token1AmtAdjusted > 0n) {
    // Mint shares in equal proportion
    temp = (token0AmtAdjusted * EIGHTEEN_DECIMALS) / debtReserves.token0Debt;
    temp2 = (token1AmtAdjusted * EIGHTEEN_DECIMALS) / debtReserves.token1Debt;

    if (temp > temp2) {
      shares = (temp2 * totalBorrowShares) / EIGHTEEN_DECIMALS;
      temp = ((temp - temp2) * debtReserves.token0Debt) / EIGHTEEN_DECIMALS;
      temp2 = 0n;
    } else if (temp2 > temp) {
      shares = (temp * totalBorrowShares) / EIGHTEEN_DECIMALS;
      temp2 = ((temp2 - temp) * debtReserves.token1Debt) / EIGHTEEN_DECIMALS;
      temp = 0n;
    } else {
      return { shares: 0n, sharesWithSlippage: 0n, success: false };
    }

    // User borrowed in equal proportion here. Hence updating col reserves and the swap will happen on updated col reserves
    debtReserves = _getUpdateDebtReserves(shares, totalBorrowShares, debtReserves, true);
    totalBorrowShares += shares;
  } else if (token0AmtAdjusted > 0n) {
    temp = token0AmtAdjusted;
    temp2 = 0n;
  } else if (token1AmtAdjusted > 0n) {
    temp = 0n;
    temp2 = token1AmtAdjusted;
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  let token0FinalImaginaryReserves;
  let token1FinalImaginaryReserves;

  if (pex.geometricMean < TWENTY_SEVEN_DECIMALS) {
    const ob_ = _calculateDebtReserves(
      pex.geometricMean,
      pex.lowerRange,
      debtReserves.token0Debt + temp,
      debtReserves.token1Debt + temp2
    );
    token0FinalImaginaryReserves = ob_.imaginaryDebtReserveA;
    token1FinalImaginaryReserves = ob_.imaginaryDebtReserveB;
  } else {
    const ob_ = _calculateDebtReserves(
      FIFTY_FOUR_DECIMALS / pex.geometricMean,
      FIFTY_FOUR_DECIMALS / pex.upperRange,
      debtReserves.token1Debt + temp2,
      debtReserves.token0Debt + temp
    );
    token0FinalImaginaryReserves = ob_.imaginaryDebtReserveB;
    token1FinalImaginaryReserves = ob_.imaginaryDebtReserveA;
  }

  if (temp > 0n) {
    // Swap into token0
    temp = _getBorrowAndSwap(
      debtReserves.token0Debt,
      debtReserves.token1Debt,
      token0FinalImaginaryReserves,
      token1FinalImaginaryReserves,
      temp
    );
  } else if (temp2 > 0n) {
    // Swap into token1
    temp = _getBorrowAndSwap(
      debtReserves.token1Debt,
      debtReserves.token0Debt,
      token1FinalImaginaryReserves,
      token0FinalImaginaryReserves,
      temp2
    );
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  // New shares to mint from borrow & swap
  temp = (temp * totalBorrowShares) / EIGHTEEN_DECIMALS;

  // Adding fee in case of borrow & swap
  temp = (temp * (BigInt(1e6) + dexFee)) / BigInt(1e6);

  // Final new shares to mint for user
  shares += temp;

  // Calculate shares with slippage
  sharesWithSlippage = BigInt(Math.floor(Number(shares) * (1 + slippage)));

  // Convert to BigInt integers
  shares = BigInt(Math.floor(Number(shares)));
  sharesWithSlippage = BigInt(Math.floor(Number(sharesWithSlippage)));

  return { shares, sharesWithSlippage, success: true };
}

// ##################### BORROW END #####################

// ##################### PAYBACK #####################

function _getSwapAndPayback(c, d, e, f, g) {
  const EIGHTEEN_DECIMALS = 10n ** 18n;

  // Calculate temp_ as B/A
  let temp = (c * f + d * e - f * g - d * g) / d;

  // Calculate temp2_ as -AC / A^2
  let temp2 = 4n * e * g;

  // Calculate the amount to swap
  let amtToSwap = (calculateSquareRoot(temp2 + temp * temp) - temp) / 2n;

  // Calculate amt0ToPayback
  let amt0ToPayback = g - amtToSwap;

  // Calculate amt1ToPayback
  let amt1ToPayback = (f * amtToSwap) / (e + amtToSwap);

  // Calculate shares0
  let shares0 = (amt0ToPayback * EIGHTEEN_DECIMALS) / (c - amtToSwap);

  // Calculate shares1
  let shares1 = (amt1ToPayback * EIGHTEEN_DECIMALS) / (d + amt1ToPayback);

  // Return the lower of shares0 and shares1
  return shares0 < shares1 ? shares0 : shares1;
}
function _paybackAdjusted(token0AmtAdjusted, token1AmtAdjusted, slippage, dexFee, totalBorrowShares, debtReserves) {
  const EIGHTEEN_DECIMALS = 10n ** 18n;

  let temp;
  let temp2;
  let shares = 0n;
  let sharesWithSlippage = 0n;

  if (token0AmtAdjusted > 0n && token1AmtAdjusted > 0n) {
    // Calculate expected shares from token0 and token1 payback
    temp = (token0AmtAdjusted * EIGHTEEN_DECIMALS) / debtReserves.token0Debt;
    temp2 = (token1AmtAdjusted * EIGHTEEN_DECIMALS) / debtReserves.token1Debt;

    if (temp > temp2) {
      shares = (temp2 * totalBorrowShares) / EIGHTEEN_DECIMALS;
      temp = token0AmtAdjusted - (temp2 * token0AmtAdjusted) / temp;
      temp2 = 0n;
    } else if (temp2 > temp) {
      shares = (temp * totalBorrowShares) / EIGHTEEN_DECIMALS;
      temp2 = token1AmtAdjusted - (temp * token1AmtAdjusted) / temp2;
      temp = 0n;
    } else {
      return { shares: 0n, sharesWithSlippage: 0n, success: false };
    }

    // Update debt reserves
    debtReserves = _getUpdateDebtReserves(shares, totalBorrowShares, debtReserves, false);
    totalBorrowShares -= shares;
  } else if (token0AmtAdjusted > 0n) {
    temp = token0AmtAdjusted;
    temp2 = 0n;
  } else if (token1AmtAdjusted > 0n) {
    temp = 0n;
    temp2 = token1AmtAdjusted;
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  if (temp > 0n) {
    temp = _getSwapAndPayback(
      debtReserves.token0Debt,
      debtReserves.token1Debt,
      debtReserves.token0ImaginaryReserves,
      debtReserves.token1ImaginaryReserves,
      temp
    );
  } else if (temp2 > 0n) {
    temp = _getSwapAndPayback(
      debtReserves.token1Debt,
      debtReserves.token0Debt,
      debtReserves.token1ImaginaryReserves,
      debtReserves.token0ImaginaryReserves,
      temp2
    );
  } else {
    return { shares: 0n, sharesWithSlippage: 0n, success: false };
  }

  // Calculate new shares to burn
  temp = (temp * totalBorrowShares) / EIGHTEEN_DECIMALS;

  // Handle dexFee with BigInt calculation
  temp = (temp * (BigInt(1e6) - dexFee)) / BigInt(1e6);

  shares += temp;

  sharesWithSlippage = BigInt(Math.floor(Number(shares) * (1 - slippage)));

  // Convert to BigInt integers
  shares = BigInt(Math.floor(Number(shares)));
  sharesWithSlippage = BigInt(Math.floor(Number(sharesWithSlippage)));

  return { shares, sharesWithSlippage, success: true };
}

// ##################### PAYBACK END #####################

// ##################### PAYBACK PERFECT IN ONE TOKEN #####################

function _getSwapAndPaybackOneTokenPerfectShares(a, b, c, d, i, j) {
  // Calculate reserves outside range
  const l = a - i;
  const m = b - j;

  // Calculate new K or final K
  const w = a * b;

  // Calculate final reserves
  const z = w / l;
  const y = w / m;
  const v = z - m - d;
  const x = (v * y) / (m + v);

  // Calculate amount to payback
  const tokenAmt = c - x;

  return tokenAmt;
}
function _paybackPerfectInOneToken(
  shares,
  paybackToken0Or1,
  decimals0Or1,
  slippage,
  dexFee,
  totalBorrowShares,
  debtReserves
) {
  let tokenAmount = 0n;
  let tokenAmountWithSlippage = 0n;
  let token0CurrentDebt = debtReserves.token0Debt;
  let token1CurrentDebt = debtReserves.token1Debt;

  // Constants for calculations
  const PRECISION = 12n;
  const BASE = 10n ** PRECISION;

  // Removing debt liquidity in equal proportion
  debtReserves = _getUpdateDebtReserves(shares, totalBorrowShares, debtReserves, false);

  if (paybackToken0Or1 === 0n) {
    // entire payback is in token0
    tokenAmount = _getSwapAndPaybackOneTokenPerfectShares(
      debtReserves.token0ImaginaryReserves,
      debtReserves.token1ImaginaryReserves,
      token0CurrentDebt,
      token1CurrentDebt,
      debtReserves.token0RealReserves,
      debtReserves.token1RealReserves
    );
  } else if (paybackToken0Or1 === 1n) {
    // entire payback is in token1
    tokenAmount = _getSwapAndPaybackOneTokenPerfectShares(
      debtReserves.token1ImaginaryReserves,
      debtReserves.token0ImaginaryReserves,
      token1CurrentDebt,
      token0CurrentDebt,
      debtReserves.token1RealReserves,
      debtReserves.token0RealReserves
    );
  } else {
    return {
      tokenAmount: 0n,
      tokenAmountWithSlippage: 0n,
      success: false,
    };
  }

  // Adjust decimals
  const decimalAdjustment = 10n ** decimals0Or1;
  tokenAmount = (tokenAmount * decimalAdjustment) / BASE;

  // adding fee on paying back in 1 token
  tokenAmount = (tokenAmount * (BigInt(1e6) + dexFee)) / BigInt(1e6);

  // Apply slippage
  tokenAmountWithSlippage = BigInt(Math.floor(Number(tokenAmount) * (1 + slippage)));

  return {
    tokenAmount,
    tokenAmountWithSlippage,
    success: true,
  };
}
// ##################### PAYBACK PERFECT IN ONE TOKEN END #####################

// ##################### DEPOSIT OR WITHDRAW PERFECT #####################
function _depositOrWithdrawPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  slippage,
  totalSupplyShares,
  colReserves
) {
  if ((token0Amt > 0n && token1Amt > 0n) || (token0Amt === 0n && token1Amt === 0n)) {
    return {
      shares: 0n,
      token0Amt: 0n,
      token1Amt: 0n,
    };
  }

  let token0AmtAdjusted = 0n;
  let token1AmtAdjusted = 0n;
  let shares = 0n;

  const PRECISION = 12n;
  const BASE = 10n ** PRECISION;

  if (token0Amt > 0n) {
    token0AmtAdjusted = (token0Amt * BASE) / 10n ** token0Decimals;
    token1AmtAdjusted = (token0AmtAdjusted * colReserves.token1RealReserves) / colReserves.token0RealReserves;
    shares = (token0AmtAdjusted * totalSupplyShares) / colReserves.token0RealReserves;
  } else {
    token1AmtAdjusted = (token1Amt * BASE) / 10n ** token1Decimals;
    token0AmtAdjusted = (token1AmtAdjusted * colReserves.token0RealReserves) / colReserves.token1RealReserves;
    shares = (token1AmtAdjusted * totalSupplyShares) / colReserves.token1RealReserves;
  }

  token0Amt = (token0AmtAdjusted * 10n ** token0Decimals) / BASE;
  token1Amt = (token1AmtAdjusted * 10n ** token1Decimals) / BASE;

  return {
    shares,
    token0Amt,
    token1Amt,
  };
}
// ##################### DEPOSIT OR WITHDRAW PERFECT END #####################

// ##################### BORROW OR PAYBACK PERFECT #####################
function _borrowOrPaybackPerfect(
  token0Amt,
  token1Amt,
  token0Decimals,
  token1Decimals,
  totalBorrowShares,
  debtReserves
) {
  if ((token0Amt > 0n && token1Amt > 0n) || (token0Amt === 0n && token1Amt === 0n)) {
    return {
      shares: 0n,
      token0Amt: 0n,
      token1Amt: 0n,
    };
  }

  let token0AmtAdjusted = 0n;
  let token1AmtAdjusted = 0n;
  let shares = 0n;

  const PRECISION = 12n;
  const BASE = 10n ** PRECISION;

  if (token0Amt > 0n) {
    token0AmtAdjusted = (token0Amt * BASE) / 10n ** token0Decimals;
    token1AmtAdjusted = (token0AmtAdjusted * debtReserves.token1Debt) / debtReserves.token0Debt;
    shares = (token0AmtAdjusted * totalBorrowShares) / debtReserves.token0Debt;
  } else {
    token1AmtAdjusted = (token1Amt * BASE) / 10n ** token1Decimals;
    token0AmtAdjusted = (token1AmtAdjusted * debtReserves.token0Debt) / debtReserves.token1Debt;
    shares = (token1AmtAdjusted * totalBorrowShares) / debtReserves.token1Debt;
  }

  token0Amt = (token0AmtAdjusted * 10n ** token0Decimals) / BASE;
  token1Amt = (token1AmtAdjusted * 10n ** token1Decimals) / BASE;

  return {
    shares,
    token0Amt,
    token1Amt,
  };
}

// ##################### BORROW OR PAYBACK PERFECT END #####################

module.exports = {
  _depositAdjusted,
  _withdrawAdjusted,
  _withdrawPerfectInOneToken,
  _borrowAdjusted,
  _paybackAdjusted,
  _paybackPerfectInOneToken,
  _depositOrWithdrawPerfect,
  _borrowOrPaybackPerfect,
};
