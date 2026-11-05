// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IWBETHOracle {
    /// @notice Returns the current exchange rate scaled by by 10**18
    function exchangeRate() external view returns (uint256 _exchangeRate);
}
