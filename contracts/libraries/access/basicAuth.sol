// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { LiquidityGovernanceAuth } from "./liquidityGovernanceAuth.sol";

/// @title BasicAuth
/// @notice Extends `LiquidityGovernanceAuth` with a class-based auth allowlist API.
/// @dev Storage stays on the inheriting contract. Override `_authClass` / `_setAuthClass` to
///      read/write that mapping (e.g. `mapping(address => uint256) internal _auths`; `0` = none).
abstract contract BasicAuth is LiquidityGovernanceAuth {
    event LogUpdateAuth(address indexed auth, uint256 authClass);

    /// @notice Whether `auth_` has any non-zero auth class (does not include governance).
    function isAuth(address auth_) public view returns (bool) {
        return _authClass(auth_) != 0;
    }

    /// @notice Auth class for `auth_` (`0` = none).
    function authClass(address auth_) public view returns (uint256) {
        return _authClass(auth_);
    }

    /// @dev Governance or any non-zero auth class.
    modifier onlyAuth() {
        if (!_isGovernance() && _authClass(msg.sender) == 0) {
            revert Access__Unauthorized();
        }
        _;
    }

    /// @dev Governance or auth class `>= class_` (hierarchical).
    modifier onlyAuthClassAbove(uint256 class_) {
        if (!_isGovernance() && _authClass(msg.sender) < class_) {
            revert Access__Unauthorized();
        }
        _;
    }

    /// @dev Governance or exact auth class `class_`.
    modifier onlyAuthClass(uint256 class_) {
        if (!_isGovernance() && _authClass(msg.sender) != class_) {
            revert Access__Unauthorized();
        }
        _;
    }

    /// @notice Set auth class (`0` revokes). Only Liquidity governance.
    function updateAuth(address auth_, uint256 authClass_) external onlyGovernance {
        if (auth_ == address(0)) {
            revert Access__Unauthorized();
        }
        _setAuthClass(auth_, authClass_);
        emit LogUpdateAuth(auth_, authClass_);
    }

    /// @dev Read auth class from the inheriting contract's storage.
    function _authClass(address auth_) internal view virtual returns (uint256);

    /// @dev Write auth class into the inheriting contract's storage.
    function _setAuthClass(address auth_, uint256 authClass_) internal virtual;
}
