//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { CommonHelpers } from "../../../../contracts/liquidity/common/helpers.sol";
import { Events } from "../../../../contracts/liquidity/userModule/events.sol";
import { ErrorTypes } from "../../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../../contracts/liquidity/error.sol";

interface IProtocol {
    function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external;
}

abstract contract CoreInternals is Error, CommonHelpers, Events {
    /// @dev Single function which handles supply, withdraw, borrow & payback
    /// @param token_ address of token
    /// @param supplyAmount_ if +ve then supply, if -ve then withdraw, if 0 then nothing
    /// @param borrowAmount_ if +ve then borrow, if -ve then payback, if 0 then nothing
    // /// @param withdrawTo_ if withdrawal then to which address
    // /// @param borrowTo_ if borrow then to which address
    /// @param callbackData_ callback data passed to `liquidityCallback` method of protocol
    /// @param temp2_ operateAmountIn: supply amount + payback amount
    /// @return temp3_ supplyExchangePrice
    /// @return temp4_ borrowExchangePrice
    function _operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address /* withdrawTo_ */,
        address /* borrowTo_ */,
        bytes calldata callbackData_,
        uint256 temp2_
    ) internal returns (uint256 /* temp3_ */, uint256 /* temp4_ */) {
        if (supplyAmount_ == 0 && borrowAmount_ == 0) {
            revert FluidLiquidityError(ErrorTypes.UserModule__OperateAmountsZero);
        }
        uint256 temp_;

        if (temp2_ > 0 && token_ != NATIVE_TOKEN_ADDRESS) {
            temp_ = IERC20(token_).balanceOf(address(this));
            (, address from_) = abi.decode(callbackData_, (bool, address));
            // forces to return abi.encode(false, from_) as callback
            IProtocol(msg.sender).liquidityCallback(token_, temp2_, abi.encode(false, from_));
            temp_ = IERC20(token_).balanceOf(address(this)) - temp_;

            if (temp_ < temp2_) {
                revert FluidLiquidityError(ErrorTypes.UserModule__TransferAmountOutOfBounds);
            }
        }
    }
}

contract UserModuleMock is CoreInternals {
    /// @notice inheritdoc IFluidLiquidity
    function operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes calldata callbackData_
    ) external payable reentrancy returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        uint256 operateAmountIn_ = uint256((supplyAmount_ > 0 ? supplyAmount_ : int256(0))) +
            uint256((borrowAmount_ < 0 ? -borrowAmount_ : int256(0)));

        if (token_ == NATIVE_TOKEN_ADDRESS && operateAmountIn_ > msg.value) {
            revert FluidLiquidityError(ErrorTypes.UserModule__TransferAmountOutOfBounds);
        }

        (supplyExchangePrice_, borrowExchangePrice_) = _operate(
            token_,
            supplyAmount_,
            borrowAmount_,
            withdrawTo_,
            borrowTo_,
            callbackData_,
            operateAmountIn_
        );
    }
}
