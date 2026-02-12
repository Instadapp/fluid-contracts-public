//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

import { Structs as LiquidityStructs } from "../../../periphery/resolvers/liquidity/structs.sol";

interface IFluidLiquidityResolver {
    /// @notice gets the `revenueAmount_` for a `token_`.
    function getRevenue(address token_) external view returns (uint256 revenueAmount_);

    /// @notice address of contract that gets sent the revenue. Configurable by governance
    function getRevenueCollector() external view returns (address);

    /// @notice Liquidity contract paused status: status = 1 -> normal. status = 2 -> paused.
    function getStatus() external view returns (uint256);

    /// @notice checks if `auth_` is an allowed auth on Liquidity.
    /// Auths can set most config values. E.g. contracts that automate certain flows like e.g. adding a new fToken.
    /// Governance can add/remove auths. Governance is auth by default.
    function isAuth(address auth_) external view returns (uint256);

    /// @notice checks if `guardian_` is an allowed Guardian on Liquidity.
    /// Guardians can pause lower class users.
    /// Governance can add/remove guardians. Governance is guardian by default.
    function isGuardian(address guardian_) external view returns (uint256);

    /// @notice gets user class for `user_`. Class defines which protocols can be paused by guardians.
    /// Currently there are 2 classes: 0 can be paused by guardians. 1 cannot be paused by guardians.
    /// New protocols are added as class 0 and will be upgraded to 1 over time.
    function getUserClass(address user_) external view returns (uint256);

    /// @notice gets exchangePricesAndConfig packed uint256 storage slot for `token_`.
    function getExchangePricesAndConfig(address token_) external view returns (uint256);

    /// @notice gets rateConfig packed uint256 storage slot for `token_`.
    function getRateConfig(address token_) external view returns (uint256);

    /// @notice gets totalAmounts packed uint256 storage slot for `token_`.
    function getTotalAmounts(address token_) external view returns (uint256);

    /// @notice gets configs2 packed uint256 storage slot for `token_`.
    function getConfigs2(address token_) external view returns (uint256);

    /// @notice gets userSupply data packed uint256 storage slot for `user_` and `token_`.
    function getUserSupply(address user_, address token_) external view returns (uint256);

    /// @notice gets userBorrow data packed uint256 storage slot for `user_` and `token_`.
    function getUserBorrow(address user_, address token_) external view returns (uint256);

    /// @notice returns all `listedTokens_` at the Liquidity contract. Once configured, a token can never be removed.
    function listedTokens() external view returns (address[] memory listedTokens_);

    /// @notice get the Rate config data `rateData_` for a `token_` compiled from the packed uint256 rateConfig storage slot
    function getTokenRateData(address token_) external view returns (LiquidityStructs.RateData memory rateData_);

    /// @notice get the Rate config datas `rateDatas_` for multiple `tokens_` compiled from the packed uint256 rateConfig storage slot
    function getTokensRateData(
        address[] calldata tokens_
    ) external view returns (LiquidityStructs.RateData[] memory rateDatas_);

    /// @notice returns general data for `token_` such as rates, exchange prices, utilization, fee, total amounts etc.
    function getOverallTokenData(
        address token_
    ) external view returns (LiquidityStructs.OverallTokenData memory overallTokenData_);

    /// @notice returns general data for multiple `tokens_` such as rates, exchange prices, utilization, fee, total amounts etc.
    function getOverallTokensData(
        address[] calldata tokens_
    ) external view returns (LiquidityStructs.OverallTokenData[] memory overallTokensData_);

    /// @notice returns general data for all `listedTokens()` such as rates, exchange prices, utilization, fee, total amounts etc.
    function getAllOverallTokensData()
        external
        view
        returns (LiquidityStructs.OverallTokenData[] memory overallTokensData_);

    /// @notice returns `user_` supply data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for `token_`
    function getUserSupplyData(
        address user_,
        address token_
    )
        external
        view
        returns (
            LiquidityStructs.UserSupplyData memory userSupplyData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        );

    /// @notice returns `user_` supply data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for multiple `tokens_`
    function getUserMultipleSupplyData(
        address user_,
        address[] calldata tokens_
    )
        external
        view
        returns (
            LiquidityStructs.UserSupplyData[] memory userSuppliesData_,
            LiquidityStructs.OverallTokenData[] memory overallTokensData_
        );

    /// @notice returns `user_` borrow data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for `token_`
    function getUserBorrowData(
        address user_,
        address token_
    )
        external
        view
        returns (
            LiquidityStructs.UserBorrowData memory userBorrowData_,
            LiquidityStructs.OverallTokenData memory overallTokenData_
        );

    /// @notice returns `user_` borrow data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for multiple `tokens_`
    function getUserMultipleBorrowData(
        address user_,
        address[] calldata tokens_
    )
        external
        view
        returns (
            LiquidityStructs.UserBorrowData[] memory userBorrowingsData_,
            LiquidityStructs.OverallTokenData[] memory overallTokensData_
        );

    /// @notice returns `user_` supply data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for multiple `supplyTokens_`
    ///     and returns `user_` borrow data and general data (such as rates, exchange prices, utilization, fee, total amounts etc.) for multiple `borrowTokens_`
    function getUserMultipleBorrowSupplyData(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    )
        external
        view
        returns (
            LiquidityStructs.UserSupplyData[] memory userSuppliesData_,
            LiquidityStructs.OverallTokenData[] memory overallSupplyTokensData_,
            LiquidityStructs.UserBorrowData[] memory userBorrowingsData_,
            LiquidityStructs.OverallTokenData[] memory overallBorrowTokensData_
        );
}
