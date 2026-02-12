// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IFluidLiquidityLogic, IFluidLiquidityAdmin } from "./interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "./adminModule/structs.sol";

/// @notice Liquidity dummy implementation used for Fluid Liquidity infinite proxy.
/// @dev see https://github.com/Instadapp/infinite-proxy?tab=readme-ov-file#dummy-implementation
contract FluidLiquidityDummyImpl is IFluidLiquidityLogic {
    /// @inheritdoc IFluidLiquidityAdmin
    function updateAuths(AdminModuleStructs.AddressBool[] calldata authsStatus_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateGuardians(AdminModuleStructs.AddressBool[] calldata guardiansStatus_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRevenueCollector(address revenueCollector_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function changeStatus(uint256 newStatus_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRateDataV1s(AdminModuleStructs.RateDataV1Params[] calldata tokensRateData_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateRateDataV2s(AdminModuleStructs.RateDataV2Params[] calldata tokensRateData_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateTokenConfigs(AdminModuleStructs.TokenConfig[] calldata tokenConfigs_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserClasses(AdminModuleStructs.AddressUint256[] calldata userClasses_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserSupplyConfigs(AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserWithdrawalLimit(address user_, address token_, uint256 newLimit_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateUserBorrowConfigs(AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function pauseUser(address user_, address[] calldata supplyTokens_, address[] calldata borrowTokens_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function unpauseUser(address user_, address[] calldata supplyTokens_, address[] calldata borrowTokens_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function collectRevenue(address[] calldata tokens_) external {}

    /// @inheritdoc IFluidLiquidityAdmin
    function updateExchangePrices(
        address[] calldata tokens_
    ) external returns (uint256[] memory supplyExchangePrices_, uint256[] memory borrowExchangePrices_) {}

    /// @inheritdoc IFluidLiquidityLogic
    function operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes calldata callbackData_
    ) external payable returns (uint256 memVar3_, uint256 memVar4_) {}
}
