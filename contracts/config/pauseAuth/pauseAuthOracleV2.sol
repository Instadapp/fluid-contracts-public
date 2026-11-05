// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidPauseAuthOracleV2 } from "./interfaces/iPauseAuthOracleV2.sol";
import { IFluidOracleV2Pause } from "./interfaces/iOracleV2Pause.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title   FluidPauseAuthOracleV2
/// @notice  OracleV2 executor of `FluidPauseAuth`: sets or lifts each token's operate pause, never the liquidate one.
///          Must be a guardian on `ORACLE_V2`.
contract FluidPauseAuthOracleV2 is Error, BasicValidations, IFluidPauseAuthOracleV2 {
    event LogSetPauseAuthContract(address indexed pauseAuthContract);

    /// @notice the `FluidUsdOracle` proxy.
    IFluidOracleV2Pause public immutable ORACLE_V2;

    /// @notice identity registry gating `setPauseAuthContract`.
    IFluidAuthGate public immutable AUTH_GATE;

    /// @notice FluidPauseAuth main contract. Set once by the MID tier, then permanently locked.
    address public pauseAuthContract;

    modifier onlyPauseAuthContract() {
        if (msg.sender != pauseAuthContract) {
            revert FluidConfigError(ErrorTypes.PauseAuthOracleV2__Unauthorized);
        }
        _;
    }

    constructor(
        address liquidity_,
        address oracleV2_,
        address authGate_
    ) validAddress(liquidity_) validAddress(oracleV2_) validAddress(authGate_) {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() != liquidity_) {
            revert FluidConfigError(ErrorTypes.PauseAuthOracleV2__InvalidParams);
        }
        ORACLE_V2 = IFluidOracleV2Pause(oracleV2_);
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    /// @notice Sets the FluidPauseAuth main contract address. Can only be called once (permanently locked after).
    function setPauseAuthContract(address pauseAuth_) external validAddress(pauseAuth_) {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        if (pauseAuthContract != address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthOracleV2__InvalidParams);
        }
        pauseAuthContract = pauseAuth_;
        emit LogSetPauseAuthContract(pauseAuth_);
    }

    /// @inheritdoc IFluidPauseAuthOracleV2
    function pauseOperate(
        address[] calldata tokens_
    ) external override onlyPauseAuthContract returns (bool[] memory acted_) {
        return _setOperatePaused(tokens_, true);
    }

    /// @inheritdoc IFluidPauseAuthOracleV2
    function unpauseOperate(
        address[] calldata tokens_
    ) external override onlyPauseAuthContract returns (bool[] memory acted_) {
        return _setOperatePaused(tokens_, false);
    }

    function _setOperatePaused(address[] calldata tokens_, bool pause_) internal returns (bool[] memory acted_) {
        uint256 length_ = tokens_.length;
        acted_ = new bool[](length_);
        for (uint256 i; i < length_; ++i) {
            (bool operatePaused_, bool liquidatePaused_, , ) = ORACLE_V2.getTokenConfig(tokens_[i]);
            if (operatePaused_ == pause_) {
                continue;
            }
            // the oracle rejects any guardian change to the liquidate bit, so it goes back as read
            ORACLE_V2.setPausedState(tokens_[i], pause_, liquidatePaused_);
            acted_[i] = true;
        }
    }
}
