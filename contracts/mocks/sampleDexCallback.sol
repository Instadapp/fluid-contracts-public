// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

interface IDexCallback {
    function dexCallback(address token_, uint256 amount_) external;
}

contract MockSampleDexCallback is IDexCallback {
    using SafeERC20 for IERC20;

    address constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public immutable FLUID_LIQUIDITY;

    address public senderTransient;

    constructor(address fluidLiquidity_) {
        FLUID_LIQUIDITY = fluidLiquidity_;
        senderTransient = DEAD_ADDRESS; // so to DEAD_ADDRESS to optimize gas refunds
    }

    // [...] Integration logic for swap, which triggers FluidDex.swapInWithCallback()
    // senderTransient = msg.sender; // tmp store (use transient on newer Solidity versions)

    // @INTEGRATOR: MUST IMPLEMENT:
    function dexCallback(address token_, uint256 amount_) external override {
        // ideally, transfer tokens from User -> Fluid liquidity layer:
        IERC20(token_).safeTransferFrom(senderTransient, FLUID_LIQUIDITY, amount_);

        senderTransient = DEAD_ADDRESS; // reset for ~5k gas refund

        // Alternative if tokens must be transferred from user -> integration contract first
        // IERC20(token_).safeTransfer(liquidityContract, amount_);
    }
}
