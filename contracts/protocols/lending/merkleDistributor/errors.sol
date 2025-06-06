// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Errors {
    error Unauthorized();
    error InvalidParams();

    // claim related errors:
    error InvalidCycle();
    error InvalidProof();
    error NothingToClaim();
    error MsgSenderNotRecipient();
}
