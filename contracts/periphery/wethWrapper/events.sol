// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

contract Events {
    /// @notice Emitted when user deposits collateral in WETH
    /// @param user   The user performing the deposit
    /// @param nftId  The vault NFT ID
    /// @param amount Amount of WETH deposited
    event LogDeposit(address indexed user, uint256 indexed nftId, uint256 amount);

    /// @notice Emitted when user withdraws collateral (receives WETH)
    /// @param user   The user performing the withdrawal
    /// @param nftId  The vault NFT ID
    /// @param amount Amount of WETH withdrawn
    event LogWithdraw(address indexed user, uint256 indexed nftId, uint256 amount);

    /// @notice Emitted when user borrows
    /// @param user   The user performing the borrow
    /// @param nftId  The vault NFT ID
    /// @param amount Amount borrowed
    event LogBorrow(address indexed user, uint256 indexed nftId, uint256 amount);

    /// @notice Emitted when user pays back debt
    /// @param user   The user performing the payback
    /// @param nftId  The vault NFT ID
    /// @param amount Amount repaid
    event LogPayback(address indexed user, uint256 indexed nftId, uint256 amount);
}
