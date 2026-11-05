// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { IFluidOracleWithDebt } from "./iFluidOracleWithDebt.sol";

interface IFluidCappedRate is IFluidOracleWithDebt {
    /// @notice Retrieves the center price for use in a Fluid dex pool
    /// @dev This function is marked as non-constant (potentially state-changing) to allow flexibility in price fetching mechanisms.
    ///      While typically used as a read-only operation, this design permits write operations if needed for certain token pairs
    ///      (e.g., fetching up-to-date exchange rates that may require state changes).
    /// @return price_ The current price ratio of token1 to token0, expressed with 27 decimal places
    function centerPrice() external returns (uint256 price_);
}
