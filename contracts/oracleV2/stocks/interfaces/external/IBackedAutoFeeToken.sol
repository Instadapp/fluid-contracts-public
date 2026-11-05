// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Backed rebasing xStock underlying: live multiplier + scheduled multiplier updates.
interface IBackedAutoFeeToken {
    function getCurrentMultiplier()
        external
        view
        returns (uint256 currentMultiplier_, uint256 periodsPassed_, uint256 currentMultiplierNonce_);

    function newMultiplier() external view returns (uint256);

    function newMultiplierActivationTime() external view returns (uint256);
}
