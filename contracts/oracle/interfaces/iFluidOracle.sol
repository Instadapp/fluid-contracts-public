// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidOracle {
    /// @dev Deprecated. Use `getExchangeRateOperate()` and `getExchangeRateLiquidate()` instead. Only implemented for
    ///      backwards compatibility.
    function getExchangeRate() external view returns (uint256 exchangeRate_);

    /// @notice Get the `exchangeRate_` between the underlying asset and the peg asset in 1e27 for operates
    function getExchangeRateOperate() external view returns (uint256 exchangeRate_);

    /// @notice Get the `exchangeRate_` between the underlying asset and the peg asset in 1e27 for liquidations
    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_);

    /// @notice helper string to easily identify the oracle. E.g. token symbols
    function infoName() external view returns (string memory);
}
