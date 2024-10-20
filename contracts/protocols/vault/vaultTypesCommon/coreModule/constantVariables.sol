// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultFactory } from "../../interfaces/iVaultFactory.sol";
import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";
import { StorageRead } from "../../../../libraries/storageRead.sol";
import { ILiquidityDexCommon } from "../../interfaces/iLiquidityDexCommon.sol";
import { Structs } from "./structs.sol";
import { Error } from "../../error.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";

interface TokenInterface {
    function decimals() external view returns (uint8);
}

abstract contract ConstantVariables is StorageRead, Structs, Error {
    /***********************************|
    |        Constant Variables         |
    |__________________________________*/

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    /// @dev collateral token address
    address internal immutable SUPPLY_TOKEN;
    /// @dev borrow token address
    address internal immutable BORROW_TOKEN;

    /// @dev contract via which we deploy oracle contract
    address internal immutable DEPLOYER_CONTRACT;

    ILiquidityDexCommon internal immutable SUPPLY;
    ILiquidityDexCommon internal immutable BORROW;

    /// @dev if smart collateral then token0 is dex token0 address else it's normal collateral token0 address
    address internal immutable SUPPLY_TOKEN0;
    /// @dev if smart collateral then token1 is dex token1 address else it's address(0)
    address internal immutable SUPPLY_TOKEN1;

    /// @dev if smart debt then token0 is dex token0 address else it's normal borrow token0 address
    address internal immutable BORROW_TOKEN0;
    /// @dev if smart debt then token1 is dex token1 address else it's address(0)
    address internal immutable BORROW_TOKEN1;

    /// @dev Vault OperateModule implemenation address
    address internal immutable OPERATE_IMPLEMENTATION;

    /// @dev Vault AdminModule implemenation address
    address internal immutable ADMIN_IMPLEMENTATION;

    /// @dev Vault Secondary implemenation (main2.sol) address
    address internal immutable SECONDARY_IMPLEMENTATION;

    /// @dev liquidity proxy contract address
    IFluidLiquidity public immutable LIQUIDITY;

    /// @dev vault factory contract address
    IFluidVaultFactory public immutable VAULT_FACTORY;

    uint public immutable VAULT_ID;

    uint public immutable TYPE;

    uint internal constant X8 = 0xff;
    uint internal constant X10 = 0x3ff;
    uint internal constant X15 = 0x7fff;
    uint internal constant X16 = 0xffff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X20 = 0xfffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X25 = 0x1ffffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X33 = 0x1ffffffff;
    uint internal constant X35 = 0x7ffffffff;
    uint internal constant X50 = 0x3ffffffffffff;
    uint internal constant X64 = 0xffffffffffffffff;
    uint internal constant X96 = 0xffffffffffffffffffffffff;
    uint internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev slot ids in Liquidity contract. Helps in low gas fetch from liquidity contract by skipping delegate call
    bytes32 internal immutable SUPPLY_EXCHANGE_PRICE_SLOT; // Can be of DEX or liquidity layer
    bytes32 internal immutable BORROW_EXCHANGE_PRICE_SLOT; // Can be of DEX or liquidity layer
    bytes32 internal immutable USER_SUPPLY_SLOT; // Can be of DEX or liquidity layer
    bytes32 internal immutable USER_BORROW_SLOT; // Can be of DEX or liquidity layer

    constructor(ConstantViews memory constants_) {
        TYPE = constants_.vaultType;

        if (
            TYPE != FluidProtocolTypes.VAULT_T1_TYPE &&
            TYPE != FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE &&
            TYPE != FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE &&
            TYPE != FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            revert FluidVaultError(ErrorTypes.Vault__ImproperConstantsSetup);
        }

        LIQUIDITY = IFluidLiquidity(constants_.liquidity);
        VAULT_FACTORY = IFluidVaultFactory(constants_.factory);
        DEPLOYER_CONTRACT = constants_.deployer;
        SUPPLY = ILiquidityDexCommon(constants_.supply);
        BORROW = ILiquidityDexCommon(constants_.borrow);
        VAULT_ID = constants_.vaultId;

        OPERATE_IMPLEMENTATION = constants_.operateImplementation == address(0)
            ? address(this)
            : constants_.operateImplementation;

        // if smart collateral then adding dex address (even though it's not a token) else adding token address
        if (
            TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
            TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            SUPPLY_TOKEN = constants_.supply;
        } else {
            SUPPLY_TOKEN = constants_.supplyToken.token0;
            if (constants_.supply != constants_.liquidity) {
                revert FluidVaultError(ErrorTypes.Vault__ImproperConstantsSetup);
            }
        }

        // if smart debt then adding dex address (even though it's not a token) else adding token address
        if (
            TYPE == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
            TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            BORROW_TOKEN = constants_.borrow;
        } else {
            BORROW_TOKEN = constants_.borrowToken.token0;
            if (constants_.borrow != constants_.liquidity) {
                revert FluidVaultError(ErrorTypes.Vault__ImproperConstantsSetup);
            }
        }

        SUPPLY_TOKEN0 = constants_.supplyToken.token0;
        BORROW_TOKEN0 = constants_.borrowToken.token0;
        SUPPLY_TOKEN1 = constants_.supplyToken.token1;
        BORROW_TOKEN1 = constants_.borrowToken.token1;

        // below slots are calculated in the deploymentLogics / VaultFactory
        // if supply is directly on liquidity layer then liquidity layer storage slot else if supply is via DEX then bytes32(0)
        SUPPLY_EXCHANGE_PRICE_SLOT = constants_.supplyExchangePriceSlot;
        // if borrow is directly on liquidity layer then liquidity layer storage slot else if borrow is via DEX then bytes32(0)
        BORROW_EXCHANGE_PRICE_SLOT = constants_.borrowExchangePriceSlot;
        // if supply is directly on liquidity layer then liquidity layer storage slot else if supply is via DEX then dex storage slot
        USER_SUPPLY_SLOT = constants_.userSupplySlot;
        // if borrow is directly on liquidity layer then liquidity layer storage slot else if borrow is via DEX then dex storage slot
        USER_BORROW_SLOT = constants_.userBorrowSlot;

        ADMIN_IMPLEMENTATION = constants_.adminImplementation;
        SECONDARY_IMPLEMENTATION = constants_.secondaryImplementation;
    }
}
