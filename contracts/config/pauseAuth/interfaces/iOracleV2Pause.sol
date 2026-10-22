// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title Fluid OracleV2 Pause Interface
/// @notice The `FluidUsdOracle` methods `FluidPauseAuthOracleV2` calls as a guardian.
interface IFluidOracleV2Pause {
    function getTokenConfig(
        address token_
    ) external view returns (bool operatePaused_, bool liquidatePaused_, uint8 tokenType_, uint8 decimals_);

    /// @notice Reverts for a guardian that changes the liquidate bit.
    function setPausedState(address token_, bool pauseOperate_, bool pauseLiquidate_) external;
}
