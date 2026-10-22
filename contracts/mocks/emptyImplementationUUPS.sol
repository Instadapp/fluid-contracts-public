// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @dev generic empty contract that can be set for UUPS proxies as initial logic contract, to avoid it affecting
///      the deterministic contract address. upgrade is auth-gated via an immutable owner set in constructor, to
///      not affect the storage layout.
contract EmptyImplementationUUPS is UUPSUpgradeable {
    /// @dev used to auth-gate upgrade triggering
    address public immutable OWNER;

    error Unauthorized();

    constructor(address owner_) {
        OWNER = owner_;
    }

    function _authorizeUpgrade(address) internal override {
        if (msg.sender != OWNER) {
            revert Unauthorized();
        }
    }
}
