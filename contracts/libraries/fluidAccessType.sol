// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @notice Access-type constants for protocol `ACCESS_TYPE()` views.
///         Resolvers default to `PUBLIC` when the selector is missing (prod / unknown contracts).
///         ERC20 `name` / `symbol` suffixes for public fTokens use `PUBLIC_METADATA_SUFFIX` instead of the
///         factory deployment name (which is typically `"Permissioned"` on this stack).
library FluidAccessType {
    /// @dev ungated protocol (anyone can transact), e.g. `fTokenPublic`
    uint8 internal constant PUBLIC = 0;
    /// @dev permission-gated protocol, e.g. `fTokenPermissioned`, `FluidVaultT1Permissioned`
    uint8 internal constant PERMISSIONED = 1;

    /// @dev appended to public fToken `name()` / `symbol()` (e.g. `Fluid USD Coin Public` / `fUSDCPublic`)
    string internal constant PUBLIC_METADATA_SUFFIX = "Public";
}
