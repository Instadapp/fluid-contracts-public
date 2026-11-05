const Decimal = require("decimal.js");
const ethers = require("ethers");

Decimal.config({ precision: 100, rounding: Decimal.ROUND_DOWN });
// Process the input ticks from command line arguments
const tickArray = process.argv[2].split(",").map((tick) => parseInt(tick, 10));
const resultsArray = [];

for (let tick of tickArray) {
  let base = new Decimal(1.0015);
  if (tick < 0) {
    // For negative ticks, use the inverse operation
    base = new Decimal(1).div(new Decimal(1.0015));
    tick = -tick; // Make the tick positive for the calculation
  }
  // Calculate 2^96 * (base^tick)
  const jsResult = base.pow(tick).mul(new Decimal(2).pow(96)).toFixed(0);
  resultsArray.push(jsResult);
}

// Encode the array of results as a uint256[] for Solidity
const encodedResults = ethers.utils.defaultAbiCoder.encode(["uint256[]"], [resultsArray]);

process.stdout.write(encodedResults);
// 2^96 * (1.0015^32701) = 153360750482885682694572874635223624670375960075523.940454124
