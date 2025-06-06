// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";


interface IDexCallback {
    function dexCallback(address token_, uint256 amount_) external;
}

contract MockDexCallback {
    using SafeERC20 for IERC20;

    address public immutable liquidityContract;

    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address liquidityContract_) {
        liquidityContract = liquidityContract_;
    }

    function dexCallback(address token_, uint256 amount_) external payable {
        IERC20(token_).safeTransfer(liquidityContract, amount_);
    }

    receive() external payable {}
}