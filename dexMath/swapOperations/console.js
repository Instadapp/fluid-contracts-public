const { swapInAdjusted, swapOutAdjusted, swapIn, swapOut } = require("./main");
const helpers = require("./helpers");

/**
 * Calculates reserves outside range for a liquidity pool
 * @param {number} geometricMeanPrice - Geometric mean of upper and lower price bounds
 * @param {number} priceAtRange - Price at range boundary (upper or lower)
 * @param {number} reserveX - Real reserves of token X
 * @param {number} reserveY - Real reserves of token Y
 * @returns {[number, number]} - [reserveXOutside, reserveYOutside]
 */
function _calculateReservesOutsideRange(geometricMeanPrice, priceAtRange, reserveX, reserveY) {
  // Scale factor for price precision (equivalent to 1e27 in Solidity)
  const SCALE = 1e27;

  // Calculate the three parts of the quadratic equation solution
  const part1 = priceAtRange - geometricMeanPrice;

  const part2 = (geometricMeanPrice * reserveX + reserveY * SCALE) / (2 * part1);

  let part3 = reserveX * reserveY;
  // Handle potential overflow like in Solidity
  part3 = part3 < 1e50 ? (part3 * SCALE) / part1 : (part3 / part1) * SCALE;

  // Calculate xa (reserveXOutside)
  const reserveXOutside = part2 + Math.sqrt(part3 + part2 * part2);

  // Calculate yb (reserveYOutside)
  const reserveYOutside = (reserveXOutside * geometricMeanPrice) / SCALE;

  return { reserveXOutside, reserveYOutside };
}

let fee = 100;

// Define the collateral reserve object
const colReservesOne = {
  token0RealReserves: 20000000006000000,
  token1RealReserves: 20000000000500000,
  token0ImaginaryReserves: 389736659726997981,
  token1ImaginaryReserves: 389736659619871949,
};

// Define the collateral reserve object
const reservesEmpty = {
  token0RealReserves: 0,
  token1RealReserves: 0,
  token0ImaginaryReserves: 0,
  token1ImaginaryReserves: 0,
};

// Define the debt reserve object
const debtReservesOne = {
  token0RealReserves: 9486832995556050,
  token1RealReserves: 9486832993079885,
  token0ImaginaryReserves: 184868330099560759,
  token1ImaginaryReserves: 184868330048879109,
};

// Real USDC-USDT reserves took from API
const debtReserveUSDCUSDT = {
  token0Debt: 1202750117771,
  token1Debt: 19119886636577,
  token0RealReserves: 19128782112310,
  token1RealReserves: 1201469487259,
  token0ImaginaryReserves: 33884684300018539,
  token1ImaginaryReserves: 33849806986423971,
};

function testDustReserves() {
  // failing
  console.log(swapOutAdjusted(true, 1200000000000, 0, debtReserveUSDCUSDT, 6, limitsWide, syncTime));
  // passing
  console.log(swapOutAdjusted(true, 1195000000000, 0, debtReserveUSDCUSDT, 6, limitsWide, syncTime));

  // failing
  console.log(swapInAdjusted(true, 1200000000000, 0, debtReserveUSDCUSDT, 6, limitsWide, syncTime));
  // passing
  console.log(swapInAdjusted(true, 1196273506126, 0, debtReserveUSDCUSDT, 6, limitsWide, syncTime));
}

const limitsTight = {
  withdrawableToken0: {
    available: 456740438880263,
    expandsTo: 711907234052361388866,
    expandDuration: 600,
  },
  withdrawableToken1: {
    available: 825179383432029,
    expandsTo: 711907234052361388866,
    expandDuration: 600,
  },
  borrowableToken0: {
    available: 941825058374170,
    expandsTo: 711907234052361388866,
    expandDuration: 600,
  },
  borrowableToken1: {
    available: 941825058374170,
    expandsTo: 711907234052361388866,
    expandDuration: 600,
  },
};

const limitsOk = {
  withdrawableToken0: {
    available: 3424233287977651508309,
    expandsTo: 3424233287977651508309,
    expandDuration: 0,
  },
  withdrawableToken1: {
    available: 2694722397017898779126,
    expandsTo: 2711907234052361388866,
    expandDuration: 22,
  },
  borrowableToken0: {
    available: 2132761927364044176263,
    expandsTo: 2132761927364044176263,
    expandDuration: 0,
  },
  borrowableToken1: {
    available: 1725411806284169057582,
    expandsTo: 1887127019149919004603,
    expandDuration: 308,
  },
};

const limitsWide = {
  withdrawableToken0: {
    available: 342423328797765150830999,
    expandsTo: 342423328797765150830999,
    expandDuration: 0,
  },
  withdrawableToken1: {
    available: 342423328797765150830999,
    expandsTo: 342423328797765150830999,
    expandDuration: 22,
  },
  borrowableToken0: {
    available: 342423328797765150830999,
    expandsTo: 342423328797765150830999,
    expandDuration: 0,
  },
  borrowableToken1: {
    available: 342423328797765150830999,
    expandsTo: 342423328797765150830999,
    expandDuration: 308,
  },
};

const outDecimals = 18;
const syncTime = Date.now() / 1000;

const getApproxCenterPriceIn = (amountToSwap, swap0To1, colReserves, debtReserves) => {
  const { token0RealReserves, token1RealReserves, token0ImaginaryReserves, token1ImaginaryReserves } = colReserves;

  const {
    token0RealReserves: debtToken0RealReserves,
    token1RealReserves: debtToken1RealReserves,
    token0ImaginaryReserves: debtToken0ImaginaryReserves,
    token1ImaginaryReserves: debtToken1ImaginaryReserves,
  } = debtReserves;

  // Check if all reserves of collateral pool are greater than 0
  const colPoolEnabled =
    token0RealReserves > 0 && token1RealReserves > 0 && token0ImaginaryReserves > 0 && token1ImaginaryReserves > 0;

  // Check if all reserves of debt pool are greater than 0
  const debtPoolEnabled =
    debtToken0RealReserves > 0 &&
    debtToken1RealReserves > 0 &&
    debtToken0ImaginaryReserves > 0 &&
    debtToken1ImaginaryReserves > 0;

  let colIReserveIn, colIReserveOut, debtIReserveIn, debtIReserveOut;

  if (swap0To1) {
    colIReserveIn = token0ImaginaryReserves;
    colIReserveOut = token1ImaginaryReserves;
    debtIReserveIn = debtToken0ImaginaryReserves;
    debtIReserveOut = debtToken1ImaginaryReserves;
  } else {
    colIReserveIn = token1ImaginaryReserves;
    colIReserveOut = token0ImaginaryReserves;
    debtIReserveIn = debtToken1ImaginaryReserves;
    debtIReserveOut = debtToken0ImaginaryReserves;
  }

  let a;
  if (colPoolEnabled && debtPoolEnabled) {
    a = helpers.swapRoutingIn(amountToSwap, colIReserveOut, colIReserveIn, debtIReserveOut, debtIReserveIn);
  } else if (debtPoolEnabled) {
    a = -1; // Route from debt pool
  } else if (colPoolEnabled) {
    a = amountToSwap + 1; // Route from collateral pool
  } else {
    throw new Error("No pools are enabled");
  }

  let amountInCollateral = 0;
  let amountInDebt = 0;

  if (a <= 0) {
    // Entire trade routes through debt pool
    amountInDebt = amountToSwap;
  } else if (a >= amountToSwap) {
    // Entire trade routes through collateral pool
    amountInCollateral = amountToSwap;
  } else {
    // Trade routes through both pools
    amountInCollateral = a;
    amountInDebt = amountToSwap - a;
  }

  let price;
  // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
  if (amountInCollateral > amountInDebt) {
    // new pool price from col pool
    price = swap0To1 ? (colIReserveOut * 1e27) / colIReserveIn : (colIReserveIn * 1e27) / colIReserveOut;
  } else {
    // new pool price from debt pool
    price = swap0To1 ? (debtIReserveOut * 1e27) / debtIReserveIn : (debtIReserveIn * 1e27) / debtIReserveOut;
  }

  return price;
};

const getApproxCenterPriceOut = (amountOut, swap0To1, colReserves, debtReserves) => {
  const { token0RealReserves, token1RealReserves, token0ImaginaryReserves, token1ImaginaryReserves } = colReserves;

  const {
    token0RealReserves: debtToken0RealReserves,
    token1RealReserves: debtToken1RealReserves,
    token0ImaginaryReserves: debtToken0ImaginaryReserves,
    token1ImaginaryReserves: debtToken1ImaginaryReserves,
  } = debtReserves;

  // Check if all reserves of collateral pool are greater than 0
  const colPoolEnabled =
    token0RealReserves > 0 && token1RealReserves > 0 && token0ImaginaryReserves > 0 && token1ImaginaryReserves > 0;

  // Check if all reserves of debt pool are greater than 0
  const debtPoolEnabled =
    debtToken0RealReserves > 0 &&
    debtToken1RealReserves > 0 &&
    debtToken0ImaginaryReserves > 0 &&
    debtToken1ImaginaryReserves > 0;

  let colIReserveIn, colIReserveOut, debtIReserveIn, debtIReserveOut;

  if (swap0To1) {
    colIReserveIn = token0ImaginaryReserves;
    colIReserveOut = token1ImaginaryReserves;
    debtIReserveIn = debtToken0ImaginaryReserves;
    debtIReserveOut = debtToken1ImaginaryReserves;
  } else {
    colIReserveIn = token1ImaginaryReserves;
    colIReserveOut = token0ImaginaryReserves;
    debtIReserveIn = debtToken1ImaginaryReserves;
    debtIReserveOut = debtToken0ImaginaryReserves;
  }

  let a;
  if (colPoolEnabled && debtPoolEnabled) {
    a = helpers.swapRoutingOut(amountOut, colIReserveIn, colIReserveOut, debtIReserveIn, debtIReserveOut);
  } else if (debtPoolEnabled) {
    a = -1; // Route from debt pool
  } else if (colPoolEnabled) {
    a = amountOut + 1; // Route from collateral pool
  } else {
    throw new Error("No pools are enabled");
  }

  let amountInCollateral = 0;
  let amountInDebt = 0;

  if (a <= 0) {
    // Entire trade routes through debt pool
    amountInDebt = helpers.getAmountIn(amountOut, debtIReserveIn, debtIReserveOut);
  } else if (a >= amountOut) {
    // Entire trade routes through collateral pool
    amountInCollateral = helpers.getAmountIn(amountOut, colIReserveIn, colIReserveOut);
  } else {
    // Trade routes through both pools
    amountInCollateral = helpers.getAmountIn(a, colIReserveIn, colIReserveOut);
    amountInDebt = helpers.getAmountIn(amountOut - a, debtIReserveIn, debtIReserveOut);
  }

  let price;
  // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
  if (amountInCollateral > amountInDebt) {
    // new pool price from col pool
    price = swap0To1 ? (colIReserveOut * 1e27) / colIReserveIn : (colIReserveIn * 1e27) / colIReserveOut;
  } else {
    // new pool price from debt pool
    price = swap0To1 ? (debtIReserveOut * 1e27) / debtIReserveIn : (debtIReserveIn * 1e27) / debtIReserveOut;
  }

  return price;
};

function testSwapIn() {
  console.log(
    swapInAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapInAdjusted(
      true,
      1e15,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, true, reservesEmpty, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapInAdjusted(
      true,
      1e15,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, true, colReservesOne, reservesEmpty),
      syncTime
    )
  );

  console.log(
    swapInAdjusted(
      false,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, false, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapInAdjusted(
      false,
      1e15,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, false, reservesEmpty, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapInAdjusted(
      false,
      1e15,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, false, colReservesOne, reservesEmpty),
      syncTime
    )
  );
}

function testExpandLimits() {
  // half expanded
  let limit = helpers.getExpandedLimit(syncTime - 300, limitsTight.withdrawableToken0);
  console.log(limit, "half expanded");
  // 3/4 expanded
  limit = helpers.getExpandedLimit(syncTime - 450, limitsTight.withdrawableToken0);
  console.log(limit, "3/4 expanded");
  // fully expanded
  limit = helpers.getExpandedLimit(syncTime - 10000, limitsTight.withdrawableToken0);
  console.log(limit, "fully expanded");
}

function testSwapInWithLimits() {
  console.log("\n LIMITS SHOULD HIT ---------------------------------");
  console.log(
    swapInAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsTight,
      getApproxCenterPriceIn(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log("\n LIMITS SHOULD NOT HIT ---------------------------------");
  console.log(
    swapInAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceIn(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log("\n EXPANDED LIMITS SHOULD NOT HIT ---------------------------------");
  console.log(
    swapInAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsTight,
      getApproxCenterPriceIn(1e15, true, colReservesOne, debtReservesOne),
      syncTime - 1000
    )
  );

  console.log("\n PRICE DIFF SHOULD HIT ---------------------------------");
  console.log(
    swapInAdjusted(
      true,
      15e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsWide,
      getApproxCenterPriceIn(15e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );
}

function testSwapOutWithLimits() {
  console.log("\n LIMITS SHOULD HIT ---------------------------------");
  console.log(
    swapOutAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsTight,
      getApproxCenterPriceOut(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log("\n LIMITS SHOULD NOT HIT ---------------------------------");
  console.log(
    swapOutAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log("\n EXPANDED LIMITS SHOULD NOT HIT ---------------------------------");
  console.log(
    swapOutAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsTight,
      getApproxCenterPriceOut(1e15, true, colReservesOne, debtReservesOne),
      syncTime - 1000
    )
  );

  console.log("\n PRICE DIFF SHOULD HIT ---------------------------------");
  console.log(
    swapOutAdjusted(
      true,
      15e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsWide,
      getApproxCenterPriceOut(15e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );
}

function testSwapOut() {
  console.log(
    swapOutAdjusted(
      true,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapOutAdjusted(
      true,
      1e15,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, true, reservesEmpty, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapOutAdjusted(
      true,
      1e15,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, true, colReservesOne, reservesEmpty),
      syncTime
    )
  );

  console.log(
    swapOutAdjusted(
      false,
      1e15,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, false, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapOutAdjusted(
      false,
      1e15,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, false, reservesEmpty, debtReservesOne),
      syncTime
    )
  );

  console.log(
    swapOutAdjusted(
      false,
      1e15,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(1e15, false, colReservesOne, reservesEmpty),
      syncTime
    )
  );
}

function testSwapInOut() {
  let amountIn = 1e15;
  let amountOut = swapInAdjusted(
    true,
    amountIn,
    colReservesOne,
    debtReservesOne,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, true, colReservesOne, debtReservesOne),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      true,
      amountOut,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, true, colReservesOne, debtReservesOne),
      syncTime
    )
  );

  amountIn = 1e15;
  amountOut = swapInAdjusted(
    false,
    amountIn,
    colReservesOne,
    debtReservesOne,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, false, colReservesOne, debtReservesOne),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      false,
      amountOut,
      colReservesOne,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, false, colReservesOne, debtReservesOne),
      syncTime
    )
  );
}

function testSwapInOutDebtEmpty() {
  let amountIn = 1e15;
  let amountOut = swapInAdjusted(
    true,
    amountIn,
    reservesEmpty,
    debtReservesOne,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, true, reservesEmpty, debtReservesOne),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      true,
      amountOut,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, true, reservesEmpty, debtReservesOne),
      syncTime
    )
  );

  amountIn = 1e15;
  amountOut = swapInAdjusted(
    false,
    amountIn,
    reservesEmpty,
    debtReservesOne,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, false, reservesEmpty, debtReservesOne),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      false,
      amountOut,
      reservesEmpty,
      debtReservesOne,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, false, reservesEmpty, debtReservesOne),
      syncTime
    )
  );
}

function testSwapInOutColEmpty() {
  let amountIn = 1e15;
  let amountOut = swapInAdjusted(
    true,
    amountIn,
    colReservesOne,
    reservesEmpty,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, true, colReservesOne, reservesEmpty),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      true,
      amountOut,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, true, colReservesOne, reservesEmpty),
      syncTime
    )
  );

  amountIn = 1e15;
  amountOut = swapInAdjusted(
    false,
    amountIn,
    colReservesOne,
    reservesEmpty,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, false, colReservesOne, reservesEmpty),
    syncTime
  );
  console.log(amountIn);
  console.log(
    swapOutAdjusted(
      false,
      amountOut,
      colReservesOne,
      reservesEmpty,
      outDecimals,
      limitsOk,
      getApproxCenterPriceOut(amountOut, false, colReservesOne, reservesEmpty),
      syncTime
    )
  );
}

function testSwapInCompareEstimateIn() {
  // values as fetched from resolver
  const colReserves = {
    token0RealReserves: 2169934539358,
    token1RealReserves: 19563846299171,
    token0ImaginaryReserves: 62490032619260838,
    token1ImaginaryReserves: 73741038977020279,
  };
  const debtReserves = {
    token0Debt: 16590678644536,
    token1Debt: 2559733858855,
    token0RealReserves: 2169108220421,
    token1RealReserves: 19572550738602,
    token0ImaginaryReserves: 62511862774117387,
    token1ImaginaryReserves: 73766803277429176,
  };

  // adjusting in amount for fee, here it was configured as 0.01% (100)
  const inAmtAfterFee = (1000000000000 * (1000000 - 100)) / 1000000;
  const expectedAmountIn = inAmtAfterFee * 1e6;

  const expectedAmountOut = 1179917402129152800;
  // see https://dashboard.tenderly.co/InstaDApp/fluid/simulator/5e5bf655-98ef-4edc-9590-ed4da467ac79
  // for resolver estimateSwapIn result at very similar reserves values (hardcoded reserves above taken some blocks before).
  // resolver says estimateSwapIn result should be 1179917367073000000
  // we get 								                       1179917402129152800

  let amountIn = inAmtAfterFee;
  let amountOut = swapInAdjusted(
    true,
    amountIn,
    colReserves,
    debtReserves,
    outDecimals,
    limitsOk,
    getApproxCenterPriceIn(amountIn, true, colReserves, debtReserves),
    syncTime
  );
  console.log(`Expected amount out: ${expectedAmountOut}`);
  console.log(`Got                : ${amountOut * 1e6}`);
  console.log(`Expected amount in: ${expectedAmountIn}`);
  console.log(`Got               : ${amountIn * 1e6}`);

  if (amountOut * 1e6 !== expectedAmountOut) {
    throw new Error(`Expected amount out: ${expectedAmountOut}, But got: ${amountOut * 1e6}`);
  }
  if (amountIn * 1e6 !== expectedAmountIn) {
    throw new Error(`Expected amount in: ${expectedAmountIn}, But got: ${amountIn * 1e6}`);
  }
}

function testSwapInVerifyReserves() {
  console.log("\n Verify reserves should HIT ---------------------------------");

  const reserves = {
    token0RealReserves: 41080000006000000,
    token1RealReserves: 83298735295,
    token0ImaginaryReserves: 0,
    token1ImaginaryReserves: 0,
  };

  const { reserveXOutside, reserveYOutside } = _calculateReservesOutsideRange(
    49999999986256610000000000,
    49999999986256610000000000 * 1.1,
    reserves.token0RealReserves,
    reserves.token1RealReserves
  );
  reserves.token0ImaginaryReserves = reserveXOutside + reserves.token0RealReserves;
  reserves.token1ImaginaryReserves = reserveYOutside + reserves.token1RealReserves;

  console.log("test reserves", reserves);

  // using equal reserves for col and debt
  const result = swapInAdjusted(
    true,
    83298735295 * 0.01,
    reserves,
    reserves,
    outDecimals,
    limitsWide,
    getApproxCenterPriceIn(83298735295 * 0.01, true, reserves, reserves),
    syncTime
  );
  console.log(result);
  if (result != 0) throw new Error("reserves ratio verification not hit");

  console.log("\n\n\n");
}

function testSwapOutVerifyReserves() {
  console.log("\n Verify reserves should HIT ---------------------------------");

  const reserves = {
    token0RealReserves: 83298735295,
    token1RealReserves: 41080000006000000,
    token0ImaginaryReserves: 0,
    token1ImaginaryReserves: 0,
  };

  const { reserveXOutside, reserveYOutside } = _calculateReservesOutsideRange(
    49999999986256610000000000,
    49999999986256610000000000 * 1.1,
    reserves.token0RealReserves,
    reserves.token1RealReserves
  );
  reserves.token0ImaginaryReserves = reserveXOutside + reserves.token0RealReserves;
  reserves.token1ImaginaryReserves = reserveYOutside + reserves.token1RealReserves;

  console.log("test reserves", reserves);

  // using equal reserves for col and debt
  const result = swapOutAdjusted(
    false,
    83298735295 * 0.01,
    reserves,
    reserves,
    outDecimals,
    limitsWide,
    getApproxCenterPriceOut(83298735295 * 0.01, false, reserves, reserves),
    syncTime
  );
  console.log(result);
  if (result != Number.MAX_VALUE) throw new Error("reserves ratio verification not hit");

  console.log("\n\n\n");
}

function testSwapInVerifyReservesInRange() {
  console.log("\n swapIn: Verify reserves should hit in expected range only ---------------------------------");
  const decimals = 6;

  const reserves = {
    token0RealReserves: 2_000_000 * 1e6 * 1e6, // e.g. 2M USDC
    token1RealReserves: 15_000 * 1e6 * 1e6, // e.g. 1 USDT
    token0ImaginaryReserves: 0,
    token1ImaginaryReserves: 0,
  };
  const { reserveXOutside, reserveYOutside } = _calculateReservesOutsideRange(
    1e27,
    1e27 * 1.000001,
    reserves.token0RealReserves,
    reserves.token1RealReserves
  );
  reserves.token0ImaginaryReserves = reserveXOutside + reserves.token0RealReserves;
  reserves.token1ImaginaryReserves = reserveYOutside + reserves.token1RealReserves;

  console.log("test reserves", reserves);

  // expected required ratio:
  // token1Reserves must be > (token0Reserves * price) / (1e27 * MIN_SWAP_LIQUIDITY)
  // so 2M / 0.85e4, which is 235.29 -> swap amount @~14_764

  // Test for swap amount 14_766, revert should hit
  let swapAmount_ = 14_766;
  let result = swapInAdjusted(
    true,
    swapAmount_ * 1e6 * 1e6,
    reserves,
    reservesEmpty,
    decimals,
    limitsWide,
    getApproxCenterPriceIn(swapAmount_ * 1e6 * 1e6, true, { ...reserves }, { ...reservesEmpty }),
    syncTime
  );
  console.log(`result for col reserves when swap amount ${swapAmount_} : ${result}`);
  if (result != 0) throw new Error("reserves ratio verification revert not hit");

  result = swapInAdjusted(
    true,
    swapAmount_ * 1e6 * 1e6,
    reservesEmpty,
    reserves,
    decimals,
    limitsWide,
    getApproxCenterPriceIn(swapAmount_ * 1e6 * 1e6, true, reservesEmpty, reserves),
    syncTime
  );
  console.log(`result for debt reserves when swap amount ${swapAmount_} : ${result}`);
  if (result != 0) throw new Error("reserves ratio verification revert not hit");

  // Test for swap amount 14_762, revert should hit
  swapAmount_ = 14_762;

  result = swapInAdjusted(
    true,
    swapAmount_ * 1e6 * 1e6,
    reserves,
    reservesEmpty,
    decimals,
    limitsWide,
    getApproxCenterPriceIn(swapAmount_ * 1e6 * 1e6, true, reserves, reservesEmpty),
    syncTime
  );
  console.log(`result for col reserves when swap amount ${swapAmount_} : ${result}`);
  if (result == 0) throw new Error("reserves ratio verification revert hit");

  result = swapInAdjusted(
    true,
    swapAmount_ * 1e6 * 1e6,
    reservesEmpty,
    reserves,
    decimals,
    limitsWide,
    getApproxCenterPriceIn(swapAmount_ * 1e6 * 1e6, true, reservesEmpty, reserves),
    syncTime
  );
  console.log(`result for debt reserves when swap amount ${swapAmount_} : ${result}`);
  if (result == 0) throw new Error("reserves ratio verification revert hit");

  console.log("\n\n\n");
}

function testSwapOutVerifyReservesInRange() {
  console.log("\n swapOut: Verify reserves should hit in expected range only ---------------------------------");
  const decimals = 6;

  const reserves = {
    token0RealReserves: 15_000 * 1e6 * 1e6, // e.g. 1 USDT
    token1RealReserves: 2_000_000 * 1e6 * 1e6, // e.g. 2M USDC
    token0ImaginaryReserves: 0,
    token1ImaginaryReserves: 0,
  };
  const { reserveXOutside, reserveYOutside } = _calculateReservesOutsideRange(
    1e27,
    1e27 * 1.000001,
    reserves.token0RealReserves,
    reserves.token1RealReserves
  );
  reserves.token0ImaginaryReserves = reserveXOutside + reserves.token0RealReserves;
  reserves.token1ImaginaryReserves = reserveYOutside + reserves.token1RealReserves;

  console.log("test reserves", reserves);

  // expected required ratio:
  // token0Reserves >= (token1Reserves * 1e27) / (price * MIN_SWAP_LIQUIDITY);
  // so 2M / 0.85e4, which is 235.29 -> swap amount @~14_764

  // Test for swap amount 14_766, revert should hit
  let swapAmount_ = 14_766;
  let result = swapOutAdjusted(
    false,
    swapAmount_ * 1e6 * 1e6,
    reserves,
    reservesEmpty,
    decimals,
    limitsWide,
    getApproxCenterPriceOut(swapAmount_ * 1e6 * 1e6, false, reserves, reservesEmpty),
    syncTime
  );
  console.log(`result for col reserves when swap amount ${swapAmount_} : ${result}`);
  if (result != Number.MAX_VALUE) throw new Error("reserves ratio verification revert not hit");

  result = swapOutAdjusted(
    false,
    swapAmount_ * 1e6 * 1e6,
    reservesEmpty,
    reserves,
    decimals,
    limitsWide,
    getApproxCenterPriceOut(swapAmount_ * 1e6 * 1e6, false, reservesEmpty, reserves),
    syncTime
  );
  console.log(`result for debt reserves when swap amount ${swapAmount_} : ${result}`);
  if (result != Number.MAX_VALUE) throw new Error("reserves ratio verification revert not hit");

  // Test for swap amount 14_762, revert should hit
  swapAmount_ = 14_762;

  result = swapOutAdjusted(
    false,
    swapAmount_ * 1e6 * 1e6,
    reserves,
    reservesEmpty,
    decimals,
    limitsWide,
    getApproxCenterPriceOut(swapAmount_ * 1e6 * 1e6, false, reserves, reservesEmpty),
    syncTime
  );
  console.log(`result for col reserves when swap amount ${swapAmount_} : ${result}`);
  if (result == Number.MAX_VALUE) throw new Error("reserves ratio verification revert hit");

  result = swapOutAdjusted(
    false,
    swapAmount_ * 1e6 * 1e6,
    reservesEmpty,
    reserves,
    decimals,
    limitsWide,
    getApproxCenterPriceOut(swapAmount_ * 1e6 * 1e6, false, reservesEmpty, reserves),
    syncTime
  );
  console.log(`result for debt reserves when swap amount ${swapAmount_} : ${result}`);
  if (result == Number.MAX_VALUE) throw new Error("reserves ratio verification revert hit");

  console.log("\n\n\n");
}

testSwapIn();
testSwapOut();
testSwapInOut();
testSwapInOutDebtEmpty();
testSwapInOutColEmpty();
testSwapInCompareEstimateIn();
testSwapInWithLimits();
testSwapOutWithLimits();
testExpandLimits();
testSwapInVerifyReserves();
testSwapOutVerifyReserves();
testSwapInVerifyReservesInRange();
testSwapOutVerifyReservesInRange();
testDustReserves();

// run with:
// npx hardhat run dexMath/swapOperations/console.js
