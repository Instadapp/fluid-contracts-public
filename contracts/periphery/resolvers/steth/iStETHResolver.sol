//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidLiquidityResolver } from "../liquidity/iLiquidityResolver.sol";
import { IFluidStETHQueue } from "../../../protocols/steth/interfaces/iStETHQueue.sol";
import { ILidoWithdrawalQueue } from "../../../protocols/steth/interfaces/external/iLidoWithdrawalQueue.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { Structs as StETHQueueStructs } from "../../../protocols/steth/structs.sol";
import { Structs as LiquidityStructs } from "../liquidity/structs.sol";

interface IFluidStETHResolver {
    /// @notice address of the stETHQueue contract
    function STETH_QUEUE() external view returns (IFluidStETHQueue);

    /// @notice address of the Lido Withdrawal Queue contract (0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1)
    function LIDO_WITHDRAWAL_QUEUE() external view returns (ILidoWithdrawalQueue);

    /// @notice address of the LiquidityResolver
    function LIQUIDITY_RESOLVER() external view returns (IFluidLiquidityResolver);

    /// @notice returns all constants and config values
    function config()
        external
        view
        returns (
            IFluidLiquidity liquidity_,
            ILidoWithdrawalQueue lidoWithdrawalQueue_,
            IERC20 stETH_,
            address owner_,
            uint16 maxLTV_,
            bool allowListActive_,
            bool isPaused_,
            LiquidityStructs.UserBorrowData memory userBorrowData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        );

    /// @notice checks if a linked claim for `claimTo_` and `claimTo_` is ready to be processed at Lido Withdrawal Queue
    /// @param claimTo_ claimTo receiver to process the claim for
    /// @param requestIdFrom_ Lido requestId from (start), as emitted at time of queuing via `LogQueue`
    function isClaimable(address claimTo_, uint256 requestIdFrom_) external view returns (bool);

    /// @notice reads if a certain `auth_` address is an allowed auth or not
    function isAuth(address auth_) external view returns (bool);

    /// @notice reads if a certain `guardian_` address is an allowed guardian or not
    function isGuardian(address guardian_) external view returns (bool);

    /// @notice reads if a certain `user_` address is an allowed user or not
    function isUserAllowed(address user_) external view returns (bool);

    /// @notice reads if the protocol is paused or not
    function isPaused() external view returns (bool);

    /// @notice reads a Claim struct containing necessary information for executing the claim process from the mapping
    /// claimTo and requestIdFrom -> claims and the claimable status.
    function claim(
        address claimTo_,
        uint256 requestIdFrom_
    ) external view returns (StETHQueueStructs.Claim memory claim_, bool isClaimable_);

    /// @notice returns borrow data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for native token
    function getUserBorrowData()
        external
        view
        returns (
            LiquidityStructs.UserBorrowData memory userBorrowData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        );
}
