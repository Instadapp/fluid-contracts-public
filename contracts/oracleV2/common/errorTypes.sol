// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

library ErrorTypes {
    /***********************************|
    |         Oracle V2 Common          |
    |__________________________________*/

    uint256 internal constant OracleV2Common__PriceZero = 310201;
    uint256 internal constant OracleV2Common__SharesZero = 310202;
    uint256 internal constant OracleV2Common__InvalidPegBuffer = 310203;

    /***********************************|
    |           Fluid Oracle            |
    |__________________________________*/

    uint256 internal constant FluidOracle__InvalidTargetDecimals = 310204;
}
