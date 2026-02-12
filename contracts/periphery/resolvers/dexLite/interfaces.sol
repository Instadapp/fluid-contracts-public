// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";
import { ICenterPrice } from "../../../protocols/dexLite/other/interfaces.sol";

interface IDexLite {
    function swapSingle(
        DexKey calldata dexKey_, 
        bool swap0To1_, 
        int256 amountSpecified_,
        uint256 amountLimit_,
        address to_,
        bool isCallback_,
        bytes calldata callbackData_,
        bytes calldata extraData_
    ) external payable returns (uint256 amountUnspecified_);

    function swapHop(
        address[] calldata path_,
        DexKey[] calldata dexKeys_,
        int256 amountSpecified_,
        uint256[] calldata amountLimits_,
        TransferParams calldata transferParams_
    ) external payable returns (uint256 amountUnspecified_);

    function readFromStorage(bytes32 slot) external view returns (bytes32);
}