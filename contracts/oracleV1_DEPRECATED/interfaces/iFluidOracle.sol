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

    /// @notice target decimals of the returned oracle rate when scaling to 1e27. E.g. for ETH / USDC it would be 15
    /// because diff of ETH decimals to 1e27 is 9, and USDC has 6 decimals, so 6+9 = 15, e.g. 2029,047772120364926
    /// For USDC / ETH: 21 + 18 = 39, e.g. 0,000492842018675092636829357843847601646
    function targetDecimals() external view returns (uint8);
}
