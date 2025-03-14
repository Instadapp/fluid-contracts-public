const main = require("./main");
function testDeposit() {
  let token0Amt = 0n;
  let token1Amt = 10000000000000000000000n;
  let token0Decimals = 6n;
  let token1Decimals = 18n;
  let slippage = 1n;
  let dexFee = 0n;
  let totalSupplyShares = 10000000000000000000000n;
  let colReserves = {
    token0RealReserves: 10000000000000000n,
    token1RealReserves: 10000000000000000n,
    token0ImaginaryReserves: 194868329830457885n,
    token1ImaginaryReserves: 194868329779644869n,
  };

  const depositOutput = main.deposit(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves
  ).shares;

  let expectedOutput = 4957116629144654050000n;

  let percentDiff = ((depositOutput - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testWithdraw1() {
  let token0Amt = 10000000000n;
  let token1Amt = 0n;
  let token0Decimals = 6n;
  let token1Decimals = 18n;
  let slippage = 1n;
  let dexFee = 0n;
  let totalSupplyShares = 115009432824532605695319n;
  let colReserves = {
    token0RealReserves: 119628948046745954n,
    token1RealReserves: 110399419798000000n,
    token0ImaginaryReserves: 2245789124165728126n,
    token1ImaginaryReserves: 2236559595332584560n,
  };

  let pex = {
    geometricMean: 999999999725139423651692543n,
    upperRange: 1111111110805710470724102826n,
    lowerRange: 899999999752625481286523289n,
  };

  const withdrawOutput = main.withdraw(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves,
    pex
  ).shares;

  let expectedOutput = 4995283515543946906575n;

  let percentDiff = ((withdrawOutput - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testWithdraw2() {
  let token0Amt = 20000000000n;
  let token1Amt = 10000000000000000000000n;
  let token0Decimals = 6n;
  let token1Decimals = 18n;
  let slippage = 1n;
  let dexFee = 0n;
  let totalSupplyShares = 125009878181515701933994n;
  let colReserves = {
    token0RealReserves: 129657312416000000n,
    token1RealReserves: 120371293337546758n,
    token0ImaginaryReserves: 194868329830n,
    token1ImaginaryReserves: 194868329779644869000000n,
  };

  let pex = {
    geometricMean: 999999999725139423651692543n,
    upperRange: 1111111110805710470724102826n,
    lowerRange: 899999999752625481286523289n,
  };

  const withdrawOutput = main.withdraw(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    dexFee,
    totalSupplyShares,
    colReserves,
    pex
  ).shares;

  let expectedOutput = 14995605029457311462962n;

  let percentDiff = ((withdrawOutput - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testPayback() {
  let token0Amt = 20000000000n;
  let token1Amt = 10000000000000000000000n;
  let token0Decimals = 6n;
  let token1Decimals = 18n;
  let slippage = 1n;
  let dexFee = 0n;
  let totalBorrowShares = 35034274327812578002852n;
  let debtReserves = {
    token0Debt: 38859182144000000n,
    token1Debt: 31186643871254094n,
    token0RealReserves: 29411523100502033n,
    token1RealReserves: 37084061354483010n,
    token0ImaginaryReserves: 643847870301020701n,
    token1ImaginaryReserves: 651520408386117313n,
  };

  const paybackOutput = main.payback(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    dexFee,
    totalBorrowShares,
    debtReserves
  ).shares;

  let expectedOutput = 15009532187463482328497n;

  let percentDiff = ((paybackOutput - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testBorrow() {
  let token0Amt = 20000000000n;
  let token1Amt = 10000000000000000000000n;
  let token0Decimals = 6n;
  let token1Decimals = 18n;
  let slippage = 1n;
  let dexFee = 0n;
  let totalBorrowShares = 10000000000000000000000n;
  let debtReserves = {
    token0Debt: 10000000000000000n,
    token1Debt: 10000000000000000n,
    token0RealReserves: 10000000000000000n,
    token1RealReserves: 10000000000000000n,
    token0ImaginaryReserves: 194868329830457885n,
    token1ImaginaryReserves: 194868329779644869n,
  };

  let pex = {
    geometricMean: 999999999725139423651692543n,
    upperRange: 1111111110805710470724102826n,
    lowerRange: 899999999752625481286523289n,
  };

  const borrowOutput = main.borrow(
    token0Amt,
    token1Amt,
    token0Decimals,
    token1Decimals,
    slippage,
    dexFee,
    totalBorrowShares,
    debtReserves,
    pex
  ).shares;

  let expectedOutput = 15027016291653544991350n;

  let percentDiff = ((borrowOutput - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testWithdrawMax() {
  const shares = 10000000000000000000000n;
  const slippage = 1n;
  const dexFee = 0n;
  const totalSupplyShares = 120000000000000000000000n;
  const colReserves = {
    token0RealReserves: 120000000002000000n,
    token1RealReserves: 120000000000000000n,
    token0ImaginaryReserves: 2338419957985981486n,
    token1ImaginaryReserves: 2338419957374225297n,
  };

  const output = main.withdrawMax(shares, 0n, 6n, slippage, dexFee, totalSupplyShares, colReserves).tokenAmount;

  let expectedOutput = 19953565081n;

  let percentDiff = ((output - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testPaybackMax() {
  const shares = 5027016291895179620000n;
  const slippage = 1n;
  const dexFee = 0n;
  const totalBorrowShares = 25027016291895179620000n;
  const debtReserves = {
    token0Debt: 29999999998000000n,
    token1Debt: 19999999999999999n,
    token0RealReserves: 18769728653334378n,
    token1RealReserves: 28769728637929501n,
    token0ImaginaryReserves: 457697286515344076n,
    token1ImaginaryReserves: 467697286379295288n,
  };

  const output = main.paybackMax(shares, 0n, 6n, slippage, dexFee, totalBorrowShares, debtReserves).tokenAmount;

  let expectedOutput = 10000000001n;

  let percentDiff = ((output - expectedOutput) * 10000n) / expectedOutput;
  percentDiff < 1 && percentDiff > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testDepositPerfect() {
  const totalSupplyShares = 10000000000000000000000n;
  let colReserves = {
    token0RealReserves: 10000000000000000n,
    token1RealReserves: 10000000000000000n,
    token0ImaginaryReserves: 194868329830457885n,
    token1ImaginaryReserves: 194868329779644869n,
  };

  const output1 = main.depositPerfect(185000001n, 0n, 6n, 18n, 1n, totalSupplyShares, colReserves).shares;

  const output2 = main.depositPerfect(0n, 185000000000001000001n, 6n, 18n, 1n, totalSupplyShares, colReserves).shares;

  let expectedOutput = 185000000000000000000n;

  let percentDiff1 = ((output1 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((output2 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testWithdrawPerfect() {
  const totalSupplyShares = 11001000000000000000000n;
  let colReserves = {
    token0RealReserves: 11001000002000000n,
    token1RealReserves: 11001000000000001n,
    token0ImaginaryReserves: 194868329830457885n,
    token1ImaginaryReserves: 194868329779644869n,
  };

  const output1 = main.withdrawPerfect(999999999n, 0n, 6n, 18n, 1n, totalSupplyShares, colReserves).shares;

  const output2 = main.withdrawPerfect(0n, 999999999999998999999n, 6n, 18n, 1n, totalSupplyShares, colReserves).shares;

  let expectedOutput = 1000000000000000000000n;

  let percentDiff1 = ((output1 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((output2 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testBorrowPerfect() {
  const totalBorrowShares = 10000000000000000000000n;
  const debtReserves = {
    token0Debt: 10000000000000000n,
    token1Debt: 10000000000000000n,
    token0RealReserves: 10000000000000000262144000000n,
    token1RealReserves: 10000000000000000262144000000n,
    token0ImaginaryReserves: 10000000000000000262144000000n,
    token1ImaginaryReserves: 10000000000000000262144000000n,
  };

  const output1 = main.borrowPerfect(999999998n, 0n, 6n, 18n, 1n, totalBorrowShares, debtReserves).shares;

  const output2 = main.borrowPerfect(0n, 999999999999998999999n, 6n, 18n, 1n, totalBorrowShares, debtReserves).shares;

  let expectedOutput = 1000000000000000000000n;

  let percentDiff1 = ((output1 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((output2 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testPaybackPerfect() {
  const totalBorrowShares = 11001000000000000000000n;
  const debtReserves = {
    token0Debt: 11000999996000000n,
    token1Debt: 11000999999999997n,
    token0RealReserves: 10000000000000000262144000000n,
    token1RealReserves: 10000000000000000262144000000n,
    token0ImaginaryReserves: 10000000000000000262144000000n,
    token1ImaginaryReserves: 10000000000000000262144000000n,
  };

  const output1 = main.paybackPerfect(1000000000n, 0n, 6n, 18n, 1n, totalBorrowShares, debtReserves).shares;

  const output2 = main.paybackPerfect(0n, 1000000000000000000001n, 6n, 18n, 1n, totalBorrowShares, debtReserves).shares;

  let expectedOutput = 1000000000000000000000n;

  let percentDiff1 = ((output1 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((output2 - expectedOutput) * 10000n) / expectedOutput;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testWithdrawPerfectMax() {
  const totalSupplyShares = 11001000000000000000000n;
  let colReserves = {
    token0RealReserves: 11001000002000000n,
    token1RealReserves: 11001000000000001n,
    token0ImaginaryReserves: 194868329830457885n,
    token1ImaginaryReserves: 194868329779644869n,
  };

  const output = main.withdrawPerfectMax(1000000000000000000000n, 6n, 18n, 1n, totalSupplyShares, colReserves);

  const token0Amount = output.token0Amt;

  const token1Amount = output.token1Amt;

  let token0ExpectedAmount = 1000000000n;
  let token1ExpectedAmount = BigInt(1e21);

  let percentDiff1 = ((token0Amount - token0ExpectedAmount) * 10000n) / token0ExpectedAmount;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((token1Amount - token1ExpectedAmount) * 10000n) / token1ExpectedAmount;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

function testPaybackPerfectMax() {
  const totalBorrowShares = 11001000000000000000000n;
  const debtReserves = {
    token0Debt: 11000999996000000n,
    token1Debt: 11000999999999997n,
    token0RealReserves: 10000000000000000262144000000n,
    token1RealReserves: 10000000000000000262144000000n,
    token0ImaginaryReserves: 10000000000000000262144000000n,
    token1ImaginaryReserves: 10000000000000000262144000000n,
  };

  const output = main.paybackPerfectMax(1000000000000000000000n, 6n, 18n, 1n, totalBorrowShares, debtReserves);

  const token0Amount = output.token0Amt;

  const token1Amount = output.token1Amt;

  let token0ExpectedAmount = 1000000000n;
  let token1ExpectedAmount = 1000000000000000000001n;

  let percentDiff1 = ((token0Amount - token0ExpectedAmount) * 100n) / token0ExpectedAmount;
  percentDiff1 < 1 && percentDiff1 > -1 ? console.log("Test Passed") : console.error("Test Failed");

  let percentDiff2 = ((token1Amount - token1ExpectedAmount) * 100n) / token1ExpectedAmount;
  percentDiff2 < 1 && percentDiff2 > -1 ? console.log("Test Passed") : console.error("Test Failed");
}

testDeposit();
testWithdraw1();
testWithdraw2();
testPayback();
testBorrow();
testWithdrawMax();
testPaybackMax();
testDepositPerfect();
testWithdrawPerfect();
testBorrowPerfect();
testPaybackPerfect();
testWithdrawPerfectMax();
testPaybackPerfectMax();
