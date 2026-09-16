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

    // @dev The config values below are stored as immutables (set in the constructor) for the standard,
    // per-instance deployed vault. They are exposed through `internal view virtual` getters so that
    // proxy-based deployments (e.g. the permissioned beacon stack) can override the getters to read the
    // per-instance config from elsewhere (the proxy) while reusing all of the vault logic via inheritance.
    // For the standard vault the getters simply return the immutables, so behaviour is unchanged.

    /// @dev collateral token address
    address private immutable _SUPPLY_TOKEN;
    /// @dev borrow token address
    address private immutable _BORROW_TOKEN;

    /// @dev Token decimals. For example wETH is 18 decimals
    uint8 private immutable _SUPPLY_DECIMALS;
    /// @dev Token decimals. For example USDC is 6 decimals
    uint8 private immutable _BORROW_DECIMALS;

    /// @dev VaultT1 AdminModule implemenation address
    address private immutable _ADMIN_IMPLEMENTATION;

    /// @dev VaultT1 Secondary implemenation (main2.sol) address
    address private immutable _SECONDARY_IMPLEMENTATION;

    /// @dev liquidity proxy contract address
    IFluidLiquidity private immutable _LIQUIDITY;

    /// @dev vault factory contract address
    IFluidVaultFactory private immutable _VAULT_FACTORY;

    uint private immutable _VAULT_ID;

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
    bytes32 private immutable _LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT;
    bytes32 private immutable _LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT;
    bytes32 private immutable _LIQUIDITY_USER_SUPPLY_SLOT;
    bytes32 private immutable _LIQUIDITY_USER_BORROW_SLOT;

    /***********************************|
    |     Config getters (virtual)      |
    |__________________________________*/

    function _supplyToken() internal view virtual returns (address) {
        return _SUPPLY_TOKEN;
    }

    function _borrowToken() internal view virtual returns (address) {
        return _BORROW_TOKEN;
    }

    function _supplyDecimals() internal view virtual returns (uint8) {
        return _SUPPLY_DECIMALS;
    }

    function _borrowDecimals() internal view virtual returns (uint8) {
        return _BORROW_DECIMALS;
    }

    function _adminImplementation() internal view virtual returns (address) {
        return _ADMIN_IMPLEMENTATION;
    }

    function _secondaryImplementation() internal view virtual returns (address) {
        return _SECONDARY_IMPLEMENTATION;
    }

    function _liquidity() internal view virtual returns (IFluidLiquidity) {
        return _LIQUIDITY;
    }

    function _vaultFactory() internal view virtual returns (IFluidVaultFactory) {
        return _VAULT_FACTORY;
    }

    function _vaultId() internal view virtual returns (uint) {
        return _VAULT_ID;
    }

    function _liquiditySupplyExchangePriceSlot() internal view virtual returns (bytes32) {
        return _LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT;
    }

    function _liquidityBorrowExchangePriceSlot() internal view virtual returns (bytes32) {
        return _LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT;
    }

    function _liquidityUserSupplySlot() internal view virtual returns (bytes32) {
        return _LIQUIDITY_USER_SUPPLY_SLOT;
    }

    function _liquidityUserBorrowSlot() internal view virtual returns (bytes32) {
        return _LIQUIDITY_USER_BORROW_SLOT;
    }

    /***********************************|
    |   Public ABI getters (virtual)    |
    |__________________________________*/

    /// @dev liquidity proxy contract address
    function LIQUIDITY() public view virtual returns (IFluidLiquidity) {
        return _liquidity();
    }

    /// @dev vault factory contract address
    function VAULT_FACTORY() public view virtual returns (IFluidVaultFactory) {
        return _vaultFactory();
    }

    function VAULT_ID() public view virtual returns (uint256) {
        return _vaultId();
    }

    /// @notice returns all Vault constants
    function constantsView() external view returns (ConstantViews memory constantsView_) {
        constantsView_.liquidity = address(_liquidity());
        constantsView_.factory = address(_vaultFactory());
        constantsView_.adminImplementation = _adminImplementation();
        constantsView_.secondaryImplementation = _secondaryImplementation();
        constantsView_.supplyToken = _supplyToken();
        constantsView_.borrowToken = _borrowToken();
        constantsView_.supplyDecimals = _supplyDecimals();
        constantsView_.borrowDecimals = _borrowDecimals();
        constantsView_.vaultId = _vaultId();
        constantsView_.liquiditySupplyExchangePriceSlot = _liquiditySupplyExchangePriceSlot();
        constantsView_.liquidityBorrowExchangePriceSlot = _liquidityBorrowExchangePriceSlot();
        constantsView_.liquidityUserSupplySlot = _liquidityUserSupplySlot();
        constantsView_.liquidityUserBorrowSlot = _liquidityUserBorrowSlot();
    }

    constructor(ConstantViews memory constants_) {
        _LIQUIDITY = IFluidLiquidity(constants_.liquidity);
        _VAULT_FACTORY = IFluidVaultFactory(constants_.factory);
        _VAULT_ID = constants_.vaultId;

        _SUPPLY_TOKEN = constants_.supplyToken;
        _BORROW_TOKEN = constants_.borrowToken;
        _SUPPLY_DECIMALS = constants_.supplyDecimals;
        _BORROW_DECIMALS = constants_.borrowDecimals;

        // @dev those slots are calculated in the deploymentLogics / VaultFactory
        _LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT = constants_.liquiditySupplyExchangePriceSlot;
        _LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT = constants_.liquidityBorrowExchangePriceSlot;
        _LIQUIDITY_USER_SUPPLY_SLOT = constants_.liquidityUserSupplySlot;
        _LIQUIDITY_USER_BORROW_SLOT = constants_.liquidityUserBorrowSlot;

        _ADMIN_IMPLEMENTATION = constants_.adminImplementation;
        _SECONDARY_IMPLEMENTATION = constants_.secondaryImplementation;
    }
}
