// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

import { Structs as AdminModuleStructs } from "../poolT1/adminModule/structs.sol";

/// @title Fluid DEX T1 Admin Interface
/// @notice Admin module methods exposed by DEX T1 pools through the pool fallback. Callable only by
///         DEX factory auths (global or per-dex).
/// @dev older config contracts keep identical local declarations; migrate them here when next touched.
interface IFluidDexT1Admin {
    function updateUserSupplyConfigs(AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_) external;

    function updateUserBorrowConfigs(AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_) external;

    /// @notice sets a new withdrawal limit as the current limit for a certain user
    /// @param user_ user address for which to update the withdrawal limit
    /// @param newLimit_ new limit until which user supply can decrease to.
    ///                  Important: input in raw. Must account for exchange price in input param calculation.
    ///                  Note any limit that is < max expansion or > current user supply will set max expansion limit or
    ///                  current user supply as limit respectively.
    ///                  - set 0 to make maximum possible withdrawable: instant full expansion, and if that goes
    ///                  below base limit then fully down to 0.
    ///                  - set type(uint256).max to make current withdrawable 0 (sets current user supply as limit).
    function updateUserWithdrawalLimit(address user_, uint256 newLimit_) external;

    function updateMaxSupplyShares(uint256 maxSupplyShares_) external;

    function updateMaxBorrowShares(uint256 maxBorrowShares_) external;

    /// @notice side-level: both operations of a paused side are blocked.
    function pauseUser(address user_, bool pauseSupply_, bool pauseBorrow_) external;

    function unpauseUser(address user_, bool unpauseSupply_, bool unpauseBorrow_) external;

    function pauseSwapAndArbitrage() external;

    function unpauseSwapAndArbitrage() external;

    function updateFeeAndRevenueCut(uint256 fee_, uint256 revenueCut_) external;

    function updateRangePercents(uint256 upperPercent_, uint256 lowerPercent_, uint256 shiftTime_) external;

    function updateThresholdPercent(
        uint256 upperThresholdPercent_,
        uint256 lowerThresholdPercent_,
        uint256 thresholdShiftTime_,
        uint256 shiftTime_
    ) external;
}
