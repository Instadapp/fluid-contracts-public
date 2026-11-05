// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @title Fluid Pause Auth Liquidity Interface
/// @notice Interface for the Liquidity-layer pause auth helper used by `FluidPauseAuth`.
interface IFluidPauseAuthLiquidity {
    /// @notice Pauses selected vault operations at the Liquidity layer.
    /// @param vaultId_ Vault ID to pause.
    /// @param pauseSupply_ Whether to pause supply/deposit operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return vault_ Resolved vault address.
    /// @return actedSupply_ Whether supply/deposit pause state changed.
    /// @return actedWithdraw_ Whether withdraw pause state changed.
    /// @return actedBorrow_ Whether borrow pause state changed.
    /// @return actedPayback_ Whether payback pause state changed.
    /// @return skippedUserClass_ Liquidity user class skipped by the helper, or zero if none.
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        returns (
            address vault_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        );

    /// @notice Unpauses selected vault operations at the Liquidity layer.
    /// @param vaultId_ Vault ID to unpause.
    /// @param unpauseSupply_ Whether to unpause supply/deposit operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return vault_ Resolved vault address.
    /// @return actedSupply_ Whether supply/deposit unpause state changed.
    /// @return actedWithdraw_ Whether withdraw unpause state changed.
    /// @return actedBorrow_ Whether borrow unpause state changed.
    /// @return actedPayback_ Whether payback unpause state changed.
    /// @return skippedUserClass_ Liquidity user class skipped by the helper, or zero if none.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        returns (
            address vault_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        );

    /// @notice Pauses selected DEX-as-Liquidity-user operations.
    /// @param dexId_ DEX ID to pause at the Liquidity layer.
    /// @param pauseSupply_ Whether to pause supply/deposit operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return dex_ Resolved DEX address.
    /// @return actedSupply_ Whether supply/deposit pause state changed.
    /// @return actedWithdraw_ Whether withdraw pause state changed.
    /// @return actedBorrow_ Whether borrow pause state changed.
    /// @return actedPayback_ Whether payback pause state changed.
    /// @return skippedUserClass_ Liquidity user class skipped by the helper, or zero if none.
    function pauseDex(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        returns (
            address dex_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        );

    /// @notice Unpauses selected DEX-as-Liquidity-user operations.
    /// @param dexId_ DEX ID to unpause at the Liquidity layer.
    /// @param unpauseSupply_ Whether to unpause supply/deposit operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return dex_ Resolved DEX address.
    /// @return actedSupply_ Whether supply/deposit unpause state changed.
    /// @return actedWithdraw_ Whether withdraw unpause state changed.
    /// @return actedBorrow_ Whether borrow unpause state changed.
    /// @return actedPayback_ Whether payback unpause state changed.
    /// @return skippedUserClass_ Liquidity user class skipped by the helper, or zero if none.
    function unpauseDex(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        returns (
            address dex_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        );

    /// @notice Pauses selected token operations at the Liquidity layer.
    /// @param tokens_ Token addresses to pause.
    /// @param pauseSupply_ Whether to pause supply operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return actedSupply_ Per-token flags for supply pause state changes.
    /// @return actedWithdraw_ Per-token flags for withdraw pause state changes.
    /// @return actedBorrow_ Per-token flags for borrow pause state changes.
    /// @return actedPayback_ Per-token flags for payback pause state changes.
    function pauseTokens(
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        );

    /// @notice Unpauses selected token operations at the Liquidity layer.
    /// @param tokens_ Token addresses to unpause.
    /// @param unpauseSupply_ Whether to unpause supply operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return actedSupply_ Per-token flags for supply pause state changes.
    /// @return actedWithdraw_ Per-token flags for withdraw pause state changes.
    /// @return actedBorrow_ Per-token flags for borrow pause state changes.
    /// @return actedPayback_ Per-token flags for payback pause state changes.
    function unpauseTokens(
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        );

    /// @notice Pauses a user's supply-side token operations at the Liquidity layer.
    /// @param user_ Liquidity user address to pause.
    /// @param tokens_ Supply tokens to pause.
    /// @param pauseSupply_ Whether to pause supply operations.
    /// @param pauseWithdraw_ Whether to pause withdraw operations.
    /// @return actedSupply_ Per-token flags for supply pause state changes.
    /// @return actedWithdraw_ Per-token flags for withdraw pause state changes.
    function pauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) external returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_);

    /// @notice Pauses a user's borrow-side token operations at the Liquidity layer.
    /// @param user_ Liquidity user address to pause.
    /// @param tokens_ Borrow tokens to pause.
    /// @param pauseBorrow_ Whether to pause borrow operations.
    /// @param pausePayback_ Whether to pause payback operations.
    /// @return actedBorrow_ Per-token flags for borrow pause state changes.
    /// @return actedPayback_ Per-token flags for payback pause state changes.
    function pauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_);

    /// @notice Unpauses a user's supply-side token operations at the Liquidity layer.
    /// @param user_ Liquidity user address to unpause.
    /// @param tokens_ Supply tokens to unpause.
    /// @param unpauseSupply_ Whether to unpause supply operations.
    /// @param unpauseWithdraw_ Whether to unpause withdraw operations.
    /// @return actedSupply_ Per-token flags for supply pause state changes.
    /// @return actedWithdraw_ Per-token flags for withdraw pause state changes.
    function unpauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_);

    /// @notice Unpauses a user's borrow-side token operations at the Liquidity layer.
    /// @param user_ Liquidity user address to unpause.
    /// @param tokens_ Borrow tokens to unpause.
    /// @param unpauseBorrow_ Whether to unpause borrow operations.
    /// @param unpausePayback_ Whether to unpause payback operations.
    /// @return actedBorrow_ Per-token flags for borrow pause state changes.
    /// @return actedPayback_ Per-token flags for payback pause state changes.
    function unpauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external returns (bool[] memory actedBorrow_, bool[] memory actedPayback_);
}
