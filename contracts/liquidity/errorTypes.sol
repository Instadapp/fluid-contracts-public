// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

library ErrorTypes {
    /***********************************|
    |         Admin Module              | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant AdminModule__AddressZero = 10001;

    /// @notice thrown when msg.sender is not governance
    uint256 internal constant AdminModule__OnlyGovernance = 10002;

    /// @notice thrown when msg.sender is not auth
    uint256 internal constant AdminModule__OnlyAuths = 10003;

    /// @notice thrown when msg.sender is not guardian
    uint256 internal constant AdminModule__OnlyGuardians = 10004;

    /// @notice thrown when base withdrawal limit, base debt limit or max withdrawal limit is sent as 0
    uint256 internal constant AdminModule__LimitZero = 10005;

    /// @notice thrown whenever an invalid input param is given
    uint256 internal constant AdminModule__InvalidParams = 10006;

    /// @notice thrown if user class 1 is paused (can not be paused)
    uint256 internal constant AdminModule__UserNotPausable = 10007;

    /// @notice thrown if user is tried to be unpaused but is not paused in the first place
    uint256 internal constant AdminModule__UserNotPaused = 10008;

    /// @notice thrown if user is not defined yet: Governance didn't yet set any config for this user on a particular token
    uint256 internal constant AdminModule__UserNotDefined = 10009;

    /// @notice thrown if a token is configured in an invalid order:  1. Set rate config for token 2. Set token config 3. allow any user.
    uint256 internal constant AdminModule__InvalidConfigOrder = 10010;

    /// @notice thrown if revenue is collected when revenue collector address is not set
    uint256 internal constant AdminModule__RevenueCollectorNotSet = 10011;

    /// @notice all ValueOverflow errors below are thrown if a certain input param overflows the allowed storage size
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_ZERO = 10012;
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_KINK = 10013;
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_MAX = 10014;
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_KINK1 = 10015;
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_KINK2 = 10016;
    uint256 internal constant AdminModule__ValueOverflow__RATE_AT_UTIL_MAX_V2 = 10017;
    uint256 internal constant AdminModule__ValueOverflow__FEE = 10018;
    uint256 internal constant AdminModule__ValueOverflow__THRESHOLD = 10019;
    uint256 internal constant AdminModule__ValueOverflow__EXPAND_PERCENT = 10020;
    uint256 internal constant AdminModule__ValueOverflow__EXPAND_DURATION = 10021;
    uint256 internal constant AdminModule__ValueOverflow__EXPAND_PERCENT_BORROW = 10022;
    uint256 internal constant AdminModule__ValueOverflow__EXPAND_DURATION_BORROW = 10023;
    uint256 internal constant AdminModule__ValueOverflow__EXCHANGE_PRICES = 10024;
    uint256 internal constant AdminModule__ValueOverflow__UTILIZATION = 10025;

    /// @notice thrown when an address is not a contract
    uint256 internal constant AdminModule__AddressNotAContract = 10026;

    uint256 internal constant AdminModule__ValueOverflow__MAX_UTILIZATION = 10027;

    /// @notice thrown if a token that is being listed has not between 6 and 18 decimals
    uint256 internal constant AdminModule__TokenInvalidDecimalsRange = 10028;

    /***********************************|
    |          User Module              | 
    |__________________________________*/

    /// @notice thrown when user operations are paused for an interacted token
    uint256 internal constant UserModule__UserNotDefined = 11001;

    /// @notice thrown when user operations are paused for an interacted token
    uint256 internal constant UserModule__UserPaused = 11002;

    /// @notice thrown when user's try to withdraw below withdrawal limit
    uint256 internal constant UserModule__WithdrawalLimitReached = 11003;

    /// @notice thrown when user's try to borrow above borrow limit
    uint256 internal constant UserModule__BorrowLimitReached = 11004;

    /// @notice thrown when user sent supply/withdraw and borrow/payback both as 0
    uint256 internal constant UserModule__OperateAmountsZero = 11005;

    /// @notice thrown when user sent supply/withdraw or borrow/payback both as bigger than 2**128
    uint256 internal constant UserModule__OperateAmountOutOfBounds = 11006;

    /// @notice thrown when the operate amount for supply / withdraw / borrow / payback is below the minimum amount
    /// that would cause a storage difference after BigMath & rounding imprecision. Extremely unlikely to ever happen
    /// for all normal use-cases.
    uint256 internal constant UserModule__OperateAmountInsufficient = 11007;

    /// @notice thrown when withdraw or borrow is executed but withdrawTo or borrowTo is the zero address
    uint256 internal constant UserModule__ReceiverNotDefined = 11008;

    /// @notice thrown when user did send excess or insufficient amount (beyond rounding issues)
    uint256 internal constant UserModule__TransferAmountOutOfBounds = 11009;

    /// @notice thrown when user sent msg.value along for an operation not for the native token
    uint256 internal constant UserModule__MsgValueForNonNativeToken = 11010;

    /// @notice thrown when a borrow operation is done when utilization is above 100%
    uint256 internal constant UserModule__MaxUtilizationReached = 11011;

    /// @notice all ValueOverflow errors below are thrown if a certain input param or calc result overflows the allowed storage size
    uint256 internal constant UserModule__ValueOverflow__EXCHANGE_PRICES = 11012;
    uint256 internal constant UserModule__ValueOverflow__UTILIZATION = 11013;
    uint256 internal constant UserModule__ValueOverflow__TOTAL_SUPPLY = 11014;
    uint256 internal constant UserModule__ValueOverflow__TOTAL_BORROW = 11015;

    /// @notice thrown when SKIP_TRANSFERS is set but the input params are invalid for skipping transfers
    uint256 internal constant UserModule__SkipTransfersInvalid = 11016;

    /***********************************|
    |         LiquidityHelpers          | 
    |__________________________________*/

    /// @notice thrown when a reentrancy happens
    uint256 internal constant LiquidityHelpers__Reentrancy = 12001;
}
