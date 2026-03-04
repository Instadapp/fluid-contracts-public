// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidCenterPrice {
    /// @notice Retrieves the center price for the pool
    /// @dev This function is marked as non-constant (potentially state-changing) to allow flexibility in price fetching mechanisms.
    ///      While typically used as a read-only operation, this design permits write operations if needed for certain token pairs
    ///      (e.g., fetching up-to-date exchange rates that may require state changes).
    /// @return price_ The current price ratio of token1 to token0, expressed with 27 decimal places
    function centerPrice() external returns (uint256 price_);

    /// @notice helper string to easily identify the oracle. E.g. token symbols
    function infoName() external view returns (string memory);

    /// @notice target decimals of the returned rate. for center price contracts it is always 27
    function targetDecimals() external view returns (uint8);
}
