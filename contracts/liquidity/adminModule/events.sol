// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { Structs } from "./structs.sol";

contract Events is Structs {
    /// @notice emitted when allowed auths are updated
    event LogUpdateAuths(AddressBool[] authsStatus);

    /// @notice emitted when allowed guardians are updated
    event LogUpdateGuardians(AddressBool[] guardiansStatus);

    /// @notice emitted when revenue collector address is updated
    event LogUpdateRevenueCollector(address indexed revenueCollector);

    /// @notice emitted when status is changed (paused / unpaused)
    event LogChangeStatus(uint256 indexed newStatus);

    /// @notice emitted when user classes are updated
    event LogUpdateUserClasses(AddressUint256[] userClasses);

    /// @notice emitted when token configs are updated
    event LogUpdateTokenConfigs(TokenConfig[] tokenConfigs);

    /// @notice emitted when user supply configs are updated
    event LogUpdateUserSupplyConfigs(UserSupplyConfig[] userSupplyConfigs);

    /// @notice emitted when user borrow configs are updated
    event LogUpdateUserBorrowConfigs(UserBorrowConfig[] userBorrowConfigs);

    /// @notice emitted when a user gets certain tokens paused
    event LogPauseUser(address user, address[] supplyTokens, address[] borrowTokens);

    /// @notice emitted when a user gets certain tokens unpaused
    event LogUnpauseUser(address user, address[] supplyTokens, address[] borrowTokens);

    /// @notice emitted when token rate data is updated with rate data v1
    event LogUpdateRateDataV1s(RateDataV1Params[] tokenRateDatas);

    /// @notice emitted when token rate data is updated with rate data v2
    event LogUpdateRateDataV2s(RateDataV2Params[] tokenRateDatas);

    /// @notice emitted when revenue is collected
    event LogCollectRevenue(address indexed token, uint256 indexed amount);

    /// @notice emitted when exchange prices and borrow rate are updated
    event LogUpdateExchangePrices(
        address indexed token,
        uint256 indexed supplyExchangePrice,
        uint256 indexed borrowExchangePrice,
        uint256 borrowRate,
        uint256 utilization
    );

    /// @notice emitted when user withdrawal limit is updated
    event LogUpdateUserWithdrawalLimit(address user, address token, uint256 newLimit);
}
