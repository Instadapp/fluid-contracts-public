// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Helpers } from "./helpers.sol";
import { TickMath } from "../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { IFluidOracle } from "../../../oracle/fluidOracle.sol";
import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { DexCalcs } from "../../../libraries/dexCalcs.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { IFluidStorageReadable } from "./variables.sol";
import { FluidProtocolTypes } from "../../../libraries/fluidProtocolTypes.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @notice Fluid Vault protocol resolver
/// Implements various view-only methods to give easy access to Vault protocol data.
/// For vaults with Smart Col / Smart Debt from the Dex protocol, combine this data with Data fetched
/// from the DexResolver e.g. via MultiCall to fetch Vault limits, shares exchange rates etc. at the Dex.
contract FluidVaultResolver is Helpers {
    constructor(address factory_, address liquidityResolver_) Helpers(factory_, liquidityResolver_) {}

    /// @notice Get the address of a vault.
    /// @param vaultId_ The ID of the vault.
    /// @return vault_ The address of the vault.
    function getVaultAddress(uint vaultId_) public view returns (address vault_) {
        return AddressCalcs.addressCalc(address(FACTORY), vaultId_);
    }

    /// @notice Get the type of a vault.
    /// @param vault_ The address of the vault.
    /// @return vaultType_ The type of the vault. 0 if not a Fluid vault.
    function getVaultType(address vault_) public view returns (uint vaultType_) {
        if (vault_.code.length == 0) {
            return 0;
        }
        try IFluidVault(vault_).TYPE() returns (uint type_) {
            return type_;
        } catch {
            if (getVaultAddress(getVaultId(vault_)) != vault_) {
                return 0;
            }
            // if TYPE() is not available but address is valid vault id, it must be vault T1
            return FluidProtocolTypes.VAULT_T1_TYPE;
        }
    }

    /// @notice Get the ID of a vault.
    /// @param vault_ The address of the vault.
    /// @return id_ The ID of the vault.
    function getVaultId(address vault_) public view returns (uint id_) {
        id_ = IFluidVault(vault_).VAULT_ID();
    }

    /// @notice Get the token configuration.
    /// @param nftId_ The ID of the NFT.
    /// @return The token configuration.
    function getTokenConfig(uint nftId_) public view returns (uint) {
        return FACTORY.readFromStorage(calculateStorageSlotUintMapping(3, nftId_));
    }

    /// @notice Get the raw variables of a vault.
    /// @param vault_ The address of the vault.
    /// @return The raw variables of the vault.
    function getVaultVariablesRaw(address vault_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(normalSlot(0));
    }

    /// @notice Get the raw variables of a vault.
    /// @param vault_ The address of the vault.
    /// @return The raw variables of the vault.
    function getVaultVariables2Raw(address vault_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(normalSlot(1));
    }

    /// @notice Get the absorbed liquidity of a vault.
    /// @param vault_ The address of the vault.
    /// @return The absorbed liquidity of the vault.
    function getAbsorbedLiquidityRaw(address vault_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(normalSlot(2));
    }

    /// @notice Get the position data of a vault.
    /// @param vault_ The address of the vault.
    /// @param positionId_ The ID of the position.
    /// @return The position data of the vault.
    function getPositionDataRaw(address vault_, uint positionId_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(calculateStorageSlotUintMapping(3, positionId_));
    }

    /// @notice Get the raw tick data of a vault.
    /// @param vault_ The address of the vault.
    /// @param tick_ The tick value.
    /// @return The raw tick data of the vault.
    // if tick > 0 then key_ = tick / 256
    // if tick < 0 then key_ = (tick / 256) - 1
    function getTickDataRaw(address vault_, int tick_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(calculateStorageSlotIntMapping(5, tick_));
    }

    /// @notice Get the raw tick data of a vault.
    /// @param vault_ The address of the vault.
    /// @param key_ The tick key.
    /// @return The raw tick data of the vault.
    function getTickHasDebtRaw(address vault_, int key_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(calculateStorageSlotIntMapping(4, key_));
    }

    /// @notice Get the raw tick data of a vault.
    /// @param vault_ The address of the vault.
    /// @param tick_ The tick value.
    /// @param id_ The ID of the tick.
    /// @return The raw tick data of the vault.
    // id_ = (realId_ / 3) + 1
    function getTickIdDataRaw(address vault_, int tick_, uint id_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(calculateDoubleIntUintMapping(6, tick_, id_));
    }

    /// @notice Get the raw branch data of a vault.
    /// @param vault_ The address of the vault.
    /// @param branch_ The branch value.
    /// @return The raw branch data of the vault.
    function getBranchDataRaw(address vault_, uint branch_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(calculateStorageSlotUintMapping(7, branch_));
    }

    /// @notice Get the raw rate of a vault.
    /// @param vault_ The address of the vault.
    /// @return The raw rate of the vault.
    function getRateRaw(address vault_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(normalSlot(8));
    }

    /// @notice Get the rebalancer of a vault.
    /// @param vault_ The address of the vault.
    /// @return The rebalancer of the vault.
    function getRebalancer(address vault_) public view returns (address) {
        return address(uint160(IFluidVault(vault_).readFromStorage(normalSlot(9))));
    }

    /// @notice Get the absorbed dust debt of a vault.
    /// @param vault_ The address of the vault.
    /// @return The absorbed dust debt of the vault.
    function getAbsorbedDustDebt(address vault_) public view returns (uint) {
        return IFluidVault(vault_).readFromStorage(normalSlot(10));
    }

    /// @notice Get the DEX from address of a vault.
    /// @param vault_ The address of the vault.
    /// @return The DEX from address of the vault.
    function getDexFromAddress(address vault_) public view returns (address) {
        return address(uint160(IFluidVault(vault_).readFromStorage(normalSlot(11))));
    }

    /// @notice Get the total number of vaults.
    /// @return The total number of vaults.
    function getTotalVaults() public view returns (uint) {
        return FACTORY.totalVaults();
    }

    /// @notice Get the addresses of all the vaults.
    /// @return vaults_ The addresses of all the vaults.
    function getAllVaultsAddresses() public view returns (address[] memory vaults_) {
        uint totalVaults_ = getTotalVaults();
        vaults_ = new address[](totalVaults_);
        for (uint i = 0; i < totalVaults_; i++) {
            vaults_[i] = getVaultAddress((i + 1));
        }
    }

    /// @notice Get the contract for deployer index of a vault.
    /// @param vault_ The address of the vault.
    /// @param index_ The index of the deployer.
    /// @return The contract for deployer index of the vault.
    function getContractForDeployerIndex(address vault_, uint index_) public view returns (address) {
        IFluidVault.ConstantViews memory constants_ = _getVaultConstants(vault_, getVaultType(vault_));
        if (constants_.deployer == address(0) || index_ == 0) {
            return address(0);
        }
        return AddressCalcs.addressCalc(constants_.deployer, index_);
    }

    /// @dev Get the constants of a vault.
    /// @param vault_ The address of the vault.
    /// @param vaultType_ The type of the vault.
    /// @return constants_ The constants of the vault.
    function _getVaultConstants(
        address vault_,
        uint vaultType_
    ) internal view returns (IFluidVault.ConstantViews memory constants_) {
        if (vaultType_ == FluidProtocolTypes.VAULT_T1_TYPE) {
            try IFluidVaultT1(vault_).constantsView() returns (IFluidVaultT1.ConstantViews memory constantsT1_) {
                constants_.liquidity = constantsT1_.liquidity;
                constants_.factory = constantsT1_.factory;
                constants_.operateImplementation = address(vault_);
                constants_.adminImplementation = constantsT1_.adminImplementation;
                constants_.secondaryImplementation = constantsT1_.secondaryImplementation;
                constants_.deployer = address(0);
                constants_.supply = constantsT1_.liquidity;
                constants_.borrow = constantsT1_.liquidity;
                constants_.supplyToken.token0 = constantsT1_.supplyToken;
                constants_.supplyToken.token1 = address(0);
                constants_.borrowToken.token0 = constantsT1_.borrowToken;
                constants_.borrowToken.token1 = address(0);
                constants_.vaultId = constantsT1_.vaultId;
                constants_.vaultType = FluidProtocolTypes.VAULT_T1_TYPE;
                constants_.supplyExchangePriceSlot = constantsT1_.liquiditySupplyExchangePriceSlot;
                constants_.borrowExchangePriceSlot = constantsT1_.liquidityBorrowExchangePriceSlot;
                constants_.userSupplySlot = constantsT1_.liquidityUserSupplySlot;
                constants_.userBorrowSlot = constantsT1_.liquidityUserBorrowSlot;
            } catch {
                // vault address is likely not a fluid vault or not deployed yet etc.
                // vault type is detected as being T1 when TYPE() is not present, which could also happen
                // on non-Fluid-vault contracts
            }
        } else {
            constants_ = IFluidVault(vault_).constantsView();
        }
    }

    /// @dev Get the configuration of a vault.
    /// @param vault_ The address of the vault.
    /// @param vaultType_ The type of the vault.
    /// @return configs_ The configuration of the vault.
    function _getVaultConfig(address vault_, uint vaultType_) internal view returns (Configs memory configs_) {
        uint vaultVariables2_ = getVaultVariables2Raw(vault_);
        configs_.supplyRateMagnifier = uint16(vaultVariables2_ & X16);
        configs_.borrowRateMagnifier = uint16((vaultVariables2_ >> 16) & X16);
        configs_.collateralFactor = (uint16((vaultVariables2_ >> 32) & X10)) * 10;
        configs_.liquidationThreshold = (uint16((vaultVariables2_ >> 42) & X10)) * 10;
        configs_.liquidationMaxLimit = (uint16((vaultVariables2_ >> 52) & X10) * 10);
        configs_.withdrawalGap = uint16((vaultVariables2_ >> 62) & X10) * 10;
        configs_.liquidationPenalty = uint16((vaultVariables2_ >> 72) & X10);
        configs_.borrowFee = uint16((vaultVariables2_ >> 82) & X10);

        if (vaultType_ == FluidProtocolTypes.VAULT_T1_TYPE) {
            configs_.oracle = address(uint160(vaultVariables2_ >> 96));
        } else {
            /// Next 30 bits => 92-121 => bits to calculate address of oracle
            uint index_ = (vaultVariables2_ >> 92) & X30;
            if (index_ > 0) {
                configs_.oracle = getContractForDeployerIndex(vault_, index_);
            }
            /// Next 33 bits => 122-154 => last update timestamp
            configs_.lastUpdateTimestamp = uint((vaultVariables2_ >> 122) & X33);
        }

        if (configs_.oracle != address(0)) {
            try IFluidOracle(configs_.oracle).getExchangeRateOperate() returns (uint exchangeRate_) {
                configs_.oraclePriceOperate = exchangeRate_;
                configs_.oraclePriceLiquidate = IFluidOracle(configs_.oracle).getExchangeRateLiquidate();
            } catch {
                // deprecated backward compatible for older vaults oracles
                configs_.oraclePriceOperate = IFluidOracle(configs_.oracle).getExchangeRate();
                configs_.oraclePriceLiquidate = configs_.oraclePriceOperate;
            }
        }

        configs_.rebalancer = getRebalancer(vault_);
    }

    /// @dev Get the exchange prices and rates of a vault.
    /// @param vault_ The address of the vault.
    /// @param vaultType_ The type of the vault.
    /// @param configs_ The configuration of the vault.
    /// @param liquiditySupplyRate_ The liquidity supply rate, only set in case of NOT smart collateral.
    /// @param liquidityBorrowRate_ The liquidity borrow rate, only set in case of NOT smart debt.
    /// @return exchangePricesAndRates_ The exchange prices and rates of the vault.
    function _getExchangePricesAndRates(
        address vault_,
        uint vaultType_,
        Configs memory configs_,
        uint liquiditySupplyRate_,
        uint liquidityBorrowRate_
    ) internal view returns (ExchangePricesAndRates memory exchangePricesAndRates_) {
        uint exchangePrices_ = getRateRaw(vault_);
        exchangePricesAndRates_.lastStoredLiquiditySupplyExchangePrice = exchangePrices_ & X64;
        exchangePricesAndRates_.lastStoredLiquidityBorrowExchangePrice = (exchangePrices_ >> 64) & X64;
        exchangePricesAndRates_.lastStoredVaultSupplyExchangePrice = (exchangePrices_ >> 128) & X64;
        exchangePricesAndRates_.lastStoredVaultBorrowExchangePrice = (exchangePrices_ >> 192) & X64;

        (
            exchangePricesAndRates_.liquiditySupplyExchangePrice,
            exchangePricesAndRates_.liquidityBorrowExchangePrice,
            exchangePricesAndRates_.vaultSupplyExchangePrice,
            exchangePricesAndRates_.vaultBorrowExchangePrice
        ) = IFluidVault(vault_).updateExchangePrices(getVaultVariables2Raw(vault_));

        exchangePricesAndRates_.supplyRateLiquidity = liquiditySupplyRate_;
        exchangePricesAndRates_.borrowRateLiquidity = liquidityBorrowRate_;

        if (
            vaultType_ == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
            vaultType_ == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            // in case of smart collateral supply magnifier bits stores supply interest rate positive or negative
            // negative meaning charging users, positive means incentivizing users
            exchangePricesAndRates_.supplyRateVault = int256((configs_.supplyRateMagnifier >> 1) & X15);
            // if first bit == 1 then positive else negative
            if ((configs_.supplyRateMagnifier & 1) == 0) {
                exchangePricesAndRates_.supplyRateVault = -exchangePricesAndRates_.supplyRateVault;
            }
            exchangePricesAndRates_.rewardsOrFeeRateSupply = exchangePricesAndRates_.supplyRateVault;
        } else {
            // NOT smart col
            unchecked {
                exchangePricesAndRates_.supplyRateVault = int256(
                    (liquiditySupplyRate_ * configs_.supplyRateMagnifier) / 10000
                );
                exchangePricesAndRates_.rewardsOrFeeRateSupply = int256(uint(configs_.supplyRateMagnifier)) - 10000;
            }
        }

        if (
            vaultType_ == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
            vaultType_ == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            // in case of smart debt borrow magnifier bits stores borrow interest rate positive or negative
            // negative meaning incentivizing users, positive means charging users
            exchangePricesAndRates_.borrowRateVault = int256((configs_.borrowRateMagnifier >> 1) & X15);
            // if first bit == 1 then positive else negative
            if ((configs_.borrowRateMagnifier & 1) == 0) {
                exchangePricesAndRates_.borrowRateVault = -exchangePricesAndRates_.borrowRateVault;
            }
            exchangePricesAndRates_.rewardsOrFeeRateBorrow = exchangePricesAndRates_.borrowRateVault;
        } else {
            unchecked {
                // NOT smart debt
                exchangePricesAndRates_.borrowRateVault = int256(
                    (liquidityBorrowRate_ * configs_.borrowRateMagnifier) / 10000
                );
                exchangePricesAndRates_.rewardsOrFeeRateBorrow = int256(uint(configs_.borrowRateMagnifier)) - 10000;
            }
        }
    }

    /// @dev Get the total supply and borrow of a vault.
    /// @param vault_ The address of the vault.
    /// @param exchangePricesAndRates_ The exchange prices and rates of the vault.
    /// @param constantsVariables_ The constants and variables of the vault.
    /// @return totalSupplyAndBorrow_ The total supply and borrow of the vault.
    function _getTotalSupplyAndBorrow(
        address vault_,
        ExchangePricesAndRates memory exchangePricesAndRates_,
        IFluidVault.ConstantViews memory constantsVariables_
    ) internal view returns (TotalSupplyAndBorrow memory totalSupplyAndBorrow_) {
        uint vaultVariables_ = getVaultVariablesRaw(vault_);
        uint absorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
        uint totalSupplyLiquidityOrDex_ = IFluidStorageReadable(constantsVariables_.supply).readFromStorage(
            constantsVariables_.userSupplySlot
        );
        // extracting user's supply
        if (constantsVariables_.supplyToken.token1 == address(0)) {
            totalSupplyLiquidityOrDex_ =
                (totalSupplyLiquidityOrDex_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) &
                X64;
        } else {
            totalSupplyLiquidityOrDex_ = (totalSupplyLiquidityOrDex_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        }
        // converting big number into normal number
        totalSupplyLiquidityOrDex_ = (totalSupplyLiquidityOrDex_ >> 8) << (totalSupplyLiquidityOrDex_ & X8);

        uint totalBorrowLiquidityOrDex_ = IFluidStorageReadable(constantsVariables_.borrow).readFromStorage(
            constantsVariables_.userBorrowSlot
        );
        // extracting user's borrow
        if (constantsVariables_.borrowToken.token1 == address(0)) {
            totalBorrowLiquidityOrDex_ =
                (totalBorrowLiquidityOrDex_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) &
                X64;
        } else {
            totalBorrowLiquidityOrDex_ = (totalBorrowLiquidityOrDex_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        }
        // converting big number into normal number
        totalBorrowLiquidityOrDex_ = (totalBorrowLiquidityOrDex_ >> 8) << (totalBorrowLiquidityOrDex_ & X8);

        totalSupplyAndBorrow_.totalSupplyVault = (vaultVariables_ >> 82) & X64;
        // Converting bignumber into normal number
        totalSupplyAndBorrow_.totalSupplyVault =
            (totalSupplyAndBorrow_.totalSupplyVault >> 8) <<
            (totalSupplyAndBorrow_.totalSupplyVault & X8);
        totalSupplyAndBorrow_.totalBorrowVault = (vaultVariables_ >> 146) & X64;
        // Converting bignumber into normal number
        totalSupplyAndBorrow_.totalBorrowVault =
            (totalSupplyAndBorrow_.totalBorrowVault >> 8) <<
            (totalSupplyAndBorrow_.totalBorrowVault & X8);

        totalSupplyAndBorrow_.totalSupplyLiquidityOrDex = totalSupplyLiquidityOrDex_;
        totalSupplyAndBorrow_.totalBorrowLiquidityOrDex = totalBorrowLiquidityOrDex_;

        totalSupplyAndBorrow_.absorbedBorrow = absorbedLiquidity_ & X128;
        totalSupplyAndBorrow_.absorbedSupply = absorbedLiquidity_ >> 128;

        unchecked {
            // converting raw total supply & total borrow into normal amounts
            totalSupplyAndBorrow_.totalSupplyVault =
                (totalSupplyAndBorrow_.totalSupplyVault * exchangePricesAndRates_.vaultSupplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            totalSupplyAndBorrow_.totalBorrowVault =
                (totalSupplyAndBorrow_.totalBorrowVault * exchangePricesAndRates_.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;

            // below logic multiply with liquidity exchange price also works for case of smart debt / smart col because
            // liquiditySupplyExchangePrice and liquidityBorrowExchangePrice will be EXCHANGE_PRICES_PRECISION
            totalSupplyAndBorrow_.totalSupplyLiquidityOrDex =
                (totalSupplyAndBorrow_.totalSupplyLiquidityOrDex *
                    exchangePricesAndRates_.liquiditySupplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            totalSupplyAndBorrow_.totalBorrowLiquidityOrDex =
                (totalSupplyAndBorrow_.totalBorrowLiquidityOrDex *
                    exchangePricesAndRates_.liquidityBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;

            totalSupplyAndBorrow_.absorbedSupply =
                (totalSupplyAndBorrow_.absorbedSupply * exchangePricesAndRates_.vaultSupplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            totalSupplyAndBorrow_.absorbedBorrow =
                (totalSupplyAndBorrow_.absorbedBorrow * exchangePricesAndRates_.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
        }
    }

    /// @dev Calculates limits and availability for a user's vault operations.
    /// @param exchangePricesAndRates_ Exchange prices and rates for the vault.
    /// @param constantsVariables_ Constants and variables for the vault.
    /// @param withdrawalGapConfig_ Configuration for the withdrawal gap.
    /// @param borrowLimit_ The borrow limit for the user. Only set if not smart debt.
    /// @param borrowLimitUtilization_ The utilization of the borrow limit. Only set if not smart debt.
    /// @param borrowableUntilLimit_ The limit until which borrowing is allowed. Only set if not smart debt.
    /// @param liquidityUserSupplyData_ User's supply data at Liquidity.
    /// @param liquidityUserBorrowData_ User's borrow data at Liquidity.
    /// @return limitsAndAvailability_ The calculated limits and availability for the user's vault operations.
    /// @return liquidityOrDexUserSupplyData_ The User's supply data at Liquidity OR dex.
    /// @return liquidityOrDexUserSupplyData_ The User's borrow data at Liquidity OR dex.
    function _getLimitsAndAvailability(
        ExchangePricesAndRates memory exchangePricesAndRates_,
        IFluidVault.ConstantViews memory constantsVariables_,
        uint withdrawalGapConfig_,
        uint borrowLimit_,
        uint borrowLimitUtilization_,
        uint borrowableUntilLimit_,
        FluidLiquidityResolverStructs.UserSupplyData memory liquidityUserSupplyData_,
        FluidLiquidityResolverStructs.UserBorrowData memory liquidityUserBorrowData_
    )
        internal
        view
        returns (
            LimitsAndAvailability memory limitsAndAvailability_,
            FluidLiquidityResolverStructs.UserSupplyData memory,
            FluidLiquidityResolverStructs.UserBorrowData memory
        )
    {
        // fetching user's supply slot data
        uint userSupplyLiquidityOrDexData_ = IFluidStorageReadable(constantsVariables_.supply).readFromStorage(
            constantsVariables_.userSupplySlot
        );
        if (userSupplyLiquidityOrDexData_ > 0) {
            {
                uint userSupply_;
                uint supplyLimitRaw_;
                if (constantsVariables_.supply == address(constantsVariables_.liquidity)) {
                    userSupply_ = (userSupplyLiquidityOrDexData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
                    userSupply_ = (userSupply_ >> 8) << (userSupply_ & X8);

                    supplyLimitRaw_ = LiquidityCalcs.calcWithdrawalLimitBeforeOperate(
                        userSupplyLiquidityOrDexData_,
                        userSupply_
                    );

                    userSupply_ = (userSupply_ * exchangePricesAndRates_.liquiditySupplyExchangePrice) /
                        EXCHANGE_PRICES_PRECISION;
                } else {
                    // smart col -> using Dex libraries
                    userSupply_ = (userSupplyLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
                    userSupply_ = (userSupply_ >> 8) << (userSupply_ & X8);

                    supplyLimitRaw_ = DexCalcs.calcWithdrawalLimitBeforeOperate(
                        userSupplyLiquidityOrDexData_,
                        userSupply_
                    );

                    liquidityUserSupplyData_.modeWithInterest = false;
                    liquidityUserSupplyData_.supply = userSupply_;
                    liquidityUserSupplyData_.lastUpdateTimestamp =
                        (userSupplyLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) &
                        X33;
                    liquidityUserSupplyData_.expandPercent =
                        (userSupplyLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) &
                        X14;
                    liquidityUserSupplyData_.expandDuration =
                        (userSupplyLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) &
                        X24;
                }

                unchecked {
                    // liquiditySupplyExchangePrice is EXCHANGE_PRICES_PRECISION in case of smart col
                    limitsAndAvailability_.withdrawLimit =
                        (supplyLimitRaw_ * exchangePricesAndRates_.liquiditySupplyExchangePrice) /
                        EXCHANGE_PRICES_PRECISION;

                    // totalSupplyLiquidityOrDex = user supply
                    limitsAndAvailability_.withdrawableUntilLimit = userSupply_ > limitsAndAvailability_.withdrawLimit
                        ? userSupply_ - limitsAndAvailability_.withdrawLimit
                        : 0;
                }

                if (constantsVariables_.supplyToken.token1 != address(0)) {
                    // mirror limits in liquidityUserSupplyData_, before applying gap, to properly simulate unaltered limits
                    // as coming from Liquidity layer / dex
                    liquidityUserSupplyData_.withdrawalLimit = limitsAndAvailability_.withdrawLimit;
                    // exchange price for SC is 1 so no conversion needed for base withdrawal limit
                    liquidityUserSupplyData_.baseWithdrawalLimit = BigMathMinified.fromBigNumber(
                        (userSupplyLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
                        8,
                        X8
                    );
                    liquidityUserSupplyData_.withdrawableUntilLimit = limitsAndAvailability_.withdrawableUntilLimit;
                    liquidityUserSupplyData_.withdrawable = limitsAndAvailability_.withdrawableUntilLimit;
                }

                unchecked {
                    uint withdrawalGap_ = limitsAndAvailability_.withdrawLimit == 0
                        ? 0 // apply withdrawal gap only if withdraw limit is actually active (not below base limit)
                        : (userSupply_ * withdrawalGapConfig_) / 1e4;

                    limitsAndAvailability_.withdrawableUntilLimit = (limitsAndAvailability_.withdrawableUntilLimit >
                        withdrawalGap_)
                        ? (((limitsAndAvailability_.withdrawableUntilLimit - withdrawalGap_) * 999999) / 1000000)
                        : 0;
                }
            }

            limitsAndAvailability_.withdrawable = limitsAndAvailability_.withdrawableUntilLimit;
            if (constantsVariables_.supplyToken.token1 == address(0)) {
                // NOT smart col -> check withdrawableUntilLimit against available balance at Liquidity
                // if smart col -> must check manually against balances using data returned at DexResolver
                uint balanceOf_;
                if (constantsVariables_.supplyToken.token0 == NATIVE_TOKEN_ADDRESS) {
                    balanceOf_ = address(constantsVariables_.liquidity).balance;
                } else {
                    balanceOf_ = TokenInterface(constantsVariables_.supplyToken.token0).balanceOf(
                        address(constantsVariables_.liquidity)
                    );
                }
                if (balanceOf_ < limitsAndAvailability_.withdrawableUntilLimit) {
                    limitsAndAvailability_.withdrawable = balanceOf_;
                }
            }
        }

        uint userBorrowLiquidityOrDexData_ = IFluidStorageReadable(constantsVariables_.borrow).readFromStorage(
            constantsVariables_.userBorrowSlot
        );
        if (userBorrowLiquidityOrDexData_ > 0) {
            if (constantsVariables_.borrowToken.token1 == address(0)) {
                // NOT smart debt. fetch limit from LiquidityResolver

                limitsAndAvailability_.borrowLimit = borrowLimit_;
                limitsAndAvailability_.borrowLimitUtilization = borrowLimitUtilization_;

                unchecked {
                    limitsAndAvailability_.borrowableUntilLimit = (borrowableUntilLimit_ * 999999) / 1000000;
                }

                uint balanceOf_;
                if (constantsVariables_.borrowToken.token0 == NATIVE_TOKEN_ADDRESS) {
                    balanceOf_ = address(constantsVariables_.liquidity).balance;
                } else {
                    balanceOf_ = TokenInterface(constantsVariables_.borrowToken.token0).balanceOf(
                        address(constantsVariables_.liquidity)
                    );
                }
                limitsAndAvailability_.borrowable = balanceOf_ > limitsAndAvailability_.borrowableUntilLimit
                    ? limitsAndAvailability_.borrowableUntilLimit
                    : balanceOf_;
            } else {
                // smart debt -> using Dex libraries
                uint userBorrow_ = (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
                userBorrow_ = (userBorrow_ >> 8) << (userBorrow_ & X8);

                limitsAndAvailability_.borrowLimit = DexCalcs.calcBorrowLimitBeforeOperate(
                    userBorrowLiquidityOrDexData_,
                    userBorrow_
                );

                unchecked {
                    limitsAndAvailability_.borrowableUntilLimit = limitsAndAvailability_.borrowLimit > userBorrow_
                        ? limitsAndAvailability_.borrowLimit - userBorrow_
                        : 0;

                    limitsAndAvailability_.borrowableUntilLimit =
                        (limitsAndAvailability_.borrowableUntilLimit * 999999) /
                        1000000;
                }

                limitsAndAvailability_.borrowable = limitsAndAvailability_.borrowableUntilLimit;

                liquidityUserBorrowData_.modeWithInterest = false;
                liquidityUserBorrowData_.borrow = userBorrow_;
                liquidityUserBorrowData_.borrowLimit = limitsAndAvailability_.borrowLimit;
                liquidityUserBorrowData_.borrowableUntilLimit = limitsAndAvailability_.borrowableUntilLimit;
                liquidityUserBorrowData_.borrowable = limitsAndAvailability_.borrowable;

                liquidityUserBorrowData_.lastUpdateTimestamp =
                    (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP) &
                    X33;
                liquidityUserBorrowData_.expandPercent =
                    (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) &
                    X14;
                liquidityUserBorrowData_.expandDuration =
                    (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) &
                    X24;

                liquidityUserBorrowData_.baseBorrowLimit = BigMathMinified.fromBigNumber(
                    (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                    8,
                    X8
                );
                liquidityUserBorrowData_.maxBorrowLimit = BigMathMinified.fromBigNumber(
                    (userBorrowLiquidityOrDexData_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                    8,
                    X8
                );
            }
        }

        limitsAndAvailability_.minimumBorrowing =
            (10001 * exchangePricesAndRates_.vaultBorrowExchangePrice) /
            EXCHANGE_PRICES_PRECISION;

        return (limitsAndAvailability_, liquidityUserSupplyData_, liquidityUserBorrowData_);
    }

    /// @notice Retrieves the state of a given vault.
    /// @param vault_ The address of the vault to retrieve the state for.
    /// @return vaultState_ The state of the vault, including top tick, current and total branches,
    ///                     total supply and borrow, total positions, and current branch state.
    function getVaultState(address vault_) public view returns (VaultState memory vaultState_) {
        uint vaultVariables_ = getVaultVariablesRaw(vault_);

        vaultState_.topTick = tickHelper(((vaultVariables_ >> 2) & X20));
        vaultState_.currentBranch = (vaultVariables_ >> 22) & X30;
        vaultState_.totalBranch = (vaultVariables_ >> 52) & X30;
        vaultState_.totalSupply = BigMathMinified.fromBigNumber((vaultVariables_ >> 82) & X64, 8, X8);
        vaultState_.totalBorrow = BigMathMinified.fromBigNumber((vaultVariables_ >> 146) & X64, 8, X8);
        vaultState_.totalPositions = (vaultVariables_ >> 210) & X32;

        uint currentBranchData_ = getBranchDataRaw(vault_, vaultState_.currentBranch);
        vaultState_.currentBranchState.status = currentBranchData_ & 3;
        vaultState_.currentBranchState.minimaTick = tickHelper(((currentBranchData_ >> 2) & X20));
        vaultState_.currentBranchState.debtFactor = (currentBranchData_ >> 116) & X50;
        vaultState_.currentBranchState.partials = (currentBranchData_ >> 22) & X30;
        vaultState_.currentBranchState.debtLiquidity = BigMathMinified.fromBigNumber(
            (currentBranchData_ >> 52) & X64,
            8,
            X8
        );
        vaultState_.currentBranchState.baseBranchId = (currentBranchData_ >> 166) & X30;
        vaultState_.currentBranchState.baseBranchMinima = tickHelper(((currentBranchData_ >> 196) & X20));
    }

    /// @notice Retrieves the entire data for a given vault.
    /// @param vault_ The address of the vault to retrieve the data for.
    /// @return vaultData_ The entire data of the vault.
    function getVaultEntireData(address vault_) public view returns (VaultEntireData memory vaultData_) {
        vaultData_.vault = vault_;
        uint vaultType_ = getVaultType(vault_);

        if (vaultType_ != 0) {
            vaultData_.constantVariables = _getVaultConstants(vault_, vaultType_);

            vaultData_.isSmartCol = vaultData_.constantVariables.supplyToken.token1 != address(0);
            vaultData_.isSmartDebt = vaultData_.constantVariables.borrowToken.token1 != address(0);

            // in case of NOT smart debt, the borrow limits are fetched from liquidity resolver
            uint borrowLimit_;
            uint borrowLimitUtilization_;
            uint borrowableUntilLimit_;

            {
                uint liquiditySupplyRate_;
                uint liquidityBorrowRate_;
                if (!vaultData_.isSmartCol) {
                    // NOT smart col
                    (
                        FluidLiquidityResolverStructs.UserSupplyData memory liquidityUserSupplyData_,
                        FluidLiquidityResolverStructs.OverallTokenData memory liquiditySupplyTokenData_
                    ) = LIQUIDITY_RESOLVER.getUserSupplyData(vault_, vaultData_.constantVariables.supplyToken.token0);

                    vaultData_.liquidityUserSupplyData = liquidityUserSupplyData_;

                    liquiditySupplyRate_ = liquiditySupplyTokenData_.supplyRate;
                }

                if (!vaultData_.isSmartDebt) {
                    // NOT smart debt
                    (
                        FluidLiquidityResolverStructs.UserBorrowData memory liquidityUserBorrowData_,
                        FluidLiquidityResolverStructs.OverallTokenData memory liquidityBorrowTokenData_
                    ) = LIQUIDITY_RESOLVER.getUserBorrowData(vault_, vaultData_.constantVariables.borrowToken.token0);

                    vaultData_.liquidityUserBorrowData = liquidityUserBorrowData_;

                    liquidityBorrowRate_ = liquidityBorrowTokenData_.borrowRate;

                    borrowLimit_ = liquidityUserBorrowData_.borrowLimit;
                    borrowLimitUtilization_ = liquidityUserBorrowData_.borrowLimitUtilization;
                    borrowableUntilLimit_ = liquidityUserBorrowData_.borrowableUntilLimit;
                }

                vaultData_.configs = _getVaultConfig(vault_, vaultData_.constantVariables.vaultType);
                vaultData_.exchangePricesAndRates = _getExchangePricesAndRates(
                    vault_,
                    vaultType_,
                    vaultData_.configs,
                    liquiditySupplyRate_,
                    liquidityBorrowRate_
                );
            }
            vaultData_.totalSupplyAndBorrow = _getTotalSupplyAndBorrow(
                vault_,
                vaultData_.exchangePricesAndRates,
                vaultData_.constantVariables
            );
            (
                vaultData_.limitsAndAvailability,
                vaultData_.liquidityUserSupplyData,
                vaultData_.liquidityUserBorrowData
            ) = _getLimitsAndAvailability(
                vaultData_.exchangePricesAndRates,
                vaultData_.constantVariables,
                vaultData_.configs.withdrawalGap,
                borrowLimit_,
                borrowLimitUtilization_,
                borrowableUntilLimit_,
                vaultData_.liquidityUserSupplyData,
                vaultData_.liquidityUserBorrowData
            );
            vaultData_.vaultState = getVaultState(vault_);
        }
    }

    /// @notice Retrieves the entire data for a list of vaults.
    /// @param vaults_ The list of vault addresses.
    /// @return vaultsData_ An array of VaultEntireData structures containing the data for each vault.
    function getVaultsEntireData(
        address[] memory vaults_
    ) external view returns (VaultEntireData[] memory vaultsData_) {
        uint length_ = vaults_.length;
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i; i < length_; i++) {
            vaultsData_[i] = getVaultEntireData(vaults_[i]);
        }
    }

    /// @notice Retrieves the entire data for all vaults.
    /// @return vaultsData_ An array of VaultEntireData structures containing the data for each vault.
    function getVaultsEntireData() external view returns (VaultEntireData[] memory vaultsData_) {
        address[] memory vaults_ = getAllVaultsAddresses();
        uint length_ = vaults_.length;
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i; i < length_; i++) {
            vaultsData_[i] = getVaultEntireData(vaults_[i]);
        }
    }

    /// @notice Retrieves the position data for a given NFT ID and the corresponding vault data.
    /// @param nftId_ The NFT ID for which to retrieve the position data.
    /// @return userPosition_ The UserPosition structure containing the position data.
    /// @return vaultData_ The VaultEntireData structure containing the vault data.
    function positionByNftId(
        uint nftId_
    ) public view returns (UserPosition memory userPosition_, VaultEntireData memory vaultData_) {
        userPosition_.nftId = nftId_;
        address vault_ = vaultByNftId(nftId_);
        if (vault_ != address(0)) {
            uint positionData_ = getPositionDataRaw(vault_, nftId_);
            vaultData_ = getVaultEntireData(vault_);

            userPosition_.owner = FACTORY.ownerOf(nftId_);
            userPosition_.isSupplyPosition = (positionData_ & 1) == 1;
            userPosition_.supply = (positionData_ >> 45) & X64;
            // Converting big number into normal number
            userPosition_.supply = (userPosition_.supply >> 8) << (userPosition_.supply & X8);
            userPosition_.beforeSupply = userPosition_.supply;
            userPosition_.dustBorrow = (positionData_ >> 109) & X64;
            // Converting big number into normal number
            userPosition_.dustBorrow = (userPosition_.dustBorrow >> 8) << (userPosition_.dustBorrow & X8);
            userPosition_.beforeDustBorrow = userPosition_.dustBorrow;
            if (!userPosition_.isSupplyPosition) {
                userPosition_.tick = (positionData_ & 2) == 2
                    ? int((positionData_ >> 2) & X19)
                    : -int((positionData_ >> 2) & X19);
                userPosition_.tickId = (positionData_ >> 21) & X24;
                userPosition_.borrow =
                    (TickMath.getRatioAtTick(int24(userPosition_.tick)) * userPosition_.supply) >>
                    96;
                userPosition_.beforeBorrow = userPosition_.borrow - userPosition_.beforeDustBorrow;

                uint tickData_ = getTickDataRaw(vault_, userPosition_.tick);

                if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > userPosition_.tickId)) {
                    // user got liquidated
                    userPosition_.isLiquidated = true;
                    (userPosition_.tick, userPosition_.borrow, userPosition_.supply, , ) = IFluidVault(vault_)
                        .fetchLatestPosition(userPosition_.tick, userPosition_.tickId, userPosition_.borrow, tickData_);
                }

                if (userPosition_.borrow > userPosition_.dustBorrow) {
                    userPosition_.borrow = userPosition_.borrow - userPosition_.dustBorrow;
                } else {
                    userPosition_.borrow = 0;
                    userPosition_.dustBorrow = 0;
                }
            }

            // converting raw amounts into normal
            userPosition_.beforeSupply =
                (userPosition_.beforeSupply * vaultData_.exchangePricesAndRates.vaultSupplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userPosition_.beforeBorrow =
                (userPosition_.beforeBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userPosition_.beforeDustBorrow =
                (userPosition_.beforeDustBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userPosition_.supply =
                (userPosition_.supply * vaultData_.exchangePricesAndRates.vaultSupplyExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userPosition_.borrow =
                (userPosition_.borrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
            userPosition_.dustBorrow =
                (userPosition_.dustBorrow * vaultData_.exchangePricesAndRates.vaultBorrowExchangePrice) /
                EXCHANGE_PRICES_PRECISION;
        }
    }

    /// @notice Returns an array of NFT IDs for all positions of a given user.
    /// @param user_ The address of the user for whom to fetch positions.
    /// @return nftIds_ An array of NFT IDs representing the user's positions.
    function positionsNftIdOfUser(address user_) public view returns (uint[] memory nftIds_) {
        uint totalPositions_ = FACTORY.balanceOf(user_);
        nftIds_ = new uint[](totalPositions_);
        for (uint i; i < totalPositions_; i++) {
            nftIds_[i] = FACTORY.tokenOfOwnerByIndex(user_, i);
        }
    }

    /// @notice Returns the vault address associated with a given NFT ID.
    /// @param nftId_ The NFT ID for which to fetch the vault address.
    /// @return vault_ The address of the vault associated with the NFT ID.
    function vaultByNftId(uint nftId_) public view returns (address vault_) {
        uint tokenConfig_ = getTokenConfig(nftId_);
        vault_ = FACTORY.getVaultAddress((tokenConfig_ >> 192) & X32);
    }

    /// @notice Fetches all positions and their corresponding vault data for a given user.
    /// @param user_ The address of the user for whom to fetch positions and vault data.
    /// @return userPositions_ An array of UserPosition structs representing the user's positions.
    /// @return vaultsData_ An array of VaultEntireData structs representing the vault data for each position.
    function positionsByUser(
        address user_
    ) external view returns (UserPosition[] memory userPositions_, VaultEntireData[] memory vaultsData_) {
        uint[] memory nftIds_ = positionsNftIdOfUser(user_);
        uint length_ = nftIds_.length;
        userPositions_ = new UserPosition[](length_);
        vaultsData_ = new VaultEntireData[](length_);
        for (uint i = 0; i < length_; i++) {
            (userPositions_[i], vaultsData_[i]) = positionByNftId(nftIds_[i]);
        }
    }

    /// @notice Returns the total number of positions across all users.
    /// @return The total number of positions.
    function totalPositions() external view returns (uint) {
        return FACTORY.totalSupply();
    }

    /// @notice fetches available liquidations
    /// @param vault_ address of vault for which to fetch
    /// @param tokenInAmt_ token in aka debt to payback, leave 0 to get max
    /// @return liquidationData_ liquidation related data. Check out structs.sol
    function getVaultLiquidation(
        address vault_,
        uint tokenInAmt_
    ) public returns (LiquidationStruct memory liquidationData_) {
        tokenInAmt_ = tokenInAmt_ == 0 ? X128 : tokenInAmt_;

        uint vaultType_ = getVaultType(vault_);
        if (vaultType_ != 0) {
            liquidationData_.vault = vault_;
            IFluidVault.ConstantViews memory constants_ = _getVaultConstants(vault_, vaultType_);

            if (constants_.vaultType == FluidProtocolTypes.VAULT_T1_TYPE) {
                liquidationData_.token0In = constants_.borrowToken.token0;
                liquidationData_.token0Out = constants_.supplyToken.token0;

                // running without absorb
                try IFluidVaultT1(vault_).liquidate(tokenInAmt_, 0, 0x000000000000000000000000000000000000dEaD, false) {
                    // Handle successful execution
                } catch Error(string memory) {
                    // Handle generic errors with a reason
                } catch (bytes memory lowLevelData_) {
                    (liquidationData_.inAmt, liquidationData_.outAmt) = _decodeLiquidationResult(lowLevelData_);
                }

                // running with absorb
                try IFluidVaultT1(vault_).liquidate(tokenInAmt_, 0, 0x000000000000000000000000000000000000dEaD, true) {
                    // Handle successful execution
                } catch Error(string memory) {
                    // Handle generic errors with a reason
                } catch (bytes memory lowLevelData_) {
                    (liquidationData_.inAmtWithAbsorb, liquidationData_.outAmtWithAbsorb) = _decodeLiquidationResult(
                        lowLevelData_
                    );
                }
            } else {
                liquidationData_.token0In = constants_.borrowToken.token0;
                liquidationData_.token0Out = constants_.supplyToken.token0;
                liquidationData_.token1In = constants_.borrowToken.token1;
                liquidationData_.token1Out = constants_.supplyToken.token1;

                // running without absorb
                try IFluidVault(vault_).simulateLiquidate(0, false) {
                    // Handle successful execution
                } catch Error(string memory) {
                    // Handle generic errors with a reason
                } catch (bytes memory lowLevelData_) {
                    (liquidationData_.inAmt, liquidationData_.outAmt) = _decodeLiquidationResult(lowLevelData_);
                }

                // running with absorb
                try IFluidVault(vault_).simulateLiquidate(0, true) {
                    // Handle successful execution
                } catch Error(string memory) {
                    // Handle generic errors with a reason
                } catch (bytes memory lowLevelData_) {
                    (liquidationData_.inAmtWithAbsorb, liquidationData_.outAmtWithAbsorb) = _decodeLiquidationResult(
                        lowLevelData_
                    );
                }
            }

            liquidationData_.absorbAvailable =
                liquidationData_.inAmtWithAbsorb > liquidationData_.inAmt ||
                liquidationData_.outAmtWithAbsorb > liquidationData_.outAmt;
        }
    }

    /// @dev helper method to decode liquidation result revert data
    function _decodeLiquidationResult(bytes memory lowLevelData_) internal pure returns (uint amtIn_, uint amtOut_) {
        // Check if the error data is long enough to contain a selector
        if (lowLevelData_.length >= 68) {
            bytes4 errorSelector_;
            assembly {
                // Extract the selector from the error data
                errorSelector_ := mload(add(lowLevelData_, 0x20))
            }
            if (errorSelector_ == IFluidVault.FluidLiquidateResult.selector) {
                assembly {
                    amtOut_ := mload(add(lowLevelData_, 36))
                    amtIn_ := mload(add(lowLevelData_, 68))
                }
            } // else -> tokenInAmtTwo & tokenOutAmtTwo remains 0
        }
    }

    /// @notice Retrieves liquidation data for multiple vaults.
    /// @param vaults_ The array of vault addresses.
    /// @param tokensInAmt_ The array of token amounts to liquidate.
    /// @return liquidationsData_ An array of LiquidationStruct containing the liquidation data for each vault.
    function getMultipleVaultsLiquidation(
        address[] memory vaults_,
        uint[] memory tokensInAmt_
    ) external returns (LiquidationStruct[] memory liquidationsData_) {
        uint length_ = vaults_.length;
        liquidationsData_ = new LiquidationStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            liquidationsData_[i] = getVaultLiquidation(vaults_[i], tokensInAmt_[i]);
        }
    }

    /// @notice Retrieves liquidation data for all vaults.
    /// @return liquidationsData_ An array of LiquidationStruct containing the liquidation data for all vaults.
    function getAllVaultsLiquidation() external returns (LiquidationStruct[] memory liquidationsData_) {
        address[] memory vaults_ = getAllVaultsAddresses();
        uint length_ = vaults_.length;

        liquidationsData_ = new LiquidationStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            liquidationsData_[i] = getVaultLiquidation(vaults_[i], 0);
        }
    }

    /// @notice DEPRECATED, only works for vaults v1.0.0: Retrieves absorb data for a single vault.
    /// @param vault_ The address of the vault.
    /// @return absorbData_ The AbsorbStruct containing the absorb data for the vault.
    function getVaultAbsorb(address vault_) public returns (AbsorbStruct memory absorbData_) {
        absorbData_.vault = vault_;
        uint absorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
        try IFluidVaultT1(vault_).absorb() {
            // Handle successful execution
            uint newAbsorbedLiquidity_ = getAbsorbedLiquidityRaw(vault_);
            if (newAbsorbedLiquidity_ != absorbedLiquidity_) {
                absorbData_.absorbAvailable = true;
            }
        } catch Error(string memory) {} catch (bytes memory) {}
    }

    /// @notice DEPRECATED, only works for vaults v1.0.0: Retrieves absorb data for multiple vaults.
    /// @param vaults_ The array of vault addresses.
    /// @return absorbData_ An array of AbsorbStruct containing the absorb data for each vault.
    function getVaultsAbsorb(address[] memory vaults_) public returns (AbsorbStruct[] memory absorbData_) {
        uint length_ = vaults_.length;
        absorbData_ = new AbsorbStruct[](length_);
        for (uint i = 0; i < length_; i++) {
            absorbData_[i] = getVaultAbsorb(vaults_[i]);
        }
    }

    /// @notice DEPRECATED, only works for vaults v1.0.0: Retrieves absorb data for all vaults.
    /// @return absorbData_ An array of AbsorbStruct containing the absorb data for all vaults.
    function getVaultsAbsorb() public returns (AbsorbStruct[] memory absorbData_) {
        return getVaultsAbsorb(getAllVaultsAddresses());
    }
}
