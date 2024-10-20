// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |           Vault Factory           | 
    |__________________________________*/

    uint256 internal constant VaultFactory__InvalidOperation = 30001;
    uint256 internal constant VaultFactory__Unauthorized = 30002;
    uint256 internal constant VaultFactory__SameTokenNotAllowed = 30003;
    uint256 internal constant VaultFactory__InvalidParams = 30004;
    uint256 internal constant VaultFactory__InvalidVault = 30005;
    uint256 internal constant VaultFactory__InvalidVaultAddress = 30006;
    uint256 internal constant VaultFactory__OnlyDelegateCallAllowed = 30007;

    /***********************************|
    |            Vault                  | 
    |__________________________________*/

    /// @notice thrown at reentrancy
    uint256 internal constant Vault__AlreadyEntered = 31001;

    /// @notice thrown when user sends deposit & borrow amount as 0
    uint256 internal constant Vault__InvalidOperateAmount = 31002;

    /// @notice thrown when msg.value is not in sync with native token deposit or payback
    uint256 internal constant Vault__InvalidMsgValueOperate = 31003;

    /// @notice thrown when msg.sender is not the owner of the vault
    uint256 internal constant Vault__NotAnOwner = 31004;

    /// @notice thrown when user's position does not exist. Sending the wrong index from the frontend
    uint256 internal constant Vault__TickIsEmpty = 31005;

    /// @notice thrown when the user's position is above CF and the user tries to make it more risky by trying to withdraw or borrow
    uint256 internal constant Vault__PositionAboveCF = 31006;

    /// @notice thrown when the top tick is not initialized. Happens if the vault is totally new or all the user's left
    uint256 internal constant Vault__TopTickDoesNotExist = 31007;

    /// @notice thrown when msg.value in liquidate is not in sync payback
    uint256 internal constant Vault__InvalidMsgValueLiquidate = 31008;

    /// @notice thrown when slippage is more on liquidation than what the liquidator sent
    uint256 internal constant Vault__ExcessSlippageLiquidation = 31009;

    /// @notice thrown when msg.sender is not the rebalancer/reserve contract
    uint256 internal constant Vault__NotRebalancer = 31010;

    /// @notice thrown when NFT of one vault interacts with the NFT of other vault
    uint256 internal constant Vault__NftNotOfThisVault = 31011;

    /// @notice thrown when the token is not initialized on the liquidity contract
    uint256 internal constant Vault__TokenNotInitialized = 31012;

    /// @notice thrown when admin updates fallback if a non-auth calls vault
    uint256 internal constant Vault__NotAnAuth = 31013;

    /// @notice thrown in operate when user tries to witdhraw more collateral than deposited
    uint256 internal constant Vault__ExcessCollateralWithdrawal = 31014;

    /// @notice thrown in operate when user tries to payback more debt than borrowed
    uint256 internal constant Vault__ExcessDebtPayback = 31015;

    /// @notice thrown when user try to withdrawal more than operate's withdrawal limit
    uint256 internal constant Vault__WithdrawMoreThanOperateLimit = 31016;

    /// @notice thrown when caller of liquidityCallback is not Liquidity
    uint256 internal constant Vault__InvalidLiquidityCallbackAddress = 31017;

    /// @notice thrown when reentrancy is not already on
    uint256 internal constant Vault__NotEntered = 31018;

    /// @notice thrown when someone directly calls operate or secondary implementation contract
    uint256 internal constant Vault__OnlyDelegateCallAllowed = 31019;

    /// @notice thrown when the safeTransferFrom for a token amount failed
    uint256 internal constant Vault__TransferFromFailed = 31020;

    /// @notice thrown when exchange price overflows while updating on storage
    uint256 internal constant Vault__ExchangePriceOverFlow = 31021;

    /// @notice thrown when debt to liquidate amt is sent wrong
    uint256 internal constant Vault__InvalidLiquidationAmt = 31022;

    /// @notice thrown when user debt or collateral goes above 2**128 or below -2**128
    uint256 internal constant Vault__UserCollateralDebtExceed = 31023;

    /// @notice thrown if on liquidation branch debt becomes lower than 100
    uint256 internal constant Vault__BranchDebtTooLow = 31024;

    /// @notice thrown when tick's debt is less than 10000
    uint256 internal constant Vault__TickDebtTooLow = 31025;

    /// @notice thrown when the received new liquidity exchange price is of unexpected value (< than the old one)
    uint256 internal constant Vault__LiquidityExchangePriceUnexpected = 31026;

    /// @notice thrown when user's debt is less than 10000
    uint256 internal constant Vault__UserDebtTooLow = 31027;

    /// @notice thrown when on only payback and only deposit the ratio of position increases
    uint256 internal constant Vault__InvalidPaybackOrDeposit = 31028;

    /// @notice thrown when liquidation just happens of a single partial or when there's nothing to liquidate
    uint256 internal constant Vault__InvalidLiquidation = 31029;

    /// @notice thrown when msg.value is sent wrong in rebalance
    uint256 internal constant Vault__InvalidMsgValueInRebalance = 31030;

    /// @notice thrown when nothing rebalanced
    uint256 internal constant Vault__NothingToRebalance = 31031;

    /// @notice thrown on unforseen liquidation scenarios. Might never come in use.
    uint256 internal constant Vault__LiquidationReverts = 31032;

    /// @notice thrown when oracle price is > 1e54
    uint256 internal constant Vault__InvalidOraclePrice = 31033;

    /// @notice thrown when constants are not set properly via contructor
    uint256 internal constant Vault__ImproperConstantsSetup = 31034;

    /// @notice thrown when externally calling fetchLatestPosition function
    uint256 internal constant Vault__FetchLatestPositionFailed = 31035;

    /// @notice thrown when dex callback is not from dex
    uint256 internal constant Vault__InvalidDexCallbackAddress = 31036;

    /// @notice thrown when dex callback is already set
    uint256 internal constant Vault__DexFromAddressAlreadySet = 31037;

    /// @notice thrown when an invalid min / max amounts config is passed to rebalance()
    uint256 internal constant Vault__InvalidMinMaxInRebalance = 31038;

    /***********************************|
    |              ERC721               | 
    |__________________________________*/

    uint256 internal constant ERC721__InvalidParams = 32001;
    uint256 internal constant ERC721__Unauthorized = 32002;
    uint256 internal constant ERC721__InvalidOperation = 32003;
    uint256 internal constant ERC721__UnsafeRecipient = 32004;
    uint256 internal constant ERC721__OutOfBoundsIndex = 32005;

    /***********************************|
    |            Vault Admin            | 
    |__________________________________*/

    /// @notice thrown when admin tries to setup invalid value which are crossing limits
    uint256 internal constant VaultAdmin__ValueAboveLimit = 33001;

    /// @notice when someone directly calls admin implementation contract
    uint256 internal constant VaultAdmin__OnlyDelegateCallAllowed = 33002;

    /// @notice thrown when auth sends NFT ID as 0 while collecting dust debt
    uint256 internal constant VaultAdmin__NftIdShouldBeNonZero = 33003;

    /// @notice thrown when trying to collect dust debt of NFT which is not of this vault
    uint256 internal constant VaultAdmin__NftNotOfThisVault = 33004;

    /// @notice thrown when dust debt of NFT is 0, meaning nothing to collect
    uint256 internal constant VaultAdmin__DustDebtIsZero = 33005;

    /// @notice thrown when final debt after liquidation is not 0, meaning position 100% liquidated
    uint256 internal constant VaultAdmin__FinalDebtShouldBeZero = 33006;

    /// @notice thrown when NFT is not liquidated state
    uint256 internal constant VaultAdmin__NftNotLiquidated = 33007;

    /// @notice thrown when total absorbed dust debt is 0
    uint256 internal constant VaultAdmin__AbsorbedDustDebtIsZero = 33008;

    /// @notice thrown when address is set as 0
    uint256 internal constant VaultAdmin__AddressZeroNotAllowed = 33009;

    /***********************************|
    |            Vault Rewards          | 
    |__________________________________*/

    uint256 internal constant VaultRewards__Unauthorized = 34001;
    uint256 internal constant VaultRewards__AddressZero = 34002;
    uint256 internal constant VaultRewards__InvalidParams = 34003;
    uint256 internal constant VaultRewards__NewMagnifierSameAsOldMagnifier = 34004;
    uint256 internal constant VaultRewards__NotTheInitiator = 34005;
    uint256 internal constant VaultRewards__NotTheGovernance = 34006;
    uint256 internal constant VaultRewards__AlreadyStarted = 34007;
    uint256 internal constant VaultRewards__RewardsNotStartedOrEnded = 34008;
    uint256 internal constant VaultRewards__InvalidStartTime = 34009;
    uint256 internal constant VaultRewards__AlreadyEnded = 34010;

    /***********************************|
    |          Vault DEX Types          | 
    |__________________________________*/

    uint256 internal constant VaultDex__InvalidOperateAmount = 35001;
    uint256 internal constant VaultDex__DebtSharesPaidMoreThanAvailableLiquidation = 35002;

    /***********************************|
    |        Vault Borrow Rewards       | 
    |__________________________________*/

    uint256 internal constant VaultBorrowRewards__Unauthorized = 36001;
    uint256 internal constant VaultBorrowRewards__AddressZero = 36002;
    uint256 internal constant VaultBorrowRewards__InvalidParams = 36003;
    uint256 internal constant VaultBorrowRewards__NewMagnifierSameAsOldMagnifier = 36004;
    uint256 internal constant VaultBorrowRewards__NotTheInitiator = 36005;
    uint256 internal constant VaultBorrowRewards__NotTheGovernance = 36006;
    uint256 internal constant VaultBorrowRewards__AlreadyStarted = 36007;
    uint256 internal constant VaultBorrowRewards__RewardsNotStartedOrEnded = 36008;
    uint256 internal constant VaultBorrowRewards__InvalidStartTime = 36009;
    uint256 internal constant VaultBorrowRewards__AlreadyEnded = 36010;
}
