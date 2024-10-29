// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";

import "forge-std/console2.sol";

contract TickMathTest is Test {
    using TickMath for int;

    // Test constants based on the TickMath library
    int24 MIN_TICK = -32767;
    int24 MAX_TICK = 32767;
    uint256 MIN_RATIOX96 = 37075072;
    uint256 MAX_RATIOX96 = 169307877264527972847801929085841449095838922544595;

    uint256 ZERO_TICK_SCALED_RATIO = 0x1000000000000000000000000; // 1 << 96 // 79228162514264337593543950336
    uint256 _1E18 = 1000000000000000000;

    uint256 constant ONE_PIP = 1e6;

    uint256[] getRatioAtTickFuzzResults;
    int24[] getTickAtRatioFuzzResults;

    function setUp() public {
        delete getRatioAtTickFuzzResults;
        delete getTickAtRatioFuzzResults;
    }

    function test_MIN_TICK_equalsNegativeMAX_TICK() public {
        int24 minTick = TickMath.MIN_TICK;
        int24 maxTick = TickMath.MAX_TICK;
        assertEq(minTick, -maxTick);
    }

    function test_MAX_TICK_equalsNegativeMIN_TICK() public {
        int24 maxTick = TickMath.MAX_TICK;
        int24 minTick = TickMath.MIN_TICK;
        assertEq(maxTick, -minTick);
    }

    function test_getRatioAtTick_throwsForTooLow() public {
        vm.expectRevert();
        TickMath.getRatioAtTick(TickMath.MIN_TICK - 1);
    }

    function test_getRatioAtTick_throwsForTooHigh() public {
        vm.expectRevert();
        TickMath.getRatioAtTick(TickMath.MAX_TICK + 1);
    }

    function test_getRatioAtTick_isValidMinTick() public {
        // (1 << 96) * (1.0015**-32766) = 169054295820796777464023780275713939224088954838218.742314304
        uint256 ratioX96 = TickMath.getRatioAtTick(TickMath.MIN_TICK);
        assertEq(ratioX96, TickMath.MIN_RATIOX96 - 1);
        assertEq(ratioX96, 37075071); // smaller than MIN_RATIOX96 and its acceptable
    }

    function test_getRatioAtTick_isValidMinTickAddOne() public {
        // (1 << 96) * (1.0015**-32766) = 37130684.5821925702256722644318237799039314818392515089649111
        uint256 ratioX96 = TickMath.getRatioAtTick(TickMath.MIN_TICK + 1);
        assertEq(ratioX96, 37130684);
    }

    function test_getRatioAtTick_isValidMaxTick() public {
        uint256 ratioX96 = TickMath.getRatioAtTick(TickMath.MAX_TICK);
        assertEq(ratioX96, TickMath.MAX_RATIOX96);
    }

    function test_getTickAtRatio_throwsForTooLow() public {
        vm.expectRevert();
        TickMath.getTickAtRatio(TickMath.MIN_RATIOX96 - 1);
    }

    function test_getTickAtRatio_throwsForTooHigh() public {
        vm.expectRevert();
        TickMath.getTickAtRatio(TickMath.MAX_RATIOX96 + 1);
    }

    function test_getTickAtRatio_isValidMinRatioX96() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio(TickMath.MIN_RATIOX96);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MIN_TICK);
    }

    function test_getTickAtRatio_isValidMinRatioPlusOne() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio(TickMath.MIN_RATIOX96 + 1);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MIN_TICK);
    }

    function test_getTickAtRatio_isValidMinRatioPlusZeroPointFourteenPercent() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio((TickMath.MIN_RATIOX96 * 10014) / 10000);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MIN_TICK);
    }

    function test_getTickAtRatio_isValidMinRatioPlusZeroPointFifteenPercent() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio((TickMath.MIN_RATIOX96 * 10015) / 10000);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MIN_TICK);
    }

    function test_getTickAtRatio_isValidMinRatioPlusLittleMoreThanZeroPointFifteenPercent() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio((TickMath.MIN_RATIOX96 * 10015001) / 10000000);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MIN_TICK + 1);
    }

    function test_getTickAtRatio_isValidMaxRatioMinusZeroPointOnePercent() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio((TickMath.MAX_RATIOX96 * 10000) / 10001);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MAX_TICK - 1); // as library rounds down tick
    }

    function test_getTickAtRatio_isValidMaxRatioMinusAlmostFifteenPercent() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio((TickMath.MAX_RATIOX96 * 100000000000000) / 100149999999999);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MAX_TICK - 1); // as library rounds down tick
    }

    function test_getTickAtRatio_isValidMaxRatioMinusZeroPointSixteenPercent() public {
        // in our case precision is 0.15%
        (int256 retrievedTick, ) = TickMath.getTickAtRatio(((TickMath.MAX_RATIOX96 * 10000) / 10016));
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MAX_TICK - 2);
    }

    function test_getTickAtRatio_isValidMaxRatioMinusOne() public {
        (, uint256 perfectRatio) = TickMath.getTickAtRatio(TickMath.MAX_RATIOX96);
        //tick 32768 is for ratio range between perfectRatio <-> TickMath.MAX_RATIOX96
        (int256 tick1, ) = TickMath.getTickAtRatio((perfectRatio * 10000) / 10001);
        int24 tickInAlmostHighestRatioInTheTick = int24(tick1);
        assertEq(tickInAlmostHighestRatioInTheTick, TickMath.MAX_TICK - 1);
        (int256 tick2, ) = TickMath.getTickAtRatio((perfectRatio * 10000) / 10014);
        int24 tickInAlmostLowestRatioInTheTick = int24(tick2);
        assertEq(tickInAlmostLowestRatioInTheTick, TickMath.MAX_TICK - 1);
    }

    function test_getTickAtRatio_isValidMaxRatioX96() public {
        (int256 retrievedTick, ) = TickMath.getTickAtRatio(TickMath.MAX_RATIOX96);
        int24 tick = int24(retrievedTick);
        assertEq(tick, TickMath.MAX_TICK);
    }

    function testFuzz_TickAndRatioConsistency(uint256 ratioX96) public {
        vm.assume(ratioX96 >= TickMath.MIN_RATIOX96 && ratioX96 <= TickMath.MAX_RATIOX96);
        (int256 retrievedTick, uint256 perfectRatio) = TickMath.getTickAtRatio(ratioX96);
        int24 tick = int24(retrievedTick);
        uint256 ratioFromTick = TickMath.getRatioAtTick(tick);

        // Calculate the difference and the percentage difference
        uint256 factor = 100000000000000000; // scaling by a factor of 1,000,000,000,000,000,00
        uint256 acceptableMargin = 1; // 0.00000000000001% scaled by 1,000,000,000,000,000,00
        if (ratioFromTick < perfectRatio) {
            uint256 difference = ratioFromTick > perfectRatio
                ? (ratioFromTick - perfectRatio)
                : (perfectRatio - ratioFromTick);

            uint256 scaledDifference = difference * factor;

            uint256 percentageDifference = scaledDifference / perfectRatio;

            assertTrue(percentageDifference <= acceptableMargin);
        } else {
            assertGe(ratioFromTick, perfectRatio);
        }
        tick += 1;

        if (tick <= TickMath.MAX_TICK) {
            uint256 nextPerfectRatio = (perfectRatio * 10015) / 10000;
            uint256 nextRatioFromTick = TickMath.getRatioAtTick(tick);
            if (nextRatioFromTick < nextPerfectRatio) {
                uint256 difference = nextRatioFromTick > nextPerfectRatio
                    ? (nextRatioFromTick - nextPerfectRatio)
                    : (nextPerfectRatio - nextRatioFromTick);

                uint256 scaledDifference = difference * factor;

                uint256 percentageDifference = scaledDifference / nextPerfectRatio;

                assertTrue(percentageDifference <= acceptableMargin);
            } else {
                assertGe(nextRatioFromTick, nextPerfectRatio);
            }
        }
    }

    // Fuzz tests for random values within the valid range
    function testFuzz_getRatioAtTick(int24 tick) public {
        vm.assume(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK);
        uint256 ratioX96 = TickMath.getRatioAtTick(tick);
        assertTrue(ratioX96 >= TickMath.MIN_RATIOX96 && ratioX96 <= TickMath.MAX_RATIOX96);
    }

    function testFuzz_getTickAtRatio(uint256 ratioX96) public {
        vm.assume(ratioX96 >= TickMath.MIN_RATIOX96 && ratioX96 <= TickMath.MAX_RATIOX96); //getTickAtRatio for MIN_RATIOX96 returns perfectRatioX96 which is TickMath.MIN_RATIOX96 - 1 which is fine
        (int tick, uint perfectRatioX96) = TickMath.getTickAtRatio(ratioX96);
        assertTrue(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK);
        if (tick > TickMath.MIN_TICK) {
            assertTrue(perfectRatioX96 >= TickMath.MIN_RATIOX96 && perfectRatioX96 <= TickMath.MAX_RATIOX96);
        }
    }

    function testSymmetry(int24 tick) public {
        vm.assume(tick > TickMath.MIN_TICK && tick < TickMath.MAX_TICK);
        uint256 ratioX96Positive = TickMath.getRatioAtTick(tick);
        uint256 ratioX96Negative = TickMath.getRatioAtTick(-tick);
        uint256 product = (ratioX96Positive * ratioX96Negative) >> 96;
        assertApproxEqRel(product, 1 << 96, 1e12); // Using a tolerance of 1e-6 for the product
    }

    // Incremental Tick Tests
    function testIncrementalTicks() public {
        for (int24 tick = TickMath.MIN_TICK; tick < TickMath.MIN_TICK + 100; tick++) {
            uint256 ratio = TickMath.getRatioAtTick(tick);
            uint256 nextRatio = TickMath.getRatioAtTick(tick + 1);
            assertTrue(nextRatio > ratio);
        }
    }

    int24[] ticksss;
    function test_getRatioAtTick_PrecisionOfGetRatioAtTick() public {
        string memory jsParameters = "";
        string[] memory runJsInputs = new string[](6);

        // build ffi command string
        runJsInputs[0] = "npm";
        runJsInputs[1] = "--silent";
        runJsInputs[2] = "run";
        runJsInputs[3] = "forge-test-getRatioAtTick-precision";
        runJsInputs[4] = "--";

        int24 tick = 1;

        while (true) {
            if (tick > MAX_TICK) break;
            // test negative and positive tick
            for (uint256 i = 0; i < 2; i++) {
                tick = tick * -1;
                if (tick != -1) jsParameters = string(abi.encodePacked(jsParameters, ",")); // do not leave comma in front of first number
                // add tick to javascript parameters to be calulated inside script
                jsParameters = string(abi.encodePacked(jsParameters, vm.toString(int256(tick))));
                // track solidity result for tick
                // console2.log("tick", tick);
                ticksss.push(tick);
                getRatioAtTickFuzzResults.push(TickMath.getRatioAtTick(tick));
            }
            tick = tick + 20;
        }

        runJsInputs[5] = jsParameters;
        bytes memory jsResult = vm.ffi(runJsInputs);
        uint256[] memory jsRatios = abi.decode(jsResult, (uint256[]));

        uint256 precision_ = 10;
        uint256 precisionInverse_ = 1e17 / precision_;
        for (uint256 i = 0; i < jsRatios.length; i++) {
            uint256 jsRatio = jsRatios[i];
            uint256 solResult = getRatioAtTickFuzzResults[i];
            assertApproxEqRel(jsRatio, solResult, precision_);
            if (jsRatio > solResult) {
                if (((jsRatio * precisionInverse_) / solResult) > precisionInverse_) {
                    console2.log(ticksss[i]);
                }
            } else {
                if (((solResult * precisionInverse_) / jsRatio) > precisionInverse_) {
                    console2.log(ticksss[i]);
                }
            }
        }
    }

    function test_getRatioAtTick_matchesJavaScriptImplByOneHundrethOfABip() public {
        string memory jsParameters = "";
        string[] memory runJsInputs = new string[](6);

        // build ffi command string
        runJsInputs[0] = "npm";
        runJsInputs[1] = "--silent";
        runJsInputs[2] = "run";
        runJsInputs[3] = "forge-test-getRatioAtTick";
        runJsInputs[4] = "--";

        int24 tick = 1;

        while (true) {
            if (tick > MAX_TICK) break;
            // test negative and positive tick
            for (uint256 i = 0; i < 2; i++) {
                tick = tick * -1;
                if (tick != -1) jsParameters = string(abi.encodePacked(jsParameters, ",")); // do not leave comma in front of first number
                // add tick to javascript parameters to be calulated inside script
                jsParameters = string(abi.encodePacked(jsParameters, vm.toString(int256(tick))));
                // track solidity result for tick
                getRatioAtTickFuzzResults.push(TickMath.getRatioAtTick(tick));
            }
            tick = tick * 2;
        }

        runJsInputs[5] = jsParameters;
        bytes memory jsResult = vm.ffi(runJsInputs);
        uint256[] memory jsRatios = abi.decode(jsResult, (uint256[]));

        for (uint256 i = 0; i < jsRatios.length; i++) {
            uint256 jsRatio = jsRatios[i];
            uint256 solResult = getRatioAtTickFuzzResults[i];
            (uint256 gtResult, uint256 ltResult) = jsRatio > solResult ? (jsRatio, solResult) : (solResult, jsRatio);
            uint256 resultsDiff = gtResult - ltResult;

            // assert solc/js result is at most off by 1/100th of a bip (aka one pip)
            assertEq((resultsDiff * ONE_PIP) / jsRatio, 0);
        }
    }

    function test_getTickAtRatio_matchesJavascriptImplWithin1() public {
        string memory jsParameters = "";
        string[] memory runJsInputs = new string[](5);

        // build ffi command string
        runJsInputs[0] = "npm";
        runJsInputs[1] = "--silent";
        runJsInputs[2] = "run";
        runJsInputs[3] = "forge-test-getTickAtRatio";

        uint256 ratio = TickMath.MIN_RATIOX96;
        unchecked {
            while (ratio < ratio * 2) {
                if (ratio > TickMath.MAX_RATIOX96) {
                    ratio = TickMath.MAX_RATIOX96;
                }
                if (ratio != TickMath.MIN_RATIOX96) jsParameters = string(abi.encodePacked(jsParameters, ",")); // do not leave comma in front of first number
                // add tick to javascript parameters to be calulated inside script
                jsParameters = string(abi.encodePacked(jsParameters, vm.toString(ratio)));
                // track solidity result for ratio
                (int tick, ) = TickMath.getTickAtRatio(ratio);
                getTickAtRatioFuzzResults.push(int24(tick));
                if (ratio == TickMath.MAX_RATIOX96) {
                    break;
                }
                ratio = ratio * 2;
            }
        }

        runJsInputs[4] = jsParameters;
        bytes memory jsResult = vm.ffi(runJsInputs);
        int24[] memory jsTicks = abi.decode(jsResult, (int24[]));

        for (uint256 i = 0; i < jsTicks.length; i++) {
            int24 jsTick = jsTicks[i];
            int24 solTick = getTickAtRatioFuzzResults[i];

            (int24 gtResult, int24 ltResult) = jsTick > solTick ? (jsTick, solTick) : (solTick, jsTick);
            int24 resultsDiff = gtResult - ltResult;
            assertLt(resultsDiff, 2);
        }
    }

    // A series of tests that focus on evaluating the precision of a function across different ranges of tick values. These tests are designed to assess the function's ability to accurately calculate tick values based on given ratios. The tick values are used to map ratios to specific points, which are essentially positions on a scale. The overall goal is to ensure that the function can reliably identify the correct tick position, even when dealing with values that are close to the boundaries between different ticks.

    // Graphic below represents where each case tries to catch nearest value to get value
    // 1. To still get same tick on max value of the same tick
    // 2. To get one tick more on min value of the one tick more
    // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
    // 4. To get two ticks less on min value of the two more ticks
    // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)

    //         TICK - 2            TICK - 1               TICK               TICK + 1
    // |--------------------|--------------------|--------------------|--------------------|
    //                     ^ ^                  ^                    ^ ^
    //                     | |                  |                    | |
    //                     4 3                  5                    1 2

    struct MultiplierDivisorTickDifference {
        uint256 multiplier;
        uint256 divisor;
        int24 tickDifference;
    }

    // TODO: Instead of having seperated tests for each range we can use bound cheatcode from Foundry (https://book.getfoundry.sh/reference/forge-std/bound)
    function testPrecisionLimits_From_Minus32767_To_Minus32668_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 1;
        int24 endTick = TickMath.MIN_TICK + 100;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 1001500001,
                divisor: 1000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015001,
                divisor: 10000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000,
                divisor: 10014999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 1000000000,
                divisor: 1001499999,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000000000000000000000000000000000000000000,
                divisor: 100000000000000000000000000000000000000000000000000000000000001,
                tickDifference: -1
            });
        // for
        // multiplier: 10000,
        // divisor: 10000,
        // its failing
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Minus32667_To_Minus31768_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 101;
        int24 endTick = TickMath.MIN_TICK + 1000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100150000001,
                divisor: 100000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015001,
                divisor: 10000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000,
                divisor: 10014999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000,
                divisor: 100149999999,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000000000000000000000000000000000000000000,
                divisor: 100000000000000000000000000000000000000000000000000000000000001,
                tickDifference: -1
            });
        // for
        // multiplier: 10000,
        // divisor: 10000,
        // its failing
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Minus31767_To_Minus22768_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 1001;
        int24 endTick = TickMath.MIN_TICK + 10000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 10015000000000001,
                divisor: 10000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015001,
                divisor: 10000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000,
                divisor: 10014999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 1000000000000000,
                divisor: 1001499999999999,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000000000000000000000000000000000000000000,
                divisor: 100000000000000000000000000000000000000000000000000000000000001,
                tickDifference: -1
            });
        // for
        // multiplier: 10000,
        // divisor: 10000,
        // its failing
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Minus22767_To_Minus12768_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 10001;
        int24 endTick = TickMath.MIN_TICK + 20000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100150000000000000000001,
                divisor: 100000000000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015000000001,
                divisor: 10000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000000000,
                divisor: 10014999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000,
                divisor: 100149999999999999999999,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 1000000000000000000000,
                divisor: 999999999999999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Minus12767_To_Minus2768_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 20001;
        int24 endTick = TickMath.MIN_TICK + 30000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 10014999999999999999999999,
                divisor: 10000000000000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 100150000000000000001,
                divisor: 100000000000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000,
                divisor: 100149999999999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10015000000000000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10000000000000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Minus2767_To_Plus7232_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 30001;
        int24 endTick = TickMath.MIN_TICK + 40000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 10014999999999999999999999,
                divisor: 10000000000000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015000000000000000000001,
                divisor: 10000000000000000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10014999999999999999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10015000000000000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10000000000000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Plus7233_To_Plus17232_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 40001;
        int24 endTick = TickMath.MIN_TICK + 50000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100149999999999999999999999,
                divisor: 100000000000000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015000000000000000000001,
                divisor: 10000000000000000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10014999999999999999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000000,
                divisor: 100150000000000000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000000000,
                divisor: 100000000000000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Plus17233_To_Plus27232_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 50001;
        int24 endTick = TickMath.MIN_TICK + 60000;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100149999999999999999,
                divisor: 100000000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015000000000000000000001,
                divisor: 10000000000000000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000000000000000000000,
                divisor: 10014999999999999999999999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000,
                divisor: 100150000000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000000,
                divisor: 100000000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_From_Plus27233_To_Max_Tick() public {
        int24 startTick = TickMath.MIN_TICK + 60001;
        int24 endTick = TickMath.MAX_TICK;
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100149999999999999,
                divisor: 100000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 1001499999999999999999999,
                divisor: 1000000000000000000000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 1000000000000000000000000,
                divisor: 1001500000000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000,
                divisor: 100150000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000,
                divisor: 100000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionLimits_ForAllTicks() public {
        // In order to test all posible ticks please comment and uncomment startTick, endTick pair variables one by one and run this test 3 times.
        // It's not possible to test all possible ticks at once because of Out of Gas issue.
        // =============== 1 ==========================
        // int24 startTick = TickMath.MIN_TICK + 1;
        // int24 endTick = TickMath.MIN_TICK + 20000;
        // =============== 2 ==========================
        // int24 startTick = TickMath.MIN_TICK + 20001;
        // int24 endTick = TickMath.MIN_TICK + 40000;
        // =============== 3 ==========================
        // int24 startTick = TickMath.MIN_TICK + 40001;
        // int24 endTick = TickMath.MIN_TICK + 60000;
        // =============== 4 ==========================
        int24 startTick = TickMath.MIN_TICK + 60001;
        int24 endTick = TickMath.MAX_TICK;
        // ============================================
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors = new MultiplierDivisorTickDifference[](5);

        // 1. To still get same tick on max value of the same tick
        MultiplierDivisorTickDifference
            memory toStillGetSomeTickOnMaxValueOfTheSameTick = MultiplierDivisorTickDifference({
                multiplier: 100149999999999999,
                divisor: 100000000000000000,
                tickDifference: 0
            });
        multipliersWithDivisors[0] = toStillGetSomeTickOnMaxValueOfTheSameTick;

        // 2. To get one tick more on min value of the one tick more
        MultiplierDivisorTickDifference
            memory toGetOneTickMoreOnMinValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10015001,
                divisor: 10000000,
                tickDifference: 1
            });
        multipliersWithDivisors[1] = toGetOneTickMoreOnMinValueOfTheOneTickMore;

        // 3. To get one tick less on max value of the one tick more (we are reaching 'almost' two ticks more)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMaxValueOfTheOneTickMore = MultiplierDivisorTickDifference({
                multiplier: 10000000,
                divisor: 10014999,
                tickDifference: -1
            });
        multipliersWithDivisors[2] = toGetOneTickLessOnMaxValueOfTheOneTickMore;

        // 4. To get two ticks less on min value of the two more ticks
        MultiplierDivisorTickDifference
            memory toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000,
                divisor: 100150000000000001,
                tickDifference: -2
            });
        multipliersWithDivisors[3] = toGetTwoTicksLessOnMinValueOfTheTwoMoreTicks;

        // 5. To get one tick less on min value of the two more ticks (we are reaching 'almost' same tick)
        MultiplierDivisorTickDifference
            memory toGetOneTickLessOnMinValueOfTheTwoMoreTicks = MultiplierDivisorTickDifference({
                multiplier: 100000000000000000,
                divisor: 100000000000000001,
                tickDifference: -1
            });
        multipliersWithDivisors[4] = toGetOneTickLessOnMinValueOfTheTwoMoreTicks;

        testPrecisionForTickRange(startTick, endTick, multipliersWithDivisors);
    }

    function testPrecisionForTickRange(
        int24 startTick,
        int24 endTick,
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors
    ) private {
        for (int24 tick = startTick; tick <= endTick; tick++) {
            uint256 ratio = TickMath.getRatioAtTick(tick);
            if (ratio >= TickMath.MIN_RATIOX96 && ratio <= TickMath.MAX_RATIOX96) {
                testTickPrecision(tick, ratio, multipliersWithDivisors);
            }
        }
    }

    function testTickPrecision(
        int24 tick,
        uint256 ratio,
        MultiplierDivisorTickDifference[] memory multipliersWithDivisors
    ) private {
        int retrievedTick;
        uint256 newRatio;
        int24 newTick;

        for (uint256 i = 0; i < multipliersWithDivisors.length; i++) {
            newRatio = (ratio * multipliersWithDivisors[i].multiplier) / multipliersWithDivisors[i].divisor;
            if (newRatio >= TickMath.MIN_RATIOX96 && newRatio <= TickMath.MAX_RATIOX96) {
                (retrievedTick, ) = TickMath.getTickAtRatio(newRatio);
                newTick = int24(retrievedTick);
                assertEq(tick + multipliersWithDivisors[i].tickDifference, newTick);
            }
        }
    }
}
