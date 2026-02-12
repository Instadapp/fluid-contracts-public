// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidCenterPrice } from "./interfaces/iFluidCenterPrice.sol";
import { ErrorTypes } from "./errorTypes.sol";
import { Error as OracleError } from "./error.sol";

/// @title   FluidCenterPrice
/// @notice  Base contract that any Fluid Center Price must implement
abstract contract FluidCenterPrice is IFluidCenterPrice, OracleError {
    /// @dev short helper string to easily identify the center price oracle. E.g. token symbols
    //
    // using a bytes32 because string can not be immutable.
    bytes32 private immutable _infoName;

    uint8 internal constant _TARGET_DECIMALS = 27; // target decimals for center price and contract rates is always 27

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

    /// @inheritdoc IFluidCenterPrice
    function targetDecimals() public pure virtual returns (uint8) {
        return _TARGET_DECIMALS;
    }

    /// @inheritdoc IFluidCenterPrice
    function infoName() public view virtual returns (string memory) {
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

    /// @inheritdoc IFluidCenterPrice
    function centerPrice() external virtual returns (uint256 price_);
}
