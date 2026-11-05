//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { AuthInternals } from "../../../contracts/liquidity/adminModule/main.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { LiquidityCalcs } from "../../../contracts/libraries/liquidityCalcs.sol";

// todo : move to libraries test

abstract contract LiquidityCalcsRateV1Test is Test, AuthInternals {
    uint256 rateData;

    function setUp() public virtual {
        rateData = _computeRateDataPackedV1(
            AdminModuleStructs.RateDataV1Params(
                address(0), // token doesn't matter, we just want the packed uint256 rate data
                80 * 1e6, // kink = 80%
                4 * 1e6, // rate at 0 = 4% (constant min borrow rate)
                7 * 1e6, // rate at kink = 7%
                67 * 1e6 // rate at 100% utilization = 67% (max borrow rate)
            )
        );
    }

    function testCalcRateV1BelowKink() public {
        uint256 result = LiquidityCalcs.calcRateV1(rateData, 40 * 1e4);

        // should be 4% + half of 3% difference until kink (because utilization is half of kink) = 5.5% in 1e4
        assertEq(result, 55_000);
    }

    function testCalcRateV1AboveKink() public {
        uint256 result = LiquidityCalcs.calcRateV1(rateData, 90 * 1e4);

        // should be 37% because 90% is half between 80% and 100% and it grows by 60%, so half at 90% which is 30%
        // 30% + initial rate at kink 7% = 37%. in 1e4.
        assertEq(result, 370_000);
    }

    function testCalcRateV1AtKink() public {
        uint256 result = LiquidityCalcs.calcRateV1(rateData, 80 * 1e4);

        // should be 7%. in 1e4.
        assertEq(result, 70_000);
    }

    function testCalcRateV1AtMin() public {
        uint256 result = LiquidityCalcs.calcRateV1(rateData, 0 * 1e4);

        // should be 4%. in 1e4.
        assertEq(result, 40_000);
    }

    function testCalcRateV1AtMax() public {
        uint256 result = LiquidityCalcs.calcRateV1(rateData, 100 * 1e4);

        // should be 67%. in 1e4.
        assertEq(result, 670_000);
    }
}

abstract contract LiquidityUserModuleHelpersRateV2Test is Test, AuthInternals {
    uint256 rateData;

    function setUp() public virtual {
        rateData = _computeRateDataPackedV2(
            AdminModuleStructs.RateDataV2Params(
                address(0), // token doesn't matter, we just want the packed uint256 rate data
                60 * 1e6, // kink1 = 60%
                80 * 1e6, // kink2 = 80%
                4 * 1e6, // rate at 0 = 4% (constant min borrow rate)
                10 * 1e6, // rate at kink1 = 10%
                20 * 1e6, // rate at kink2 = 20%
                90 * 1e6 // rate at 100% utilization = 90% (max borrow rate)
            )
        );
    }

    function testCalcRateV2BelowKink1() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 30 * 1e4);

        // should be 4% + half of 6% difference until kink1 (because utilization is half of kink) = 7% in 1e4
        assertEq(result, 70_000);
    }

    function testCalcRateV2BetweenKinks() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 70 * 1e4);

        // should be 15% because 70% is half between 60% and 80% and it grows by 10%, so half at 70% which is 5%
        // 5% + initial rate at kink1 10% = 15%. in 1e4.
        assertEq(result, 150_000);
    }

    function testCalcRateV2AboveKink2() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 90 * 1e4);

        // should be 37% because 90% is half between 80% and 100% and it grows by 70%, so half at 90% which is 35%
        // 35% + initial rate at kink2 20% = 55%. in 1e4.
        assertEq(result, 550_000);
    }

    function testCalcRateV2AtKink1() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 60 * 1e4);

        // should be 10%. in 1e4.
        assertEq(result, 100_000);
    }

    function testCalcRateV2AtKink2() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 80 * 1e4);

        // should be 20%. in 1e4.
        assertEq(result, 200_000);
    }

    function testCalcRateV2AtMin() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 0 * 1e4);

        // should be 4%. in 1e4.
        assertEq(result, 40_000);
    }

    function testCalcRateV2AtMax() public {
        uint256 result = LiquidityCalcs.calcRateV2(rateData, 100 * 1e4);

        // should be 90%. in 1e4.
        assertEq(result, 900_000);
    }
}
