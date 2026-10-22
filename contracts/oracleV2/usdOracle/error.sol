// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

contract Error {
    error FluidUsdOracleError(uint256 errorId_);

    function _revert(uint256 errorId_) internal pure {
        revert FluidUsdOracleError(errorId_);
    }
}
