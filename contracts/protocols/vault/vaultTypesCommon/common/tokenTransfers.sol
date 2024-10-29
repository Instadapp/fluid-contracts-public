// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";

abstract contract TokenTransfers is Error {
    function _validateEth(uint initialEth_) internal {
        uint finalEth_ = payable(address(this)).balance;
        if (finalEth_ > initialEth_) {
            unchecked {
                SafeTransfer.safeTransferNative(msg.sender, finalEth_ - initialEth_); // sending back excess ETH
            }
        } else if (finalEth_ < initialEth_) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueOperate);
        }
    }
}
