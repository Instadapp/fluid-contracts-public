// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /// @notice thrown when sequencer on a L2 has an outage and grace period has not yet passed.
    uint256 internal constant FluidOracleL2__SequencerOutage = 60000;

    /// @notice thrown when an invalid info name is passed into a fluid oracle.
    uint256 internal constant FluidOracle__InvalidInfoName = 60010;

    /// @notice thrown when an invalid parameter is passed to a method.
    uint256 internal constant CenterPrice__InvalidParams = 60421;

    /// @notice thrown when the referenced center price rate is zero.
    uint256 internal constant CenterPrice__RateZero = 60422;
}
