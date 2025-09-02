const main = require("./main");

// custom function selector
// deposit => 1
// withdraw => 2
// borrow => 3
// payback => 4
// depositPerfect => 5
// withdrawPerfect => 6
// borrowPerfect => 7
// paybackPerfect => 8
// withdrawMax => 9
// paybackMax => 10
// withdrawPerfectMax => 11
// paybackPerfectMax => 12

function validate() {
  const inputArray = [...process.argv];
  const inputArrayAdjusted = inputArray.slice(2);
  if (inputArrayAdjusted[0] == "1") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let dexFee = BigInt(inputArrayAdjusted[6]);
    let totalSupplyShares = BigInt(inputArrayAdjusted[7]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[8]),
      token1RealReserves: BigInt(inputArrayAdjusted[9]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
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
    console.log(depositOutput);
  } else if (inputArrayAdjusted[0] == "2") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let dexFee = BigInt(inputArrayAdjusted[6]);
    let totalSupplyShares = BigInt(inputArrayAdjusted[7]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[8]),
      token1RealReserves: BigInt(inputArrayAdjusted[9]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
    };

    let pex = {
      geometricMean: BigInt(inputArrayAdjusted[12]),
      upperRange: BigInt(inputArrayAdjusted[13]),
      lowerRange: BigInt(inputArrayAdjusted[14]),
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
    console.log(withdrawOutput);
  } else if (inputArrayAdjusted[0] == "3") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let dexFee = BigInt(inputArrayAdjusted[6]);
    let totalBorrowShares = BigInt(inputArrayAdjusted[7]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[8]),
      token1Debt: BigInt(inputArrayAdjusted[9]),
      token0RealReserves: BigInt(inputArrayAdjusted[10]),
      token1RealReserves: BigInt(inputArrayAdjusted[11]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[12]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[13]),
    };
    let pex = {
      geometricMean: BigInt(inputArrayAdjusted[14]),
      upperRange: BigInt(inputArrayAdjusted[15]),
      lowerRange: BigInt(inputArrayAdjusted[16]),
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
    console.log(borrowOutput);
  } else if (inputArrayAdjusted[0] == "4") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let dexFee = BigInt(inputArrayAdjusted[6]);
    let totalBorrowShares = BigInt(inputArrayAdjusted[7]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[8]),
      token1Debt: BigInt(inputArrayAdjusted[9]),
      token0RealReserves: BigInt(inputArrayAdjusted[10]),
      token1RealReserves: BigInt(inputArrayAdjusted[11]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[12]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[13]),
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
    console.log(paybackOutput);
  } else if (inputArrayAdjusted[0] == "5") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let totalSupplyShares = BigInt(inputArrayAdjusted[6]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[7]),
      token1RealReserves: BigInt(inputArrayAdjusted[8]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[9]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
    };
    const depositOutput = main.depositPerfect(
      token0Amt,
      token1Amt,
      token0Decimals,
      token1Decimals,
      slippage,
      totalSupplyShares,
      colReserves
    ).shares;
    console.log(depositOutput);
  } else if (inputArrayAdjusted[0] == "6") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let totalSupplyShares = BigInt(inputArrayAdjusted[6]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[7]),
      token1RealReserves: BigInt(inputArrayAdjusted[8]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[9]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
    };
    const withdrawOutput = main.withdrawPerfect(
      token0Amt,
      token1Amt,
      token0Decimals,
      token1Decimals,
      slippage,
      totalSupplyShares,
      colReserves
    ).shares;
    console.log(withdrawOutput);
  } else if (inputArrayAdjusted[0] == "7") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let totalBorrowShares = BigInt(inputArrayAdjusted[6]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[7]),
      token1Debt: BigInt(inputArrayAdjusted[8]),
      token0RealReserves: BigInt(inputArrayAdjusted[9]),
      token1RealReserves: BigInt(inputArrayAdjusted[10]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[12]),
    };
    const borrowOutput = main.borrowPerfect(
      token0Amt,
      token1Amt,
      token0Decimals,
      token1Decimals,
      slippage,
      totalBorrowShares,
      debtReserves
    ).shares;
    console.log(borrowOutput);
  } else if (inputArrayAdjusted[0] == "8") {
    let token0Amt = BigInt(inputArrayAdjusted[1]);
    let token1Amt = BigInt(inputArrayAdjusted[2]);
    let token0Decimals = BigInt(inputArrayAdjusted[3]);
    let token1Decimals = BigInt(inputArrayAdjusted[4]);
    let slippage = inputArrayAdjusted[5];
    let totalBorrowShares = BigInt(inputArrayAdjusted[6]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[7]),
      token1Debt: BigInt(inputArrayAdjusted[8]),
      token0RealReserves: BigInt(inputArrayAdjusted[9]),
      token1RealReserves: BigInt(inputArrayAdjusted[10]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[12]),
    };
    const paybackOutput = main.paybackPerfect(
      token0Amt,
      token1Amt,
      token0Decimals,
      token1Decimals,
      slippage,
      totalBorrowShares,
      debtReserves
    ).shares;
    console.log(paybackOutput);
  } else if (inputArrayAdjusted[0] == "9") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let withdrawToken0Or1 = BigInt(inputArrayAdjusted[2]);
    let decimals0Or1 = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let dexFee = BigInt(inputArrayAdjusted[5]);
    let totalSupplyShares = BigInt(inputArrayAdjusted[6]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[7]),
      token1RealReserves: BigInt(inputArrayAdjusted[8]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[9]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
    };
    const withdrawMaxOutput = main.withdrawMax(
      shares,
      withdrawToken0Or1,
      decimals0Or1,
      slippage,
      dexFee,
      totalSupplyShares,
      colReserves
    ).tokenAmount;

    console.log(withdrawMaxOutput);
  } else if (inputArrayAdjusted[0] == "10") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let withdrawToken0Or1 = BigInt(inputArrayAdjusted[2]);
    let decimals0Or1 = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let dexFee = BigInt(inputArrayAdjusted[5]);
    let totalBorrowShares = BigInt(inputArrayAdjusted[6]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[7]),
      token1Debt: BigInt(inputArrayAdjusted[8]),
      token0RealReserves: BigInt(inputArrayAdjusted[9]),
      token1RealReserves: BigInt(inputArrayAdjusted[10]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[12]),
    };
    const paybackOutput = main.paybackMax(
      shares,
      withdrawToken0Or1,
      decimals0Or1,
      slippage,
      dexFee,
      totalBorrowShares,
      debtReserves
    ).tokenAmount;

    console.log(paybackOutput);
  } else if (inputArrayAdjusted[0] == "11") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let token0Decimals = BigInt(inputArrayAdjusted[2]);
    let token1Decimals = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let totalSupplyShares = BigInt(inputArrayAdjusted[5]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[6]),
      token1RealReserves: BigInt(inputArrayAdjusted[7]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[8]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[9]),
    };
    const withdrawPerfectMaxOutput = main.withdrawPerfectMax(
      shares,
      token0Decimals,
      token1Decimals,
      slippage,
      totalSupplyShares,
      colReserves
    );
    const token0Amount = withdrawPerfectMaxOutput.token0Amt;

    console.log(token0Amount);
  } else if (inputArrayAdjusted[0] == "12") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let token0Decimals = BigInt(inputArrayAdjusted[2]);
    let token1Decimals = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let totalSupplyShares = BigInt(inputArrayAdjusted[5]);
    let colReserves = {
      token0RealReserves: BigInt(inputArrayAdjusted[6]),
      token1RealReserves: BigInt(inputArrayAdjusted[7]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[8]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[9]),
    };
    const withdrawPerfectMaxOutput = main.withdrawPerfectMax(
      shares,
      token0Decimals,
      token1Decimals,
      slippage,
      totalSupplyShares,
      colReserves
    );
    const token1Amount = withdrawPerfectMaxOutput.token1Amt;

    console.log(token1Amount);
  } else if (inputArrayAdjusted[0] == "13") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let token0Decimals = BigInt(inputArrayAdjusted[2]);
    let token1Decimals = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let totalBorrowShares = BigInt(inputArrayAdjusted[5]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[6]),
      token1Debt: BigInt(inputArrayAdjusted[7]),
      token0RealReserves: BigInt(inputArrayAdjusted[8]),
      token1RealReserves: BigInt(inputArrayAdjusted[9]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
    };
    const paybackPerfectMaxOutput = main.paybackPerfectMax(
      shares,
      token0Decimals,
      token1Decimals,
      slippage,
      totalBorrowShares,
      debtReserves
    );
    const token0Amount = paybackPerfectMaxOutput.token0Amt;

    console.log(token0Amount);
  } else if (inputArrayAdjusted[0] == "14") {
    let shares = BigInt(inputArrayAdjusted[1]);
    let token0Decimals = BigInt(inputArrayAdjusted[2]);
    let token1Decimals = BigInt(inputArrayAdjusted[3]);
    let slippage = inputArrayAdjusted[4];
    let totalBorrowShares = BigInt(inputArrayAdjusted[5]);
    let debtReserves = {
      token0Debt: BigInt(inputArrayAdjusted[6]),
      token1Debt: BigInt(inputArrayAdjusted[7]),
      token0RealReserves: BigInt(inputArrayAdjusted[8]),
      token1RealReserves: BigInt(inputArrayAdjusted[9]),
      token0ImaginaryReserves: BigInt(inputArrayAdjusted[10]),
      token1ImaginaryReserves: BigInt(inputArrayAdjusted[11]),
    };
    const paybackPerfectMaxOutput = main.paybackPerfectMax(
      shares,
      token0Decimals,
      token1Decimals,
      slippage,
      totalBorrowShares,
      debtReserves
    );
    const token1Amount = paybackPerfectMaxOutput.token1Amt;

    console.log(token1Amount);
  }
}

validate();
