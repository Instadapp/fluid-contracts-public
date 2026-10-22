// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { LiquidityGovernanceAuth } from "./liquidityGovernanceAuth.sol";

/// @title BasicUpgradeable
/// @notice UUPS upgradeable base gated by Liquidity Layer governance.
/// @dev Constructor disables initializers on the implementation. Override `initialize` to set
///      proxy state; `_authorizeUpgrade` is `onlyGovernance`.
abstract contract BasicUpgradeable is LiquidityGovernanceAuth, Initializable, UUPSUpgradeable {
    /// @param liquidity_ Liquidity proxy whose EIP-1967 admin is governance for this contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address liquidity_) LiquidityGovernanceAuth(liquidity_) {
        _disableInitializers();
    }

    /// @notice Empty proxy initializer. Override to set initial state.
    function initialize() public virtual initializer {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal virtual override onlyGovernance {}
}
