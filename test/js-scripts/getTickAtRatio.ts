import Decimal from "decimal.js";
import { ethers } from "ethers";

const ratioArray = process.argv[2].split(",");
const resultsArray = [];
for (let ratio of ratioArray) {
  const jsResult = new Decimal(ratio).div(new Decimal(2).pow(96)).log(1.0015).floor().toFixed(0);
  resultsArray.push(jsResult);
}
process.stdout.write(ethers.utils.defaultAbiCoder.encode(["int256[]"], [resultsArray]));
