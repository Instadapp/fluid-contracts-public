// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |             DexT1                 | 
    |__________________________________*/

    /// @notice thrown at reentrancy
    uint256 internal constant DexT1__AlreadyEntered = 51001;

    uint256 internal constant DexT1__NotAnAuth = 51002;

    uint256 internal constant DexT1__SmartColNotEnabled = 51003;

    uint256 internal constant DexT1__SmartDebtNotEnabled = 51004;

    uint256 internal constant DexT1__PoolNotInitialized = 51005;

    uint256 internal constant DexT1__TokenReservesTooLow = 51006;

    uint256 internal constant DexT1__EthAndAmountInMisMatch = 51007;

    uint256 internal constant DexT1__EthSentForNonNativeSwap = 51008;

    uint256 internal constant DexT1__NoSwapRoute = 51009;

    uint256 internal constant DexT1__NotEnoughAmountOut = 51010;

    uint256 internal constant DexT1__LiquidityLayerTokenUtilizationCapReached = 51011;

    uint256 internal constant DexT1__HookReturnedFalse = 51012;

    // Either user's config are not set or user is paused
    uint256 internal constant DexT1__UserSupplyInNotOn = 51013;

    // Either user's config are not set or user is paused
    uint256 internal constant DexT1__UserDebtInNotOn = 51014;

    // Thrown when contract asks for more token0 or token1 than what user's wants to give on deposit
    uint256 internal constant DexT1__AboveDepositMax = 51015;

    uint256 internal constant DexT1__MsgValueLowOnDepositOrPayback = 51016;

    uint256 internal constant DexT1__WithdrawLimitReached = 51017;

    // Thrown when contract gives less token0 or token1 than what user's wants on withdraw
    uint256 internal constant DexT1__BelowWithdrawMin = 51018;

    uint256 internal constant DexT1__DebtLimitReached = 51019;

    // Thrown when contract gives less token0 or token1 than what user's wants on borrow
    uint256 internal constant DexT1__BelowBorrowMin = 51020;

    // Thrown when contract asks for more token0 or token1 than what user's wants on payback
    uint256 internal constant DexT1__AbovePaybackMax = 51021;

    uint256 internal constant DexT1__InvalidDepositAmts = 51022;

    uint256 internal constant DexT1__DepositAmtsZero = 51023;

    uint256 internal constant DexT1__SharesMintedLess = 51024;

    uint256 internal constant DexT1__WithdrawalNotEnough = 51025;

    uint256 internal constant DexT1__InvalidWithdrawAmts = 51026;

    uint256 internal constant DexT1__WithdrawAmtsZero = 51027;

    uint256 internal constant DexT1__WithdrawExcessSharesBurn = 51028;

    uint256 internal constant DexT1__InvalidBorrowAmts = 51029;

    uint256 internal constant DexT1__BorrowAmtsZero = 51030;

    uint256 internal constant DexT1__BorrowExcessSharesMinted = 51031;

    uint256 internal constant DexT1__PaybackAmtTooHigh = 51032;

    uint256 internal constant DexT1__InvalidPaybackAmts = 51033;

    uint256 internal constant DexT1__PaybackAmtsZero = 51034;

    uint256 internal constant DexT1__PaybackSharedBurnedLess = 51035;

    uint256 internal constant DexT1__NothingToArbitrage = 51036;

    uint256 internal constant DexT1__MsgSenderNotLiquidity = 51037;

    // On liquidity callback reentrancy bit should be on
    uint256 internal constant DexT1__ReentrancyBitShouldBeOn = 51038;

    // Thrown is reentrancy is already on and someone tries to fetch oracle price. Should not be possible to this
    uint256 internal constant DexT1__OraclePriceFetchAlreadyEntered = 51039;

    // Thrown when swap changes the current price by more than 5%
    uint256 internal constant DexT1__OracleUpdateHugeSwapDiff = 51040;

    uint256 internal constant DexT1__Token0ShouldBeSmallerThanToken1 = 51041;

    uint256 internal constant DexT1__OracleMappingOverflow = 51042;

    /// @notice thrown if governance has paused the swapping & arbitrage so only perfect functions are usable
    uint256 internal constant DexT1__SwapAndArbitragePaused = 51043;

    uint256 internal constant DexT1__ExceedsAmountInMax = 51044;

    /// @notice thrown if amount in is too high or too low
    uint256 internal constant DexT1__SwapInLimitingAmounts = 51045;

    /// @notice thrown if amount out is too high or too low
    uint256 internal constant DexT1__SwapOutLimitingAmounts = 51046;

    uint256 internal constant DexT1__MintAmtOverflow = 51047;

    uint256 internal constant DexT1__BurnAmtOverflow = 51048;

    uint256 internal constant DexT1__LimitingAmountsSwapAndNonPerfectActions = 51049;

    uint256 internal constant DexT1__InsufficientOracleData = 51050;

    uint256 internal constant DexT1__SharesAmountInsufficient = 51051;

    uint256 internal constant DexT1__CenterPriceOutOfRange = 51052;

    uint256 internal constant DexT1__DebtReservesTooLow = 51053;

    uint256 internal constant DexT1__SwapAndDepositTooLowOrTooHigh = 51054;

    uint256 internal constant DexT1__WithdrawAndSwapTooLowOrTooHigh = 51055;

    uint256 internal constant DexT1__BorrowAndSwapTooLowOrTooHigh = 51056;

    uint256 internal constant DexT1__SwapAndPaybackTooLowOrTooHigh = 51057;

    uint256 internal constant DexT1__InvalidImplementation = 51058;

    uint256 internal constant DexT1__OnlyDelegateCallAllowed = 51059;

    uint256 internal constant DexT1__IncorrectDataLength = 51060;

    uint256 internal constant DexT1__AmountToSendLessThanAmount = 51061;

    uint256 internal constant DexT1__InvalidCollateralReserves = 51062;

    uint256 internal constant DexT1__InvalidDebtReserves = 51063;

    uint256 internal constant DexT1__SupplySharesOverflow = 51064;

    uint256 internal constant DexT1__BorrowSharesOverflow = 51065;

    uint256 internal constant DexT1__OracleNotActive = 51066;

    /***********************************|
    |            DEX Admin              | 
    |__________________________________*/

    /// @notice thrown when pool is not initialized
    uint256 internal constant DexT1Admin__PoolNotInitialized = 52001;

    uint256 internal constant DexT1Admin__SmartColIsAlreadyOn = 52002;

    uint256 internal constant DexT1Admin__SmartDebtIsAlreadyOn = 52003;

    /// @notice thrown when any of the configs value overflow the maximum limit
    uint256 internal constant DexT1Admin__ConfigOverflow = 52004;

    uint256 internal constant DexT1Admin__AddressNotAContract = 52005;

    uint256 internal constant DexT1Admin__InvalidParams = 52006;

    uint256 internal constant DexT1Admin__UserNotDefined = 52007;

    uint256 internal constant DexT1Admin__OnlyDelegateCallAllowed = 52008;

    uint256 internal constant DexT1Admin__UnexpectedPoolState = 52009;

    /// @notice thrown when trying to pause or unpause but user is already in the target pause state
    uint256 internal constant DexT1Admin__InvalidPauseToggle = 52009;

    /***********************************|
    |            DEX Factory            | 
    |__________________________________*/

    uint256 internal constant DexFactory__InvalidOperation = 53001;
    uint256 internal constant DexFactory__Unauthorized = 53002;
    uint256 internal constant DexFactory__SameTokenNotAllowed = 53003;
    uint256 internal constant DexFactory__TokenConfigNotProper = 53004;
    uint256 internal constant DexFactory__InvalidParams = 53005;
    uint256 internal constant DexFactory__OnlyDelegateCallAllowed = 53006;
    uint256 internal constant DexFactory__InvalidDexAddress = 53007;

    /***********************************|
    |            Smart Lending          | 
    |__________________________________*/

    uint256 internal constant SmartLending__ZeroAddress = 54001;
    uint256 internal constant SmartLending__Unauthorized = 54002;
    uint256 internal constant SmartLending__InvalidMsgValue = 54003;
    uint256 internal constant SmartLending__OutOfRange = 54004;
    uint256 internal constant SmartLending__InvalidRebalancer = 54005;
    uint256 internal constant SmartLending__Reentrancy = 54006;
    uint256 internal constant SmartLending__InvalidAmounts = 54007;

    /***********************************|
    |        Smart Lending Factory       | 
    |__________________________________*/

    uint256 internal constant SmartLendingFactory__ZeroAddress = 55001;
    uint256 internal constant SmartLendingFactory__Unauthorized = 55002;
    uint256 internal constant SmartLendingFactory__AlreadyDeployed = 55003;
    uint256 internal constant SmartLendingFactory__InvalidParams = 55004;
    uint256 internal constant SmartLendingFactory__InvalidOperation = 55005;
}
