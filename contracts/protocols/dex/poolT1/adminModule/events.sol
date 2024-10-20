// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Structs } from "./structs.sol";

abstract contract Events is Structs {
    /// @dev Emitted when smart collateral is turned on
    /// @param token0Amt The amount of token0 used for smart collateral
    event LogTurnOnSmartCol(uint token0Amt);

    /// @dev Emitted when smart debt is turned on
    /// @param token0Amt The amount of token0 used for smart debt
    event LogTurnOnSmartDebt(uint token0Amt);

    /// @dev Emitted when fee and revenue cut are updated
    /// @param fee The new fee value
    /// @param revenueCut The new revenue cut value
    event LogUpdateFeeAndRevenueCut(uint fee, uint revenueCut);

    /// @dev Emitted when range percents are updated
    /// @param upperPercent The new upper percent value
    /// @param lowerPercent The new lower percent value
    /// @param shiftTime The new shift time value
    event LogUpdateRangePercents(uint upperPercent, uint lowerPercent, uint shiftTime);

    /// @dev Emitted when threshold percent is updated
    /// @param upperThresholdPercent The new upper threshold percent value
    /// @param lowerThresholdPercent The new lower threshold percent value
    /// @param thresholdShiftTime The new threshold shift time value
    /// @param shiftTime The new shift time value
    event LogUpdateThresholdPercent(
        uint upperThresholdPercent,
        uint lowerThresholdPercent,
        uint thresholdShiftTime,
        uint shiftTime
    );

    /// @dev Emitted when center price address is updated
    /// @param centerPriceAddress The new center price address nonce
    /// @param percent The new percent value
    /// @param time The new time value
    event LogUpdateCenterPriceAddress(uint centerPriceAddress, uint percent, uint time);

    /// @dev Emitted when hook address is updated
    /// @param hookAddress The new hook address nonce
    event LogUpdateHookAddress(uint hookAddress);

    /// @dev Emitted when center price limits are updated
    /// @param maxCenterPrice The new maximum center price
    /// @param minCenterPrice The new minimum center price
    event LogUpdateCenterPriceLimits(uint maxCenterPrice, uint minCenterPrice);

    /// @dev Emitted when utilization limit is updated
    /// @param token0UtilizationLimit The new utilization limit for token0
    /// @param token1UtilizationLimit The new utilization limit for token1
    event LogUpdateUtilizationLimit(uint token0UtilizationLimit, uint token1UtilizationLimit);

    /// @dev Emitted when user supply configs are updated
    /// @param userSupplyConfigs The array of updated user supply configurations
    event LogUpdateUserSupplyConfigs(UserSupplyConfig[] userSupplyConfigs);

    /// @dev Emitted when user borrow configs are updated
    /// @param userBorrowConfigs The array of updated user borrow configurations
    event LogUpdateUserBorrowConfigs(UserBorrowConfig[] userBorrowConfigs);

    /// @dev Emitted when a user is paused
    /// @param user The address of the paused user
    /// @param pauseSupply Whether supply operations are paused
    /// @param pauseBorrow Whether borrow operations are paused
    event LogPauseUser(address user, bool pauseSupply, bool pauseBorrow);

    /// @dev Emitted when a user is unpaused
    /// @param user The address of the unpaused user
    /// @param unpauseSupply Whether supply operations are unpaused
    /// @param unpauseBorrow Whether borrow operations are unpaused
    event LogUnpauseUser(address user, bool unpauseSupply, bool unpauseBorrow);

    /// @notice Emitted when the pool configuration is initialized
    /// @param smartCol Whether smart collateral is enabled
    /// @param smartDebt Whether smart debt is enabled
    /// @param token0ColAmt The amount of token0 collateral
    /// @param token0DebtAmt The amount of token0 debt
    /// @param fee The fee percentage (in 4 decimals, 10000 = 1%)
    /// @param revenueCut The revenue cut percentage (in 4 decimals, 100000 = 10%)
    /// @param centerPriceAddress The nonce for the center price contract address
    /// @param hookAddress The nonce for the hook contract address
    event LogInitializePoolConfig(
        bool smartCol,
        bool smartDebt,
        uint token0ColAmt,
        uint token0DebtAmt,
        uint fee,
        uint revenueCut,
        uint centerPriceAddress,
        uint hookAddress
    );

    /// @notice Emitted when the price parameters are initialized
    /// @param upperPercent The upper range percent (in 4 decimals, 10000 = 1%)
    /// @param lowerPercent The lower range percent (in 4 decimals, 10000 = 1%)
    /// @param upperShiftThreshold The upper shift threshold (in 4 decimals, 10000 = 1%)
    /// @param lowerShiftThreshold The lower shift threshold (in 4 decimals, 10000 = 1%)
    /// @param thresholdShiftTime The time for threshold shift (in seconds)
    /// @param maxCenterPrice The maximum center price
    /// @param minCenterPrice The minimum center price
    event LogInitializePriceParams(
        uint upperPercent,
        uint lowerPercent,
        uint upperShiftThreshold,
        uint lowerShiftThreshold,
        uint thresholdShiftTime,
        uint maxCenterPrice,
        uint minCenterPrice
    );

    /// @dev Emitted when swap and arbitrage are paused
    event LogPauseSwapAndArbitrage();

    /// @dev Emitted when swap and arbitrage are unpaused
    event LogUnpauseSwapAndArbitrage();

    /// @notice emitted when user withdrawal limit is updated
    event LogUpdateUserWithdrawalLimit(address user, uint256 newLimit);

    /// @dev Emitted when funds are rescued
    /// @param token The address of the token
    event LogRescueFunds(address token);

    /// @dev Emitted when max supply shares are updated
    /// @param maxSupplyShares The new maximum supply shares
    event LogUpdateMaxSupplyShares(uint maxSupplyShares);

    /// @dev Emitted when max borrow shares are updated
    /// @param maxBorrowShares The new maximum borrow shares
    event LogUpdateMaxBorrowShares(uint maxBorrowShares);

    /// @dev Emitted when oracle activation is toggled
    /// @param turnOn Whether oracle is turned on
    event LogToggleOracleActivation(bool turnOn);
}
