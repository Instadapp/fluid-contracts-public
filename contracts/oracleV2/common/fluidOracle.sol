// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IFluidOracle } from "../interfaces/iFluidOracle.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error as OracleError } from "./error.sol";
import { StringBytes32Utils } from "../../libraries/StringBytes32Utils.sol";

/// @title   FluidOracle
/// @notice  Base contract that any Fluid Oracle must implement
abstract contract FluidOracle is IFluidOracle, OracleError {
    /// @dev short helper string to easily identify the oracle. E.g. token symbols
    //
    // using a bytes32 because string can not be immutable.
    bytes32 private immutable _infoName;
    uint8 private immutable _infoNameLength;

    uint8 internal constant _TARGET_DECIMALS = 27; // oracleV2 rates are always 27 decimals

    /// @dev kept as a constructor param for parity with `IFluidOracle`; any token-decimal adjustment is the
    /// consuming vault oracle's job, as it is for capped rates.
    uint8 private immutable _targetDecimals;

    constructor(string memory infoName_, uint8 targetDecimals_) {
        if (targetDecimals_ != _TARGET_DECIMALS) {
            revert OracleV2CommonError(ErrorTypes.FluidOracle__InvalidTargetDecimals);
        }
        _targetDecimals = targetDecimals_;

        (_infoName, _infoNameLength) = StringBytes32Utils.stringMemoryToBytes32(infoName_);
    }

    /// @inheritdoc IFluidOracle
    function targetDecimals() external view returns (uint8) {
        return _targetDecimals;
    }

    /// @inheritdoc IFluidOracle
    function infoName() external view returns (string memory) {
        return StringBytes32Utils.bytes32ToString(_infoName, _infoNameLength);
    }
}
