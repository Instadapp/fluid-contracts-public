// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidLiquidityResolver } from "../liquidity/iLiquidityResolver.sol";
import { IFluidStETHResolver } from "./iStETHResolver.sol";
import { IFluidStETHQueue } from "../../../protocols/steth/interfaces/iStETHQueue.sol";
import { Structs as StETHQueueStructs } from "../../../protocols/steth/structs.sol";
import { ILidoWithdrawalQueue } from "../../../protocols/steth/interfaces/external/iLidoWithdrawalQueue.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { Structs as LiquidityStructs } from "../liquidity/structs.sol";

/// @notice Fluid StETH protocol resolver
/// Implements various view-only methods to give easy access to StETH protocol data.
contract FluidStETHResolver is IFluidStETHResolver {
    /// @inheritdoc IFluidStETHResolver
    IFluidStETHQueue public immutable STETH_QUEUE;

    /// @inheritdoc IFluidStETHResolver
    ILidoWithdrawalQueue public immutable LIDO_WITHDRAWAL_QUEUE;

    /// @inheritdoc IFluidStETHResolver
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;

    /// @dev address that is mapped to the chain native token at Liquidity
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice thrown if an input param address is zero
    error FluidStETHResolver__AddressZero();
    /// @notice thrown if there is no Claim queued for the given input data
    error FluidStETHResolver__NoClaimQueued();

    constructor(IFluidStETHQueue stEthQueue_, IFluidLiquidityResolver liquidityResolver_, ILidoWithdrawalQueue lidoWithdrawalQueue_) {
        if (address(stEthQueue_) == address(0) || address(liquidityResolver_) == address(0) || address(lidoWithdrawalQueue_) == address(0)) {
            revert FluidStETHResolver__AddressZero();
        }

        STETH_QUEUE = stEthQueue_;
        LIQUIDITY_RESOLVER = liquidityResolver_;
        LIDO_WITHDRAWAL_QUEUE = lidoWithdrawalQueue_;
    }

    /// @inheritdoc IFluidStETHResolver
    function isClaimable(address claimTo_, uint256 requestIdFrom_) public view returns (bool) {
        StETHQueueStructs.Claim memory claim_ = STETH_QUEUE.claims(claimTo_, requestIdFrom_);

        if (claim_.checkpoint == 0) {
            revert FluidStETHResolver__NoClaimQueued();
        }

        uint256 requestsLength_ = claim_.requestIdTo - requestIdFrom_ + 1;
        uint256[] memory requestIds_;
        if (requestsLength_ == 1) {
            // only one request id
            requestIds_ = new uint256[](1);
            requestIds_[0] = requestIdFrom_;
            return LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(requestIds_)[0].isFinalized;
        }

        // build requestIds array from `requestIdFrom` to `requestIdTo`
        uint256 curRequest_ = requestIdFrom_;
        for (uint256 i; i < requestsLength_; ) {
            requestIds_[i] = curRequest_;

            unchecked {
                ++i;
                ++curRequest_;
            }
        }

        // get requests statuses
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses_ = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds_
        );

        // check for each status that it is finalized
        for (uint256 i; i < requestsLength_; ) {
            if (!statuses_[i].isFinalized) {
                return false;
            }

            unchecked {
                ++i;
            }
        }

        return true;
    }

    /// @inheritdoc IFluidStETHResolver
    function config()
        public
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
        )
    {
        (liquidity_, lidoWithdrawalQueue_, stETH_) = STETH_QUEUE.constantsView();
        maxLTV_ = STETH_QUEUE.maxLTV();
        allowListActive_ = STETH_QUEUE.allowListActive();
        owner_ = STETH_QUEUE.owner();
        isPaused_ = STETH_QUEUE.isPaused();
        (userBorrowData_, overallTokenData_) = getUserBorrowData();
    }

    /// @inheritdoc IFluidStETHResolver
    function isAuth(address auth_) public view returns (bool) {
        return STETH_QUEUE.isAuth(auth_);
    }

    /// @inheritdoc IFluidStETHResolver
    function isGuardian(address guardian_) public view returns (bool) {
        return STETH_QUEUE.isGuardian(guardian_);
    }

    /// @inheritdoc IFluidStETHResolver
    function isUserAllowed(address user_) public view returns (bool) {
        return STETH_QUEUE.isUserAllowed(user_);
    }

    /// @inheritdoc IFluidStETHResolver
    function isPaused() public view returns (bool) {
        return STETH_QUEUE.isPaused();
    }

    /// @inheritdoc IFluidStETHResolver
    function claim(
        address claimTo_,
        uint256 requestIdFrom_
    ) public view returns (StETHQueueStructs.Claim memory claim_, bool isClaimable_) {
        claim_ = STETH_QUEUE.claims(claimTo_, requestIdFrom_);
        isClaimable_ = isClaimable(claimTo_, requestIdFrom_);
    }

    /// @inheritdoc IFluidStETHResolver
    function getUserBorrowData()
        public
        view
        returns (
            LiquidityStructs.UserBorrowData memory userBorrowData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        )
    {
        (userBorrowData_, overallTokenData_) = LIQUIDITY_RESOLVER.getUserBorrowData(
            address(STETH_QUEUE),
            NATIVE_TOKEN_ADDRESS
        );
    }
}
