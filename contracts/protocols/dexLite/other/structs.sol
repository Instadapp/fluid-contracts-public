// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./events.sol";

struct DexKey {
    address token0;
    address token1;
    bytes32 salt;
}

struct TransferParams {
    address to;
    bool isCallback;
    bytes callbackData;
    bytes extraData;
}
