// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title FluidUsdOracleBootstrapAuth
/// @notice Shared bootstrap-admin state + auth helpers for temporary setup implementations.
/// @dev Does **not** inherit `FluidUsdOracle` / `FluidUsdOracleL2` — leaves inherit the final oracle type and
///      override `_getGovernanceAddr` / `_authorizeUpgrade` using these helpers (avoids diamond + price-wrapper conflicts).
///      **Do not leave bootstrap implementations live in production.**
///      Includes `multicall` (self-delegatecall) so `BOOTSTRAP_ADMIN` can wire token + per-key configs in one tx
///      (transient `registerTransientOracleKey` sessions). Removed when the proxy is upgraded to Final.
abstract contract FluidUsdOracleBootstrapAuth is Error {
    /// @notice Setup EOA (or contract) treated as governance while this impl is active behind the proxy.
    address public immutable BOOTSTRAP_ADMIN;

    /// @param bootstrapAdmin_ Address allowed to configure and to authorize UUPS upgrades while bootstrapping.
    constructor(address bootstrapAdmin_) {
        if (bootstrapAdmin_ == address(0)) {
            _revert(ErrorTypes.UsdOracle__AddressZero);
        }
        BOOTSTRAP_ADMIN = bootstrapAdmin_;
    }

    /// @notice Bootstrap-only batch: self-delegatecall so `msg.sender` stays `BOOTSTRAP_ADMIN`.
    /// @dev Use for same-tx wiring of token-level + per-key admin methods (transient key sessions).
    ///      Not present on Final `FluidUsdOracle` / `FluidUsdOracleL2`. Callable only by `BOOTSTRAP_ADMIN`.
    /// @param data_ Encoded calls to this contract (e.g. `setTokenType`, `registerTransientOracleKey`, `setPriceMode`).
    /// @return results_ Return data of each delegatecall, in order.
    function multicall(bytes[] calldata data_) external returns (bytes[] memory results_) {
        if (msg.sender != BOOTSTRAP_ADMIN) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }
        uint256 length_ = data_.length;
        results_ = new bytes[](length_);
        for (uint256 i_ = 0; i_ < length_; ) {
            results_[i_] = Address.functionDelegateCall(address(this), data_[i_]);
            unchecked {
                ++i_;
            }
        }
    }

    /// @dev If `msg.sender` is the bootstrap admin, treat that address as governance; otherwise return `realGov_`.
    function _governanceAddrWithBootstrap(address realGov_) internal view returns (address) {
        if (msg.sender == BOOTSTRAP_ADMIN) {
            return BOOTSTRAP_ADMIN;
        }
        return realGov_;
    }

    /// @dev Allow bootstrap admin, Team MS, or real Liquidity governance to authorize `upgradeTo`.
    function _authorizeUpgradeWithBootstrap(address teamMultisig_, address realGov_) internal view {
        if (msg.sender != BOOTSTRAP_ADMIN && msg.sender != teamMultisig_ && msg.sender != realGov_) {
            _revert(ErrorTypes.UsdOracle__Unauthorized);
        }
    }
}
