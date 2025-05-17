//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import "forge-std/console2.sol";

contract LibraryLiquidityCalcsWithdrawalLimitsBaseTest is LibraryLiquidityCalcsBaseTest {
    uint256 constant DEFAULT_EXPAND_PERCENTAGE = 20 * 1e2; // 20%
    uint256 constant DEFAULT_BASE_LIMIT = 5 ether;
    uint256 constant DEFAULT_EXPAND_DURATION = 200 seconds;

    uint256 immutable DEFAULT_BASE_LIMIT_AFTER_BIG_MATH;

    constructor() {
        DEFAULT_BASE_LIMIT_AFTER_BIG_MATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(DEFAULT_BASE_LIMIT, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN),
            8,
            0xff
        );
    }

    function setUp() public virtual override {
        super.setUp();

        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp
    }

    function _getUserSupplyDataForBeforeOperate(
        uint256 userSupply,
        uint256 previousLimit,
        uint256 lastUpdateTimestamp,
        uint256 expandPercentage,
        uint256 expandDuration,
        uint256 baseLimit
    ) internal pure returns (uint256) {
        return
            _simulateUserSupplyDataFull(
                1, // interest mode irrelevant for withdrawal limit calculation
                userSupply,
                previousLimit,
                lastUpdateTimestamp,
                expandPercentage,
                expandDuration,
                baseLimit,
                false // user pause status irrelevant for withdrawal limit calculation
            );
    }

    function _getUserSupplyDataForAfterOperate(
        uint256 userSupply,
        uint256 expandPercentage,
        uint256 expandDuration,
        uint256 baseLimit
    ) internal pure returns (uint256) {
        return
            _simulateUserSupplyDataFull(
                1, // interest mode irrelevant for withdrawal limit calculation
                userSupply,
                0, // previous limit in storage should never matter for after operate limit
                0, // last update timestamp in storage should never matter for after operate limit
                expandPercentage,
                expandDuration,
                baseLimit,
                false // user pause status irrelevant for withdrawal limit calculation
            );
    }
}

contract LibraryLiquidityCalcsWithdrawalLimitBeforeOperateTests is LibraryLiquidityCalcsWithdrawalLimitsBaseTest {
    function test_calcWithdrawalLimitBeforeOperate_WhenLastWithdrawalLimitZero() public {
        uint256 userSupply = 0;
        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = 0;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenUserSupply0() public {
        uint256 userSupply = 0;
        uint256 previousLimit = 0; // can only be 0 as afterOperate withdrawal limit method always goes into base limit is >
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10 percent passed
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitBeforeOperate_When10PercentOf30PercentExpanded() public {
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 1 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10 percent passed
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        // 30% would be at 0.7 ether, but only 10% is expanded so 3% -> 0.97
        assertEq(limit, 0.97 ether);
    }

    function test_calcWithdrawalLimitBeforeOperate_When10PercentOf30PercentExpandedFromPreviousLimit() public {
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.9 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 10; // 10 percent passed
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        // 30% would be at 0.7 ether, but only 10% is expanded so 3% but from last limit 0.9 ether -> so 0.87 ether
        assertEq(limit, 0.87 ether);
    }

    function test_calcWithdrawalLimitBeforeOperate_When50PercentOf20PercentExpanded() public {
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 1 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 2; // 50 percent passed
        uint256 expandPercentage = 20 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        // 20% would be at 0.8 ether, but only 50% is expanded so 10% -> 0.9
        assertEq(limit, 0.9 ether);
    }

    function test_calcWithdrawalLimitBeforeOperate_When50PercentOf20PercentExpandedFromPreviousLimit() public {
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.9 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION / 2; // 50 percent passed
        uint256 expandPercentage = 20 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        // 20% would be at 0.8 ether, but only 50% is expanded so 10%, but starting from 0.9 -> so 0.8
        assertEq(limit, 0.8 ether);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenBeyondMaxExpansion() public {
        // e.g. because > 100% of expand duration passed
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.9 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION * 2; // > 100 percent passed
        uint256 expandPercentage = 20 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        // limit should be fully expanded -> 1 ether - 20% -> 0.8 ether
        assertEq(limit, 0.8 ether);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenExpandPercent100() public {
        // withdrawable is full user supply (meaning limit is 0)
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 1; // should not matter
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded
        uint256 expandPercentage = 100 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0);

        previousLimit = userSupply + 1; // verify last limit should not matter when fully expanded

        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenExpandPercent0() public {
        // withdrawable should be 0 (limit = userSupply).
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 1 ether; // should not matter
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded
        uint256 expandPercentage = 0;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, userSupply);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenExpandPercent0FromPreviousLimit() public {
        // withdrawable should be 0 (limit = userSupply).
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.9 ether; // should not matter, limit should still be userSupply
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded
        uint256 expandPercentage = 0;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, userSupply);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenLastUpdateTimestampIsBlockTimestamp() public {
        // no expansion happened yet so limit should be previous Limit
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 1 ether;
        uint256 lastUpdateTimestamp = block.timestamp;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, previousLimit);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenLastUpdateTimestampIsBlockTimestampFromPreviousLimit() public {
        // no expansion happened yet so limit should be previous Limit
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.9 ether;
        uint256 lastUpdateTimestamp = block.timestamp;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, previousLimit);
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenPreviousLimitBelowMaxExpansion() public {
        // limit should be max expansion
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.7 ether;
        uint256 lastUpdateTimestamp = block.timestamp;

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0.8 ether); // 0.8 ether is max expansion
    }

    function test_calcWithdrawalLimitBeforeOperate_WhenLastWithdrawalLimitSmallerThanExpansionAmount() public {
        // limit should be max expansion
        uint256 userSupply = 1 ether;
        uint256 previousLimit = 0.1 ether;
        uint256 lastUpdateTimestamp = block.timestamp - DEFAULT_EXPAND_DURATION; // fully expanded

        uint256 userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        // expansion amount is 0.2 ether. last limit only 0.1 ether.
        // limit should still be max expansion limit of 0.8 ether.

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 0.8 ether); // 0.8 ether is max expansion
    }
}

contract LibraryLiquidityCalcsWithdrawalLimitAfterOperateTests is LibraryLiquidityCalcsWithdrawalLimitsBaseTest {
    function test_calcWithdrawalLimitAfterOperate_WhenUserSupply0() public {
        // limit should be 0
        uint256 userSupply = 0;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 0; // irrelevant for this test

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyBelowBaseLimit() public {
        // limit should be 0
        uint256 userSupply = DEFAULT_BASE_LIMIT_AFTER_BIG_MATH - 1;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 0; // irrelevant for this test

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyExactlyBaseLimit() public {
        uint256 userSupply = DEFAULT_BASE_LIMIT_AFTER_BIG_MATH;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            DEFAULT_EXPAND_PERCENTAGE,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 0;

        // limit will be full expansion from userSupply (~5ether * 0.8 = ~4 ether)

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, (DEFAULT_BASE_LIMIT_AFTER_BIG_MATH * 8) / 10);
        assertApproxEqAbs(limit, 4 ether, 1e16);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyExactlyBaseLimitWithLimitBeforeBigger() public {
        uint256 userSupply = DEFAULT_BASE_LIMIT_AFTER_BIG_MATH;
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 4.9 ether; // e.g. deposit was 7 ether and limit was fully expanded to 4.9 ether.

        // limit will be 4.9 ether as that is > fully expanded limit

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 4.9 ether);

        // cross check new limit beforeOperate
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 4.9 ether
            block.timestamp - DEFAULT_EXPAND_DURATION / 5, // last update timestamp 20% of expand duration
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 4.9 ether - ((((DEFAULT_BASE_LIMIT_AFTER_BIG_MATH * 3) / 10) * 2) / 10));
        assertApproxEqAbs(limit, 4.6 ether, 1e16); // should be 20% of ~1.5 ether expansion expanded, starting from 4.9 ether. so ~4.6 ether
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyAboveBaseLimitButExpansionGoesBelow() public {
        // big deposit case
        uint256 userSupply = 6 ether;
        uint256 expandPercentage = 30 * 1e2; // so going to 4.2 ether

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 2 ether; // limit will be instantly fully expanded (deposit case)

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 4.2 ether);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyAboveBaseLimitButExpansionGoesBelowWithLimitBefore()
        public
    {
        // small deposit case
        uint256 userSupply = 5.2 ether;
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 4.8 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate); // should be previous limit
    }

    function test_calcWithdrawalLimitAfterOperate_WhenUserSupplyAboveBaseLimitButExpansionGoesBelowWithLimitBeforeWithdrawalCase()
        public
    {
        // withdrawal case
        uint256 userSupply = 5.2 ether;
        uint256 expandPercentage = 30 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 6 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate); // should be previous limit
    }

    function test_calcWithdrawalLimitAfterOperate_WhenExpandPercent0() public {
        // withdrawal case
        uint256 userSupply = 5.2 ether;
        uint256 expandPercentage = 0;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 1 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, userSupply); // should be user supply exactly as no expansion happens
    }

    function test_calcWithdrawalLimitAfterOperate_WhenExpandPercent100() public {
        uint256 userSupply = 5.2 ether;
        uint256 expandPercentage = 100 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 5 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 5 ether);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenExpandPercent100To0() public {
        uint256 userSupply = 5.2 ether;
        uint256 expandPercentage = 100 * 1e2;

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        // expansion starts from last limit, but limit would be instantly max expansion.
        // so with last limit being 0 we know expansion goes to 0
        uint256 limitFromBeforeOperate = 0;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 0);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenSimulateBigDepositToInstantExpansion() public {
        // e.g. after big enough deposit withdrawal limit is instantly fully expanded
        uint256 userSupply = 8 ether;
        uint256 expandPercentage = 30 * 1e2; // so going to 5.6 ether

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 5 ether; // limit will be instantly fully expanded (deposit case)

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 5.6 ether);
    }

    function test_calcWithdrawalLimitAfterOperate_WhenSimulateSmallDeposit() public {
        // e.g. after big enough deposit withdrawal limit is instantly fully expanded
        // e.g. user supply was 7.5 ether, 0.5 ether is deposited. limit before was 7 ether.
        uint256 userSupply = 8 ether;
        uint256 expandPercentage = 30 * 1e2; // so going to 5.6 ether

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether; // was only partially expanded

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, 7 ether); // new limit starts from 7 ether.

        // cross check new limit beforeOperate
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 7 ether
            block.timestamp - DEFAULT_EXPAND_DURATION / 5, // last update timestamp 20% of expand duration
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);

        assertEq(limit, 6.52 ether); // should be 20% of 2.4 ether expansion expanded, starting from 7 ether. so 6.52 ether

        // cross check new limit beforeOperate fully expansion after only 60% of time because starting from 7
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 7 ether
            block.timestamp - (DEFAULT_EXPAND_DURATION * 6) / 10, // last update timestamp 60% of expand duration
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);

        assertEq(limit, 5.6 ether); // should be 60% of 2.4 ether expansion expanded, starting from 7 ether. so 5.56 ether
    }

    function test_calcWithdrawalLimitAfterOperate_WhenSimulateSmallWithdrawal() public {
        // withdrawal case
        // e.g. user supply was 8 ether, 0.5 ether is withdrawn. limit before was 7 ether.
        uint256 userSupply = 7.5 ether;
        uint256 expandPercentage = 30 * 1e2; // so going to 5.25 ether

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 7 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate); // should start from previous limit

        // cross check new limit beforeOperate
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 7 ether
            block.timestamp - DEFAULT_EXPAND_DURATION / 2, // last update timestamp 50% of expand duration
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 5.875 ether); // should be 50% of 2.4 ether expansion expanded, starting from 7 ether. so 5.875 ether
    }

    function test_calcWithdrawalLimitAfterOperate_WhenSimulateBigWithdrawalToLimit() public {
        // withdrawal case
        // e.g. user supply was 8 ether, 0.5 ether is withdrawn. limit before was 7.5 ether.
        uint256 userSupply = 7.5 ether;
        uint256 expandPercentage = 30 * 1e2; // so going to 5.25 ether

        uint256 userSupplyData = _getUserSupplyDataForAfterOperate(
            userSupply,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        uint256 limitFromBeforeOperate = 7.5 ether;

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, limitFromBeforeOperate);
        assertEq(limit, limitFromBeforeOperate); // should start from previous limit

        // cross check new limit beforeOperate right after
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 7.5 ether
            block.timestamp,
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );
        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 7.5 ether); // should be no withdrawal possible anymore

        // cross check new limit beforeOperate after some expansion
        userSupplyData = _getUserSupplyDataForBeforeOperate(
            userSupply,
            limit, // previous limit is 7.5 ether
            block.timestamp - (DEFAULT_EXPAND_DURATION * 8) / 10, // last update timestamp 80% of expand duration
            expandPercentage,
            DEFAULT_EXPAND_DURATION,
            DEFAULT_BASE_LIMIT
        );

        limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        assertEq(limit, 5.7 ether); // should be 80% of 2.25 ether expansion expanded, starting from 7.5 ether. so 5.7 ether
    }
}

contract LibraryLiquidityCalcsWithdrawalLimitTests is LibraryLiquidityCalcsBaseTest {
    function test_calcWithdrawalLimit_CombinationSequence() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 expandPercentage = 20 * 1e2; // 20%
        uint256 baseLimit = 5 ether;
        uint256 expandDuration = 200 seconds;

        console2.log("-------------------------------");
        console2.log("Config expandPercentage 20%", expandPercentage);
        console2.log("Config baseLimit 5 ether", baseLimit);
        console2.log("Config expandDuration 200 seconds", expandDuration);

        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = 0;

        console2.log("\n--------- Simulate 1. action: deposit of 1 ether ---------");
        uint256 userSupply = 0;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 0);

        userSupply = 1 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 0);

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 100);
        console2.log("--------- TIME WARP 100 seconds ---------");

        console2.log("\n--------- Simulate 2. action: deposit of 4.5 ether to 5.5 ether total ---------");
        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 0);

        userSupply += 4.5 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 4.4 ether); // fully expanded immediately because of deposits only

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 3. action: deposit of 0.5 ether to 6 ether total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 4.4 ether); // fully expanded immediately because of deposits only

        userSupply += 0.5 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 4.8 ether); // fully expanded immediately because of deposits only

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 4. action: withdraw 0.01 ether to total 5.99 ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 4.8 ether); // fully expanded immediately because of deposits only

        userSupply -= 0.01 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 4.8 ether); // triggered expansion from 4.8 down

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log("--------- TIME WARP 200 seconds ---------");

        console2.log("\n--------- Simulate 5. action: deposit of 1.01 ether to 7 ether total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 4.792 ether); // fully expanded from 5.99

        userSupply += 1.01 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 5.6 ether); // fully expanded immediately because of deposits only

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 6. action: withdraw 1.4 ether down to 5.6 total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 5.6 ether); // fully expanded immediately because of deposits only

        userSupply -= 1.4 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 5.6 ether); // last withdrawal limit used as point to expand from

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 40);
        console2.log("--------- TIME WARP 40 seconds (20% of 20% epanded, 0.224 down to 5.376) ---------\n");

        console2.log("\n--------- Simulate 7. action: withdraw 0.1 ether down to 5.5 total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 5.376 ether); // last withdrawal limit 5.6 20% of 20% epanded, 0.224 down to 5.376

        userSupply -= 0.1 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 5.376 ether); // last withdrawal limit used as point to expand from

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 200);
        console2.log("--------- TIME WARP 200 seconds (full expansion to 4.4) ---------");

        console2.log("\n--------- Simulate 8. action: withdraw 0.51 ether down to 4.99 total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 4.4 ether); // fully expanded from 5.5

        userSupply -= 0.51 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 0); // below base limit so 0

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 1);
        console2.log("--------- TIME WARP 1 seconds ---------");

        console2.log("\n--------- Simulate 9. action: withdraw 4.99 ether down to 0 total ---------");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 0); // below base limit so 0

        userSupply -= 4.99 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 0); // below base limit so 0
    }

    function test_calcWithdrawalLimit_CalcWithdrawalLimitAfterOperate() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 previousLimit = 0; // not used in calcWithdrawalLimitAfterOperate
        uint256 lastUpdateTimestamp = block.timestamp; // not used in calcWithdrawalLimitAfterOperate
        uint256 expandDuration = 200 seconds; // not used in calcWithdrawalLimitAfterOperate

        uint256 userSupply = 5.5 ether;
        uint256 expandPercentage = 20 * 1e2; // 20%
        uint256 baseLimit = 2 ether;
        uint256 beforeOperateWithdrawalLimit = 0;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );

        uint256 limit = testHelper.calcWithdrawalLimitAfterOperate(
            userSupplyData,
            userSupply,
            beforeOperateWithdrawalLimit
        );

        console2.log("limit", limit);
    }

    function test_calcWithdrawalLimit_CalcWithdrawalLimitBeforeOperate() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 userSupply = 10 ether;
        uint256 previousLimit = 9.5 ether;
        uint256 lastUpdateTimestamp = block.timestamp - 100;
        uint256 expandPercentage = 20 * 1e2; // 20%
        uint256 expandDuration = 200 seconds;
        uint256 baseLimit = 2 ether;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);

        console2.log("limit", limit);
    }

    function test_calcWithdrawalLimit_CalcWithdrawalLimitBeforeOperate1() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 userSupply = 5.5 ether;
        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = block.timestamp;
        uint256 expandPercentage = 20 * 1e2; // 20% -> down to 4,4
        uint256 expandDuration = 200 seconds;
        uint256 baseLimit = 5 ether;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);

        console2.log("limit", limit);
    }

    function test_calcWithdrawalLimit_CalcWithdrawalLimitBeforeOperate2() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 userSupply = 5.5 ether;
        uint256 previousLimit = 4.4 ether;
        uint256 lastUpdateTimestamp = block.timestamp - 100; // half time passed
        uint256 expandPercentage = 20 * 1e2; // 20% -> down to 4,4
        uint256 expandDuration = 200 seconds;
        uint256 baseLimit = 5 ether;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );

        uint256 limit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);

        console2.log("limit", limit);
    }

    function test_calcWithdrawalLimit_CalcWithdrawalLimit_FirstTimeAboveBaseLimit() public {
        vm.warp(block.timestamp + 10_000); // skip ahead to not cause an underflow for last update timestamp

        uint256 expandPercentage = 10 * 1e2; // 10%
        uint256 expandDuration = 200 seconds;
        uint256 baseLimit = 5 ether;

        console2.log("-------------------------------");
        console2.log("Config expandPercentage 10%", expandPercentage);
        console2.log("Config baseLimit 5 ether", baseLimit);
        console2.log("Config expandDuration 200 seconds", expandDuration);

        uint256 previousLimit = 0;
        uint256 lastUpdateTimestamp = 0;

        console2.log("\n--------- Simulate 1. action: deposit of 6 ether ---------");
        uint256 userSupply = 0;

        uint256 userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );

        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 0);

        userSupply = 6 ether;
        console2.log("userSupply", userSupply);
        assertEq(userSupply >= previousLimit, true, "USER SUPPLY IS < LIMIT");

        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitAfterOperate(userSupplyData, userSupply, previousLimit);
        console2.log("AFTER operate limit", previousLimit);
        assertEq(previousLimit, 5.4 ether);

        lastUpdateTimestamp = block.timestamp;
        vm.warp(block.timestamp + 100);
        console2.log("--------- TIME WARP 100 seconds ---------");

        console2.log("\n--------- Simulate 2. action: check before operate limit ---------");
        userSupplyData = _simulateUserSupplyDataFull(
            1,
            userSupply,
            previousLimit,
            lastUpdateTimestamp,
            expandPercentage,
            expandDuration,
            baseLimit,
            false
        );
        previousLimit = testHelper.calcWithdrawalLimitBeforeOperate(userSupplyData, userSupply);
        console2.log("BEFORE operate limit", previousLimit);
        assertEq(previousLimit, 5.4 ether);
    }
}
