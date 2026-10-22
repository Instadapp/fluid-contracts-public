// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |               StETH               | 
    |__________________________________*/

    /// @notice thrown when maxLTV precent amount is set to 0
    uint256 internal constant StETH__MaxLTVZero = 40001;

    /// @notice thrown when the borrow ETH amount to StETH collateral ratio is bigger than the configured `maxLTV`
    uint256 internal constant StETH__MaxLTV = 40002;

    /// @notice thrown when an ERC721 other than a Lido Withdrawal NFT is transferred to this contract
    uint256 internal constant StETH__InvalidERC721Transfer = 40003;

    /// @notice thrown when an input amount (ethBorrowAmount or stETHAmount) is zero
    uint256 internal constant StETH__InputAmountZero = 40004;

    /// @notice thrown when `liquidityCallback` is called, as this protocol only uses native token as borrow asset
    uint256 internal constant StETH__UnexpectedLiquidityCallback = 40005;

    /// @notice thrown when there is no claim queued for a claim owner
    uint256 internal constant StETH__NoClaimQueued = 40006;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant StETH__Unauthorized = 40007;

    /// @notice thrown when the borrowAmountRaw is rounded to zero because of the exchange price
    uint256 internal constant StETH__BorrowAmountRawRoundingZero = 40008;

    /// @notice thrown when an input address is zero
    uint256 internal constant StETH__AddressZero = 40009;

    /// @notice thrown when a reentrancy happens
    uint256 internal constant StETH__Reentrancy = 40010;

    /// @notice thrown when maxLTV precent amount is set to >= 100%
    uint256 internal constant StETH__MaxLTVAboveCap = 40011;

    /// @notice thrown when renounceOwnership is called
    uint256 internal constant StETH__RenounceOwnershipUnsupported = 40012;
}
