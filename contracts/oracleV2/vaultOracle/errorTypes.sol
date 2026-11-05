// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

library ErrorTypes {
    /***********************************|
    |           Vault Oracle            |
    |__________________________________*/

    uint256 internal constant VaultOracle__PriceZero = 310101;
    uint256 internal constant VaultOracle__AddressZero = 310102;

    /***********************************|
    |       Vault Oracle Factory        |
    |__________________________________*/

    uint256 internal constant VaultOracleFactory__AlreadyRegistered = 310110;
    uint256 internal constant VaultOracleFactory__UnsupportedType = 310111;
    uint256 internal constant VaultOracleFactory__AddressZero = 310112;
    uint256 internal constant VaultOracleFactory__InvalidVault = 310113;
    /// @dev `vault.constantsView().deployer` must match the factory's `DEPLOYER_FACTORY` address.
    uint256 internal constant VaultOracleFactory__DeployerMismatch = 310114;
    /// @dev `IFluidVault.VAULT_ID()` returned zero.
    uint256 internal constant VaultOracleFactory__VaultIdZero = 310115;
    /// @dev No oracle registered for this vault ID, or getter invariants failed.
    uint256 internal constant VaultOracleFactory__NotRegistered = 310116;
    /// @dev Deployed oracle address does not match `DEPLOYER_FACTORY.getContractAddress(nonce)`.
    uint256 internal constant VaultOracleFactory__DeploymentInvariantFailed = 310117;
    /// @dev Caller is not governance, team multisig, or an allow-listed vault-oracle deployer (also UUPS upgrade).
    uint256 internal constant VaultOracleFactory__Unauthorized = 310118;
    /// @dev Requested eMode has no `configsMap` entry on any relevant token (see `IUSDOracle.isEmodeValid`).
    uint256 internal constant VaultOracleFactory__InvalidEMode = 310119;
    /// @dev DEX liquidity band (`upperRange`/`lowerRange`) too wide — pool is not a peg pool, unsafe for DEX-share valuation.
    uint256 internal constant VaultOracleFactory__DexIsNotPeg = 310120;
    /// @dev Could not read DEX center/range prices via `getPricesAndExchangePrices()` at registration.
    uint256 internal constant VaultOracleFactory__DexPriceReadFailed = 310121;
    /// @dev Operate peg buffer above `MAX_PEG_BUFFER_PPM`, or liquidate buffer above the operate buffer.
    uint256 internal constant VaultOracleFactory__InvalidPegBuffer = 310122;
}
