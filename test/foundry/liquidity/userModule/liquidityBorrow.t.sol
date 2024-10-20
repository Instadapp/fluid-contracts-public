//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { SafeTransfer } from "../../../../contracts/libraries/safeTransfer.sol";
import { LibsErrorTypes } from "../../../../contracts/libraries/errorTypes.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { LiquidityUserModuleOperateTestSuite } from "./liquidityOperate.t.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

import "forge-std/console2.sol";

contract LiquidityUserModuleBorrowTestSuite is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

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
            int256(0),
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

contract LiquidityUserModuleBorrowTestSuiteInterestFree is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));

        // alice supplies USDC liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            assertEq(utilization, 5000); // utilization should be 50%
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(address(USDC)),
                utilization
            );
            assertEq(borrowRate, 775); // borrow rate at 50% utilization should be 7.75%

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

        _setTestOperateParams(
            address(USDC),
            int256(0),
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

contract LiquidityUserModuleBorrowTestSuiteNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

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
            int256(0),
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

contract LiquidityUserModuleBorrowTestSuiteInterestFreeNative is LiquidityUserModuleOperateTestSuite {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));

        // alice supplies liquidity
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);

        uint256 supplyExchangePrice = EXCHANGE_PRICES_PRECISION;
        uint256 borrowExchangePrice = EXCHANGE_PRICES_PRECISION;

        uint256 exchangePricesAndConfig;
        {
            uint256 utilization = (DEFAULT_BORROW_AMOUNT * FOUR_DECIMALS) / DEFAULT_SUPPLY_AMOUNT;
            assertEq(utilization, 5000); // utilization should be 50%
            uint256 borrowRate = LiquidityCalcs.calcBorrowRateFromUtilization(
                resolver.getRateConfig(NATIVE_TOKEN_ADDRESS),
                utilization
            );
            assertEq(borrowRate, 775); // borrow rate at 50% utilization should be 7.75%

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

        _setTestOperateParams(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
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

contract LiquidityUserModuleBorrowTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_RevertBorrowOperateAmountOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__OperateAmountOutOfBounds)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(0),
            int256(type(int128).max) + 1,
            address(0),
            alice,
            abi.encode(alice)
        );
    }

    function test_operate_RevertIfBorrowToNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__ReceiverNotDefined)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            address(USDC),
            int256(0),
            int256(DEFAULT_BORROW_AMOUNT),
            address(0),
            address(0),
            new bytes(0)
        );
    }

    function test_operate_RevertIfBorrowToNotSetNative() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__ReceiverNotDefined)
        );

        // execute operate
        vm.prank(alice);
        mockProtocol.operate(
            NATIVE_TOKEN_ADDRESS,
            int256(0),
            int256(DEFAULT_BORROW_AMOUNT),
            address(0),
            address(0),
            new bytes(0)
        );
    }

    function test_operate_RevertIfBorrowMoreThanAvailableBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeTransfer.FluidSafeTransferError.selector, LibsErrorTypes.SafeTransfer__TransferFailed)
        );

        // with just that small a difference between supply and borrow, utilization gets rounded to 100%
        // so that passes but there is not enough balance of the borrowed token at Liquidity so that reverts instead
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT + 1);
    }

    function test_operate_RevertIfBorrowMoreThanAvailableBalanceNative() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeTransfer.FluidSafeTransferError.selector, LibsErrorTypes.SafeTransfer__TransferFailed)
        );

        // with just that small a difference between supply and borrow, utilization gets rounded to 100%
        // so that passes but there is not enough balance of the borrowed token at Liquidity so that reverts instead
        _borrowNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT + 1);
    }

    function test_operate_RevertIfBorrowMoreThanAvailableSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );

        // with just that small a difference between supply and borrow, utilization gets rounded to 100%
        // so that passes but there is not enough balance of the borrowed token at Liquidity so that reverts instead
        _borrow(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT + 0.01 ether);
    }

    function test_operate_RevertIfBorrowMoreThanAvailableSupplyNative() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );

        // with just that small a difference between supply and borrow, utilization gets rounded to 100%
        // so that passes but there is not enough balance of the borrowed token at Liquidity so that reverts instead
        _borrowNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT + 0.01 ether);
    }
}

contract LiquidityUserModuleBorrowTestsInterestFree is LiquidityUserModuleBorrowTests {
    function setUp() public virtual override {
        super.setUp();

        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefaultInterestFree(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
    }
}

contract LiquidityUserModuleBorrowTestsWithInterest is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // alice supplies liquidity
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);
    }

    function test_operate_BorrowWhenUtilizationAbove100Percent() public {
        // borrow to 100% utilization, with very high borrow rate APR + some fee
        // meaning increase in borrow exchange price happens faster than supply exchange price
        // so utilization will grow above 100%.
        // then someone supplies again and brings utilization down but still above 100%.
        // but this newly supplied amount can immediately be borrowed again.

        // set max possible borrow rate at all utilization levels
        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(
            address(USDC),
            DEFAULT_KINK,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE,
            MAX_POSSIBLE_BORROW_RATE
        );
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateData);

        // set fee to 30%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 30 * DEFAULT_PERCENT_PRECISION, // 30%
            threshold: DEFAULT_STORAGE_UPDATE_THRESHOLD, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // borrow full available supply amount to get to 100% utilization
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        _borrow(
            mockProtocol,
            address(USDC),
            alice,
            overallTokenData.supplyRawInterest + overallTokenData.supplyInterestFree
        );

        // expect utilization to be 100%
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 100 * DEFAULT_PERCENT_PRECISION);

        // warp until utilization grows enough above 100%
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        _warpWithExchangePriceUpdates(address(liquidity), admin, tokens, PASS_1YEAR_TIME);

        // expect utilization to be 142,54 %
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 14254);
        assertEq(overallTokenData.supplyExchangePrice, 134600667245412);
        assertEq(overallTokenData.borrowExchangePrice, 191864066984546);

        // execute supply. Raw supply / borrow is still 1 ether (actually DEFAULT_SUPPLY_AMOUNT_AFTER_BIGMATH which also is 1 ether).
        // so total amounts here = DEFAULT_SUPPLY_AMOUNT_AFTER_BIGMATH * exchangepPrices
        // total supply: 1e18 * 134600667245412 / 1e12 = 1.34600667245412 × 10^20
        // total borrow: 1e18 * 191864066984546 / 1e12 = 1.9186406698454 × 10^20
        _supply(mockProtocol, address(USDC), alice, 50 ether);

        // total supply now: 1.34600667245412 × 10^20 + 50 ether = 1.84600667245412×10^20

        // expect utilization to be down to 1.9186406698454 × 10^20 * 100 / 1.84600667245412×10^20 = 103,93 %
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 10393);

        // supplied amount can NOT be borrowed because utilization is above 100%
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__MaxUtilizationReached)
        );
        _borrow(mockProtocol, address(USDC), alice, 1 ether);

        // supply again to bring utilization further down
        _supply(mockProtocol, address(USDC), alice, 100 ether);

        // total supply now: 1.84600667245412×10^20 + 100 ether = 2.84600667245412×10^20
        // total borrow still: 1.9186406698454 × 10^20

        // expect utilization to be down to 1.9186406698454 × 10^20 * 100 / 2.84600667245412×10^20 = 67,4151 %
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 6741);

        // borrow now should work normally again.
        _borrow(mockProtocol, address(USDC), alice, 10 ether);

        // total borrow now: 1.9186406698454 × 10^20 + 10 ether = 2.0186406698454 × 10^20

        // expect utilization to be 2.0186406698454 × 10^20 * 100 / 2.84600667245412×10^20 = 70,9288 %
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.lastStoredUtilization, 7092);
    }
}
