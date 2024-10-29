// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract MockSwap {
    using SafeERC20 for IERC20;
    
    function swap(address buy_, address sell_, uint256 buyAmount_, uint256 sellAmount_) external payable {
        if (sell_ == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            // nothing
        } else {
            IERC20(sell_).safeTransferFrom(msg.sender, address(this), sellAmount_);
        }

        if (buy_ == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            Address.sendValue(payable(msg.sender), buyAmount_);
        } else {
            IERC20(buy_).safeTransfer(msg.sender, buyAmount_);
        }
    }
}