// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

/// @notice inherit to use the `SECURITY_LEVEL_*` constants by name.
/// @dev spaced values so future levels can slot in without renumbering consumers; checks use `>=`.
abstract contract FluidAuthLevels {
    uint256 internal constant SECURITY_LEVEL_LOW = 1;
    uint256 internal constant SECURITY_LEVEL_MID = 5;
    uint256 internal constant SECURITY_LEVEL_HIGH = 10;
    uint256 internal constant SECURITY_LEVEL_CRITICAL = 15;
    uint256 internal constant SECURITY_LEVEL_MAX = 20;
}

interface IFluidAuthGate {
    function governance() external view returns (address);

    function isGovernance(address addr_) external view returns (bool);

    function authLevel(address addr_) external view returns (uint256);

    /// @notice reverts `Access__Unauthorized` unless `authLevel(addr_)` is non-zero and
    ///         >= `minSecurityLevel_`. `SECURITY_LEVEL_MAX` is governance-only.
    function requireAuthLevel(address addr_, uint256 minSecurityLevel_) external view;

    function requireAuthLevelLow(address addr_) external view;

    function requireAuthLevelMid(address addr_) external view;

    function requireAuthLevelHigh(address addr_) external view;

    function requireAuthLevelCritical(address addr_) external view;

    function requireAuthLevelMax(address addr_) external view;
}

/// @notice the gate inherits `LIQUIDITY` as a public immutable, so its getter can't sit in `IFluidAuthGate`
interface IFluidAuthGateLiquidity {
    function LIQUIDITY() external view returns (address);
}
