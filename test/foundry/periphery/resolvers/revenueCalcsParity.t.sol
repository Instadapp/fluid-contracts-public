//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { CalcsSimulatedTime } from "../../../../contracts/periphery/resolvers/revenue/calcsSimulatedTime.sol";

import { LibraryLiquidityCalcsBaseTest } from "../../libraries/liquidityCalcs/liquidityCalcsBaseTest.t.sol";

contract CalcsSimulatedTimeHarness {
    function calcExchangePrices(
        uint256 exchangePricesAndConfig_,
        uint256 blockTimestamp_
    ) external pure returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        return CalcsSimulatedTime.calcExchangePrices(exchangePricesAndConfig_, blockTimestamp_);
    }

    function calcRevenue(
        uint256 totalAmounts_,
        uint256 exchangePricesAndConfig_,
        uint256 liquidityTokenBalance_,
        uint256 blockTimestamp_
    ) external pure returns (uint256 revenueAmount_) {
        return
            CalcsSimulatedTime.calcRevenue(
                totalAmounts_,
                exchangePricesAndConfig_,
                liquidityTokenBalance_,
                blockTimestamp_
            );
    }
}

/// @notice The revenue resolver's simulated-time copy of `LiquidityCalcs` must return exactly what the production
///         library returns at the same timestamp, including the rounding directions.
contract RevenueCalcsParityTest is LibraryLiquidityCalcsBaseTest {
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;
    uint256 internal constant NOW = 1_000_000_000;

    CalcsSimulatedTimeHarness internal simulated;

    function setUp() public virtual override {
        super.setUp();
        simulated = new CalcsSimulatedTimeHarness();
        vm.warp(NOW);
    }

    function _config(
        uint256 borrowRate_,
        uint256 elapsed_,
        uint256 supplyExchangePrice_,
        uint256 borrowExchangePrice_
    ) internal pure returns (uint256) {
        return
            _simulateExchangePricesAndConfig(
                borrowRate_,
                0, // fee
                5000, // utilization 50%
                0, // updateOnStorageThreshold
                NOW - elapsed_,
                supplyExchangePrice_,
                borrowExchangePrice_,
                0, // supplyRatioMode
                5000, // supplyRatio
                0, // borrowRatioMode
                5000 // borrowRatio
            );
    }

    function _assertExchangePricesMatch(uint256 config_) internal {
        (uint256 supply_, uint256 borrow_) = testHelper.calcExchangePrices(config_);
        (uint256 simulatedSupply_, uint256 simulatedBorrow_) = simulated.calcExchangePrices(config_, NOW);
        assertEq(simulatedSupply_, supply_, "supply exchange price");
        assertEq(simulatedBorrow_, borrow_, "borrow exchange price");
    }

    function test_calcExchangePrices_MatchesWhenBorrowAccrualRoundsUp() public {
        // 1 second at 0.01% accrues 3.17 on a 1e12 price: ceil gives +4 where a floored copy gives +3
        uint256 config_ = _config(1, 1, EXCHANGE_PRICES_PRECISION, EXCHANGE_PRICES_PRECISION);

        (, uint256 borrow_) = simulated.calcExchangePrices(config_, NOW);
        assertEq(borrow_, EXCHANGE_PRICES_PRECISION + 4);
        _assertExchangePricesMatch(config_);
    }

    function testFuzz_calcExchangePrices_MatchesLiquidityCalcs(
        uint16 borrowRate_,
        uint256 fee_,
        uint256 utilization_,
        uint32 elapsed_,
        uint256 supplyExchangePrice_,
        uint256 borrowExchangePrice_,
        bool supplyRatioMode_,
        uint256 supplyRatio_,
        bool borrowRatioMode_,
        uint256 borrowRatio_
    ) public {
        uint256 config_ = _simulateExchangePricesAndConfig(
            borrowRate_,
            bound(fee_, 0, 1e4),
            bound(utilization_, 0, 1e4),
            0,
            NOW - bound(elapsed_, 0, 10 * 365 days),
            bound(supplyExchangePrice_, EXCHANGE_PRICES_PRECISION, 1e15),
            bound(borrowExchangePrice_, EXCHANGE_PRICES_PRECISION, 1e15),
            supplyRatioMode_ ? 1 : 0,
            bound(supplyRatio_, 0, 1e4),
            borrowRatioMode_ ? 1 : 0,
            bound(borrowRatio_, 0, 1e4)
        );

        _assertExchangePricesMatch(config_);
    }

    function test_calcRevenue_MatchesWhenTotalSupplyRoundsUp() public {
        // 7 raw at a price of 1e12 + 1 owes depositors 7.000000000007, so the ceil-rounded copy keeps 8 back
        uint256 totalAmounts_ = _simulateTotalAmounts(7, 0, 0, 0);
        uint256 config_ = _config(0, 0, EXCHANGE_PRICES_PRECISION + 1, EXCHANGE_PRICES_PRECISION);

        assertEq(simulated.calcRevenue(totalAmounts_, config_, 10, NOW), 2);
        assertEq(
            simulated.calcRevenue(totalAmounts_, config_, 10, NOW),
            testHelper.calcRevenue(totalAmounts_, config_, 10)
        );
    }

    function testFuzz_calcRevenue_MatchesLiquidityCalcs(
        uint64 supplyWithInterest_,
        uint64 supplyInterestFree_,
        uint64 borrowWithInterest_,
        uint64 borrowInterestFree_,
        uint16 borrowRate_,
        uint32 elapsed_,
        uint256 supplyExchangePrice_,
        uint256 borrowExchangePrice_,
        uint128 balance_
    ) public {
        uint256 totalAmounts_ = _simulateTotalAmounts(
            supplyWithInterest_,
            supplyInterestFree_,
            borrowWithInterest_,
            borrowInterestFree_
        );
        uint256 config_ = _config(
            borrowRate_,
            bound(elapsed_, 0, 10 * 365 days),
            bound(supplyExchangePrice_, EXCHANGE_PRICES_PRECISION, 1e15),
            bound(borrowExchangePrice_, EXCHANGE_PRICES_PRECISION, 1e15)
        );

        assertEq(
            simulated.calcRevenue(totalAmounts_, config_, balance_, NOW),
            testHelper.calcRevenue(totalAmounts_, config_, balance_)
        );
    }
}
