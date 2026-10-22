//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Structs } from "../structs.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { ILidoWithdrawalQueue } from "../interfaces/external/iLidoWithdrawalQueue.sol";

interface IFluidStETHQueue {
    /// @notice returns the constant values for LIQUIDITY, LIDO_WITHDRAWAL_QUEUE, STETH
    function constantsView() external view returns (IFluidLiquidity, ILidoWithdrawalQueue, IERC20);

    /// @notice gets an open Claim for `claimTo_` and `requestIdFrom_`
    function claims(address claimTo_, uint256 requestIdFrom_) external view returns (Structs.Claim memory);

    /// @notice reads if a certain `auth_` address is an allowed auth or not
    function isAuth(address auth_) external view returns (bool);

    /// @notice reads if a certain `guardian_` address is an allowed guardian or not
    function isGuardian(address guardian_) external view returns (bool);

    /// @notice reads if a certain `user_` address is an allowed user or not
    function isUserAllowed(address user_) external view returns (bool);

    /// @notice maximum allowed percentage of LTV (loan-to-value). E.g. 90% -> max. 90 ETH can be borrowed with 100 stETH
    /// as collateral in withdrawal queue. ETH will be received at time of claim to cover the paid borrowed ETH amount.
    /// In 1e2 (1% = 100, 90% = 9_000, 100% = 10_000).
    /// Configurable by auths.
    function maxLTV() external view returns (uint16);

    /// @notice flag whether allow list behavior is enabled or not.
    function allowListActive() external view returns (bool);

    /// @notice reads if the protocol is paused or not
    function isPaused() external view returns (bool);

    /// @notice reads owner address
    function owner() external view returns (address);
}
