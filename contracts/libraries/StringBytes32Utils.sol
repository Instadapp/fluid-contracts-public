// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

/// @dev Helpers for strings stored as a `bytes32` word plus an explicit byte length.
library StringBytes32Utils {
    error StringBytes32Utils__InvalidStringLength();

    function _validatedStringLength(uint256 lengthUint_) private pure returns (uint8 length_) {
        if (lengthUint_ == 0 || lengthUint_ > 32) revert StringBytes32Utils__InvalidStringLength();
        length_ = uint8(lengthUint_);
    }

    function stringToBytes32(string calldata string_) internal pure returns (bytes32 bytes32_, uint8 length_) {
        length_ = _validatedStringLength(bytes(string_).length);

        assembly {
            bytes32_ := calldataload(string_.offset)
        }
    }

    function stringMemoryToBytes32(string memory string_) internal pure returns (bytes32 bytes32_, uint8 length_) {
        length_ = _validatedStringLength(bytes(string_).length);

        assembly {
            bytes32_ := mload(add(string_, 0x20))
        }
    }

    function bytes32ToString(bytes32 bytes32_, uint8 length_) internal pure returns (string memory string_) {
        if (length_ > 32) revert StringBytes32Utils__InvalidStringLength();

        string_ = new string(length_);
        bytes memory stringBytes_ = bytes(string_);
        assembly {
            mstore(add(stringBytes_, 0x20), bytes32_)
        }
    }
}
