//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/// @notice common Fluid vaults interface, some methods only available for vaults > T1 (type, simulateLiquidate, rebalance is different)
interface IFluidVault {
    /// @notice returns the vault id
    function VAULT_ID() external view returns (uint256);

    /// @notice returns the vault id
    function TYPE() external view returns (uint256);

    /// @notice reads uint256 data `result_` from storage at a bytes32 storage `slot_` key.
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);

    struct Tokens {
        address token0;
        address token1;
    }

    struct ConstantViews {
        address liquidity;
        address factory;
        address operateImplementation;
        address adminImplementation;
        address secondaryImplementation;
        address deployer; // address which deploys oracle
        address supply; // either liquidity layer or DEX protocol
        address borrow; // either liquidity layer or DEX protocol
        Tokens supplyToken; // if smart collateral then address of token0 & token1 else just supply token address at token0 and token1 as empty
        Tokens borrowToken; // if smart debt then address of token0 & token1 else just borrow token address at token0 and token1 as empty
        uint256 vaultId;
        uint256 vaultType;
        bytes32 supplyExchangePriceSlot; // if smart collateral then slot is from DEX protocol else from liquidity layer
        bytes32 borrowExchangePriceSlot; // if smart debt then slot is from DEX protocol else from liquidity layer
        bytes32 userSupplySlot; // if smart collateral then slot is from DEX protocol else from liquidity layer
        bytes32 userBorrowSlot; // if smart debt then slot is from DEX protocol else from liquidity layer
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

    error FluidLiquidateResult(uint256 colLiquidated, uint256 debtLiquidated);

    function rebalance(
        int colToken0MinMax_,
        int colToken1MinMax_,
        int debtToken0MinMax_,
        int debtToken1MinMax_
    ) external payable returns (int supplyAmt_, int borrowAmt_);

    /// @notice reverts with FluidLiquidateResult
    function simulateLiquidate(uint debtAmt_, bool absorb_) external;
}
