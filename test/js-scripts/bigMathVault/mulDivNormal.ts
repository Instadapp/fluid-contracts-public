import Decimal from "decimal.js";
import { ethers } from "ethers";

const DECIMALS_DEBT_FACTOR = 16384;

const number1 = process.argv[2];
const coefficient1 = process.argv[3];
const exponent1 = process.argv[4];
const coefficient2 = process.argv[5];
const exponent2 = process.argv[6];
const resultNumber = process.argv[7];

const decimalCoefficient1 = new Decimal(coefficient1.toString());
const decimalExponent1 = new Decimal(exponent1.toString());
const decimalCoefficient2 = new Decimal(coefficient2.toString());
const decimalExponent2 = new Decimal(exponent2.toString());

const normalNumber1 = new Decimal(number1);
const normalNumber2 = decimalCoefficient1.mul(
  new Decimal(2).pow(decimalExponent1.sub(DECIMALS_DEBT_FACTOR).toNumber())
);
const normalNumber3 = decimalCoefficient2.mul(
  new Decimal(2).pow(decimalExponent2.sub(DECIMALS_DEBT_FACTOR).toNumber())
);
const normalNumberResult = new Decimal(resultNumber);

const normalDivJSResult = normalNumber1.mul(normalNumber2).div(normalNumber3);

const normalDivJSResultWithoutDecimals = new Decimal(normalDivJSResult.toFixed(0));

const diff = normalDivJSResultWithoutDecimals.sub(normalNumberResult).abs();

// Calculate the average of the two values
const average = normalDivJSResultWithoutDecimals.add(normalNumberResult).div(2);

// Calculate the percentage difference
const percentageDiff = diff.div(average).mul(100);

// Tolerance: (1e-1%)
const tolerance = new Decimal("1e-1");

if (diff.toFixed() == "0" || percentageDiff.lte(tolerance)) {
  process.stdout.write(ethers.utils.defaultAbiCoder.encode(["bool"], [true]));
} else {
  process.stdout.write(ethers.utils.defaultAbiCoder.encode(["bool"], [false]));
}
