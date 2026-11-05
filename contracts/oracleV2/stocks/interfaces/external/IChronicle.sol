// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Chronicle router / Scribe read surface. Reads revert for callers without a toll.
interface IChronicle {
    /// @return ok_ false if the value is not readable (e.g. zero)
    /// @return value_ 18 decimals
    /// @return age_ Unix timestamp of the poke
    function tryReadWithAge() external view returns (bool ok_, uint256 value_, uint256 age_);
}
