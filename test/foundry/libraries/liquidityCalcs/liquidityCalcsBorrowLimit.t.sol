//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import "forge-std/console2.sol";

contract LibraryLiquidityCalcsBorrowLimitsBaseTest is LibraryLiquidityCalcsBaseTest {
    uint256 constant DEFAULT_EXPAND_PERCENTAGE = 20 * 1e2; // 20%
    uint256 constant DEFAULT_BASE_LIMIT = 5 ether;
    uint256 constant DEFAULT_MAX_LIMIT = 10 ether;
    uint256 constant DEFAULT_EXPAND_DURATION = 200 seconds;

    uint256 immutable DEFAULT_BASE_LIMIT_AFTER_BIG_MATH;
    uint256 immutable DEFAULT_MAX_LIMIT_AFTER_BIG_MATH;

    constructor() {
        DEFAULT_BASE_LIMIT_AFTER_BIG_MATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(DEFAULT_BASE_LIMIT, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN),
            8,
            0xff
        );

        DEFAULT_MAX_LIMIT_AFTER_BIG_MATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(DEFAULT_MAX_LIMIT, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN),
            8,
            0xff
        );
    }

    function setUp() public virtual override {
        super.setUp();

        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp
    }

    function _getUserBorrowDataForBeforeOperate(
        uint256 userBorrow,
        uint256 previousLimit,
        uint256 lastUpdateTimestamp,
        uint256 expandPercentage,
        uint256 expandDuration,
        uint256 baseLimit,
        uint256 maxLimit
    ) internal pure returns (uint256) {
        return
            _simulateUserBorrowDataFull(
                1, // interest mode irrelevant for borrow limit calculation
                userBorrow,
                previousLimit,
                lastUpdateTimestamp,
                expandPercentage,
                expandDuration,
                baseLimit,
                maxLimit,
                false // user pause status irrelevant for borrow limit calculation
            );
    }

    function _getUserBorrowDataForAfterOperate(
        uint256 userBorrow,
        uint256 expandPercentage,
        uint256 expandDuration,
        uint256 baseLimit,
        uint256 maxLimit
    ) internal pure returns (uint256) {
        return
            _simulateUserBorrowDataFull(
                1, // interest mode irrelevant for borrow limit calculation
                userBorrow,
                0, // previous limit in storage should never matter for after operate limit
                0, // last update timestamp in storage should never matter for after operate limit
                expandPercentage,
                expandDuration,
                baseLimit,
                maxLimit,
                false // user pause status irrelevant for borrow limit calculation
            );
    }
}

contract LibraryLiquidityCalcsBorrowLimitBeforeOperateTests is LibraryLiquidityCalcsBorrowLimitsBaseTest {
    function test_calcBorrowLimitBeforeOperate_WhenLastUpdateTimestampIsZero() public {
        uint256 userBorrow = 0;
        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = 0;

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH); // limit should be base limit
    }

    function test_calcBorrowLimitBeforeOperate_WhenFullExpansionIsBelowBaseLimit() public {
        uint256 userBorrow = 2 ether; // full expansion will be 2.8 ether
        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH); // limit should be base limit
    }

    function test_calcBorrowLimitBeforeOperate_WhenFullExpansionIsExactlyBaseLimit() public {
        uint256 userBorrow = 4.8 ether;
        uint256 previousLimit = DEFAULT_BASE_LIMIT_AFTER_BIG_MATH;
        uint256 lastUpdateTimestamp = block.timestamp; // 0 difference so limit should be previous limit

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH); // limit should be base limit
    }

    function test_calcBorrowLimitBeforeOperate_WhenLastUpdateTimestampIsBlockTimestamp() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 6 ether;
        uint256 lastUpdateTimestamp = block.timestamp; // 0 difference so limit should be previous limit

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, previousLimit);
    }

    function test_calcBorrowLimitBeforeOperate_WhenExpandPercentZero() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 8 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            0, // expand percent = 0
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, userBorrow); // should be user Borrow
    }

    function test_calcBorrowLimitBeforeOperate_WhenExpandPercent100() public {
        uint256 userBorrow = 7 ether; // full expansion will be 14 ether
        uint256 previousLimit = 8 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            100 * 1e2, // expand percent = 100%
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            100 ether // ignore max limit for this test
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, 14 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenExpandPercentMax() public {
        uint256 userBorrow = 7 ether; // full expansion will be 18,4681 ether
        uint256 previousLimit = 8 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 2; // half expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            16_383, // expand percent = 163,83%.  max expand percent is 16_383 (14 bits)
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            100 ether // ignore max limit for this test
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // total expansion is 11,4681 ether. half of that has elapsed so 5,73405 ether. starting from 8 ether.
        // so limit should be 8 ether + 5,73405 ether = 13,73405 ether
        assertEq(limit, 13.73405 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenShrinking() public {
        // because of new payback -> shrinking. previous limit higher than expansion

        uint256 userBorrow = 6 ether; // full expansion will be 7.2 ether
        uint256 previousLimit = 8 ether;
        uint256 lastUpdateTimestamp = block.timestamp - 1;

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // shrinking must be instant
        assertEq(limit, 7.2 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenShrinkingMaxExpansionAbovePreviousLimit() public {
        uint256 userBorrow = 6 ether; // full expansion will be 7.2 ether
        uint256 previousLimit = 7 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // 10% expanded of 1.2 ether = 0.12 ether, starting from 7 ether. so limit should be 7.12 ether
        assertEq(limit, 7.12 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenExpanding() public {
        // because of new borrow -> expansion. previous limit lower than expansion
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 7.5 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 5; // 20% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // 20% expanded of 1.4 ether = 0.28 ether, starting from 7.5 ether. so limit should be 7.78 ether
        assertEq(limit, 7.78 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenExpandingBorrowedExactlyToLimit() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 7 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, 8.4 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenShrinkingToBelowBaseLimit() public {
        uint256 userBorrow = 4 ether; // full expansion will be 4.8 ether
        uint256 previousLimit = 8 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // shrinking to base limit is instant
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitBeforeOperate_WhenMoreThanExpandDurationElapsed() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 7.5 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION * 5; // way more than 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, 8.4 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenUserBorrow0() public {
        uint256 userBorrow = 0;
        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // limit should be base limit
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitBeforeOperate_When10PercentOf30PercentExpanded() public {
        uint256 userBorrow = 7 ether; // full expansion will be 9.1 ether
        uint256 previousLimit = 7.5 ether;
        uint256 expandPercentage = 30 * 1e2;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // 10% expanded of 2.1 ether = 0.21 ether
        assertEq(limit, 7.71 ether);
    }

    function test_calcBorrowLimitBeforeOperate_When10PercentOf30PercentExpandedFromPreviousLimitHigher() public {
        uint256 userBorrow = 7 ether; // full expansion will be 9.1 ether
        uint256 previousLimit = 10 ether;
        uint256 expandPercentage = 30 * 1e2;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // shrinked to max expansion immediately because last limit > max expansion
        assertEq(limit, 9.1 ether);
    }

    function test_calcBorrowLimitBeforeOperate_When50PercentOf20PercentExpanded() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 7.5 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 2; // 50% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // 50% expanded of 1.4 ether = 0.7 ether
        assertEq(limit, 8.2 ether);
    }

    function test_calcBorrowLimitBeforeOperate_When80PercentOf20PercentExpanded() public {
        uint256 userBorrow = 7 ether; // full expansion will be 8.4 ether
        uint256 previousLimit = 7.5 ether;
        uint256 lastUpdateTimestamp = block.timestamp - (DEFAULT_EXPAND_DURATION * 8) / 10; // 80% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        // 80% expanded of 1.4 ether = 1.12 ether. starting from 7.5 ether so already above max expansion.
        assertEq(limit, 8.4 ether);
    }

    function test_calcBorrowLimitBeforeOperate_WhenAboveHardMaxLimit() public {
        uint256 userBorrow = 9 ether; // full expansion will be 10.8 ether
        uint256 previousLimit = 9 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, DEFAULT_MAX_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitBeforeOperate_WhenAboveHardMaxLimitWithPreviousLimitAbove() public {
        uint256 userBorrow = 9 ether; // full expansion will be 10.8 ether
        uint256 previousLimit = 11 ether; // should not change outcome of limit being max hard cap
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // 100% expanded

        uint256 userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, DEFAULT_MAX_LIMIT_AFTER_BIG_MATH);
    }
}

contract LibraryLiquidityCalcsBorrowLimitAfterOperateTests is LibraryLiquidityCalcsBorrowLimitsBaseTest {
    function test_calcBorrowLimitAfterOperate_WhenUserBorrow0() public {
        // limit should be base limit
        uint256 userBorrow = 0;

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 0; // irrelevant for this test

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitAfterOperate_WhenMaxExpansionIsBelowBaseLimit() public {
        // limit should be base limit
        uint256 userBorrow = 4 ether; // max expansion is to 4.8 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 0; // irrelevant for this test

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitAfterOperate_WhenMaxExpansionIsExactlyBaseLimit() public {
        // limit should be base limit
        uint256 userBorrow = DEFAULT_BASE_LIMIT_AFTER_BIG_MATH; // max expansion is to 4.8 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            0, // 0% expansion
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether; // limit before operate can only ever be >= userBorrow.

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitAfterOperate_WhenExpandPercent0() public {
        uint256 userBorrow = 6 ether;

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            0, // 0% expansion
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 6 ether;
        // limit before operate can only ever be >= userBorrow.
        // because even for payback, limit beforeOperate would be userBorrow before operate. (so > than after because of payback)

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, userBorrow);
    }

    function test_calcBorrowLimitAfterOperate_WhenExpandPercent0WithPreviousLimitHigher() public {
        uint256 userBorrow = 6 ether;

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            0, // 0% expansion
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, userBorrow);
    }

    function test_calcBorrowLimitAfterOperate_WhenExpandPercent100() public {
        uint256 userBorrow = 6 ether;

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            100 * 1e2, // 100% expansion
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 8 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, 8 ether); // should be previous limit and expand from there

        // cross-test expansion at next beforeOperate limit
        userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            limit,
            block.timestamp - DEFAULT_EXPAND_DURATION / 10, // 10% of 6 ether expanded
            100 * 1e2, // 100% expansion
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, 8.6 ether);
    }

    function test_calcBorrowLimitAfterOperate_WhenExpandPercentMax() public {
        uint256 userBorrow = 6 ether;

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            16_383, // expand percent = 163,83%.  max expand percent is 16_383 (14 bits)
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate); // should be previous limit and expand from there
    }

    function test_calcBorrowLimitAfterOperate_WhenMaxExpandedIsAboveHardMaxLimit() public {
        uint256 userBorrow = 9 ether; // would expand to 10.8 ether (above hard max of 10 ether)

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 12 ether; // shrinking to max hard limit should be instant

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, DEFAULT_MAX_LIMIT_AFTER_BIG_MATH);
    }

    function test_calcBorrowLimitAfterOperate_WhenShrinkingInstantlyOnRepay() public {
        // shrinking instantly to fully expanded borrow limit from new borrow amount. shrinking is instant)
        uint256 userBorrow = 6 ether; // expands to 7.2 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 9 ether; // shrinking to max expansion limit should be instant

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, 7.2 ether);
    }

    function test_calcBorrowLimitAfterOperate_WhenExpandingFromLimitBeforeOperate() public {
        // previous limit will be limit before operate. E.g. new Borrow that causes expansion
        uint256 userBorrow = 6 ether; // expands to 7.2 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 6.5 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate);
    }

    function test_calcBorrowLimitAfterOperate_WhenSimulateBigBorrowToLimit() public {
        // borrow to full limit
        uint256 userBorrow = 6 ether; // expands to 7.2 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 6 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate);

        // cross-test expansion at next beforeOperate limit
        userBorrowData = _getUserBorrowDataForBeforeOperate(
            userBorrow,
            limit,
            block.timestamp - DEFAULT_EXPAND_DURATION / 10, // 10% of 1.2 ether expanded
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        limit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        assertEq(limit, 6.12 ether);
    }

    function test_calcBorrowLimitAfterOperate_WhenSimulateSmallBorrow() public {
        // e.g. user borrow before was 5.83333 ether fully expanded to 7 ether borrow limit
        uint256 userBorrow = 6 ether; // expands to 7.2 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate);
    }

    function test_calcBorrowLimitAfterOperate_WhenSimulatePayback() public {
        // e.g. user borrow before was 5.83333 ether fully expanded to 7 ether borrow limit
        uint256 userBorrow = 5.5 ether; // expands to 6.6 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, 6.6 ether); // should be shrinked to fully expanded instantly
    }

    function test_calcBorrowLimitAfterOperate_WhenSimulateBigPaybackToBelowBaseLimit() public {
        // e.g. user borrow before was 5.83333 ether fully expanded to 7 ether borrow limit
        uint256 userBorrow = 4 ether; // expands to 4.8 ether

        uint256 userBorrowData = _getUserBorrowDataForAfterOperate(
            userBorrow,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT,
            DEFAULT_MAX_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, limitFromBeforeOperate);
        assertEq(limit, DEFAULT_BASE_LIMIT_AFTER_BIG_MATH); // should be shrinked to base borrow limit instantly
    }
}

contract LibraryLiquidityCalcsBorrowLimitTests is LibraryLiquidityCalcsBaseTest {
    function test_calcBorrowLimit_CombinationSequence() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 expandPercentage = 20 * 1e2; // 20%
        uint256 baseLimit = 5 ether;
        uint256 maxLimit = 7 ether;
        uint256 expandDuration = 200 seconds;

        console2.log("-------------------------------");
        console2.log("Config expandPercentage 20%", expandPercentage);
        console2.log("Config baseLimit 5 ether", baseLimit);
        console2.log("Config maxLimit 7 ether", maxLimit);
        console2.log("Config expandDuration 200 seconds", expandDuration);

        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = 0;

        console2.log(
            "\n--------- Simulate 1. action: borrow of 4.18 ether, expands to 5.01 (above base limit) ---------"
        );
        uint256 userBorrow = 0;

        uint256 userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, baseLimit, 1e16); // allow BigMath precision delta

        userBorrow = 4.18 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, baseLimit, 1e16); // allow BigMath precision delta

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log("--------- TIME WARP 200 seconds ---------");

        console2.log("\n--------- Simulate 2. action: borrow of 0.82 ether to 5 ether total ---------");
        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 5.016 ether); // fully expanded from 4.18 to 5.016 ether (not base limit)

        userBorrow += 0.82 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 5.016 ether); // fully expanded from 4.18 to 5.016 ether (not base limit)

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 97); // tiny bit less than half to get closest to 5.5 & make up for 0.016 already as last limit
        console2.log("--------- TIME WARP 97 seconds (half expanded) ---------");

        console2.log("\n--------- Simulate 3. action: borrow of 0.5 ether to 5.5 ether total ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 5.5 ether, 1e16); // allow BigMath precision delta

        userBorrow += 0.5 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 5.5 ether, 1e16); // allow BigMath precision delta

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 4. action: payback 0.01 ether to total 5.49 ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 5.5 ether, 1e16); // allow BigMath precision delta

        userBorrow -= 0.01 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 5.5 ether, 1e16); // allow BigMath precision delta right after still 5.5 ether

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log("--------- TIME WARP 200 seconds (full expansion to 6.588 limit) ---------");

        console2.log("\n--------- Simulate 5. action: borrow of 1.01 ether to 6.5 ether total ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 6.588 ether, 1e16); // 5.49 * 1.2 -> 6,588

        userBorrow += 1.01 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 6.588 ether, 1e16); // 5.49 * 1.2 -> 6,588

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log(
            "--------- TIME WARP 200 seconds (max expansion to 7.8 ether but max limit of 7 ether gets active)  ---------"
        );

        console2.log("\n--------- Simulate 6. action: borrow 0.49 ether up to max limit of 7 total ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 7 ether, 1e16); // max limit of 7 ether with BigMath imprecision

        userBorrow += 0.49 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 7 ether, 1e16); // max limit of 7 ether with BigMath imprecision

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log("--------- TIME WARP 200 seconds ---------");

        console2.log(
            "\n--------- Simulate 7. action: borrow 0.01 ether would fail even after expansion (above max limit) ---------"
        );

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 7 ether, 1e16, "Limit is not ~7 ether");

        console2.log("\n--------- Simulate 8. action: payback 1.49 ether down to 5.5 total ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 7 ether, 1e16, "Limit is not ~7 ether");

        userBorrow -= 1.49 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 6.6 ether, 1e16, "Limit is not ~6.6 ether"); // immediately shrinked to full expansion 5.5 * 1.2 = 6.6

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 9. action: payback 5.5 ether down to 0 total ---------");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, 6.6 ether, 1e16, "Limit is not ~6.6 ether"); // immediately shrinked to full expansion 5.5 * 1.2 = 6.6

        userBorrow -= 5.5 ether;
        console2.log("userBorrow", userBorrow);
        assertEq(userBorrow < previousLimit, true, "USER BORROW IS > LIMIT");

        userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitAfterOperate(userBorrowData, userBorrow, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertApproxEqAbs(previousLimit, baseLimit, 1e16, "Limit is not baseLimit"); // immediately shrinked to base limit
    }

    function test_calcBorrowLimit_CalcBorrowLimitFirstAction() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 expandPercentage = 20 * 1e2; // 20%
        uint256 baseLimit = 5 ether;
        uint256 maxLimit = 7 ether;
        uint256 expandDuration = 200 seconds;
        uint256 previousLimit = 0; // previous limit is not set at config
        uint256 lastUpdateTimestamp = 0; // last update timestamp is 0 at first interaction (not set at config)
        uint256 userBorrow = 0; // user borrow amount at first action can only be 0 still

        uint256 userBorrowData = _simulateUserBorrowDataFull(
            1,
            userBorrow,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            maxLimit,
            false
        );
        previousLimit = testHelper.calcBorrowLimitBeforeOperate(userBorrowData, userBorrow);
        console2.log("BEFORE operate limit first action (should be ~5 ether base limit)", previousLimit);
        assertApproxEqAbs(previousLimit, baseLimit, 1e16); // allow BigMath precision delta
    }
}
