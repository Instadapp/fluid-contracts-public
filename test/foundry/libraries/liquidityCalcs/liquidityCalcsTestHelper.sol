//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

/// @title LiquidityCalcsTestHelper
/// @notice used to measure gas for LiquidityCalcs methods via foundry --gas-report (which doesn't work for libraries)
contract LiquidityCalcsTestHelper {
    function calcExchangePrices(
        uint256 exchangePricesAndConfig_
    ) public view returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        return LiquidityCalcs.calcExchangePrices(exchangePricesAndConfig_);
    }

    function calcWithdrawalLimitBeforeOperate(
        uint256 userSupplyData_,
        uint256 userSupply_
    ) public view returns (uint256 currentWithdrawalLimit_) {
        return LiquidityCalcs.calcWithdrawalLimitBeforeOperate(userSupplyData_, userSupply_);
    }

    function calcWithdrawalLimitAfterOperate(
        uint256 userSupplyData_,
        uint256 userSupply_,
        uint256 newWithdrawalLimit_
    ) public pure returns (uint256) {
        return LiquidityCalcs.calcWithdrawalLimitAfterOperate(userSupplyData_, userSupply_, newWithdrawalLimit_);
    }

    function calcBorrowLimitBeforeOperate(
        uint256 userBorrowData_,
        uint256 userBorrow_
    ) public view returns (uint256 currentBorrowLimit_) {
        return LiquidityCalcs.calcBorrowLimitBeforeOperate(userBorrowData_, userBorrow_);
    }

    function calcBorrowLimitAfterOperate(
        uint256 userBorrowData_,
        uint256 userBorrow_,
        uint256 newBorrowLimit_
    ) public pure returns (uint256 borrowLimit_) {
        return LiquidityCalcs.calcBorrowLimitAfterOperate(userBorrowData_, userBorrow_, newBorrowLimit_);
    }

    function calcBorrowRateFromUtilization(uint256 rateData_, uint256 utilization_) public returns (uint256 rate_) {
        return LiquidityCalcs.calcBorrowRateFromUtilization(rateData_, utilization_);
    }

    function calcRateV1(uint256 rateData_, uint256 utilization_) public pure returns (uint256 rate_) {
        return LiquidityCalcs.calcRateV1(rateData_, utilization_);
    }

    function calcRateV2(uint256 rateData_, uint256 utilization_) public pure returns (uint256 rate_) {
        return LiquidityCalcs.calcRateV2(rateData_, utilization_);
    }

    function getTotalSupply(
        uint256 totalAmounts_,
        uint256 supplyExchangePrice_
    ) public pure returns (uint256 totalSupply_) {
        return LiquidityCalcs.getTotalSupply(totalAmounts_, supplyExchangePrice_);
    }

    function getTotalBorrow(
        uint256 totalAmounts_,
        uint256 borrowExchangePrice_
    ) public pure returns (uint256 totalBorrow_) {
        return LiquidityCalcs.getTotalBorrow(totalAmounts_, borrowExchangePrice_);
    }
}
