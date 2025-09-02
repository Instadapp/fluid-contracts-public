// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { BytesSliceAndConcat } from "../../../libraries/bytesSliceAndConcat.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

interface TokenInterface {
    function balanceOf(address) external view returns (uint);
}

/// @title DexFactoryViews
/// @notice Abstract contract providing view functions for DEX factory-related operations
abstract contract DexFactoryViews is Variables {
    /// @notice Get the address of a Pool given its ID
    /// @param poolId_ The ID of the Pool
    /// @return pool_ The address of the Pool
    function getPoolAddress(uint256 poolId_) public view returns (address pool_) {
        return AddressCalcs.addressCalc(address(FACTORY), poolId_);
    }

    /// @notice Get the total number of Pools
    /// @return The total number of Pools
    function getTotalPools() public view returns (uint) {
        return FACTORY.totalDexes();
    }

    /// @notice Get an array of all Pool addresses
    /// @return pools_ An array containing all Pool addresses
    function getAllPoolAddresses() public view returns (address[] memory pools_) {
        uint totalPools_ = getTotalPools();
        pools_ = new address[](totalPools_);
        for (uint i = 0; i < totalPools_; i++) {
            pools_[i] = getPoolAddress((i + 1));
        }
    }
}

/// @title DexPublicViews
/// @notice Abstract contract providing view functions for DEX public data
abstract contract DexPublicViews {
    /// @notice Get the prices and exchange prices for a DEX
    /// @param dex_ The address of the DEX
    /// @return pex_ A struct containing prices and exchange prices
    /// @dev expected to be called via callStatic
    function getDexPricesAndExchangePrices(
        address dex_
    ) public returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
        try IFluidDexT1(dex_).getPricesAndExchangePrices() {} catch (bytes memory lowLevelData_) {
            bytes4 errorSelector_;
            assembly {
                // Extract the selector from the error data
                errorSelector_ := mload(add(lowLevelData_, 0x20))
            }
            if (errorSelector_ == IFluidDexT1.FluidDexPricesAndExchangeRates.selector) {
                pex_ = abi.decode(
                    BytesSliceAndConcat.bytesSlice(lowLevelData_, 4, lowLevelData_.length - 4),
                    (IFluidDexT1.PricesAndExchangePrice)
                );
            }
        }
    }

    /// @notice Get the collateral reserves for a DEX in token decimals amounts
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing collateral reserve information
    /// @dev expected to be called via callStatic
    function getDexCollateralReserves(address dex_) public returns (IFluidDexT1.CollateralReserves memory reserves_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        if ((dexVariables2_ & 1) != 1) {
            // smart col not enabled
            return IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }

        try this.getDexPricesAndExchangePrices(dex_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            reserves_ = _getDexCollateralReserves(dex_, pex_);
        } catch {
            reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }
    }

    /// @notice Get the collateral reserves for a DEX scaled to 1e12
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing collateral reserve information
    /// @dev expected to be called via callStatic
    function getDexCollateralReservesAdjusted(
        address dex_
    ) public returns (IFluidDexT1.CollateralReserves memory reserves_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        if ((dexVariables2_ & 1) != 1) {
            // smart col not enabled
            return IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }

        try this.getDexPricesAndExchangePrices(dex_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            reserves_ = _getDexCollateralReservesAdjusted(dex_, pex_);
        } catch {
            reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }
    }

    /// @notice Get the debt reserves for a DEX in token decimals amounts
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing debt reserve information
    /// @dev expected to be called via callStatic
    function getDexDebtReserves(address dex_) public returns (IFluidDexT1.DebtReserves memory reserves_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        if ((dexVariables2_ & 2) != 2) {
            // smart debt not enabled
            return IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }

        try this.getDexPricesAndExchangePrices(dex_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            reserves_ = _getDexDebtReserves(dex_, pex_);
        } catch {
            reserves_ = IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }
    }

    /// @notice Get the debt reserves for a DEX scaled to 1e12
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing debt reserve information
    /// @dev expected to be called via callStatic
    function getDexDebtReservesAdjusted(address dex_) public returns (IFluidDexT1.DebtReserves memory reserves_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        if ((dexVariables2_ & 2) != 2) {
            // smart debt not enabled
            return IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }

        try this.getDexPricesAndExchangePrices(dex_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            reserves_ = _getDexDebtReservesAdjusted(dex_, pex_);
        } catch {
            reserves_ = IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }
    }

    /// @dev Retrieves and normalizes the collateral reserves for a given DEX.
    /// @param dex_ The address of the DEX.
    /// @param pex_ A struct containing price and exchange price information.
    /// @return reserves_ A struct containing the normalized collateral reserves.
    function _getDexCollateralReserves(
        address dex_,
        IFluidDexT1.PricesAndExchangePrice memory pex_
    ) internal view returns (IFluidDexT1.CollateralReserves memory reserves_) {
        reserves_ = _getDexCollateralReservesAdjusted(dex_, pex_);

        IFluidDexT1.ConstantViews2 memory constantsView2_ = IFluidDexT1(dex_).constantsView2();

        // returned reserves are in 1e12 decimals -> normalize to token decimals
        reserves_.token0RealReserves =
            (reserves_.token0RealReserves * constantsView2_.token0DenominatorPrecision) /
            constantsView2_.token0NumeratorPrecision;
        reserves_.token0ImaginaryReserves =
            (reserves_.token0ImaginaryReserves * constantsView2_.token0DenominatorPrecision) /
            constantsView2_.token0NumeratorPrecision;
        reserves_.token1RealReserves =
            (reserves_.token1RealReserves * constantsView2_.token1DenominatorPrecision) /
            constantsView2_.token1NumeratorPrecision;
        reserves_.token1ImaginaryReserves =
            (reserves_.token1ImaginaryReserves * constantsView2_.token1DenominatorPrecision) /
            constantsView2_.token1NumeratorPrecision;
    }

    /// @dev Retrieves the adjusted collateral reserves for a given DEX.
    /// @param dex_ The address of the DEX.
    /// @param pex_ A struct containing price and exchange price information.
    /// @return reserves_ A struct containing the adjusted collateral reserves.
    function _getDexCollateralReservesAdjusted(
        address dex_,
        IFluidDexT1.PricesAndExchangePrice memory pex_
    ) internal view returns (IFluidDexT1.CollateralReserves memory reserves_) {
        try
            IFluidDexT1(dex_).getCollateralReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.supplyToken0ExchangePrice,
                pex_.supplyToken1ExchangePrice
            )
        returns (IFluidDexT1.CollateralReserves memory colReserves_) {
            // returned reserves are in 1e12 decimals -> normalize to token decimals
            reserves_ = colReserves_;
        } catch {
            reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }
    }

    /// @dev Retrieves and normalizes the debt reserves for a given DEX.
    /// @param dex_ The address of the DEX.
    /// @param pex_ A struct containing price and exchange price information.
    /// @return reserves_ A struct containing the normalized debt reserves.
    function _getDexDebtReserves(
        address dex_,
        IFluidDexT1.PricesAndExchangePrice memory pex_
    ) internal view returns (IFluidDexT1.DebtReserves memory reserves_) {
        reserves_ = _getDexDebtReservesAdjusted(dex_, pex_);

        IFluidDexT1.ConstantViews2 memory constantsView2_ = IFluidDexT1(dex_).constantsView2();

        // returned reserves are in 1e12 decimals -> normalize to token decimals
        reserves_.token0Debt =
            (reserves_.token0Debt * constantsView2_.token0DenominatorPrecision) /
            constantsView2_.token0NumeratorPrecision;
        reserves_.token0RealReserves =
            (reserves_.token0RealReserves * constantsView2_.token0DenominatorPrecision) /
            constantsView2_.token0NumeratorPrecision;
        reserves_.token0ImaginaryReserves =
            (reserves_.token0ImaginaryReserves * constantsView2_.token0DenominatorPrecision) /
            constantsView2_.token0NumeratorPrecision;
        reserves_.token1Debt =
            (reserves_.token1Debt * constantsView2_.token1DenominatorPrecision) /
            constantsView2_.token1NumeratorPrecision;
        reserves_.token1RealReserves =
            (reserves_.token1RealReserves * constantsView2_.token1DenominatorPrecision) /
            constantsView2_.token1NumeratorPrecision;
        reserves_.token1ImaginaryReserves =
            (reserves_.token1ImaginaryReserves * constantsView2_.token1DenominatorPrecision) /
            constantsView2_.token1NumeratorPrecision;
    }

    /// @dev Retrieves the adjusted debt reserves for a given DEX.
    /// @param dex_ The address of the DEX.
    /// @param pex_ A struct containing price and exchange price information.
    /// @return reserves_ A struct containing the adjusted debt reserves.
    function _getDexDebtReservesAdjusted(
        address dex_,
        IFluidDexT1.PricesAndExchangePrice memory pex_
    ) internal view returns (IFluidDexT1.DebtReserves memory reserves_) {
        try
            IFluidDexT1(dex_).getDebtReserves(
                pex_.geometricMean,
                pex_.upperRange,
                pex_.lowerRange,
                pex_.borrowToken0ExchangePrice,
                pex_.borrowToken1ExchangePrice
            )
        returns (IFluidDexT1.DebtReserves memory debtReserves_) {
            // returned reserves are in 1e12 decimals -> normalize to token decimals
            reserves_ = debtReserves_;
        } catch {
            reserves_ = IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }
    }
}

/// @title DexConstantsViews
/// @notice Abstract contract providing view functions for DEX constants
abstract contract DexConstantsViews {
    /// @notice returns all Pool constants
    function getPoolConstantsView(address pool_) public view returns (IFluidDexT1.ConstantViews memory constantsView_) {
        return IFluidDexT1(pool_).constantsView();
    }

    /// @notice returns all Pool constants 2
    function getPoolConstantsView2(
        address pool_
    ) public view returns (IFluidDexT1.ConstantViews2 memory constantsView2_) {
        return IFluidDexT1(pool_).constantsView2();
    }

    /// @notice Get the addresses of the tokens in a Pool
    /// @param pool_ The address of the Pool
    /// @return token0_ The address of token0 in the Pool
    /// @return token1_ The address of token1 in the Pool
    function getPoolTokens(address pool_) public view returns (address token0_, address token1_) {
        IFluidDexT1.ConstantViews memory constantsView_ = IFluidDexT1(pool_).constantsView();
        return (constantsView_.token0, constantsView_.token1);
    }
}

abstract contract DexSwapLimits is Variables, Structs, DexConstantsViews {
    /// @notice get the swap limits for a DEX
    /// @param dex_ The address of the DEX
    /// @return limits_ A struct containing the swap limits for the DEX
    function getDexLimits(address dex_) public view returns (DexLimits memory limits_) {
        // additional liquidity related data such as supply amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserSupplyData memory liquidityUserSupplyDataToken0_;
        FluidLiquidityResolverStructs.UserSupplyData memory liquidityUserSupplyDataToken1_;
        // liquidity token related data
        FluidLiquidityResolverStructs.OverallTokenData memory liquidityTokenData0_;
        FluidLiquidityResolverStructs.OverallTokenData memory liquidityTokenData1_;
        // additional liquidity related data such as borrow amount, limits, expansion etc.
        FluidLiquidityResolverStructs.UserBorrowData memory liquidityUserBorrowDataToken0_;
        FluidLiquidityResolverStructs.UserBorrowData memory liquidityUserBorrowDataToken1_;

        {
            (address token0_, address token1_) = getPoolTokens(dex_);
            (liquidityUserSupplyDataToken0_, liquidityTokenData0_) = LIQUIDITY_RESOLVER.getUserSupplyData(
                dex_,
                token0_
            );
            (liquidityUserSupplyDataToken1_, liquidityTokenData1_) = LIQUIDITY_RESOLVER.getUserSupplyData(
                dex_,
                token1_
            );
            (liquidityUserBorrowDataToken0_, ) = LIQUIDITY_RESOLVER.getUserBorrowData(dex_, token0_);
            (liquidityUserBorrowDataToken1_, ) = LIQUIDITY_RESOLVER.getUserBorrowData(dex_, token1_);

            // ----------------------- 1. UTILIZATION LIMITS (include liquidity layer balances) -----------------------
            // for dex, utilization limit check is not just after borrow but also after withdraw (after any swap).
            // for liquidity, utilization limit check is only after borrow.
            // so for borrow, use utilization config of either liquidity or dex, whatever is smaller. for withdraw, use dex.

            uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
            /// Next 10 bits => 228-237 => utilization limit of token0. Max value 1000 = 100%, if 100% then no need to check the utilization.
            /// Next 10 bits => 238-247 => utilization limit of token1. Max value 1000 = 100%, if 100% then no need to check the utilization.
            {
                // TOKEN 0
                uint256 maxUtilizationToken0Dex_ = ((dexVariables2_ >> 228) & X10) * 10; // bring to 1e2 same as liquidity layer
                // check if max utilization at liquidity layer is smaller for combined config
                uint256 maxUtilizationToken0Combined_ = maxUtilizationToken0Dex_;
                if (liquidityTokenData0_.maxUtilization < maxUtilizationToken0Combined_) {
                    maxUtilizationToken0Combined_ = liquidityTokenData0_.maxUtilization;
                }

                // calculate utilization limit amount % of total supply (with combined config for borrow)
                uint256 maxUtilizationToken0_ = (liquidityTokenData0_.totalSupply * maxUtilizationToken0Combined_) /
                    1e4;

                if (liquidityTokenData0_.totalBorrow < maxUtilizationToken0_) {
                    // expands to & available: amount until utilization max
                    // get amount where currently borrowed = utilization limit of total supply. for withdraw only dex config counts.
                    limits_.withdrawableToken0.available = maxUtilizationToken0Dex_ == 0
                        ? 0
                        : (1e4 * liquidityTokenData0_.totalBorrow) / maxUtilizationToken0Dex_;
                    limits_.withdrawableToken0.available = liquidityTokenData0_.totalSupply >
                        limits_.withdrawableToken0.available
                        ? liquidityTokenData0_.totalSupply - limits_.withdrawableToken0.available
                        : 0;
                    // no expansion on utilization
                    limits_.withdrawableToken0.expandsTo = limits_.withdrawableToken0.available;

                    limits_.borrowableToken0.available = maxUtilizationToken0_ - liquidityTokenData0_.totalBorrow;
                    // no expansion on utilization
                    limits_.borrowableToken0.expandsTo = limits_.borrowableToken0.available;

                    // balance at liquidity layer is a hard limit that can not be expanded beyond
                    uint balanceLiquidity_ = token0_ == NATIVE_TOKEN_ADDRESS
                        ? address(LIQUIDITY).balance
                        : TokenInterface(token0_).balanceOf(address(LIQUIDITY));
                    if (limits_.withdrawableToken0.expandsTo > balanceLiquidity_) {
                        limits_.withdrawableToken0.expandsTo = balanceLiquidity_;
                    }
                    if (limits_.borrowableToken0.expandsTo > balanceLiquidity_) {
                        limits_.borrowableToken0.expandsTo = balanceLiquidity_;
                    }
                }
            }

            {
                // TOKEN 1
                uint256 maxUtilizationToken1Dex_ = ((dexVariables2_ >> 238) & X10) * 10;
                uint256 maxUtilizationToken1Combined_ = maxUtilizationToken1Dex_;
                if (liquidityTokenData1_.maxUtilization < maxUtilizationToken1Combined_) {
                    maxUtilizationToken1Combined_ = liquidityTokenData1_.maxUtilization;
                }
                uint256 maxUtilizationToken1_ = (liquidityTokenData1_.totalSupply * maxUtilizationToken1Combined_) /
                    1e4;
                if (liquidityTokenData1_.totalBorrow < maxUtilizationToken1_) {
                    // expands to & available: amount until utilization max
                    // get amount where currently borrowed = utilization limit of total supply. for withdraw only dex config counts.
                    limits_.withdrawableToken1.available = maxUtilizationToken1Dex_ == 0
                        ? 0
                        : (1e4 * liquidityTokenData1_.totalBorrow) / maxUtilizationToken1Dex_;
                    limits_.withdrawableToken1.available = liquidityTokenData1_.totalSupply >
                        limits_.withdrawableToken1.available
                        ? liquidityTokenData1_.totalSupply - limits_.withdrawableToken1.available
                        : 0;
                    // no expansion on utilization
                    limits_.withdrawableToken1.expandsTo = limits_.withdrawableToken1.available;

                    limits_.borrowableToken1.available = maxUtilizationToken1_ - liquidityTokenData1_.totalBorrow;
                    // no expansion on utilization
                    limits_.borrowableToken1.expandsTo = limits_.borrowableToken1.available;

                    // balance at liquidity layer is a hard limit that can not be expanded beyond
                    uint balanceLiquidity_ = token1_ == NATIVE_TOKEN_ADDRESS
                        ? address(LIQUIDITY).balance
                        : TokenInterface(token1_).balanceOf(address(LIQUIDITY));
                    if (limits_.withdrawableToken1.expandsTo > balanceLiquidity_) {
                        limits_.withdrawableToken1.expandsTo = balanceLiquidity_;
                    }
                    if (limits_.borrowableToken1.expandsTo > balanceLiquidity_) {
                        limits_.borrowableToken1.expandsTo = balanceLiquidity_;
                    }
                }
            }
        }

        // ----------------------- 2. WITHDRAW AND BORROW LIMITS (include liquidity layer balances) -----------------------

        // expandsTo = max possible amount at full expansion
        // expandDuration = time of expandDuration config left until maxExpansion is reached

        // TOKEN 0 WITHDRAWABLE
        {
            uint256 expandTimeLeft_ = liquidityUserSupplyDataToken0_.lastUpdateTimestamp +
                liquidityUserSupplyDataToken0_.expandDuration;
            expandTimeLeft_ = block.timestamp > expandTimeLeft_ ? 0 : expandTimeLeft_ - block.timestamp;

            uint256 maxWithdrawable_ = (liquidityUserSupplyDataToken0_.expandPercent *
                liquidityUserSupplyDataToken0_.supply) / 1e4;
            if (liquidityUserSupplyDataToken0_.withdrawable > maxWithdrawable_) {
                // max expansion already reached or below base limit
                maxWithdrawable_ = liquidityUserSupplyDataToken0_.withdrawable;
                expandTimeLeft_ = 0;
            }

            if (maxWithdrawable_ <= limits_.withdrawableToken0.expandsTo) {
                // if max withdrawable until limit is less than utilization limit, then set max withdrawable until limit as expansion limit.
                limits_.withdrawableToken0.expandsTo = maxWithdrawable_;

                expandTimeLeft_ = maxWithdrawable_ == 0
                    ? 0
                    : ((limits_.withdrawableToken0.expandsTo - liquidityUserSupplyDataToken0_.withdrawable) *
                        liquidityUserSupplyDataToken0_.expandDuration) / maxWithdrawable_;
            } else {
                // max withdrawable expansion is limited by utilization or liquidity layer balance.
                // recalculate the duration until that earlier limit is hit.
                if (liquidityUserSupplyDataToken0_.withdrawable > limits_.withdrawableToken0.expandsTo) {
                    // withdrawable amount at LiquidityResolver does not have dex utilization limit included
                    // so this case could actually happen. if so, then adjust withdrawable and expansion is already
                    // max reached so duration left is 0.
                    expandTimeLeft_ = 0;
                    liquidityUserSupplyDataToken0_.withdrawable = limits_.withdrawableToken0.expandsTo;
                } else {
                    // expansionPerSecond_ = maxWithdrawable_ / expandDuration;
                    // withdrawable + expansionPerSecond_ * x = expandsTo;
                    // so x = (expandsTo - withdrawable) / expansionPerSecond_;
                    // so x = (expandsTo - withdrawable) / (maxWithdrawable_ / expandDuration);
                    // so x = (expandsTo - withdrawable) * expandDuration / maxWithdrawable_;
                    expandTimeLeft_ = maxWithdrawable_ == 0
                        ? 0
                        : ((limits_.withdrawableToken0.expandsTo - liquidityUserSupplyDataToken0_.withdrawable) *
                            liquidityUserSupplyDataToken0_.expandDuration) / maxWithdrawable_;
                }
            }
            limits_.withdrawableToken0.expandDuration = expandTimeLeft_;
        }

        // TOKEN 1 WITHDRAWABLE
        {
            uint256 expandTimeLeft_ = liquidityUserSupplyDataToken1_.lastUpdateTimestamp +
                liquidityUserSupplyDataToken1_.expandDuration;
            expandTimeLeft_ = block.timestamp > expandTimeLeft_ ? 0 : expandTimeLeft_ - block.timestamp;

            uint256 maxWithdrawable_ = (liquidityUserSupplyDataToken1_.expandPercent *
                liquidityUserSupplyDataToken1_.supply) / 1e4;
            if (liquidityUserSupplyDataToken1_.withdrawable > maxWithdrawable_) {
                // max expansion already reached or below base limit
                maxWithdrawable_ = liquidityUserSupplyDataToken1_.withdrawable;
                expandTimeLeft_ = 0;
            }

            if (maxWithdrawable_ <= limits_.withdrawableToken1.expandsTo) {
                // if max withdrawable until limit is less than utilization limit, then set max withdrawable until limit as expansion limit.
                limits_.withdrawableToken1.expandsTo = maxWithdrawable_;

                expandTimeLeft_ = maxWithdrawable_ == 0
                    ? 0
                    : ((limits_.withdrawableToken1.expandsTo - liquidityUserSupplyDataToken1_.withdrawable) *
                        liquidityUserSupplyDataToken1_.expandDuration) / maxWithdrawable_;
            } else {
                // max withdrawable expansion is limited by utilization or liquidity layer balance.
                // recalculate the duration until that earlier limit is hit.
                if (liquidityUserSupplyDataToken1_.withdrawable > limits_.withdrawableToken1.expandsTo) {
                    // withdrawable amount at LiquidityResolver does not have dex utilization limit included
                    // so this case could actually happen. if so, then adjust withdrawable and expansion is already
                    // max reached so duration left is 0.
                    expandTimeLeft_ = 0;
                    liquidityUserSupplyDataToken1_.withdrawable = limits_.withdrawableToken1.expandsTo;
                } else {
                    expandTimeLeft_ = maxWithdrawable_ == 0
                        ? 0
                        : ((limits_.withdrawableToken1.expandsTo - liquidityUserSupplyDataToken1_.withdrawable) *
                            liquidityUserSupplyDataToken1_.expandDuration) / maxWithdrawable_;
                }
            }
            limits_.withdrawableToken1.expandDuration = expandTimeLeft_;
        }

        // TOKEN 0 BORROWABLE
        {
            uint256 expandTimeLeft_ = liquidityUserBorrowDataToken0_.lastUpdateTimestamp +
                liquidityUserBorrowDataToken0_.expandDuration;
            expandTimeLeft_ = block.timestamp > expandTimeLeft_ ? 0 : expandTimeLeft_ - block.timestamp;

            uint256 maxBorrowable_ = (liquidityUserBorrowDataToken0_.expandPercent *
                liquidityUserBorrowDataToken0_.borrow) / 1e4;
            {
                // consider max hard borrow limit
                uint256 maxBorrowableUntilHardLimit_ = liquidityUserBorrowDataToken0_.maxBorrowLimit >
                    liquidityUserBorrowDataToken0_.borrow
                    ? liquidityUserBorrowDataToken0_.maxBorrowLimit - liquidityUserBorrowDataToken0_.borrow
                    : 0;
                if (limits_.borrowableToken0.expandsTo > maxBorrowableUntilHardLimit_) {
                    limits_.borrowableToken0.expandsTo = maxBorrowableUntilHardLimit_;
                }
            }
            if (liquidityUserBorrowDataToken0_.borrowable > maxBorrowable_) {
                // max expansion already reached or below base limit
                maxBorrowable_ = liquidityUserBorrowDataToken0_.borrowable;
                expandTimeLeft_ = 0;
            }

            if (maxBorrowable_ <= limits_.borrowableToken0.expandsTo) {
                // if max borrowable until limit is less than utilization limit, then set max borrowable until limit as expansion limit.
                limits_.borrowableToken0.expandsTo = maxBorrowable_;

                // expansionPerSecond_ = maxBorrowable_ / expandDuration;
                // borrowable + expansionPerSecond_ * x = expandsTo;
                expandTimeLeft_ = maxBorrowable_ == 0
                    ? 0
                    : ((limits_.borrowableToken0.expandsTo - liquidityUserBorrowDataToken0_.borrowable) *
                        liquidityUserBorrowDataToken0_.expandDuration) / maxBorrowable_;
            } else {
                // max borrowable expansion is limited by utilization or liquidity layer balance.
                // recalculate the duration until that earlier limit is hit.
                if (liquidityUserBorrowDataToken0_.borrowable > limits_.borrowableToken0.expandsTo) {
                    // borrowable amount at LiquidityResolver does not have dex utilization limit included
                    // so this case could actually happen. if so, then adjust borrowable and expansion is already
                    // max reached so duration left is 0.
                    expandTimeLeft_ = 0;
                    liquidityUserBorrowDataToken0_.borrowable = limits_.borrowableToken0.expandsTo;
                } else {
                    expandTimeLeft_ = maxBorrowable_ == 0
                        ? 0
                        : ((limits_.borrowableToken0.expandsTo - liquidityUserBorrowDataToken0_.borrowable) *
                            liquidityUserBorrowDataToken0_.expandDuration) / maxBorrowable_;
                }
            }
            limits_.borrowableToken0.expandDuration = expandTimeLeft_;
        }

        // TOKEN 1 BORROWABLE
        {
            uint256 expandTimeLeft_ = liquidityUserBorrowDataToken1_.lastUpdateTimestamp +
                liquidityUserBorrowDataToken1_.expandDuration;
            expandTimeLeft_ = block.timestamp > expandTimeLeft_ ? 0 : expandTimeLeft_ - block.timestamp;

            uint256 maxBorrowable_ = (liquidityUserBorrowDataToken1_.expandPercent *
                liquidityUserBorrowDataToken1_.borrow) / 1e4;
            {
                // consider max hard borrow limit
                uint256 maxBorrowableUntilHardLimit_ = liquidityUserBorrowDataToken1_.maxBorrowLimit >
                    liquidityUserBorrowDataToken1_.borrow
                    ? liquidityUserBorrowDataToken1_.maxBorrowLimit - liquidityUserBorrowDataToken1_.borrow
                    : 0;
                if (limits_.borrowableToken1.expandsTo > maxBorrowableUntilHardLimit_) {
                    limits_.borrowableToken1.expandsTo = maxBorrowableUntilHardLimit_;
                }
            }
            if (liquidityUserBorrowDataToken1_.borrowable > maxBorrowable_) {
                // max expansion already reached or below base limit
                maxBorrowable_ = liquidityUserBorrowDataToken1_.borrowable;
                expandTimeLeft_ = 0;
            }

            if (maxBorrowable_ <= limits_.borrowableToken1.expandsTo) {
                // if max borrowable until limit is less than utilization limit, then set max borrowable until limit as expansion limit.
                limits_.borrowableToken1.expandsTo = maxBorrowable_;

                // expansionPerSecond_ = maxBorrowable_ / expandDuration;
                // borrowable + expansionPerSecond_ * x = expandsTo;
                expandTimeLeft_ = maxBorrowable_ == 0
                    ? 0
                    : ((limits_.borrowableToken1.expandsTo - liquidityUserBorrowDataToken1_.borrowable) *
                        liquidityUserBorrowDataToken1_.expandDuration) / maxBorrowable_;
            } else {
                // max borrowable expansion is limited by utilization or liquidity layer balance.
                // recalculate the duration until that earlier limit is hit.
                if (liquidityUserBorrowDataToken1_.borrowable > limits_.borrowableToken1.expandsTo) {
                    // borrowable amount at LiquidityResolver does not have dex utilization limit included
                    // so this case could actually happen. if so, then adjust borrowable and expansion is already
                    // max reached so duration left is 0.
                    expandTimeLeft_ = 0;
                    liquidityUserBorrowDataToken1_.borrowable = limits_.borrowableToken1.expandsTo;
                } else {
                    expandTimeLeft_ = maxBorrowable_ == 0
                        ? 0
                        : ((limits_.borrowableToken1.expandsTo - liquidityUserBorrowDataToken1_.borrowable) *
                            liquidityUserBorrowDataToken1_.expandDuration) / maxBorrowable_;
                }
            }
            limits_.borrowableToken1.expandDuration = expandTimeLeft_;
        }

        // for available amounts, set withdrawable / borrowable (incl. liquidity balances) if less than available until utilization
        if (liquidityUserSupplyDataToken1_.withdrawable < limits_.withdrawableToken0.available) {
            limits_.withdrawableToken0.available = liquidityUserSupplyDataToken0_.withdrawable;
        }
        if (liquidityUserSupplyDataToken1_.withdrawable < limits_.withdrawableToken1.available) {
            limits_.withdrawableToken1.available = liquidityUserSupplyDataToken1_.withdrawable;
        }
        if (liquidityUserBorrowDataToken0_.borrowable < limits_.borrowableToken0.available) {
            limits_.borrowableToken0.available = liquidityUserBorrowDataToken0_.borrowable;
        }
        if (liquidityUserBorrowDataToken1_.borrowable < limits_.borrowableToken1.available) {
            limits_.borrowableToken1.available = liquidityUserBorrowDataToken1_.borrowable;
        }
    }
}

abstract contract DexActionEstimates is DexPublicViews, DexSwapLimits {
    address private constant ADDRESS_DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @param t total amount in
    /// @param x imaginary reserves of token out of collateral
    /// @param y imaginary reserves of token in of collateral
    /// @param x2 imaginary reserves of token out of debt
    /// @param y2 imaginary reserves of token in of debt
    /// @return a_ how much swap should go through collateral pool. Remaining will go from debt
    /// note if a < 0 then entire trade route through debt pool and debt pool arbitrage with col pool
    /// note if a > t then entire trade route through col pool and col pool arbitrage with debt pool
    /// note if a > 0 & a < t then swap will route through both pools
    function _swapRoutingIn(uint t, uint x, uint y, uint x2, uint y2) private pure returns (int a_) {
        // Main equations:
        // 1. out = x * a / (y + a)
        // 2. out2 = x2 * (t - a) / (y2 + (t - a))
        // final price should be same
        // 3. (y + a) / (x - out) = (y2 + (t - a)) / (x2 - out2)
        // derivation: https://chatgpt.com/share/dce6f381-ee5f-4d5f-b6ea-5996e84d5b57

        // adding 1e18 precision
        uint xyRoot_ = FixedPointMathLib.sqrt(x * y * 1e18);
        uint x2y2Root_ = FixedPointMathLib.sqrt(x2 * y2 * 1e18);

        a_ = (int(y2 * xyRoot_ + t * xyRoot_) - int(y * x2y2Root_)) / int(xyRoot_ + x2y2Root_);
    }

    /// @param t total amount out
    /// @param x imaginary reserves of token in of collateral
    /// @param y imaginary reserves of token out of collateral
    /// @param x2 imaginary reserves of token in of debt
    /// @param y2 imaginary reserves of token out of debt
    /// @return a_ how much swap should go through collateral pool. Remaining will go from debt
    /// note if a < 0 then entire trade route through debt pool and debt pool arbitrage with col pool
    /// note if a > t then entire trade route through col pool and col pool arbitrage with debt pool
    /// note if a > 0 & a < t then swap will route through both pools
    function _swapRoutingOut(uint t, uint x, uint y, uint x2, uint y2) private pure returns (int a_) {
        // Main equations:
        // 1. in = (x * a) / (y - a)
        // 2. in2 = (x2 * (t - a)) / (y2 - (t - a))
        // final price should be same
        // 3. (y - a) / (x + in) = (y2 - (t - a)) / (x2 + in2)
        // derivation: https://chatgpt.com/share/6585bc28-841f-49ec-aea2-1e5c5b7f4fa9

        // adding 1e18 precision
        uint xyRoot_ = FixedPointMathLib.sqrt(x * y * 1e18);
        uint x2y2Root_ = FixedPointMathLib.sqrt(x2 * y2 * 1e18);

        // 1e18 precision gets cancelled out in division
        a_ = (int(t * xyRoot_ + y * x2y2Root_) - int(y2 * xyRoot_)) / int(xyRoot_ + x2y2Root_);
    }

    /// @dev Given an input amount of asset and pair reserves, returns the maximum output amount of the other asset
    /// @param amountIn_ The amount of input asset.
    /// @param iReserveIn_ Imaginary token reserve with input amount.
    /// @param iReserveOut_ Imaginary token reserve of output amount.
    function _getAmountOut(
        uint256 amountIn_,
        uint iReserveIn_,
        uint iReserveOut_
    ) private pure returns (uint256 amountOut_) {
        unchecked {
            // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
            uint256 numerator_ = amountIn_ * iReserveOut_;
            uint256 denominator_ = iReserveIn_ + amountIn_;

            // Using the swap formula: (AmountIn * iReserveY) / (iReserveX + AmountIn)
            amountOut_ = numerator_ / denominator_;
        }
    }

    /// @dev Given an output amount of asset and pair reserves, returns the input amount of the other asset
    /// @param amountOut_ Desired output amount of the asset.
    /// @param iReserveIn_ Imaginary token reserve of input amount.
    /// @param iReserveOut_ Imaginary token reserve of output amount.
    function _getAmountIn(
        uint256 amountOut_,
        uint iReserveIn_,
        uint iReserveOut_
    ) private pure returns (uint256 amountIn_) {
        // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
        uint256 numerator_ = amountOut_ * iReserveIn_;
        uint256 denominator_ = iReserveOut_ - amountOut_;

        // Using the swap formula: (AmountOut * iReserveX) / (iReserveY - AmountOut)
        amountIn_ = numerator_ / denominator_;
    }

    struct EstimateMemoryVars {
        uint256 colTokenInImaginaryReserves;
        uint256 colTokenOutImaginaryReserves;
        uint256 debtTokenInImaginaryReserves;
        uint256 debtTokenOutImaginaryReserves;
        uint256 amountOutCollateralAdjusted;
        uint256 amountOutDebtAdjusted;
        uint256 amountInCollateralAdjusted;
        uint256 amountInDebtAdjusted;
    }

    /// @notice estimates swap IN tokens execution
    /// @param dex_ Dex pool
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountIn_ The exact amount of input tokens to swap
    /// @param amountOutMin_ The minimum amount of output tokens the user is willing to accept
    /// @return amountOut_ The amount of output tokens received from the swap
    function estimateSwapIn(
        address dex_,
        bool swap0to1_,
        uint256 amountIn_,
        uint256 amountOutMin_
    ) public payable returns (uint256 amountOut_) {
        try IFluidDexT1(dex_).swapIn{ value: msg.value }(swap0to1_, amountIn_, amountOutMin_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (amountOut_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexSwapResult.selector);
        }

        EstimateMemoryVars memory e_;
        {
            IFluidDexT1.CollateralReserves memory colReserves_ = getDexCollateralReservesAdjusted(dex_);
            IFluidDexT1.DebtReserves memory debtReserves_ = getDexDebtReservesAdjusted(dex_);
            if (swap0to1_) {
                e_.colTokenInImaginaryReserves = colReserves_.token0ImaginaryReserves;
                e_.colTokenOutImaginaryReserves = colReserves_.token1ImaginaryReserves;
                e_.debtTokenInImaginaryReserves = debtReserves_.token0ImaginaryReserves;
                e_.debtTokenOutImaginaryReserves = debtReserves_.token1ImaginaryReserves;
            } else {
                e_.colTokenInImaginaryReserves = colReserves_.token1ImaginaryReserves;
                e_.colTokenOutImaginaryReserves = colReserves_.token0ImaginaryReserves;
                e_.debtTokenInImaginaryReserves = debtReserves_.token1ImaginaryReserves;
                e_.debtTokenOutImaginaryReserves = debtReserves_.token0ImaginaryReserves;
            }
        }

        IFluidDexT1.ConstantViews2 memory constantsView2_ = IFluidDexT1(dex_).constantsView2();

        {
            int256 swapRoutingAmt_;
            uint256 poolFee_;
            uint256 amountInAdjusted_;
            // bring amount in to 1e12 decimals adjusted
            if (swap0to1_) {
                amountInAdjusted_ =
                    (amountIn_ * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
            } else {
                amountInAdjusted_ =
                    (amountIn_ * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
            }

            {
                uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
                poolFee_ = (dexVariables2_ >> 2) & X17;
                bool colPoolEnabled_ = (dexVariables2_ & 1) == 1;
                bool debtPoolEnabled_ = (dexVariables2_ & 2) == 2;
                if (colPoolEnabled_ && debtPoolEnabled_) {
                    swapRoutingAmt_ = _swapRoutingIn(
                        amountInAdjusted_,
                        e_.colTokenOutImaginaryReserves,
                        e_.colTokenInImaginaryReserves,
                        e_.debtTokenOutImaginaryReserves,
                        e_.debtTokenInImaginaryReserves
                    );
                } else if (debtPoolEnabled_) {
                    swapRoutingAmt_ = -1; // Route from debt pool
                } else if (colPoolEnabled_) {
                    swapRoutingAmt_ = int256(amountInAdjusted_) + 1; // Route from collateral pool
                } else {
                    revert("No pools are enabled");
                }
            }

            if (swapRoutingAmt_ <= 0) {
                // Entire trade routes through debt pool
                e_.amountInDebtAdjusted = amountInAdjusted_;
                e_.amountOutDebtAdjusted = _getAmountOut(
                    ((amountInAdjusted_ * (1e6 - poolFee_)) / 1e6),
                    e_.debtTokenInImaginaryReserves,
                    e_.debtTokenOutImaginaryReserves
                );
            } else if (swapRoutingAmt_ >= int256(amountInAdjusted_)) {
                // Entire trade routes through collateral pool
                e_.amountInCollateralAdjusted = amountInAdjusted_;
                e_.amountOutCollateralAdjusted = _getAmountOut(
                    ((amountInAdjusted_ * (1e6 - poolFee_)) / 1e6),
                    e_.colTokenInImaginaryReserves,
                    e_.colTokenOutImaginaryReserves
                );
            } else {
                // Trade routes through both pools
                e_.amountInCollateralAdjusted = uint(swapRoutingAmt_);
                e_.amountInDebtAdjusted = amountInAdjusted_ - e_.amountInCollateralAdjusted;

                e_.amountOutCollateralAdjusted = _getAmountOut(
                    ((e_.amountInCollateralAdjusted * (1e6 - poolFee_)) / 1e6),
                    e_.colTokenInImaginaryReserves,
                    e_.colTokenOutImaginaryReserves
                );

                e_.amountOutDebtAdjusted = _getAmountOut(
                    ((e_.amountInDebtAdjusted * (1e6 - poolFee_)) / 1e6),
                    e_.debtTokenInImaginaryReserves,
                    e_.debtTokenOutImaginaryReserves
                );
            }
        }

        {
            uint256 borrowableAdjusted_;
            uint256 withdrawableAdjusted_;
            DexLimits memory limits_ = getDexLimits(dex_);

            // bring amount to 1e12 decimals adjusted
            if (swap0to1_) {
                borrowableAdjusted_ =
                    (limits_.borrowableToken1.available * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
                withdrawableAdjusted_ =
                    (limits_.withdrawableToken1.available * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
            } else {
                borrowableAdjusted_ =
                    (limits_.borrowableToken0.available * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
                withdrawableAdjusted_ =
                    (limits_.withdrawableToken0.available * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
            }

            if (e_.amountOutDebtAdjusted > borrowableAdjusted_) {
                return 0;
            }
            if (e_.amountOutCollateralAdjusted > withdrawableAdjusted_) {
                return 0;
            }
        }

        uint256 oldPrice_;
        uint256 newPrice_;
        // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
        if (e_.amountInCollateralAdjusted > e_.amountInDebtAdjusted) {
            // new pool price from col pool
            oldPrice_ = swap0to1_
                ? (e_.colTokenOutImaginaryReserves * 1e27) / (e_.colTokenInImaginaryReserves)
                : (e_.colTokenInImaginaryReserves * 1e27) / (e_.colTokenOutImaginaryReserves);
            newPrice_ = swap0to1_
                ? ((e_.colTokenOutImaginaryReserves - e_.amountOutCollateralAdjusted) * 1e27) /
                    (e_.colTokenInImaginaryReserves + e_.amountInCollateralAdjusted)
                : ((e_.colTokenInImaginaryReserves + e_.amountInCollateralAdjusted) * 1e27) /
                    (e_.colTokenOutImaginaryReserves - e_.amountOutCollateralAdjusted);
        } else {
            // new pool price from debt pool
            oldPrice_ = swap0to1_
                ? (e_.debtTokenOutImaginaryReserves * 1e27) / (e_.debtTokenInImaginaryReserves)
                : (e_.debtTokenInImaginaryReserves * 1e27) / (e_.debtTokenOutImaginaryReserves);
            newPrice_ = swap0to1_
                ? ((e_.debtTokenOutImaginaryReserves - e_.amountOutDebtAdjusted) * 1e27) /
                    (e_.debtTokenInImaginaryReserves + e_.amountInDebtAdjusted)
                : ((e_.debtTokenInImaginaryReserves + e_.amountInDebtAdjusted) * 1e27) /
                    (e_.debtTokenOutImaginaryReserves - e_.amountOutDebtAdjusted);
        }

        uint256 priceDiff_ = oldPrice_ > newPrice_ ? oldPrice_ - newPrice_ : newPrice_ - oldPrice_;
        if (priceDiff_ > ((oldPrice_ * ORACLE_LIMIT) / 1e18)) {
            // if price diff is > 5% then swap would revert.
            return 0;
        }

        return amountOut_;
    }

    /// @notice estimates swap OUT tokens execution
    /// @param dex_ Dex pool
    /// @param swap0to1_ Direction of swap. If true, swaps token0 for token1; if false, swaps token1 for token0
    /// @param amountOut_ The exact amount of tokens to receive after swap
    /// @param amountInMax_ Maximum amount of tokens to swap in
    /// @return amountIn_ The amount of input tokens used for the swap
    function estimateSwapOut(
        address dex_,
        bool swap0to1_,
        uint256 amountOut_,
        uint256 amountInMax_
    ) public payable returns (uint256 amountIn_) {
        try IFluidDexT1(dex_).swapOut{ value: msg.value }(swap0to1_, amountOut_, amountInMax_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (amountIn_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexSwapResult.selector);
        }

        EstimateMemoryVars memory e_;
        {
            IFluidDexT1.CollateralReserves memory colReserves_ = getDexCollateralReservesAdjusted(dex_);
            IFluidDexT1.DebtReserves memory debtReserves_ = getDexDebtReservesAdjusted(dex_);
            if (swap0to1_) {
                e_.colTokenInImaginaryReserves = colReserves_.token0ImaginaryReserves;
                e_.colTokenOutImaginaryReserves = colReserves_.token1ImaginaryReserves;
                e_.debtTokenInImaginaryReserves = debtReserves_.token0ImaginaryReserves;
                e_.debtTokenOutImaginaryReserves = debtReserves_.token1ImaginaryReserves;
            } else {
                e_.colTokenInImaginaryReserves = colReserves_.token1ImaginaryReserves;
                e_.colTokenOutImaginaryReserves = colReserves_.token0ImaginaryReserves;
                e_.debtTokenInImaginaryReserves = debtReserves_.token1ImaginaryReserves;
                e_.debtTokenOutImaginaryReserves = debtReserves_.token0ImaginaryReserves;
            }
        }

        IFluidDexT1.ConstantViews2 memory constantsView2_ = IFluidDexT1(dex_).constantsView2();

        {
            int256 swapRoutingAmt_;
            uint256 poolFee_;
            uint256 amountOutAdjusted_;
            // bring amount in to 1e12 decimals adjusted
            if (swap0to1_) {
                amountOutAdjusted_ =
                    (amountOut_ * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
            } else {
                amountOutAdjusted_ =
                    (amountOut_ * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
            }

            {
                uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
                poolFee_ = (dexVariables2_ >> 2) & X17;
                bool colPoolEnabled_ = (dexVariables2_ & 1) == 1;
                bool debtPoolEnabled_ = (dexVariables2_ & 2) == 2;
                if (colPoolEnabled_ && debtPoolEnabled_) {
                    swapRoutingAmt_ = _swapRoutingOut(
                        amountOutAdjusted_,
                        e_.colTokenInImaginaryReserves,
                        e_.colTokenOutImaginaryReserves,
                        e_.debtTokenInImaginaryReserves,
                        e_.debtTokenOutImaginaryReserves
                    );
                } else if (debtPoolEnabled_) {
                    swapRoutingAmt_ = -1; // Route from debt pool
                } else if (colPoolEnabled_) {
                    swapRoutingAmt_ = int256(amountOutAdjusted_) + 1; // Route from collateral pool
                } else {
                    revert("No pools are enabled");
                }
            }

            if (swapRoutingAmt_ <= 0) {
                // Entire trade routes through debt pool
                e_.amountOutDebtAdjusted = amountOutAdjusted_;
                e_.amountInDebtAdjusted = _getAmountIn(
                    e_.amountOutDebtAdjusted,
                    e_.debtTokenInImaginaryReserves,
                    e_.debtTokenOutImaginaryReserves
                );
                e_.amountInDebtAdjusted = (e_.amountInDebtAdjusted * 1e6) / (1e6 - poolFee_);
            } else if (swapRoutingAmt_ >= int256(amountOutAdjusted_)) {
                // Entire trade routes through collateral pool
                e_.amountOutCollateralAdjusted = amountOutAdjusted_;
                e_.amountInCollateralAdjusted = _getAmountIn(
                    e_.amountOutCollateralAdjusted,
                    e_.colTokenInImaginaryReserves,
                    e_.colTokenOutImaginaryReserves
                );
                e_.amountInCollateralAdjusted = (e_.amountInCollateralAdjusted * 1e6) / (1e6 - poolFee_);
            } else {
                // Trade routes through both pools
                e_.amountOutCollateralAdjusted = uint(swapRoutingAmt_);
                e_.amountOutDebtAdjusted = amountOutAdjusted_ - e_.amountOutCollateralAdjusted;

                e_.amountInCollateralAdjusted = _getAmountIn(
                    e_.amountOutCollateralAdjusted,
                    e_.colTokenInImaginaryReserves,
                    e_.colTokenOutImaginaryReserves
                );
                e_.amountInCollateralAdjusted = (e_.amountInCollateralAdjusted * 1e6) / (1e6 - poolFee_);

                e_.amountInDebtAdjusted = _getAmountIn(
                    e_.amountOutDebtAdjusted,
                    e_.debtTokenInImaginaryReserves,
                    e_.debtTokenOutImaginaryReserves
                );
                e_.amountInDebtAdjusted = (e_.amountInDebtAdjusted * 1e6) / (1e6 - poolFee_);
            }
        }

        {
            uint256 borrowableAdjusted_;
            uint256 withdrawableAdjusted_;
            DexLimits memory limits_ = getDexLimits(dex_);

            // bring amount to 1e12 decimals adjusted
            if (swap0to1_) {
                borrowableAdjusted_ =
                    (limits_.borrowableToken1.available * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
                withdrawableAdjusted_ =
                    (limits_.withdrawableToken1.available * constantsView2_.token1NumeratorPrecision) /
                    constantsView2_.token1DenominatorPrecision;
            } else {
                borrowableAdjusted_ =
                    (limits_.borrowableToken0.available * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
                withdrawableAdjusted_ =
                    (limits_.withdrawableToken0.available * constantsView2_.token0NumeratorPrecision) /
                    constantsView2_.token0DenominatorPrecision;
            }

            if (e_.amountOutDebtAdjusted > borrowableAdjusted_) {
                return type(uint256).max;
            }
            if (e_.amountOutCollateralAdjusted > withdrawableAdjusted_) {
                return type(uint256).max;
            }
        }

        uint256 oldPrice_;
        uint256 newPrice_;
        // from whatever pool higher amount of swap is routing we are taking that as final price, does not matter much because both pools final price should be same
        if (e_.amountOutCollateralAdjusted > e_.amountOutDebtAdjusted) {
            // new pool price from col pool
            oldPrice_ = swap0to1_
                ? (e_.colTokenOutImaginaryReserves * 1e27) / (e_.colTokenInImaginaryReserves)
                : (e_.colTokenInImaginaryReserves * 1e27) / (e_.colTokenOutImaginaryReserves);
            newPrice_ = swap0to1_
                ? ((e_.colTokenOutImaginaryReserves - e_.amountOutCollateralAdjusted) * 1e27) /
                    (e_.colTokenInImaginaryReserves + e_.amountInCollateralAdjusted)
                : ((e_.colTokenInImaginaryReserves + e_.amountInCollateralAdjusted) * 1e27) /
                    (e_.colTokenOutImaginaryReserves - e_.amountOutCollateralAdjusted);
        } else {
            // new pool price from debt pool
            oldPrice_ = swap0to1_
                ? (e_.debtTokenOutImaginaryReserves * 1e27) / (e_.debtTokenInImaginaryReserves)
                : (e_.debtTokenInImaginaryReserves * 1e27) / (e_.debtTokenOutImaginaryReserves);
            newPrice_ = swap0to1_
                ? ((e_.debtTokenOutImaginaryReserves - e_.amountOutDebtAdjusted) * 1e27) /
                    (e_.debtTokenInImaginaryReserves + e_.amountInDebtAdjusted)
                : ((e_.debtTokenInImaginaryReserves + e_.amountInDebtAdjusted) * 1e27) /
                    (e_.debtTokenOutImaginaryReserves - e_.amountOutDebtAdjusted);
        }

        uint256 priceDiff_ = oldPrice_ > newPrice_ ? oldPrice_ - newPrice_ : newPrice_ - oldPrice_;
        if (priceDiff_ > ((oldPrice_ * ORACLE_LIMIT) / 1e18)) {
            // if price diff is > 5% then swap would revert.
            return type(uint256).max;
        }

        return amountIn_;
    }

    function _decodeLowLevelUint1x(
        bytes memory lowLevelData_,
        bytes4 targetErrorSelector_
    ) internal pure returns (uint value1_) {
        if (lowLevelData_.length < 36) {
            return 0;
        }

        bytes4 errorSelector_;
        assembly {
            // Extract the selector from the error data
            errorSelector_ := mload(add(lowLevelData_, 0x20))
        }
        if (errorSelector_ == targetErrorSelector_) {
            assembly {
                value1_ := mload(add(lowLevelData_, 36))
            }
        }
        // else => values remain 0
    }
}

/// @notice Fluid Dex Reserves resolver
/// Implements various view-only methods to give easy access to Dex protocol reserves data.
contract FluidDexReservesResolver is DexFactoryViews, DexActionEstimates {
    constructor(
        address factory_,
        address liquidity_,
        address liquidityResolver_
    ) Variables(factory_, liquidity_, liquidityResolver_) {}

    /// @notice Get a Pool's address and its token addresses
    /// @param poolId_ The ID of the Pool
    /// @return pool_ The Pool data
    function getPool(uint256 poolId_) public view returns (Pool memory pool_) {
        address poolAddress_ = getPoolAddress(poolId_);
        (address token0_, address token1_) = getPoolTokens(poolAddress_);
        return Pool(poolAddress_, token0_, token1_, getPoolFee(poolAddress_));
    }

    /// @notice Get a Pool's fee
    /// @param pool_ The Pool address
    /// @return fee_ The Pool fee as 1% = 10000
    function getPoolFee(address pool_) public view returns (uint256 fee_) {
        uint256 dexVariables2_ = IFluidDexT1(pool_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        return (dexVariables2_ >> 2) & X17;
    }

    /// @notice Get an array of all Pool addresses and their token addresses
    /// @return pools_ An array containing all Pool data
    function getAllPools() public view returns (Pool[] memory pools_) {
        uint256 totalPools_ = getTotalPools();
        pools_ = new Pool[](totalPools_);
        for (uint256 i; i < totalPools_; i++) {
            pools_[i] = getPool(i + 1);
        }
    }

    /// @notice Get the token addresses, collateral reserves, and debt reserves for a given Pool address
    /// @param pool_ The Pool address
    /// @return poolReserves_ The Pool data with reserves.
    /// @dev expected to be called via callStatic
    function getPoolReserves(address pool_) public returns (PoolWithReserves memory poolReserves_) {
        (poolReserves_.token0, poolReserves_.token1) = getPoolTokens(pool_);

        try this.getDexPricesAndExchangePrices(pool_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            poolReserves_.centerPrice = pex_.centerPrice;
            poolReserves_.collateralReserves = _getDexCollateralReserves(pool_, pex_);
            poolReserves_.debtReserves = _getDexDebtReserves(pool_, pex_);
        } catch {
            poolReserves_.collateralReserves = getDexCollateralReserves(pool_);
            poolReserves_.debtReserves = getDexDebtReserves(pool_);
        }

        poolReserves_.pool = pool_;
        poolReserves_.fee = getPoolFee(pool_);

        poolReserves_.limits = getDexLimits(pool_);
    }

    /// @notice Get an array of Pool addresses, their token addresses, collateral reserves, and debt reserves for a given array of Pool addresses
    /// @param pools_ The array of Pool addresses
    /// @return poolsReserves_ An array containing all Pool data with reserves
    /// @dev expected to be called via callStatic
    function getPoolsReserves(address[] memory pools_) public returns (PoolWithReserves[] memory poolsReserves_) {
        poolsReserves_ = new PoolWithReserves[](pools_.length);
        for (uint256 i; i < pools_.length; i++) {
            poolsReserves_[i] = getPoolReserves(pools_[i]);
        }
    }

    /// @notice Get an array of all Pool addresses, their token addresses, collateral reserves, and debt reserves
    /// @return poolsReserves_ An array containing all Pool data with reserves
    /// @dev expected to be called via callStatic
    function getAllPoolsReserves() public returns (PoolWithReserves[] memory poolsReserves_) {
        return getPoolsReserves(getAllPoolAddresses());
    }

    /// @notice Get the token addresses, adjusted collateral reserves, and adjusted debt reserves for a given Pool address
    /// @param pool_ The Pool address
    /// @return poolReserves_ The Pool data with adjusted reserves scaled to 1e12. balanceTokens are in token decimals.
    /// @dev expected to be called via callStatic
    function getPoolReservesAdjusted(address pool_) public returns (PoolWithReserves memory poolReserves_) {
        (poolReserves_.token0, poolReserves_.token1) = getPoolTokens(pool_);

        try this.getDexPricesAndExchangePrices(pool_) returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
            poolReserves_.centerPrice = pex_.centerPrice;
            poolReserves_.collateralReserves = _getDexCollateralReservesAdjusted(pool_, pex_);
            poolReserves_.debtReserves = _getDexDebtReservesAdjusted(pool_, pex_);
        } catch {
            poolReserves_.collateralReserves = getDexCollateralReservesAdjusted(pool_);
            poolReserves_.debtReserves = getDexDebtReservesAdjusted(pool_);
        }

        poolReserves_.pool = pool_;
        poolReserves_.fee = getPoolFee(pool_);

        poolReserves_.limits = getDexLimits(pool_);
    }

    /// @notice Get an array of Pool addresses, their token addresses, adjusted collateral reserves, and adjusted debt reserves for a given array of Pool addresses
    /// @param pools_ The array of Pool addresses
    /// @return poolsReserves_ An array containing all Pool data with adjusted reserves scaled to 1e12
    /// @dev expected to be called via callStatic
    function getPoolsReservesAdjusted(
        address[] memory pools_
    ) public returns (PoolWithReserves[] memory poolsReserves_) {
        poolsReserves_ = new PoolWithReserves[](pools_.length);
        for (uint256 i; i < pools_.length; i++) {
            poolsReserves_[i] = getPoolReservesAdjusted(pools_[i]);
        }
    }

    /// @notice Get an array of all Pool addresses, their token addresses, adjusted collateral reserves, and adjusted debt reserves
    /// @return poolsReserves_ An array containing all Pool data with adjusted reserves scaled to 1e12
    /// @dev expected to be called via callStatic
    function getAllPoolsReservesAdjusted() public returns (PoolWithReserves[] memory poolsReserves_) {
        return getPoolsReservesAdjusted(getAllPoolAddresses());
    }
}
