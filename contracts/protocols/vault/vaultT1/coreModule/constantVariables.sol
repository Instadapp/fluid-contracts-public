// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";
import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";
import { StorageRead } from "../../../../libraries/storageRead.sol";

import { Structs } from "./structs.sol";

interface TokenInterface {
    function decimals() external view returns (uint8);
}

contract ConstantVariables is StorageRead, Structs {
    /***********************************|
    |        Constant Variables         |
    |__________________________________*/

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev collateral token address
    address internal immutable SUPPLY_TOKEN;
    /// @dev borrow token address
    address internal immutable BORROW_TOKEN;

    /// @dev Token decimals. For example wETH is 18 decimals
    uint8 internal immutable SUPPLY_DECIMALS;
    /// @dev Token decimals. For example USDC is 6 decimals
    uint8 internal immutable BORROW_DECIMALS;

    /// @dev VaultT1 AdminModule implemenation address
    address internal immutable ADMIN_IMPLEMENTATION;

    /// @dev VaultT1 Secondary implemenation (main2.sol) address
    address internal immutable SECONDARY_IMPLEMENTATION;

    /// @dev liquidity proxy contract address
    IFluidLiquidity public immutable LIQUIDITY;

    /// @dev vault factory contract address
    IFluidVaultFactory public immutable VAULT_FACTORY;

    uint public immutable VAULT_ID;

    uint internal constant X8 = 0xff;
    uint internal constant X10 = 0x3ff;
    uint internal constant X16 = 0xffff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X20 = 0xfffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X25 = 0x1ffffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X35 = 0x7ffffffff;
    uint internal constant X50 = 0x3ffffffffffff;
    uint internal constant X64 = 0xffffffffffffffff;
    uint internal constant X96 = 0xffffffffffffffffffffffff;
    uint internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev slot ids in Liquidity contract. Helps in low gas fetch from liquidity contract by skipping delegate call
    bytes32 internal immutable LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT;
    bytes32 internal immutable LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT;
    bytes32 internal immutable LIQUIDITY_USER_SUPPLY_SLOT;
    bytes32 internal immutable LIQUIDITY_USER_BORROW_SLOT;

    /// @notice returns all Vault constants
    function constantsView() external view returns (ConstantViews memory constantsView_) {
        constantsView_.liquidity = address(LIQUIDITY);
        constantsView_.factory = address(VAULT_FACTORY);
        constantsView_.adminImplementation = ADMIN_IMPLEMENTATION;
        constantsView_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constantsView_.supplyToken = SUPPLY_TOKEN;
        constantsView_.borrowToken = BORROW_TOKEN;
        constantsView_.supplyDecimals = SUPPLY_DECIMALS;
        constantsView_.borrowDecimals = BORROW_DECIMALS;
        constantsView_.vaultId = VAULT_ID;
        constantsView_.liquiditySupplyExchangePriceSlot = LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT;
        constantsView_.liquidityBorrowExchangePriceSlot = LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT;
        constantsView_.liquidityUserSupplySlot = LIQUIDITY_USER_SUPPLY_SLOT;
        constantsView_.liquidityUserBorrowSlot = LIQUIDITY_USER_BORROW_SLOT;
    }

    constructor(ConstantViews memory constants_) {
        LIQUIDITY = IFluidLiquidity(constants_.liquidity);
        VAULT_FACTORY = IFluidVaultFactory(constants_.factory);
        VAULT_ID = constants_.vaultId;

        SUPPLY_TOKEN = constants_.supplyToken;
        BORROW_TOKEN = constants_.borrowToken;
        SUPPLY_DECIMALS = constants_.supplyDecimals;
        BORROW_DECIMALS = constants_.borrowDecimals;

        // @dev those slots are calculated in the deploymentLogics / VaultFactory
        LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT = constants_.liquiditySupplyExchangePriceSlot;
        LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT = constants_.liquidityBorrowExchangePriceSlot;
        LIQUIDITY_USER_SUPPLY_SLOT = constants_.liquidityUserSupplySlot;
        LIQUIDITY_USER_BORROW_SLOT = constants_.liquidityUserBorrowSlot;

        ADMIN_IMPLEMENTATION = constants_.adminImplementation;
        SECONDARY_IMPLEMENTATION = constants_.secondaryImplementation;
    }
}
