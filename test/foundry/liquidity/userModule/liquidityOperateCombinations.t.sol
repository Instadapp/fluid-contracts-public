//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleOperateTestSuite } from "./liquidityOperate.t.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

/***********************************|
|         SUPPLY & BORROW           | 
|__________________________________*/

contract LiquidityUserModuleSupplyAndBorrowTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            address(0),
            alice,
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT, 0),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndBorrowTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1,
                1
            );
        }

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            address(0),
            alice,
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndBorrowTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            address(0),
            alice,
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT, 0),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndBorrowTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1,
                1
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            address(0),
            alice,
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT, 0, DEFAULT_BORROW_AMOUNT),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

/***********************************|
|         SUPPLY & PAYBACK          | 
|__________________________________*/

contract LiquidityUserModuleSupplyAndPaybackTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        uint256 totalSupplyRawInterest;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalSupplyRawInterest =
                DEFAULT_SUPPLY_AMOUNT + // previous supply raw
                ((DEFAULT_SUPPLY_AMOUNT * EXCHANGE_PRICES_PRECISION) / supplyExchangePrice); // new supply adjusted to raw
            assertEq(totalSupplyRawInterest, 1962695547533092659);

            uint256 totalSupply = ((DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION) +
                DEFAULT_SUPPLY_AMOUNT;
            assertEq(totalSupply, 2038750000000000000); // 1 ether * 1038750000000 + 1 ether

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 11,7106 %
            assertEq(utilization, 1171);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 487); // expected borrow rate at ~11,71% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                totalSupplyRawInterest,
                0, // previous limit
                block.timestamp
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndPaybackTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 totalAmounts;
        uint256 totalSupply = DEFAULT_SUPPLY_AMOUNT * 2;
        uint256 exchangePricesAndConfig;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference
            uint256 totalBorrow = defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT;
            totalAmounts = _simulateTotalAmounts(0, totalSupply, 0, totalBorrow);

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 10%
            assertEq(utilization, 1000);

            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 475); // expected borrow rate at 10% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        uint256 userSupplyData = _simulateUserSupplyData(
            resolver,
            address(mockProtocol),
            address(USDC),
            totalSupply,
            0, // previous limit
            block.timestamp
        );

        _setTestOperateParams(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            userSupplyData,
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndPaybackTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        uint256 totalSupplyRawInterest;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalSupplyRawInterest =
                DEFAULT_SUPPLY_AMOUNT + // previous supply raw
                ((DEFAULT_SUPPLY_AMOUNT * EXCHANGE_PRICES_PRECISION) / supplyExchangePrice); // new supply adjusted to raw
            assertEq(totalSupplyRawInterest, 1962695547533092659);

            uint256 totalSupply = ((DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION) +
                DEFAULT_SUPPLY_AMOUNT;
            assertEq(totalSupply, 2038750000000000000); // 1 ether * 1038750000000 + 1 ether

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 11,7106 %
            assertEq(utilization, 1171);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 487); // expected borrow rate at ~11,71% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                totalSupplyRawInterest,
                0, // previous limit
                block.timestamp
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModuleSupplyAndPaybackTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 totalAmounts;
        uint256 totalSupply = DEFAULT_SUPPLY_AMOUNT * 2;
        uint256 exchangePricesAndConfig;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference
            uint256 totalBorrow = defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT;
            totalAmounts = _simulateTotalAmounts(0, totalSupply, 0, totalBorrow);

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 10%
            assertEq(utilization, 1000);

            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 475); // expected borrow rate at 10% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        uint256 userSupplyData = _simulateUserSupplyData(
            resolver,
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS,
            totalSupply,
            0, // previous limit
            block.timestamp
        );

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(DEFAULT_SUPPLY_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            address(0),
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            userSupplyData,
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

/***********************************|
|        WITHDRAW & BORROW          | 
|__________________________________*/

contract LiquidityUserModuleWithdrawAndBorrowTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) /
                (DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            alice,
            alice,
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, DEFAULT_BORROW_AMOUNT, 0),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndBorrowTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) /
                (DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1,
                1
            );
        }

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            alice,
            alice,
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, DEFAULT_BORROW_AMOUNT),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndBorrowTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) /
                (DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            alice,
            alice,
            _simulateTotalAmounts(DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, DEFAULT_BORROW_AMOUNT, 0),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndBorrowTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) /
                (DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );

            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1,
                1
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            int256(DEFAULT_BORROW_AMOUNT),
            alice,
            alice,
            alice,
            _simulateTotalAmounts(0, DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT, 0, DEFAULT_BORROW_AMOUNT),
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT,
                0, // previous limit
                block.timestamp
            ),
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

/***********************************|
|        WITHDRAW & PAYBACK         | 
|__________________________________*/

contract LiquidityUserModuleWithdrawAndPaybackTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        uint256 totalSupplyRawInterest;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalSupplyRawInterest =
                DEFAULT_SUPPLY_AMOUNT - // previous supply raw
                ((DEFAULT_WITHDRAW_AMOUNT * EXCHANGE_PRICES_PRECISION) / supplyExchangePrice); // new supply adjusted to raw
            assertEq(totalSupplyRawInterest, 518652226233453671);

            uint256 totalSupply = ((DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION) -
                DEFAULT_WITHDRAW_AMOUNT;
            assertEq(totalSupply, 538750000000000000); // 1 ether * 1038750000000 - 0.5 ether

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 44,31554 %
            assertEq(utilization, 4431);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 732); // expected borrow rate at ~44,31% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            alice,
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                address(USDC),
                totalSupplyRawInterest,
                0, // previous limit
                block.timestamp
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndPaybackTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows USDC liquidity
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 totalAmounts;
        uint256 totalSupply = DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT;
        uint256 exchangePricesAndConfig;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference
            uint256 totalBorrow = defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT;
            totalAmounts = _simulateTotalAmounts(0, totalSupply, 0, totalBorrow);

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 40%
            assertEq(utilization, 4000);

            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 700); // expected borrow rate at 40% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                address(USDC),
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        uint256 userSupplyData = _simulateUserSupplyData(
            resolver,
            address(mockProtocol),
            address(USDC),
            totalSupply,
            0, // previous limit
            block.timestamp
        );

        _setTestOperateParams(
            address(USDC),
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            alice,
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            userSupplyData,
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                address(USDC),
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndPaybackTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        uint256 supplyExchangePrice = 1038750000000; // increased half of 7.75% -> 3.875% (because half of supply is borrowed out)
        uint256 borrowExchangePrice = 1077500000000; // increased 7.75%

        uint256 totalAmounts;
        uint256 userBorrowData;
        uint256 exchangePricesAndConfig;
        uint256 totalSupplyRawInterest;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference

            uint256 totalBorrow = (((defaultBorrowAmountAfterRounding * borrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION) - DEFAULT_PAYBACK_AMOUNT);
            assertEq(totalBorrow, 238750000000000008);
            uint256 totalBorrowRawInterest = ((totalBorrow * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice) + 1; // should be 0.221577726218097455 +1 for round up
            assertEq(totalBorrowRawInterest, 221577726218097456);

            totalSupplyRawInterest =
                DEFAULT_SUPPLY_AMOUNT - // previous supply raw
                ((DEFAULT_WITHDRAW_AMOUNT * EXCHANGE_PRICES_PRECISION) / supplyExchangePrice); // new supply adjusted to raw
            assertEq(totalSupplyRawInterest, 518652226233453671);

            uint256 totalSupply = ((DEFAULT_SUPPLY_AMOUNT * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION) -
                DEFAULT_WITHDRAW_AMOUNT;
            assertEq(totalSupply, 538750000000000000); // 1 ether * 1038750000000 - 0.5 ether

            totalAmounts = _simulateTotalAmounts(totalSupplyRawInterest, 0, totalBorrowRawInterest, 0);

            userBorrowData = _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                totalBorrowRawInterest, // taking interest on borrow amount until payback into account
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            );

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 44,31554 %
            assertEq(utilization, 4431);
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 732); // expected borrow rate at ~44,31% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                0,
                0
            );
        }

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            alice,
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            _simulateUserSupplyData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                totalSupplyRawInterest,
                0, // previous limit
                block.timestamp
            ),
            userBorrowData,
            true
        );
    }
}

contract LiquidityUserModuleWithdrawAndPaybackTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        // alice borrows liquidity
        _borrowNative(mockProtocol, alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year to get a better predicatable borrow rate and amounts
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // exchange prices are not changing because of interest free mode
        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 totalAmounts;
        uint256 totalSupply = DEFAULT_SUPPLY_AMOUNT - DEFAULT_WITHDRAW_AMOUNT;
        uint256 exchangePricesAndConfig;
        {
            uint256 defaultBorrowAmountAfterRounding = 500000000000000008; // BigMath round up at borrow leads to minor difference
            uint256 totalBorrow = defaultBorrowAmountAfterRounding - DEFAULT_PAYBACK_AMOUNT;
            totalAmounts = _simulateTotalAmounts(0, totalSupply, 0, totalBorrow);

            // utilization AFTER payback
            uint256 utilization = (totalBorrow * FOUR_DECIMALS) / totalSupply; // results in 40%
            assertEq(utilization, 4000);

            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 700); // expected borrow rate at 40% utilization
            exchangePricesAndConfig = _simulateExchangePricesWithRatesAndRatios(
                resolver,
                NATIVE_TOKEN_ADDRESS,
                supplyExchangePrice,
                borrowExchangePrice,
                utilization,
                borrowRate,
                block.timestamp,
                1, // supplyRatio = 1 for mode set to total supply with interest < interest free
                1 // borrowRatio = 1 for mode set to total supply with interest < interest free
            );
        }

        uint256 userSupplyData = _simulateUserSupplyData(
            resolver,
            address(mockProtocol),
            NATIVE_TOKEN_ADDRESS,
            totalSupply,
            0, // previous limit
            block.timestamp
        );

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            -int256(DEFAULT_WITHDRAW_AMOUNT),
            -int256(DEFAULT_PAYBACK_AMOUNT),
            alice,
            alice,
            address(0),
            totalAmounts,
            exchangePricesAndConfig,
            supplyExchangePrice,
            borrowExchangePrice,
            userSupplyData,
            _simulateUserBorrowData(
                resolver,
                address(mockProtocol),
                NATIVE_TOKEN_ADDRESS,
                DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH - DEFAULT_PAYBACK_AMOUNT,
                DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH, // base borrow limit will be set as previous limit
                block.timestamp
            ),
            true
        );
    }
}
