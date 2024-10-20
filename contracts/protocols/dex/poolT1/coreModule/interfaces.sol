// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface IHook {
    /// @notice Hook function to check for liquidation opportunities before external swaps
    /// @dev The primary use of this hook is to check if a particular pair vault has liquidation available.
    ///      If liquidation is available, it gives priority to the liquidation process before allowing external swaps.
    ///      In most cases, this hook will not be set.
    /// @param id_ Identifier for the operation type: 1 for swap, 2 for internal arbitrage
    /// @param swap0to1_ Direction of the swap: true if swapping token0 for token1, false otherwise
    /// @param token0_ Address of the first token in the pair
    /// @param token1_ Address of the second token in the pair
    /// @param price_ The price ratio of token1 to token0, expressed with 27 decimal places
    /// @return isOk_ Boolean indicating whether the operation should proceed
    function dexPrice(
        uint id_,
        bool swap0to1_,
        address token0_,
        address token1_,
        uint price_
    ) external returns (bool isOk_);
}

interface ICenterPrice {
    /// @notice Retrieves the center price for the pool
    /// @dev This function is marked as non-constant (potentially state-changing) to allow flexibility in price fetching mechanisms.
    ///      While typically used as a read-only operation, this design permits write operations if needed for certain token pairs
    ///      (e.g., fetching up-to-date exchange rates that may require state changes).
    /// @return price The current price ratio of token1 to token0, expressed with 27 decimal places
    function centerPrice() external returns (uint price);
}
