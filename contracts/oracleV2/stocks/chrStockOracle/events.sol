// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

abstract contract Events {
    event LogPause(address indexed sender);
    event LogUnpause(address indexed sender);
    event LogPauseLatched(uint256 causes);
    event LogSetAnchor(uint256 oldValue, uint256 newValue, uint256 oldMultiplier, uint256 newMultiplier);
    event LogRecordHint(uint256 value, uint256 age, uint256 regularEnd);
    event LogSealAnchor(uint256 value, uint256 age);
}
