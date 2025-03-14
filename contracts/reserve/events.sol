// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Events {
    /// @notice Emitted when an address is added or removed from the auths
    event LogUpdateAuth(address indexed auth, bool isAuth);

    /// @notice Emitted when an address is added or removed from the rebalancers
    event LogUpdateRebalancer(address indexed rebalancer, bool isRebalancer);

    /// @notice Emitted when a token is approved for use by a protocol
    event LogAllow(address indexed protocol, address indexed token, uint256 newAllowance, uint existingAllowance);

    /// @notice Emitted when a token is revoked for use by a protocol
    event LogRevoke(address indexed protocol, address indexed token);

    /// @notice Emitted when fToken is rebalanced
    event LogRebalanceFToken(address indexed protocol, uint amount);

    /// @notice Emitted when vault is rebalanced
    event LogRebalanceVault(address indexed protocol, int colAmount, int debtAmount);

    /// @notice Emitted whenever funds for a certain `token` are transfered to Liquidity
    event LogTransferFunds(address indexed token);

    /// @notice Emitted whenever funds for a certain `token` are withdrawn to receiver
    event LogWithdrawFunds(address indexed token, uint256 indexed amount, address receiver);
}
