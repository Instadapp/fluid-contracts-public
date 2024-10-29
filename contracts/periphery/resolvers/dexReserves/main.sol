// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { BytesSliceAndConcat } from "../../../libraries/bytesSliceAndConcat.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { Variables } from "./variables.sol";
import { Structs } from "./structs.sol";

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
        reserves_ = getDexCollateralReservesAdjusted(dex_);

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
        } catch {
            reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }
    }

    /// @notice Get the debt reserves for a DEX in token decimals amounts
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing debt reserve information
    /// @dev expected to be called via callStatic
    function getDexDebtReserves(address dex_) public returns (IFluidDexT1.DebtReserves memory reserves_) {
        reserves_ = getDexDebtReservesAdjusted(dex_);

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

abstract contract DexActionEstimates {
    address private constant ADDRESS_DEAD = 0x000000000000000000000000000000000000dEaD;

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
contract FluidDexReservesResolver is
    Variables,
    Structs,
    DexFactoryViews,
    DexConstantsViews,
    DexPublicViews,
    DexActionEstimates
{
    constructor(address factory_) Variables(factory_) {}

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
    /// @return poolReserves_ The Pool data with reserves
    /// @dev expected to be called via callStatic
    function getPoolReserves(address pool_) public returns (PoolWithReserves memory poolReserves_) {
        (address token0_, address token1_) = getPoolTokens(pool_);
        IFluidDexT1.CollateralReserves memory collateralReserves_ = getDexCollateralReserves(pool_);
        IFluidDexT1.DebtReserves memory debtReserves_ = getDexDebtReserves(pool_);
        return PoolWithReserves(pool_, token0_, token1_, getPoolFee(pool_), collateralReserves_, debtReserves_);
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
    /// @return poolReserves_ The Pool data with adjusted reserves scaled to 1e12
    /// @dev expected to be called via callStatic
    function getPoolReservesAdjusted(address pool_) public returns (PoolWithReserves memory poolReserves_) {
        (address token0_, address token1_) = getPoolTokens(pool_);
        IFluidDexT1.CollateralReserves memory collateralReserves_ = getDexCollateralReservesAdjusted(pool_);
        IFluidDexT1.DebtReserves memory debtReserves_ = getDexDebtReservesAdjusted(pool_);
        return PoolWithReserves(pool_, token0_, token1_, getPoolFee(pool_), collateralReserves_, debtReserves_);
    }

    /// @notice Get an array of Pool addresses, their token addresses, adjusted collateral reserves, and adjusted debt reserves for a given array of Pool addresses
    /// @param pools_ The array of Pool addresses
    /// @return poolsReserves_ An array containing all Pool data with adjusted reserves scaled to 1e12
    /// @dev expected to be called via callStatic
    function getPoolsReservesAdjusted(address[] memory pools_) public returns (PoolWithReserves[] memory poolsReserves_) {
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
