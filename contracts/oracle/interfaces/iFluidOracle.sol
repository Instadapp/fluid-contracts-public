// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidOracle {
    /// @notice Get the `exchangeRate_` between the underlying asset and the peg asset in 1e27
    function getExchangeRate() external view returns (uint256 exchangeRate_);
}
