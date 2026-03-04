// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

event LogSwap(uint256 swapData, uint256 dexVariables);
// swapData
// First 64 bits => 0   - 63  => dexId
// Next  1  bit  => 64        => swap 0 to 1 (1 => true, 0 => false)
// Next  60 bits => 65  - 124 => amount in adjusted
// Next  60 bits => 125 - 184 => amount out adjusted

// dexVariables
// Same as variables.sol