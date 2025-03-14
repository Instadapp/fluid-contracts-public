//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";
import { LiquidityUserModuleBaseTest } from "./liquidityUserModuleBaseTest.t.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import "forge-std/console2.sol";

contract LiquidityUserModuleYieldTests is LiquidityUserModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_operate_ExchangePriceSupplyWithInterestOnly() public {
        // alice supplies liquidity
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 4); // supply rate = 1% of borrow rate

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // at 1% utilization, for default values of 4% at 0% utilization and 10% at 80% utilization.
        // so over the range of 80%, the rate grows 6% linearly.
        // 80 = 6, 1 = x => x = 6 / 80 * 1 = 0,075
        // so 4% + 0.075% = 4.075%
        // but borrow rate precision in Liquidity is only 0.01% so it becomes 4.07%.
        // with supplyExchangePrice increasing 1% of that because only 1% of supply is borrowed out

        uint256 expectedBorrowExchangePrice = 1040700000000;
        uint256 expectedSupplyExchangePrice = 1000407000000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceSupplyInterestFreeOnly() public {
        // alice supplies liquidity
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 0); // supply rate = 0 because no borrowers with interest

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        // with supplyExchangePrice staying the same as no suppliers that earn any interest
        uint256 expectedSupplyExchangePrice = 1e12;
        uint256 expectedBorrowExchangePrice = 1040700000000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceNumberUpOnlyWhenNoStorageUpdate() public {
        // alice supplies liquidity
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // set storage update threshold to 5%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 0, // no fee for simplicity
            threshold: DEFAULT_STORAGE_UPDATE_THRESHOLD * 5, // 5%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME / 1000);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        // just divided by 1000 to be below forced storage update if time diff > 1 day
        // 407000000 / 1000 = 407000
        uint256 expectedSupplyExchangePrice = 1000000407000; // increased 1% of borrow exchange price (because 1% of supply is borrowed out)
        uint256 expectedBorrowExchangePrice = 1000040700000;

        uint256 exchangePricesAndConfigBefore = resolver.getExchangePricesAndConfig(address(USDC));

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);

        // no storage update happening but that must not cause any issue with supplyExchangePrice

        // assert exchangePricesAndConfig had no storage update
        assertEq(exchangePricesAndConfigBefore, resolver.getExchangePricesAndConfig(address(USDC)));

        vm.prank(alice);
        (uint256 supplyExchangePrice2, uint256 borrowExchangePrice2) = mockProtocolWithInterest.operate(
            address(USDC),
            int256(DEFAULT_SUPPLY_AMOUNT),
            0,
            address(0),
            address(0),
            abi.encode(alice)
        );

        assertGe(supplyExchangePrice2, expectedSupplyExchangePrice);
        assertGe(borrowExchangePrice2, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenSupplyWithInterestBigger() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 80) / 100);

        // alice supplies liquidity interest free
        _supply(mockProtocolInterestFree, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 20) / 100);

        // total supply 1 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 18750); // 187.5%

        // simulate passing time 1 / 10 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME / 10);

        // at 100% utilization, borrow rate is 150%.
        // just here we only warp 1/10 of the year so 15% increase.
        uint256 expectedBorrowExchangePrice = 1150000000000;
        // total earnings for suppliers are 100% of borrow increase. But only 80% of suppliers earn that.
        // so exchange price must grow 25% more to account for that: 150000000000 * 1.25 = 187500000000
        uint256 expectedSupplyExchangePrice = 1187500000000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenSupplyInterestFreeBigger() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 20);

        // alice supplies liquidity interest free
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 80);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 20);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase (0,0407%). But only 20% of suppliers earn that.
        // so exchange price must grow 5x more to account for that: 407000000 * 5 = 2035000000
        uint256 expectedSupplyExchangePrice = 1002035000000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenSupplyWithInterestExactlySupplyInterestFree() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 50);

        // alice supplies liquidity interest free
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 50);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 8);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase (0,0407%). But only 50% of suppliers earn that.
        // so exchange price must grow 2x more to account for that: 407000000 * 2 = 814000000
        uint256 expectedSupplyExchangePrice = 1000814000000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenSupplyWithInterestBiggerWithRevenueFee() public {
        // set revenue fee to 10%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 10 * DEFAULT_PERCENT_PRECISION,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 80);

        // alice supplies liquidity interest free
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 20);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 4);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase MINUS the revenue fee.
        // so 40700000000 * 1% - 10% = 366300000. But only 80% of suppliers earn that.
        // so exchange price must grow 25% more to account for that: 366300000 * 1.25 = 457875000
        uint256 expectedSupplyExchangePrice = 1000457875000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenSupplyInterestFreeBiggerWithRevenueFee() public {
        // set revenue fee to 10%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 10 * DEFAULT_PERCENT_PRECISION,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 20);

        // alice supplies liquidity interest free
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 80);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 18);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase MINUS the revenue fee.
        // so 40700000000 * 1% - 10% = 366300000. But only 20% of suppliers earn that.
        // so exchange price must grow 5x more to account for that: 366300000 * 5 = 1831500000
        uint256 expectedSupplyExchangePrice = 1001831500000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceSequences() public {
        // alice supplies liquidity
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 10);

        // total supply 10 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 47); // 10% of borrow rate

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for exchange price calculation.
        // 10% utilization borrow rate => x = 6 / 80 * 10 = 0,75. 4 + 0.75 => 4.75%
        // with 10% of supply earning yield
        uint256 expectedBorrowExchangePrice = 1047500000000;
        uint256 expectedSupplyExchangePrice = 1004750000000;

        // deposits DEFAULT_BORROW_AMOUNT
        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);

        // utilization here increased to:
        // total borrow = DEFAULT_BORROW_AMOUNT * 1047500000000 / 1e12 = 0,52375
        // total supply = 10 * DEFAULT_BORROW_AMOUNT * 1004750000000 / 1e12 + DEFAULT_BORROW_AMOUNT
        // = 5,02375 ether + 0,5 ether = 5,52375
        // utilization = 0,52375 / 5,52375 = 9,4817%; cut off precision to 0.01%-> 9,48%.
        // so borrow rate:
        // at 9,48% utilization x = 6 / 80 * 9,48% = 0.711
        // so 4% + 0.711% = 4.711% but cut off precision to 0.01%-> 4,71%.

        // cross-check resolver supply rate. see calc exchange price below
        overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 44); // 9,48% of borrow rate

        // simulate passing time 1 year for yield again
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        expectedBorrowExchangePrice = (1047500000000 * (1e4 + 471)) / 1e4;
        // same multiplicator here for supple exchange price as no revenue fee and only with interest suppliers.
        // only 9.48% of supply is borrowed out though so
        // increase in supplyExchangePrice = ((1004750000000 * 471 * 948) / 1e4 / 1e4) =    4486289130
        expectedSupplyExchangePrice = 1004750000000 + 4486289130; // = 1009236289130

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    // function test_operate_ExchangePriceBorrowWithInterestOnly() public {
    // already covered by tests for supply exchange prices as they use borrow with interest only
    // }

    function test_operate_ExchangePriceBorrowInterestFreeOnly() public {
        // alice supplies liquidity
        _supply(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity
        _borrow(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // both exchange prices should be initial value as there is no yield.
        uint256 expectedSupplyExchangePrice = 1e12;
        uint256 expectedBorrowExchangePrice = 1e12;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenBorrowWithInterestBigger() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity with interest
        _borrow(mockProtocolWithInterest, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 8) / 10);

        // alice borrows liquidity interest free
        _borrow(mockProtocolInterestFree, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 2) / 10);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 3);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase (1% is lent out).
        // But only 80% of the borrowers pay the yield.
        // so exchange price must grow 20% less to account for that:
        // supplyRate = 4,07% * 0,8 = 3,256%. so supplyIncrease = 325600000
        uint256 expectedSupplyExchangePrice = 1000325600000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenBorrowInterestFreeBigger() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity with interest
        _borrow(mockProtocolWithInterest, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 2) / 10);

        // alice borrows liquidity interest free
        _borrow(mockProtocolInterestFree, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 8) / 10);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 0); // 0.008%

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase (1% is lent out).
        // But only 20% of the borrowers pay the yield.
        // so exchange price must grow 80% less to account for that: 407000000 * 0.2 = 81400000
        uint256 expectedSupplyExchangePrice = 1000081400000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenBorrowWithInterestExacltyBorrowInterestFree() public {
        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity with interest
        _borrow(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 2);

        // alice borrows liquidity interest free
        _borrow(mockProtocolInterestFree, address(USDC), alice, DEFAULT_BORROW_AMOUNT / 2);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 2);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for borrow exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // total earnings for suppliers are 1% of borrow increase. But only 50% of borrowers pay that.
        // so exchange price must grow half to account for that: 407000000 / 2 = 203500000
        uint256 expectedSupplyExchangePrice = 1000203500000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenBorrowWithInterestBiggerWithRevenueFee() public {
        // set revenue fee to 10%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 10 * DEFAULT_PERCENT_PRECISION,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity with interest
        _borrow(mockProtocolWithInterest, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 8) / 10);

        // alice borrows liquidity interest free
        _borrow(mockProtocolInterestFree, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 2) / 10);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 2);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // 10% of total earnings go to revenue so 4,07% * 0,9 = 3,663%
        // and only 1% total is lent out so 3,663% *0,01 = 0,03663%
        // But only 80% of the borrowers pay the yield. so rate must grow 20% less: 0,03663% *0,8 = 0,029304%
        // so supplyRate 0,029304%. so supplyIncrease = 293040000
        uint256 expectedSupplyExchangePrice = 1000293040000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    function test_operate_ExchangePriceWhenBorrowInterestFreeBiggerWithRevenueFee() public {
        // set revenue fee to 10%
        AdminModuleStructs.TokenConfig[] memory tokenConfigs = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 10 * DEFAULT_PERCENT_PRECISION,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs);

        // alice supplies liquidity with interest
        _supply(mockProtocolWithInterest, address(USDC), alice, DEFAULT_BORROW_AMOUNT * 100);

        // total supply 100 * DEFAULT_BORROW_AMOUNT.

        // alice borrows liquidity with interest
        _borrow(mockProtocolWithInterest, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 2) / 10);

        // alice borrows liquidity interest free
        _borrow(mockProtocolInterestFree, address(USDC), alice, (DEFAULT_BORROW_AMOUNT * 8) / 10);

        // cross-check resolver supply rate. see calc exchange price below
        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(overallTokenData.supplyRate, 0);

        // simulate passing time 1 year for yield
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // see test_operate_ExchangePriceSupplyWithInterestOnly for exchange price calculation.
        uint256 expectedBorrowExchangePrice = 1040700000000;
        // 10% of total earnings go to revenue so 40700000000 * 0.9 = 36630000000 = 3,663%
        // total earnings for suppliers are 1% of borrow increase (1% is lent out). so 366300000  = 0,03663%
        // But only 20% of the borrowers pay the yield.
        // so exchange price must grow 80% less to account for that: 366300000 * 0.2 = 73260000 = supplyRate: 0,07326%
        uint256 expectedSupplyExchangePrice = 1000073260000;

        _assertExchangePrices(expectedSupplyExchangePrice, expectedBorrowExchangePrice);
    }

    // todo: test supply with interest only but only borrow interest free -> no yield
    // todo: supply with interest free only, with borrow with interest -> all goes to revenue

    function _assertExchangePrices(uint256 expectedSupplyExchangePrice, uint256 expectedBorrowExchangePrice) internal {
        vm.prank(alice);
        (uint256 supplyExchangePrice, uint256 borrowExchangePrice) = mockProtocolWithInterest.operate(
            address(USDC),
            int256(DEFAULT_BORROW_AMOUNT),
            0,
            address(0),
            address(0),
            abi.encode(alice)
        );

        assertEq(supplyExchangePrice, expectedSupplyExchangePrice, "supply exchange price off");
        assertEq(borrowExchangePrice, expectedBorrowExchangePrice, "borrow exchange price off");
    }
}

abstract contract LiquidityUserModuleYieldCombinationBaseTest is LiquidityUserModuleBaseTest {
    uint256 constant baseLimit = 5 ether;

    uint256 immutable baseLimitAfterBigMath;

    constructor() {
        baseLimitAfterBigMath = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                baseLimit,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
    }

    function setUp() public virtual override {
        super.setUp();

        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: DEFAULT_TOKEN_FEE, // 5%
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        // Set withdraw config with actual limits
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT, // 20%
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION, // 2 days;
            baseWithdrawalLimit: baseLimit
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // Set borrow config with actual limits
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT, // 20%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION, // 2 days;
            baseDebtCeiling: baseLimit,
            maxDebtCeiling: 20 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    // test uses default values from liquidityTestHelpers.sol:
    // uint256 constant DEFAULT_TOKEN_FEE = 5 * DEFAULT_PERCENT_PRECISION; // 5%

    // uint256 constant DEFAULT_KINK = 80 * DEFAULT_PERCENT_PRECISION; // 80%
    // uint256 constant DEFAULT_RATE_AT_ZERO = 4 * DEFAULT_PERCENT_PRECISION; // 4%
    // uint256 constant DEFAULT_RATE_AT_KINK = 10 * DEFAULT_PERCENT_PRECISION; // 10%
    // uint256 constant DEFAULT_RATE_AT_MAX = 150 * DEFAULT_PERCENT_PRECISION; // 150%
    // // for rate data v2:
    // uint256 constant DEFAULT_KINK2 = 90 * DEFAULT_PERCENT_PRECISION; // 90%
    // uint256 constant DEFAULT_RATE_AT_KINK2 = 80 * DEFAULT_PERCENT_PRECISION; // 10% + half way to 150% = 80% for data compatibility with v1

    function test_operate_YieldCombinationTest() public {
        // supply liquidity with interest
        _supply(mockProtocol, address(USDC), alice, 4 ether);

        // 1. test yield at ~zero: borrow very little amount
        _borrow(mockProtocol, address(USDC), alice, 1e15);

        _assertState(
            400, // expected borrow rate
            0, // expected supply rate. only very tiny amount of borrowers are paying yield
            1e12, // expected supply exchange price.
            1e12, // expected borrow exchange price.
            0, // expected revenue
            4 ether, // expected supply raw interest
            0 ether, // expected supply interest free
            1e15, // expected borrow raw interest
            0 ether, // expected borrow interest free
            0, // expected withdrawal limit
            baseLimitAfterBigMath // expected borrow limit
        );

        // warp & assert everything
        // 1e15 paying 4% for half a year -> 2% yield. 5% of that is revenue.
        // supply rate = 4% - 5% revenue fee -> 3.8%. only 0.025% utilization -> 0.095%.
        // only earned for half a year so 0.0475%.
        // BUT: precision for utilization is actually cut off at 0.02% so we get 0.076%. / 2 = 0.038%.
        // Revenue should be 1e12 but precision cut off in utilization leads to supply exchange price difference.
        // the precision loss is counted towards revenue. total supply ends up being 4 ether * 1000003800000 / 1e12 instead of
        // 4 ether * 10000047500000 / 1e12, leading to a total diff of 3.8e12
        vm.warp(block.timestamp + 365 days / 2); // earn half a year yield
        uint256 expectedSupplyExchangePrice = 1000003800000;
        uint256 expectedBorrowExchangePrice = 1020000000000; // increased by 2%
        uint256 expectedRevenue = 48e11; // 4.8e12
        _assertState(
            400, // expected borrow rate
            0, // expected supply rate. supply rate precision is cut off to 0
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            4 ether, // expected supply raw interest
            0 ether, // expected supply interest free
            1e15, // expected borrow raw interest
            0 ether, // expected borrow interest free
            0, // expected withdrawal limit
            (baseLimitAfterBigMath * expectedBorrowExchangePrice) / 1e12 // expected borrow limit
        );

        // 2. test yield at below kink 1
        _supply(mockProtocol, address(USDC), alice, 6 ether - 4000015200000000000); // bring total supply to 6 ether
        _borrow(mockProtocol, address(USDC), alice, 1.2 ether - 1020000000000000); // bring utilization to 20%

        // warp & assert everything
        // borrow rate = 4% + 1/4 of slope 6% (10% -4%) -> 5.5%.
        // 1.2 ether paying 5.5% for 10% of a year -> 0.55% yield. 5% of that is revenue.
        // supply rate = 5.5% - 5% revenue fee -> 5.225%. only 20% utilization -> 1.045%.
        // only earned for 10% of a year so 0.1045%.
        // 0.55% of 1.2 ether is 0.0066 ether in yield. 5% goes to revenue -> 0,00033
        vm.warp(block.timestamp + 365 days / 10); // earn 10% of a year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 1001045) / 1000000; // increased by 0.1045%.
        assertEq(expectedSupplyExchangePrice, 1001048803971);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 1005500) / 1000000; // increased by 0.55%
        assertEq(expectedBorrowExchangePrice, 1025610000000);
        expectedRevenue += 0.00033 ether;
        // expected withdrawal limit:
        // 20% of total supply expanded (5999977200086639488 * 0.8 = 4799981760069311590)
        uint256 expectedWithdrawalLimit = (4799981760069311590 * expectedSupplyExchangePrice) / 1e12;
        _assertState(
            550, // expected borrow rate
            104, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            5999977200086639488, // expected supply raw interest. total supply 6006269999999999817
            0 ether, // expected supply interest free
            1176470588235294144, // expected borrow raw interest. total borrow 1206600000000000027
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit. fully expanded 20%
            (baseLimitAfterBigMath * expectedBorrowExchangePrice) / 1e12 // expected borrow limit
        );

        // 3. test yield at kink 1
        _supply(mockProtocol, address(USDC), alice, 6.2 ether - 6006269999999999817); // bring total supply to 6.2 ether
        _borrow(mockProtocol, address(USDC), alice, 4.96 ether - 1206600000000000027); // bring utilization to 80%

        // warp & assert everything
        // borrow rate at kink1 = 10%
        // 4.96 ether paying 10% for a year -> 10% yield. 5% of that is revenue.
        // supply rate = 10% - 5% revenue fee -> 9.5%. only 80% utilization -> 7.6%.
        // 0.496 ether in yield. 5% goes to revenue -> 0,0248
        vm.warp(block.timestamp + 365 days); // earn a year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 1076000) / 1000000; // increased by 7.6%.
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 1100000) / 1000000; // increased by 10%
        expectedRevenue += 0.0248 ether + 4930649; // tolerate some inaccuracy 4930649, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 5336959999996055776; // user total supply 20% expanded
        _assertState(
            1000, // expected borrow rate
            760, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            6193504228171088640, // expected supply raw interest. total supply 6671199999995069720
            0 ether, // expected supply interest free
            4836146293425376256, // expected borrow raw interest. total borrow 5456000000000000156
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit. fully expanded 20%
            6547200000000000187 // expected borrow limit. user total borrow fully expanded 20%
        );

        // 4. test yield above kink 1
        _supply(mockProtocol, address(USDC), alice, 7.5 ether - 6671199999995069720); // bring total supply to 7.5 ether
        _borrow(mockProtocol, address(USDC), alice, 6.375 ether - 5456000000000000156); // bring utilization to 85%

        // warp & assert everything
        // borrow rate = 10% + 1/4 of slope 140% (150% -10%) -> 45%.
        // 6.375 ether paying 45% for a 1/3 year -> 15% yield. 5% of that is revenue.
        // supply rate = 45% - 5% revenue fee -> 42.75%. only 85% utilization -> 36.3375%.
        // 0.95625 ether in yield. 5% goes to revenue -> 0,0478125
        vm.warp(block.timestamp + 365 days / 3); // earn a 1/3 year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 1121125) / 1000000; // increased by 12,1125% (rate for 1/3 year)
        assertEq(expectedSupplyExchangePrice, 1207595704217);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 1150000) / 1000000; // increased by 15% (rate for 1/3 year)
        assertEq(expectedBorrowExchangePrice, 1297396650000);
        expectedRevenue += 0.0478125 ether + 5891211; // tolerate some inaccuracy 5891211, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 6726749999995287266; // user total supply 20% expanded
        _assertState(
            4500, // expected borrow rate
            3633, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            6962957445634592384, // expected supply raw interest. total supply 8408437499994109082
            0 ether, // expected supply interest free
            5650739116676461440, // expected borrow raw interest. total borrow 7331250000000000206
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit. fully expanded 20%
            8797500000000000247 // expected borrow limit. user total borrow fully expanded 20%
        );

        // 5. test yield at kink 2 (same values without another kink for v1)
        _supply(mockProtocol, address(USDC), alice, 8.5 ether - 8408437499994109082); // bring total supply to 8.5 ether
        _borrow(mockProtocol, address(USDC), alice, 7.65 ether - 7331250000000000206); // bring utilization to 90%

        // warp & assert everything
        // borrow rate at kink2 = 80%
        // 7.65 ether paying 80% for 5% of a year -> 4% yield. 5% of that is revenue.
        // supply rate = 80% - 5% revenue fee -> 76%. only 90% utilization -> 68.4%.
        // 0.306 ether in yield. 5% goes to revenue -> 0,0153
        vm.warp(block.timestamp + 365 days / 20); // earn 5% of a year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 1034200) / 1000000; // increased by 3.42%. (rate for 1/20 year)
        assertEq(expectedSupplyExchangePrice, 1248895477301);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 1040000) / 1000000; // increased by 4% (rate for 1/20 year)
        assertEq(expectedBorrowExchangePrice, 1349292516000);
        expectedRevenue += 0.0153 ether + 1559103; // tolerate some inaccuracy 1559103, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 7032559999998753095; // user total supply 20% expanded
        _assertState(
            8000, // expected borrow rate
            6840, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            7038779593466146176, // expected supply raw interest. total supply 8790699999998441369
            0 ether, // expected supply interest free
            5896423426097177216, // expected borrow raw interest. total borrow 7956000000000000306
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit. fully expanded 20%
            9547200000000000367 // expected borrow limit. user total borrow fully expanded 20%
        );

        // 6. test yield above kink 2 (same values without another kink for v1)
        _supply(mockProtocol, address(USDC), alice, 8.8 ether - 8790699999998441369); // bring total supply to 8.8 ether
        _borrow(mockProtocol, address(USDC), alice, 8.096 ether - 7956000000000000306); // bring utilization to 92%

        // warp & assert everything
        // borrow rate = 80% + 1/5 of slope 70% (150% -80%) -> 94%.
        // 8.096 ether paying 94% for a 1/365 year -> 0.25753424657534246% yield. 5% of that is revenue.
        // supply rate = 94% - 5% revenue fee -> 89.3%. only 92% utilization -> 82.156%.
        // 0.020849972602739726 ether in yield. 5% goes to revenue -> 0,001042498630136986
        vm.warp(block.timestamp + 1 days); // earn a 1 day yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 10022508493150684) / 10000000000000000; // increased by 0.22508493150684931% (rate for 1/365 year)
        assertEq(expectedSupplyExchangePrice, 1251706552830);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 10025753424657534) / 10000000000000000; // increased by 0.25753424657534246% (rate for 1/365 year)
        assertEq(expectedBorrowExchangePrice, 1352767406315);
        expectedRevenue += 0.001042498630136986 ether + 3689037; // tolerate some inaccuracy 3689037, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 7055845979174276467; // user total supply 20% fully expanded because start expand point was close
        _assertState(
            9400, // expected borrow rate
            8215, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            7046226173400646912, // expected supply raw interest. total supply 8819807473967845584
            0 ether, // expected supply interest free
            6000181505490541312, // expected borrow raw interest. total borrow 8116849972601671502
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit.
            9740219967122005802 // expected borrow limit. user total borrow fully expanded 20% because start expand point was close
        );

        // 7. test yield at max
        _supply(mockProtocol, address(USDC), alice, 9.6 ether - 8819807473967845584); // bring total supply to 9.6 ether
        _borrow(mockProtocol, address(USDC), alice, 9.6 ether - 8116849972601671502); // bring utilization to 100%

        // warp & assert everything
        // borrow rate at max = 150%.
        // 9.6 ether paying 150% for a 10% of a year -> 15% yield. 5% of that is revenue.
        // supply rate = 150% - 5% revenue fee -> 142.5%. 100% utilization.
        // 1.44 ether in yield. 5% goes to revenue -> 0,072
        vm.warp(block.timestamp + 365 days / 10); // earn a 10% year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 1142500) / 1000000; // increased by 14.25% (rate for 1/10 year)
        assertEq(expectedSupplyExchangePrice, 1430074736608);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 1150000) / 1000000; // increased by 15% (rate for 1/10 year)
        assertEq(expectedBorrowExchangePrice, 1555682517262);
        expectedRevenue += 0.072 ether + 335487; // tolerate some inaccuracy 1335487, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 8774399999998312507; // user total supply 20% fully expanded
        _assertState(
            15000, // expected borrow rate
            14250, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            7669529234544016768, // expected supply raw interest. total supply 10967999999997890634
            0 ether, // expected supply interest free
            7096563648107724032, // expected borrow raw interest. total borrow 11039999999998226085
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit.
            13247999999997871301 // expected borrow limit.  user total borrow fully expanded
        );

        // 8. test yield at utilization > 100%
        // utilization is at 11039999999998226085 / 10967999999997890634 = 100.656455142235132184% precision cut off 100.65%

        // warp & assert everything
        // borrow rate at max = 150%. + continuing the slope of rate -> 6.5% of slope 70% (150% -80%)
        // -> 150% + 4,55% = 154,55%
        // 11039999999998226085 ether paying 154,55% for 1 year yield. 5% of that is revenue.
        // supply rate = 154,55 - 5% revenue fee -> 146,8225%. 100.656455142235132184% utilization so 147,78624289%
        // Note: supply rate calculation in resolver uses utilization not from storage so result has higher precision)
        // supply exchange price calculation however uses 100.65% utilization so there it is 147,77684625.
        // 17.062319999997258414 ether in yield. 5% goes to revenue -> 0,853115999999862920 ether
        vm.warp(block.timestamp + 365 days); // earn a 1 year yield
        expectedSupplyExchangePrice = (expectedSupplyExchangePrice * 24777684625) / 10000000000; // increased by 147,77684625%
        assertEq(expectedSupplyExchangePrice, 3543394081385);
        expectedBorrowExchangePrice = (expectedBorrowExchangePrice * 25455) / 10000; // increased by 154,55%
        assertEq(expectedBorrowExchangePrice, 3959989847690);
        expectedRevenue += 0.853115999999862920 ether + 1039503299800972; // tolerate some inaccuracy 1039503299800972, from total amounts rounding
        // expected withdrawal limit:
        expectedWithdrawalLimit = 21740931597353998440; // user total supply 20% fully expanded
        _assertState(
            15455, // expected borrow rate
            14778, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            7669529234544016640, // expected supply raw interest. no changes only rounded down. total supply 27176164496692498051
            0 ether, // expected supply interest free
            7096563648107724160, // expected borrow raw interest. no changes only rounded up. total borrow 28102319999992497353
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit.
            33722783999990996823 // expected borrow limit. user total borrow fully expanded
        );

        // 9. test max limit
        // Set borrow config with lower max limit
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT, // 20%
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION, // 2 days;
            baseDebtCeiling: 2 ether, // raw, so at exchange price ~4, this is ~8 ether
            maxDebtCeiling: 5 ether // raw, so at exchange price ~4, this is ~20 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // assert borrowLimit
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(
            userBorrowData.borrowLimit,
            (baseLimitAfterBigMath * expectedBorrowExchangePrice) / 1e12,
            "borrowLimit off"
        );
        assertEq(userBorrowData.borrowableUntilLimit, 0, "borrowableUntilLimit off");
        assertEq(userBorrowData.borrowable, 0, "borrowable off");

        // assert reverts if borrowing more
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable + 1);

        // 10. payback down to 50% utilization
        _payback(mockProtocol, address(USDC), alice, (userBorrowData.borrow - 13588082248346249025)); // to 27176164496692498051 / 2

        // borrow rate = 4% + 5/8 of slope 6% (10% -4%) -> 7.75%.
        // supply rate = 7.75% - 5% revenue fee -> 7.3625%. only 50% utilization -> 3.68125%.
        expectedRevenue += 1538; // no changes but tolerate some inaccuracy 1538, from total amounts rounding
        _assertState(
            775, // expected borrow rate
            368, // expected supply rate.
            expectedSupplyExchangePrice, // expected supply exchange price.
            expectedBorrowExchangePrice, // expected borrow exchange price.
            expectedRevenue, // expected revenue.
            7669529234544016512, // expected supply raw interest. no changes only rounded down. total supply 27176164496692497597
            0 ether, // expected supply interest free
            3431342698081069760, // expected borrow raw interest. total borrow 13588082248346249094
            0 ether, // expected borrow interest free
            expectedWithdrawalLimit, // expected withdrawal limit.
            16305698698015498659 // expected borrow limit. user total borrow fully expanded. allow minor precision diff of 253
        );

        // later:
        // todo: 11. test with supply Interest free being added
        // todo: 12. test with borrow interest free being added
    }

    function _assertState(
        uint256 borrowRate,
        uint256 supplyRate,
        uint256 supplyExchangePrice,
        uint256 borrowExchangePrice,
        uint256 revenue,
        uint256 supplyRawInterest,
        uint256 supplyInterestFree,
        uint256 borrowRawInterest,
        uint256 borrowInterestFree,
        uint256 withdrawalLimit,
        uint256 borrowLimit
    ) internal {
        (
            ResolverStructs.UserSupplyData memory userSupplyData,
            ResolverStructs.OverallTokenData memory tokenData
        ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        assertEq(tokenData.borrowRate, borrowRate, "borrowRate off");
        assertEq(tokenData.supplyRate, supplyRate, "supplyRate off");
        assertEq(tokenData.supplyExchangePrice, supplyExchangePrice, "supplyExchangePrice off");
        assertEq(tokenData.borrowExchangePrice, borrowExchangePrice, "borrowExchangePrice off");
        assertApproxEqAbs(tokenData.revenue, revenue, 1e3, "revenue off");
        assertEq(tokenData.supplyRawInterest, supplyRawInterest, "supplyRawInterest off");
        assertEq(tokenData.supplyInterestFree, supplyInterestFree, "supplyInterestFree off");
        assertEq(tokenData.borrowRawInterest, borrowRawInterest, "borrowRawInterest off");
        assertEq(tokenData.borrowInterestFree, borrowInterestFree, "borrowInterestFree off");
        assertEq(
            tokenData.totalSupply,
            (supplyRawInterest * supplyExchangePrice) / 1e12 + supplyInterestFree,
            "totalSupply off"
        );
        assertEq(
            tokenData.totalBorrow,
            (borrowRawInterest * borrowExchangePrice) / 1e12 + borrowInterestFree,
            "totalBorrow off"
        );

        assertGe(tokenData.totalBorrow + USDC.balanceOf(address(liquidity)), tokenData.totalSupply + tokenData.revenue);

        // create liquidity to test withdrawable
        _supply(mockProtocolInterestFree, address(USDC), alice, 30 ether);
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));

        // assert withdrawalLimit
        assertApproxEqAbs(userSupplyData.withdrawalLimit, withdrawalLimit, 1e3, "withdrawalLimit off");
        assertApproxEqAbs(
            userSupplyData.withdrawableUntilLimit,
            userSupplyData.supply - withdrawalLimit,
            1e3,
            "withdrawableUntilLimit off"
        );
        assertApproxEqAbs(
            userSupplyData.withdrawable,
            userSupplyData.supply - withdrawalLimit,
            1e3,
            "withdrawable off"
        );

        if (userSupplyData.supply > 0 && userSupplyData.withdrawable < userSupplyData.supply) {
            // assert reverts if withdrawing more
            vm.expectRevert(
                abi.encodeWithSelector(
                    Error.FluidLiquidityError.selector,
                    ErrorTypes.UserModule__WithdrawalLimitReached
                )
            );
            _withdraw(mockProtocol, address(USDC), alice, userSupplyData.withdrawable + 1);
        }

        if (userSupplyData.withdrawable > 0) {
            // assert withdrawing exactly works
            _withdraw(mockProtocol, address(USDC), alice, userSupplyData.withdrawable - 1);
            // supply it back
            _supply(mockProtocol, address(USDC), alice, userSupplyData.withdrawable - 1);
        }

        // assert borrowLimit
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userBorrowData.borrowLimit, borrowLimit, "borrowLimit off");
        assertEq(userBorrowData.borrowableUntilLimit, borrowLimit - userBorrowData.borrow, "borrowableUntilLimit off");
        assertEq(userBorrowData.borrowable, borrowLimit - userBorrowData.borrow, "borrowable off");

        // assert reverts if borrowing more
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.UserModule__BorrowLimitReached)
        );
        _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable + 1);

        if (userBorrowData.borrowable > 1e3) {
            {
                uint256 borrowedBefore_ = userBorrowData.borrow;
                // assert borrowing exactly works
                _borrow(mockProtocol, address(USDC), alice, userBorrowData.borrowable - 1);
                // payback
                (userBorrowData, ) = resolver.getUserBorrowData(address(mockProtocol), address(USDC));
                _payback(mockProtocol, address(USDC), alice, userBorrowData.borrow - borrowedBefore_);
            }
        }

        _withdraw(mockProtocolInterestFree, address(USDC), alice, 30 ether);

        uint256[] memory returnedSupplyExchangePrice;
        uint256[] memory returnedBorrowExchangePrice;
        {
            address[] memory tokens = new address[](1);
            tokens[0] = address(USDC);
            vm.prank(admin);
            (returnedSupplyExchangePrice, returnedBorrowExchangePrice) = FluidLiquidityAdminModule(address(liquidity))
                .updateExchangePrices(tokens);
        }

        assertEq(returnedSupplyExchangePrice[0], supplyExchangePrice);
        assertEq(returnedBorrowExchangePrice[0], borrowExchangePrice);
    }
}

contract LiquidityUserModuleYieldCombinationRateV1Test is LiquidityUserModuleYieldCombinationBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // set rate data v1
        _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
    }
}

contract LiquidityUserModuleYieldCombinationRateV2Test is LiquidityUserModuleYieldCombinationBaseTest {
    function setUp() public virtual override {
        super.setUp();

        // set rate data v2
        _setDefaultRateDataV2(address(liquidity), admin, address(USDC));
    }
}
