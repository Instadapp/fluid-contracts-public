// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FluidLiquidityUserModule } from "../liquidity/userModule/main.sol";
import { IFluidLiquidity } from "../liquidity/interfaces/iLiquidity.sol";

/// @title    Mock Protocol
/// @notice   Mock protocol for testing, implements:
///           function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external;
///           This callback method MUST transferFrom data_ decoded from address to the liquidity contract
contract MockProtocol {
    using SafeERC20 for IERC20;

    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable liquidityContract;

    /// @notice thrown when liquidity callback is called for a native token operation
    error MockProtocol__UnexpectedLiquidityCallback();

    bool transferInsufficientMode = false;
    bool transferExcessMode = false;
    bool reentrancyFromCallback = false;
    address transferFromAddress;

    /// @notice   Construct a new MockProtocol
    /// @param    liquidityContract_ The address of the liquidity contract
    constructor(address liquidityContract_) {
        liquidityContract = liquidityContract_;
    }

    receive() external payable {}

    function setTransferInsufficientMode(bool transferInsufficientMode_) public {
        transferInsufficientMode = transferInsufficientMode_;
    }

    function setTransferExcessMode(bool transferExcessMode_) public {
        transferExcessMode = transferExcessMode_;
    }

    function setReentrancyFromCallback(bool reentrancyFromCallback_) public {
        reentrancyFromCallback = reentrancyFromCallback_;
    }

    function setTransferFromAddress(address transferFromAddress_) public {
        transferFromAddress = transferFromAddress_;
    }

    /// @notice   Mock liquidity callback
    /// @param    token_ The token being transferred
    /// @param    amount_ The amount being transferred
    function liquidityCallback(address token_, uint256 amount_, bytes memory data_) external {
        if (reentrancyFromCallback) {
            // call operate with some random values (should not matter as it reverts anyway)
            IFluidLiquidity(liquidityContract).operate(
                token_,
                10,
                0,
                address(0),
                address(0),
                abi.encode(address(this))
            );
        }

        if (token_ == NATIVE_TOKEN_ADDRESS) {
            revert MockProtocol__UnexpectedLiquidityCallback();
        }

        address from_;
        if (transferFromAddress == address(0)) {
            // take the last 20 bytes of data_ and decode them to address. Gives more flexibility in type of
            // data that can be passed in to Liquidity at mock calls while ensuring mock Protocol can do what it
            // is supposed to do: transfer amount of token to liquidity.
            assembly {
                from_ := mload(
                    add(
                        // add padding for length as present for dynamic arrays in memory
                        add(data_, 32),
                        // assembly expects address with leading zeros / left padded so need to use 32 as length here
                        sub(mload(data_), 32)
                    )
                )
            }
        } else {
            from_ = transferFromAddress;
        }

        if (amount_ > 0) {
            if (transferExcessMode) {
                amount_ += (amount_ * 10101) / 10000; // max excess is 1%
            } else if (transferInsufficientMode) {
                amount_ -= 1;
            }
        }

        if (from_ == address(this)) {
            // use approve and transferFrom for more consistent testing of methods called
            // (always transferFrom instead of transfer)
            IERC20(token_).safeApprove(address(this), amount_);
            IERC20(token_).safeTransferFrom(address(this), liquidityContract, amount_);
        } else {
            IERC20(token_).safeTransferFrom(from_, liquidityContract, amount_);
        }
    }

    /// @notice   Proxy method for executing `operate` on the liquidity contract
    function operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes calldata callbackData_
    ) external payable returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        uint256 valueAmount = msg.value;

        if (valueAmount > 0) {
            if (transferExcessMode) {
                valueAmount += (valueAmount * 10101) / 10000; // max excess is 1%
            } else if (transferInsufficientMode) {
                valueAmount -= 1;
            }
        }

        return
            FluidLiquidityUserModule(liquidityContract).operate{ value: valueAmount }(
                token_,
                supplyAmount_,
                borrowAmount_,
                withdrawTo_,
                borrowTo_,
                callbackData_
            );
    }
}
