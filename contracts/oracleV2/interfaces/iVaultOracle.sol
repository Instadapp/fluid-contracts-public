// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

interface IVaultOracle {
    /// @dev Deprecated. Use `getExchangeRateOperate()` and `getExchangeRateLiquidate()` instead.
    function getExchangeRate() external view returns (uint256 exchangeRate_);

    /// @notice Get the exchange rate between collateral and debt in 1e27 for operates
    function getExchangeRateOperate() external view returns (uint256 exchangeRate_);

    /// @notice Get the exchange rate between collateral and debt in 1e27 for liquidations
    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_);
}
