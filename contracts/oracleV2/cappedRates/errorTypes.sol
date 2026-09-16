// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /// @notice thrown when sequencer on a L2 has an outage and grace period has not yet passed.
    uint256 internal constant FluidOracleL2__SequencerOutage = 60000;

    /// @notice thrown when an invalid info name is passed into a fluid oracle.
    uint256 internal constant FluidOracle__InvalidInfoName = 60010;

    /// @notice thrown when an invalid parameter is passed to a method.
    uint256 internal constant CappedRate__InvalidParams = 60351;

    /// @notice thrown when caller is not authorized.
    uint256 internal constant CappedRate__Unauthorized = 60352;

    /// @notice thrown when minimum diff for triggering update on the stored rate is not reached.
    uint256 internal constant CappedRate__MinUpdateDiffNotReached = 60353;

    /// @notice thrown when the external rate source returns 0 for the new rate.
    uint256 internal constant CappedRate__NewRateZero = 60354;

    /// @notice thrown when new rate source does not fit in uint192 storage.
    uint256 internal constant CappedRate__StorageOverflow = 60355;
}
