const { deposit, withdraw, withdrawMax, borrow, payback, paybackMax } = require("./main");

let fee = 0.001;
let slippage = 0.0001;

// Define the collateral reserve object
const colReservesOne = {
  token0RealReserves: 20000000006000000,
  token1RealReserves: 20000000000500000,
  token0ImaginaryReserves: 389736659726997981,
  token1ImaginaryReserves: 389736659619871949,
};

const totalSupplyShares = 20000000000000000000000;

// Define the collateral reserve object
const reservesEmpty = {
  token0RealReserves: 0,
  token1RealReserves: 0,
  token0ImaginaryReserves: 0,
  token1ImaginaryReserves: 0,
};

// Define the debt reserve object
const debtReservesOne = {
  token0Debt: 10000000000000000,
  token1Debt: 10000000000000000,
  token0RealReserves: 9486832995556050,
  token1RealReserves: 9486832993079885,
  token0ImaginaryReserves: 184868330099560759,
  token1ImaginaryReserves: 184868330048879109,
};

const totalBorrowShares = 10000000000000000000000;

let r_ = {
  shares: 0,
  sharesWithSlippage: 0,
  success: false,
};

let r2_ = {
  tokenAmount: 0,
  tokenAmountWithSlippage: 0,
  success: false,
};

let pex = {
  geometricMean: 1e27,
  upperRange: 1.01e27,
  lowerRange: 1e27 / 1.01,
};

function testDeposit() {
  r_ = deposit(1000 * 1e18, 0, 18, 6, slippage, fee, totalSupplyShares, colReservesOne);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = deposit(0, 1000 * 1e6, 18, 6, slippage, fee, totalSupplyShares, colReservesOne);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
}
// testDeposit();

function testWithdraw() {
  r_ = withdraw(1000 * 1e18, 0, 18, 6, slippage, fee, totalSupplyShares, colReservesOne, pex);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = withdraw(0, 1000 * 1e6, 18, 6, slippage, fee, totalSupplyShares, colReservesOne, pex);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
}
testWithdraw();

function testWithdrawMax() {
  r2_ = withdrawMax(499 * 1e18, 0, 18, slippage, fee, totalSupplyShares, colReservesOne);
  console.log(r2_.tokenAmount, r2_.tokenAmountWithSlippage, r2_.success);
  r2_ = withdrawMax(499 * 1e18, 1, 6, slippage, fee, totalSupplyShares, colReservesOne);
  console.log(r2_.tokenAmount, r2_.tokenAmountWithSlippage, r2_.success);
}
// testWithdrawMax();

function testBorrow() {
  r_ = borrow(1000 * 1e18, 0, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne, pex);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = borrow(0, 1000 * 1e6, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne, pex);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = borrow(1000 * 1e18, 999 * 1e6, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne, pex);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
}
testBorrow();

function testPayback() {
  r_ = payback(1000 * 1e18, 0, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = payback(0, 1000 * 1e6, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
  r_ = payback(1000 * 1e18, 999 * 1e6, 18, 6, slippage, fee, totalBorrowShares, debtReservesOne);
  console.log(r_.shares, r_.sharesWithSlippage, r_.success);
}
// testPayback();

function testPaybackMax() {
  r_ = paybackMax(1000 * 1e18, 0, 18, slippage, fee, totalBorrowShares, debtReservesOne);
  console.log(r_.tokenAmount, r_.tokenAmountWithSlippage, r_.success);
  r_ = paybackMax(1000 * 1e18, 1, 6, slippage, fee, totalBorrowShares, debtReservesOne);
  console.log(r_.tokenAmount, r_.tokenAmountWithSlippage, r_.success);
}
// testPaybackMax();
