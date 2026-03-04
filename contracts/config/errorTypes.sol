// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

library ErrorTypes {
    /***********************************|
    |    ExpandPercentConfigHandler     | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant ExpandPercentConfigHandler__AddressZero = 100001;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant ExpandPercentConfigHandler__Unauthorized = 100002;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant ExpandPercentConfigHandler__InvalidParams = 100003;

    /// @notice thrown when no update is currently needed
    uint256 internal constant ExpandPercentConfigHandler__NoUpdate = 100004;

    /// @notice thrown when slot is not used, e.g. when borrow token is 0 there is no borrow data
    uint256 internal constant ExpandPercentConfigHandler__SlotDoesNotExist = 100005;

    /***********************************|
    |      EthenaRateConfigHandler      | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant EthenaRateConfigHandler__AddressZero = 100011;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant EthenaRateConfigHandler__Unauthorized = 100012;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant EthenaRateConfigHandler__InvalidParams = 100013;

    /// @notice thrown when no update is currently needed
    uint256 internal constant EthenaRateConfigHandler__NoUpdate = 100014;

    /***********************************|
    |       MaxBorrowConfigHandler      | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant MaxBorrowConfigHandler__AddressZero = 100021;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant MaxBorrowConfigHandler__Unauthorized = 100022;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant MaxBorrowConfigHandler__InvalidParams = 100023;

    /// @notice thrown when no update is currently needed
    uint256 internal constant MaxBorrowConfigHandler__NoUpdate = 100024;

    /***********************************|
    |       BufferRateConfigHandler     | 
    |__________________________________*/

    /// @notice thrown when an input address is zero
    uint256 internal constant BufferRateConfigHandler__AddressZero = 100031;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant BufferRateConfigHandler__Unauthorized = 100032;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant BufferRateConfigHandler__InvalidParams = 100033;

    /// @notice thrown when no update is currently needed
    uint256 internal constant BufferRateConfigHandler__NoUpdate = 100034;

    /// @notice thrown when rate data version is not supported
    uint256 internal constant BufferRateConfigHandler__RateVersionUnsupported = 100035;

    /***********************************|
    |          FluidRatesAuth           | 
    |__________________________________*/

    /// @notice thrown when no update is currently needed
    uint256 internal constant RatesAuth__NoUpdate = 100041;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant RatesAuth__Unauthorized = 100042;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant RatesAuth__InvalidParams = 100043;

    /// @notice thrown when cooldown is not yet expired
    uint256 internal constant RatesAuth__CooldownLeft = 100044;

    /// @notice thrown when version is invalid
    uint256 internal constant RatesAuth__InvalidVersion = 100045;

    /***********************************|
    |       LiquidityTokenAuth          | 
    |__________________________________*/

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant LiquidityTokenAuth__Unauthorized = 100051;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant LiquidityTokenAuth_AlreadyInitialized = 100052;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant LiquidityTokenAuth__InvalidParams = 100053;

    /***********************************|
    |       CollectRevenueAuth          | 
    |__________________________________*/

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant CollectRevenueAuth__Unauthorized = 100061;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant CollectRevenueAuth__InvalidParams = 100062;

    /***********************************|
    |       FluidWithdrawLimitAuth      | 
    |__________________________________*/

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant WithdrawLimitAuth__NoUserSupply = 100071;

    /// @notice thrown when an unauthorized `msg.sender` calls a protected method
    uint256 internal constant WithdrawLimitAuth__Unauthorized = 100072;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant WithdrawLimitAuth__InvalidParams = 100073;

    /// @notice thrown when no more withdrawal limit can be set for the day
    uint256 internal constant WithdrawLimitAuth__DailyLimitReached = 100074;

    /// @notice thrown when no more withdrawal limit can be set for the hour
    uint256 internal constant WithdrawLimitAuth__HourlyLimitReached = 100075;

    /// @notice thrown when the withdrawal limit and userSupply difference exceeds 5%
    uint256 internal constant WithdrawLimitAuth__ExcessPercentageDifference = 100076;

    /***********************************|
    |       DexFeeHandler               | 
    |__________________________________*/

    /// @notice thrown when fee update is not required
    uint256 internal constant DexFeeHandler__FeeUpdateNotRequired = 100081;

    /// @notice thrown when invalid params are passed into a method
    uint256 internal constant DexFeeHandler__InvalidParams = 100082;

    /// @notice thrown when an unauthorized `msg.sender` calls
    uint256 internal constant DexFeeHandler__Unauthorized = 100083;

    /***********************************|
    |           RangeAuthDex            | 
    |__________________________________*/

    uint256 internal constant RangeAuthDex__InvalidParams = 100091;
    uint256 internal constant RangeAuthDex__CooldownLeft = 100092;
    uint256 internal constant RangeAuthDex__Unauthorized = 100093;
    uint256 internal constant RangeAuthDex__ExceedAllowedPercentageChange = 100094;
    uint256 internal constant RangeAuthDex__InvalidShiftTime = 100095;

    /***********************************|
    |           FluidLimitsAuth         | 
    |__________________________________*/

    uint256 internal constant LimitsAuth__InvalidParams = 100101;
    uint256 internal constant LimitsAuth__Unauthorized = 100102;
    uint256 internal constant LimitsAuth__UserNotDefinedYet = 100103;
    uint256 internal constant LimitsAuth__ExceedAllowedPercentageChange = 100104;
    uint256 internal constant LimitsAuth__CoolDownPending = 100105;

    /***********************************|
    |          DexFeeAuth               | 
    |__________________________________*/

    /// @notice thrown when an unauthorized `msg.sender` calls
    uint256 internal constant DexFeeAuth__Unauthorized = 100111;

    /***********************************|
    |       VaultFeeRewardsAuth         | 
    |__________________________________*/

    /// @notice thrown when an unauthorized `msg.sender` calls
    uint256 internal constant VaultFeeRewardsAuth__Unauthorized = 100121;
    /// @notice thrown when magnifier or rate is being updated for a non matching vault type
    uint256 internal constant VaultFeeRewardsAuth__InvalidVaultType = 100122;
}
