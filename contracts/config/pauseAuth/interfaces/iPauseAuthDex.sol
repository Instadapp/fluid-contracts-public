// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title Fluid Pause Auth DEX Interface
/// @notice Interface for the DEX-layer pause auth helper used by `FluidPauseAuth`.
///         DEX user pause is side-level: a whole side toggles the pool's pause bit, borrow without payback freezes
///         the user's borrow limits (restored by the matching unpause), and the other half-side shapes revert
///         `PauseAuthDex__PartialSideNotSupported`.
interface IFluidPauseAuthDex {
    /// @notice Pauses selected vault operations at the DEX layer.
    /// @param vaultId_ Vault ID to pause.
    /// @param pauseSupply_ Whether to pause supply/deposit operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return vault_ Resolved vault address.
    /// @return actedSupply_ Whether supply/deposit pause state changed.
    /// @return actedWithdraw_ Whether withdraw pause state changed.
    /// @return actedBorrow_ Whether borrow state changed (pause bit, or limits freeze for borrow-only).
    /// @return actedPayback_ Whether payback pause state changed.
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_);

    /// @notice Unpauses selected vault operations at the DEX layer.
    /// @param vaultId_ Vault ID to unpause.
    /// @param unpauseSupply_ Whether to unpause supply/deposit operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return vault_ Resolved vault address.
    /// @return actedSupply_ Whether supply/deposit unpause state changed.
    /// @return actedWithdraw_ Whether withdraw unpause state changed.
    /// @return actedBorrow_ Whether borrow state changed (pause bit, or frozen limits restored).
    /// @return actedPayback_ Whether payback unpause state changed.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_);

    /// @notice Pauses swap and arbitrage on a DEX pool.
    /// @param dexId_ DEX ID to pause.
    /// @return dex_ Resolved DEX address.
    /// @return acted_ Whether swap and arbitrage pause state changed.
    function pauseSwapAndArbitrage(uint256 dexId_) external returns (address dex_, bool acted_);

    /// @notice Unpauses swap and arbitrage on a DEX pool.
    /// @param dexId_ DEX ID to unpause.
    /// @return dex_ Resolved DEX address.
    /// @return acted_ Whether swap and arbitrage unpause state changed.
    function unpauseSwapAndArbitrage(uint256 dexId_) external returns (address dex_, bool acted_);

    /// @notice Pauses the smart lending contract on a DEX pool; both flags must be set, else 100143.
    /// @param dexId_ DEX ID whose smart lending contract should be paused.
    /// @param pauseSupply_ Whether to pause smart lending supply/deposit operations.
    /// @param pauseWithdraw_ Whether to pause smart lending withdraw operations.
    /// @return dex_ Resolved DEX address.
    /// @return smartLending_ Resolved smart lending address.
    /// @return actedSupply_ Whether smart lending supply/deposit pause state changed.
    /// @return actedWithdraw_ Whether smart lending withdraw pause state changed.
    function pauseSmartLending(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) external returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_);

    /// @notice Unpauses the smart lending contract on a DEX pool; both flags must be set, else 100143.
    /// @param dexId_ DEX ID whose smart lending contract should be unpaused.
    /// @param unpauseSupply_ Whether to unpause smart lending supply/deposit operations.
    /// @param unpauseWithdraw_ Whether to unpause smart lending withdraw operations.
    /// @return dex_ Resolved DEX address.
    /// @return smartLending_ Resolved smart lending address.
    /// @return actedSupply_ Whether smart lending supply/deposit unpause state changed.
    /// @return actedWithdraw_ Whether smart lending withdraw unpause state changed.
    function unpauseSmartLending(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_);

    /// @notice Pauses a user's selected operations on a DEX pool.
    ///         Reverts `PauseAuthDex__InvalidParams` if a requested side has no row on the pool.
    /// @param dexId_ DEX ID where the user should be paused.
    /// @param user_ User address to pause on the DEX.
    /// @param pauseSupply_ Whether to pause supply/deposit operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return dex_ Resolved DEX address.
    /// @return actedSupply_ Whether supply/deposit pause state changed.
    /// @return actedWithdraw_ Whether withdraw pause state changed.
    /// @return actedBorrow_ Whether borrow state changed (pause bit, or limits freeze for borrow-only).
    /// @return actedPayback_ Whether payback pause state changed.
    function pauseUser(
        uint256 dexId_,
        address user_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_);

    /// @notice Unpauses a user's selected operations on a DEX pool.
    ///         Reverts `PauseAuthDex__InvalidParams` if a requested side has no row on the pool.
    /// @param dexId_ DEX ID where the user should be unpaused.
    /// @param user_ User address to unpause on the DEX.
    /// @param unpauseSupply_ Whether to unpause supply/deposit operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return dex_ Resolved DEX address.
    /// @return actedSupply_ Whether supply/deposit unpause state changed.
    /// @return actedWithdraw_ Whether withdraw unpause state changed.
    /// @return actedBorrow_ Whether borrow state changed (pause bit, or frozen limits restored).
    /// @return actedPayback_ Whether payback unpause state changed.
    function unpauseUser(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_);
}
