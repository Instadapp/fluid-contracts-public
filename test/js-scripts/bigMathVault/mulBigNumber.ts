import Decimal from "decimal.js";
import { ethers } from "ethers";

const DECIMALS_DEBT_FACTOR = 16384;

const coefficient1 = process.argv[2];
const exponent1 = process.argv[3];
const coefficient2 = process.argv[4];
const exponent2 = process.argv[5];
const coefficientFromMultiplication = process.argv[6];
const exponentFromMultiplication = process.argv[7];

const decimalCoefficient1 = new Decimal(coefficient1.toString());
const decimalExponent1 = new Decimal(exponent1.toString());
const decimalCoefficient2 = new Decimal(coefficient2.toString());
const decimalExponent2 = new Decimal(exponent2.toString());
const decimalCoefficientFromMultiplication = new Decimal(coefficientFromMultiplication.toString());

const normalNumber1 = decimalCoefficient1.mul(
  new Decimal(2).pow(decimalExponent1.sub(DECIMALS_DEBT_FACTOR).toNumber())
);
const normalNumber2 = decimalCoefficient2.mul(
  new Decimal(2).pow(decimalExponent2.sub(DECIMALS_DEBT_FACTOR).toNumber())
);

const normalDivJSResult = normalNumber1.mul(normalNumber2);

let normalDivSolidityResult;

var exponentResult = new Decimal(exponentFromMultiplication).sub(DECIMALS_DEBT_FACTOR);
if (exponentResult.isNegative()) {
  var divisionResult = new Decimal(1).div(new Decimal(2).pow(exponentResult.abs()));
  normalDivSolidityResult = divisionResult.mul(decimalCoefficientFromMultiplication);
} else {
  normalDivSolidityResult = decimalCoefficientFromMultiplication.mul(new Decimal(2).pow(exponentResult));
}

// Calculate the absolute difference
const diff = normalDivJSResult.sub(normalDivSolidityResult).abs();

// Calculate the average of the two values
const average = normalDivJSResult.add(normalDivSolidityResult).div(2);

// Calculate the percentage difference
const percentageDiff = diff.div(average).mul(100);

// Tolerance: (1e-8%)
const tolerance = new Decimal("1e-8");

// Compare percentage difference with tolerance
if (percentageDiff.lte(tolerance)) {
  process.stdout.write(ethers.utils.defaultAbiCoder.encode(["bool"], [true]));
} else {
  process.stdout.write(ethers.utils.defaultAbiCoder.encode(["bool"], [false]));
}
