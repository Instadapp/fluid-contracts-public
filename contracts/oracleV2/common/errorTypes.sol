// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

library ErrorTypes {
    /***********************************|
    |         Oracle V2 Common          |
    |__________________________________*/

    uint256 internal constant OracleV2Common__PriceZero = 310201;
    uint256 internal constant OracleV2Common__SharesZero = 310202;
    uint256 internal constant OracleV2Common__InvalidPegBuffer = 310203;

    /***********************************|
    |           Fluid Oracle            |
    |__________________________________*/

    uint256 internal constant FluidOracle__InvalidTargetDecimals = 310204;

    /***********************************|
    |           Sequencer L2            |
    |__________________________________*/

    /// @dev replaces `UsdOracle__SequencerDown` (310017) and, for down, `FluidOracleL2__SequencerOutage` (60000) of
    ///      the V2 center prices / capped rates
    uint256 internal constant SequencerL2__SequencerDown = 310205;
    /// @dev replaces `UsdOracle__SequencerGracePeriod` (310018) and, for the grace period, `FluidOracleL2__SequencerOutage`
    ///      (60000) of the V2 center prices / capped rates
    uint256 internal constant SequencerL2__GracePeriod = 310206;
    /// @dev sequencer uptime feed address has no code; replaces the per-oracle constructor checks
    ///      (`CenterPrice__InvalidParams`, `UsdOracle__AddressZero` / `UsdOracle__InvalidParams`)
    uint256 internal constant SequencerL2__InvalidFeed = 310207;
}
