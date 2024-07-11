// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

import { IAllowanceTransfer } from "../interfaces/permit2/iAllowanceTransfer.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { IFToken } from "../interfaces/iFToken.sol";
import { IAllowanceTransfer } from "../interfaces/permit2/iAllowanceTransfer.sol";
import { IFluidLendingRewardsRateModel  } from "../interfaces/iLendingRewardsRateModel.sol";
import { IFluidLendingFactory } from "../interfaces/iLendingFactory.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

abstract contract Constants {
    /// @dev permit2 contract, deployed to same address on EVM networks, see https://github.com/Uniswap/permit2
    IAllowanceTransfer internal constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @dev precision for exchange prices
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @dev max allowed reward rate is 50%
    uint256 internal constant MAX_REWARDS_RATE = 50 * 1e12; // 50%;

    /// @dev address of the Liquidity contract.
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @dev address of the Lending factory contract.
    IFluidLendingFactory internal immutable LENDING_FACTORY;

    /// @dev address of the underlying asset contract.
    IERC20 internal immutable ASSET;

    /// @dev number of decimals for the fToken, same as ASSET
    uint8 internal immutable DECIMALS;

    /// @dev slot ids in Liquidity contract for underlying token.
    /// Helps in low gas fetch from liquidity contract by skipping delegate call with `readFromStorage`
    bytes32 internal immutable LIQUIDITY_EXCHANGE_PRICES_SLOT;
    bytes32 internal immutable LIQUIDITY_TOTAL_AMOUNTS_SLOT;
    bytes32 internal immutable LIQUIDITY_USER_SUPPLY_SLOT;

    /// @param liquidity_ liquidity contract address
    /// @param lendingFactory_ lending factory contract address
    /// @param asset_ underlying token address
    constructor(IFluidLiquidity liquidity_, IFluidLendingFactory lendingFactory_, IERC20 asset_) {
        DECIMALS = IERC20Metadata(address(asset_)).decimals();
        ASSET = asset_;
        LIQUIDITY = liquidity_;
        LENDING_FACTORY = lendingFactory_;

        LIQUIDITY_EXCHANGE_PRICES_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            _getLiquiditySlotLinksAsset()
        );
        LIQUIDITY_TOTAL_AMOUNTS_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            _getLiquiditySlotLinksAsset()
        );
        LIQUIDITY_USER_SUPPLY_SLOT = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
            address(this),
            _getLiquiditySlotLinksAsset()
        );
    }

    /// @dev gets asset address for liquidity slot links, extracted to separate method so it can be overridden if needed
    function _getLiquiditySlotLinksAsset() internal view virtual returns (address) {
        return address(ASSET);
    }
}

abstract contract Variables is ERC20, ERC20Permit, Error, Constants, IFToken {
    /// @dev prefix for token name. fToken will append the underlying asset name
    string private constant TOKEN_NAME_PREFIX = "Fluid ";
    /// @dev prefix for token symbol. fToken will append the underlying asset symbol
    string private constant TOKEN_SYMBOL_PREFIX = "f";

    // ------------ storage variables from inherited contracts come before vars here --------
    // _________ ERC20 _______________
    // ----------------------- slot 0 ---------------------------
    // mapping(address => uint256) private _balances;

    // ----------------------- slot 1 ---------------------------
    // mapping(address => mapping(address => uint256)) private _allowances;

    // ----------------------- slot 2 ---------------------------
    // uint256 private _totalSupply;

    // ----------------------- slot 3 ---------------------------
    // string private _name;
    // ----------------------- slot 4 ---------------------------
    // string private _symbol;

    // _________ ERC20Permit _______________
    // ----------------------- slot 5 ---------------------------
    // mapping(address => Counters.Counter) private _nonces;

    // ----------------------- slot 6 ---------------------------
    // bytes32 private _PERMIT_TYPEHASH_DEPRECATED_SLOT;

    // ----------------------- slot 7 ---------------------------
    /// @dev address of the LendingRewardsRateModel.
    IFluidLendingRewardsRateModel  internal _rewardsRateModel;

    // -> 12 bytes empty
    uint96 private __placeholder_gap;

    // ----------------------- slot 8 ---------------------------
    // optimized to put all storage variables where a SSTORE happens on actions in the same storage slot

    /// @dev exchange price for the underlying assset in the liquidity protocol (without rewards)
    uint64 internal _liquidityExchangePrice; // in 1e12 -> (max value 18_446_744,073709551615)

    /// @dev exchange price between fToken and the underlying assset (with rewards)
    uint64 internal _tokenExchangePrice; // in 1e12 -> (max value 18_446_744,073709551615)

    /// @dev timestamp when exchange prices were updated the last time
    uint40 internal _lastUpdateTimestamp;

    /// @dev status for reentrancy guard
    uint8 internal _status;

    /// @dev flag to signal if rewards are active without having to read slot 6
    bool internal _rewardsActive;

    // 72 bits empty (9 bytes)

    // ----------------------- slot 9 ---------------------------
    /// @dev rebalancer address allowed to call `rebalance()` and source for funding rewards (ReserveContract).
    address internal _rebalancer;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param liquidity_ liquidity contract address
    /// @param lendingFactory_ lending factory contract address
    /// @param asset_ underlying token address
    constructor(
        IFluidLiquidity liquidity_,
        IFluidLendingFactory lendingFactory_,
        IERC20 asset_
    )
        validAddress(address(liquidity_))
        validAddress(address(lendingFactory_))
        validAddress(address(asset_))
        Constants(liquidity_, lendingFactory_, asset_)
        ERC20(
            string(abi.encodePacked(TOKEN_NAME_PREFIX, IERC20Metadata(address(asset_)).name())),
            string(abi.encodePacked(TOKEN_SYMBOL_PREFIX, IERC20Metadata(address(asset_)).symbol()))
        )
        ERC20Permit(string(abi.encodePacked(TOKEN_NAME_PREFIX, IERC20Metadata(address(asset_)).name())))
    {}

    /// @dev checks that address is not the zero address, reverts if so. Calling the method in the modifier reduces
    /// bytecode size as modifiers are inlined into bytecode
    function _checkValidAddress(address value_) internal pure {
        if (value_ == address(0)) {
            revert FluidLendingError(ErrorTypes.fToken__InvalidParams);
        }
    }

    /// @dev validates that an address is not the zero address
    modifier validAddress(address value_) {
        _checkValidAddress(value_);
        _;
    }
}
