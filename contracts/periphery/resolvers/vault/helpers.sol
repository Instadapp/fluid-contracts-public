// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { TickMath } from "../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";

contract Helpers is Variables, Structs {
    function normalSlot(uint256 slot_) public pure returns (bytes32) {
        return bytes32(slot_);
    }

    /// @notice Calculating the slot ID for Liquidity contract for single mapping
    function calculateStorageSlotUintMapping(uint256 slot_, uint key_) public pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Liquidity contract for single mapping
    function calculateStorageSlotIntMapping(uint256 slot_, int key_) public pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Liquidity contract for double mapping
    function calculateDoubleIntUintMapping(uint256 slot_, int key1_, uint key2_) public pure returns (bytes32) {
        bytes32 intermediateSlot_ = keccak256(abi.encode(key1_, slot_));
        return keccak256(abi.encode(key2_, intermediateSlot_));
    }

    function tickHelper(uint tickRaw_) public pure returns (int tick) {
        require(tickRaw_ < X20, "invalid-number");
        if (tickRaw_ > 0) {
            tick = tickRaw_ & 1 == 1 ? int((tickRaw_ >> 1) & X19) : -int((tickRaw_ >> 1) & X19);
        } else {
            tick = type(int).min;
        }
    }

    constructor(address factory_, address liquidityResolver_) Variables(factory_, liquidityResolver_) {}
}
