// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import "./structs.sol";

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}

interface IDexLiteCallback {
    function dexCallback(address token_, uint256 amount_, bytes calldata data_) external;
}

interface ICenterPrice {
    /// @notice Retrieves the center price for the pool
    /// @dev This function is marked as non-constant (potentially state-changing) to allow flexibility in price fetching mechanisms.
    ///      While typically used as a read-only operation, this design permits write operations if needed for certain token pairs
    ///      (e.g., fetching up-to-date exchange rates that may require state changes).
    /// @return price The current price of token0 in terms of token1, expressed with 27 decimal places
    function centerPrice(address token0_, address token1_) external returns (uint256);
}