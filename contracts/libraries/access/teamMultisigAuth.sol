// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { LiquidityGovernanceAuth } from "./liquidityGovernanceAuth.sol";

/// @title TeamMultisigAuth
/// @notice Shared gate for Fluid team Avocado multisig actions.
/// @dev Extends `LiquidityGovernanceAuth` so inheritors get both `onlyGovernance` and `onlyTeamMultisig`.
///      Unauthorized callers revert with the same `Access__Unauthorized` error.
abstract contract TeamMultisigAuth is LiquidityGovernanceAuth {
    /// @dev Fluid team Avocado multisig (same address used across config / reserve contracts).
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @dev Whether `msg.sender` is the team multisig.
    function _isTeamMultisig() internal view returns (bool) {
        return msg.sender == TEAM_MULTISIG;
    }

    /// @dev Team multisig or Liquidity governance (governance is the higher authority).
    modifier onlyTeamMultisig() {
        if (!_isTeamMultisig() && !_isGovernance()) {
            revert Access__Unauthorized();
        }
        _;
    }
}
