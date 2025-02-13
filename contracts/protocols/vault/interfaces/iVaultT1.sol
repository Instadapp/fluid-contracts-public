//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFluidVaultT1 {
    /// @notice returns the vault id
    function VAULT_ID() external view returns (uint256);

    /// @notice returns the vault factory address
    function VAULT_FACTORY() external view returns (address);

    /// @notice reads uint256 data `result_` from storage at a bytes32 storage `slot_` key.
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);

    struct ConstantViews {
        address liquidity;
        address factory;
        address adminImplementation;
        address secondaryImplementation;
        address supplyToken;
        address borrowToken;
        uint8 supplyDecimals;
        uint8 borrowDecimals;
        uint vaultId;
        bytes32 liquiditySupplyExchangePriceSlot;
        bytes32 liquidityBorrowExchangePriceSlot;
        bytes32 liquidityUserSupplySlot;
        bytes32 liquidityUserBorrowSlot;
    }

    /// @notice returns all Vault constants
    function constantsView() external view returns (ConstantViews memory constantsView_);

    /// @notice fetches the latest user position after a liquidation
    function fetchLatestPosition(
        int256 positionTick_,
        uint256 positionTickId_,
        uint256 positionRawDebt_,
        uint256 tickData_
    )
        external
        view
        returns (
            int256, // tick
            uint256, // raw debt
            uint256, // raw collateral
            uint256, // branchID_
            uint256 // branchData_
        );

    /// @notice calculates the updated vault exchange prices
    function updateExchangePrices(
        uint256 vaultVariables2_
    )
        external
        view
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        );

    /// @notice calculates the updated vault exchange prices and writes them to storage
    function updateExchangePricesOnStorage()
        external
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        );

    /// @notice returns the liquidity contract address
    function LIQUIDITY() external view returns (address);

    function operate(
        uint256 nftId_, // if 0 then new position
        int256 newCol_, // if negative then withdraw
        int256 newDebt_, // if negative then payback
        address to_ // address at which the borrow & withdraw amount should go to. If address(0) then it'll go to msg.sender
    )
        external
        payable
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        );

    function liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // min collateral needed per unit of debt in 1e18
        address to_,
        bool absorb_
    ) external payable returns (uint actualDebtAmt_, uint actualColAmt_);

    function absorb() payable external;

    function rebalance() external payable returns (int supplyAmt_, int borrowAmt_);

    error FluidLiquidateResult(uint256 colLiquidated, uint256 debtLiquidated);
}
