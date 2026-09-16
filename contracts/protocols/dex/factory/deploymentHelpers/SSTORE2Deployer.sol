// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SSTORE2 } from "solmate/src/utils/SSTORE2.sol";
import { BytesSliceAndConcat } from "../../../../libraries/bytesSliceAndConcat.sol";

/// @notice This contract is open and can be called by any address.
/// It provides functionality to deploy and read code using SSTORE2.
contract SStore2Deployer {
    /// @dev deploys code and emits an event with the pointer and code hash
    /// @param code_ code to deploy
    /// @return pointer_ pointer to the deployed code
    function deployCode(bytes memory code_) external returns (address pointer_) {
        pointer_ = SSTORE2.write(code_);
        emit LogCodeDeployed(pointer_, keccak256(code_));
    }

    /// @dev deploys code and emits an event with the pointer and code hash
    /// @param code_ code to deploy
    /// @return pointer1_ pointer to the first part of the deployed code
    /// @return pointer2_ pointer to the second part of the deployed code
    function deployCodeSplit(bytes memory code_) external returns (address pointer1_, address pointer2_) {
        // split storing creation code into two SSTORE2 pointers, because:
        // due to contract code limits 24576 bytes is the maximum amount of data that can be written in a single pointer / key.
        // Attempting to write more will result in failure.
        // So by splitting in two parts we can make sure that the contract bytecode size can use up the full limit of 24576 bytes.
        bytes memory code1_ = BytesSliceAndConcat.bytesSlice(code_, 0, code_.length / 2);
        // slice lengths:
        // when even length, e.g. 250:
        //      part 1 = 0 -> 250 / 2, so 0 until 125 length, so 0 -> 125
        //      part 2 = 250 / 2 -> 250 - 250 / 2, so 125 until 125 length, so 125 -> 250
        // when odd length: e.g. 251:
        //      part 1 = 0 -> 251 / 2, so 0 until 125 length, so 0 -> 125
        //      part 2 = 251 / 2 -> 251 - 251 / 2, so 125 until 126 length, so 125 -> 251
        bytes memory code2_ = BytesSliceAndConcat.bytesSlice(code_, code_.length / 2, code_.length - code_.length / 2);
        pointer1_ = SSTORE2.write(code1_);
        pointer2_ = SSTORE2.write(code2_);
        emit LogCodeDeployedSplit(pointer1_, pointer2_, keccak256(code_));
    }

    /// @dev reads code from a pointer
    /// @param pointer_ pointer to the code
    /// @return code_ code
    function readCode(address pointer_) external view returns (bytes memory code_) {
        code_ = SSTORE2.read(pointer_);
    }

    function readCodeSplit(address pointer1_, address pointer2_) external view returns (bytes memory code_) {
        code_ = BytesSliceAndConcat.bytesConcat(SSTORE2.read(pointer1_), SSTORE2.read(pointer2_));
    }

    event LogCodeDeployed(address pointer_, bytes32 codeHash_);
    event LogCodeDeployedSplit(address pointer1_, address pointer2_, bytes32 codeHash_);
}
