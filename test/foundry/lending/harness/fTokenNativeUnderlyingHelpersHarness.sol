//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { fTokenNativeUnderlyingHelpers } from "../../../../contracts/protocols/lending/fToken/nativeUnderlying/fTokenNativeUnderlying.sol";
import { IAllowanceTransfer } from "../../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";

contract fTokenNativeUnderlyingHelpersHarness is fTokenNativeUnderlyingHelpers {
    function exposed_prepareWrappedNativeDeposit(
        IAllowanceTransfer permit2_,
        IERC20 asset_,
        uint256 assets_,
        bytes memory liquidityCallbackData_
    ) external {
        _prepareWrappedNativeDeposit(permit2_, asset_, assets_, liquidityCallbackData_);
    }

    receive() external payable {}
}
