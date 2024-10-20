// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "./interfaces/iFluidOracle.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error as OracleError } from "./error.sol";

/// @title   FluidOracle
/// @notice  Base contract that any Fluid Oracle must implement
abstract contract FluidOracle is IFluidOracle, OracleError {
    /// @dev short helper string to easily identify the oracle. E.g. token symbols
    //
    // using a bytes32 because string can not be immutable.
    bytes32 private immutable _infoName;

    constructor(string memory infoName_) {
        if (bytes(infoName_).length > 32 || bytes(infoName_).length == 0) {
            revert FluidOracleError(ErrorTypes.FluidOracle__InvalidInfoName);
        }

        // convert string to bytes32
        bytes32 infoNameBytes32_;
        assembly {
            infoNameBytes32_ := mload(add(infoName_, 32))
        }
        _infoName = infoNameBytes32_;
    }

    /// @inheritdoc IFluidOracle
    function infoName() external view returns (string memory) {
        // convert bytes32 to string
        uint256 length_;
        while (length_ < 32 && _infoName[length_] != 0) {
            length_++;
        }
        bytes memory infoNameBytes_ = new bytes(length_);
        for (uint256 i; i < length_; i++) {
            infoNameBytes_[i] = _infoName[i];
        }
        return string(infoNameBytes_);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() external view virtual returns (uint256 exchangeRate_);

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() external view virtual returns (uint256 exchangeRate_);

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() external view virtual returns (uint256 exchangeRate_);
}
