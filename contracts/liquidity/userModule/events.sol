// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

contract Events {
    /// @notice emitted on any `operate()` execution: deposit / supply / withdraw / borrow.
    /// includes info related to the executed operation, new total amounts (packed uint256 of BigMath numbers as in storage)
    /// and exchange prices (packed uint256 as in storage).
    /// @param user protocol that triggered this operation (e.g. via an fToken or via Vault protocol)
    /// @param token token address for which this operation was executed
    /// @param supplyAmount supply amount for the operation. if >0 then a deposit happened, if <0 then a withdrawal happened.
    ///                     if 0 then nothing.
    /// @param borrowAmount borrow amount for the operation. if >0 then a borrow happened, if <0 then a payback happened.
    ///                     if 0 then nothing.
    /// @param withdrawTo   address that funds where withdrawn to (if supplyAmount <0)
    /// @param borrowTo     address that funds where borrowed to (if borrowAmount >0)
    /// @param totalAmounts updated total amounts, stacked uint256 as written to storage:
    /// First  64 bits =>   0- 63 => total supply with interest in raw (totalSupply = totalSupplyRaw * supplyExchangePrice); BigMath: 56 | 8
    /// Next   64 bits =>  64-127 => total interest free supply in normal token amount (totalSupply = totalSupply); BigMath: 56 | 8
    /// Next   64 bits => 128-191 => total borrow with interest in raw (totalBorrow = totalBorrowRaw * borrowExchangePrice); BigMath: 56 | 8
    /// Next   64 bits => 192-255 => total interest free borrow in normal token amount (totalBorrow = totalBorrow); BigMath: 56 | 8
    /// @param exchangePricesAndConfig updated exchange prices and configs storage slot. Contains updated supply & borrow exchange price:
    /// First 16 bits =>   0- 15 => borrow rate (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
    /// Next  14 bits =>  16- 29 => fee on interest from borrowers to lenders (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
    /// Next  14 bits =>  30- 43 => last stored utilization (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    /// Next  14 bits =>  44- 57 => update on storage threshold (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
    /// Next  33 bits =>  58- 90 => last update timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  64 bits =>  91-154 => supply exchange price (1e12 -> max value 18_446_744,073709551615)
    /// Next  64 bits => 155-218 => borrow exchange price (1e12 -> max value 18_446_744,073709551615)
    /// Next   1 bit  => 219-219 => if 0 then ratio is supplyInterestFree / supplyWithInterest else ratio is supplyWithInterest / supplyInterestFree
    /// Next  14 bits => 220-233 => supplyRatio: supplyInterestFree / supplyWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    /// Next   1 bit  => 234-234 => if 0 then ratio is borrowInterestFree / borrowWithInterest else ratio is borrowWithInterest / borrowInterestFree
    /// Next  14 bits => 235-248 => borrowRatio: borrowInterestFree / borrowWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    event LogOperate(
        address indexed user,
        address indexed token,
        int256 supplyAmount,
        int256 borrowAmount,
        address withdrawTo,
        address borrowTo,
        uint256 totalAmounts,
        uint256 exchangePricesAndConfig
    );
}
