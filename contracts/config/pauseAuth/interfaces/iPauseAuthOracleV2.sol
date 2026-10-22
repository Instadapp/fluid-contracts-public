// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title Fluid Pause Auth OracleV2 Interface
/// @notice OracleV2 executor used by `FluidPauseAuth`; touches the operate pause only.
interface IFluidPauseAuthOracleV2 {
    /// @notice Pauses OracleV2 operate prices; `acted_[i]` is false where a token was already paused.
    function pauseOperate(address[] calldata tokens_) external returns (bool[] memory acted_);

    /// @notice Lifts the operate pause; `acted_[i]` is false where a token was not paused.
    function unpauseOperate(address[] calldata tokens_) external returns (bool[] memory acted_);
}
