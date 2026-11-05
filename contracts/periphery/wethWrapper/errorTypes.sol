// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |               WethWrapper         | 
    |__________________________________*/

    /// @notice thrown when amount is zero
    uint256 internal constant WETH__ZeroAmount = 110001;

    /// @notice re-entracy
    uint256 internal constant Weth_ReEntracy = 110002;

    /// @notice zero address check
    uint256 internal constant Weth_ZeroAddress = 110003;

    /// @notice Only vault is allowed
    uint256 internal constant Weth_NotVaultFactory = 110004;

    /// @notice Only user is allowed
    uint256 internal constant Weth_AssetNotSupported = 110005;

    /// @notice Only one nft transfer
    uint256 internal constant Weth_AlreadyMinted = 110006;

    /// @notice msg.sender is not onBehalf
    uint256 internal constant Weth_NotOwner = 110007;

    /// @notice Only one nft transfer
    uint256 internal constant Weth_NotLiquidity = 110008;

    /// @notice address borrow not supported
    uint256 internal constant Weth_BorrowNotSupported = 110009;
}
