// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { DexCalcs } from "../../../libraries/dexCalcs.sol";
import { BigMathMinified } from "../../../libraries/bigMathMinified.sol";
import { BytesSliceAndConcat } from "../../../libraries/bytesSliceAndConcat.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { Structs as FluidLiquidityResolverStructs } from "../liquidity/structs.sol";
import { Structs } from "./structs.sol";
import { Variables } from "./variables.sol";

/// @title DexFactoryViews
/// @notice Abstract contract providing view functions for DEX factory-related operations
abstract contract DexFactoryViews is Variables {
    /// @notice Get the address of a DEX given its ID
    /// @param dexId_ The ID of the DEX
    /// @return dex_ The address of the DEX
    function getDexAddress(uint256 dexId_) public view returns (address dex_) {
        return AddressCalcs.addressCalc(address(FACTORY), dexId_);
    }

    /// @notice Get the ID of a DEX given its address
    /// @param dex_ The address of the DEX
    /// @return id_ The ID of the DEX
    function getDexId(address dex_) public view returns (uint id_) {
        id_ = IFluidDexT1(dex_).DEX_ID();
    }

    /// @notice Get the total number of DEXes
    /// @return The total number of DEXes
    function getTotalDexes() public view returns (uint) {
        return FACTORY.totalDexes();
    }

    /// @notice Get an array of all DEX addresses
    /// @return dexes_ An array containing all DEX addresses
    function getAllDexAddresses() public view returns (address[] memory dexes_) {
        uint totalDexes_ = getTotalDexes();
        dexes_ = new address[](totalDexes_);
        for (uint i = 0; i < totalDexes_; i++) {
            dexes_[i] = getDexAddress((i + 1));
        }
    }
}

/// @title DexStorageVars
/// @notice Abstract contract providing view functions for DEX storage variables
abstract contract DexStorageVars is Variables {
    /// @notice Get the raw DEX variables
    /// @param dex_ The address of the DEX
    /// @return The raw DEX variables
    function getDexVariablesRaw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));
    }

    /// @notice Get the raw DEX variables2
    /// @param dex_ The address of the DEX
    /// @return The raw DEX variables2
    function getDexVariables2Raw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
    }

    /// @notice Get the total supply shares slot data of a DEX
    /// @param dex_ The address of the DEX
    /// @return The total supply shares
    function getTotalSupplySharesRaw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT));
    }

    /// @notice Get the raw user supply data for a specific user and DEX
    /// @param dex_ The address of the DEX
    /// @param user_ The address of the user
    /// @return The raw user supply data
    function getUserSupplyDataRaw(address dex_, address user_) public view returns (uint) {
        return
            IFluidDexT1(dex_).readFromStorage(
                DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user_)
            );
    }

    /// @notice Get the total borrow shares slot data of a DEX
    /// @param dex_ The address of the DEX
    /// @return The total borrow shares
    function getTotalBorrowSharesRaw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT));
    }

    /// @notice Get the raw user borrow data for a specific user and DEX
    /// @param dex_ The address of the DEX
    /// @param user_ The address of the user
    /// @return The raw user borrow data
    function getUserBorrowDataRaw(address dex_, address user_) public view returns (uint) {
        return
            IFluidDexT1(dex_).readFromStorage(
                DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT, user_)
            );
    }

    /// @notice Get the raw oracle data for a specific DEX and index
    /// @param dex_ The address of the DEX
    /// @param index_ The index of the oracle data
    /// @return The raw oracle data
    function getOracleRaw(address dex_, uint index_) public view returns (uint) {
        return
            IFluidDexT1(dex_).readFromStorage(
                _calculateStorageSlotUintMapping(DexSlotsLink.DEX_ORACLE_MAPPING_SLOT, index_)
            );
    }

    /// @notice Get the raw range shift for a DEX
    /// @param dex_ The address of the DEX
    /// @return The raw range shift
    function getRangeShiftRaw(address dex_) public view returns (uint) {
        return
            IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_RANGE_THRESHOLD_SHIFTS_SLOT)) &
            type(uint128).max;
    }

    /// @notice Get the raw threshold shift for a DEX
    /// @param dex_ The address of the DEX
    /// @return The raw threshold shift
    function getThresholdShiftRaw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_RANGE_THRESHOLD_SHIFTS_SLOT)) >> 128;
    }

    /// @notice Get the raw center price shift for a DEX
    /// @param dex_ The address of the DEX
    /// @return The raw center price shift
    function getCenterPriceShiftRaw(address dex_) public view returns (uint) {
        return IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_CENTER_PRICE_SHIFT_SLOT));
    }

    /// @dev Calculate the storage slot for a uint mapping
    /// @param slot_ The base slot of the mapping
    /// @param key_ The key of the mapping
    /// @return The calculated storage slot
    function _calculateStorageSlotUintMapping(uint256 slot_, uint key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
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

    /// @dev Estimate deposit tokens in equal proportion to the current pool ratio
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to mint
    /// @param maxToken0Deposit_ Maximum amount of token0 to deposit
    /// @param maxToken1Deposit_ Maximum amount of token1 to deposit
    /// @return token0Amt_ Estimated amount of token0 to deposit
    /// @return token1Amt_ Estimated amount of token1 to deposit
    function estimateDepositPerfect(
        address dex_,
        uint shares_,
        uint maxToken0Deposit_,
        uint maxToken1Deposit_
    ) public payable returns (uint token0Amt_, uint token1Amt_) {
        try
            IFluidDexT1(dex_).depositPerfect{ value: msg.value }(shares_, maxToken0Deposit_, maxToken1Deposit_, true)
        {} catch (bytes memory lowLevelData_) {
            (token0Amt_, token1Amt_) = _decodeLowLevelUint2x(
                lowLevelData_,
                IFluidDexT1.FluidDexPerfectLiquidityOutput.selector
            );
        }
    }

    /// @dev Estimate withdrawal of a perfect amount of collateral liquidity
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @return token0Amt_ Estimated amount of token0 to be withdrawn
    /// @return token1Amt_ Estimated amount of token1 to be withdrawn
    function estimateWithdrawPerfect(
        address dex_,
        uint shares_,
        uint minToken0Withdraw_,
        uint minToken1Withdraw_
    ) public returns (uint token0Amt_, uint token1Amt_) {
        try IFluidDexT1(dex_).withdrawPerfect(shares_, minToken0Withdraw_, minToken1Withdraw_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (token0Amt_, token1Amt_) = _decodeLowLevelUint2x(
                lowLevelData_,
                IFluidDexT1.FluidDexPerfectLiquidityOutput.selector
            );
        }
    }

    /// @dev Estimate borrowing tokens in equal proportion to the current debt pool ratio
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to borrow
    /// @param minToken0Borrow_ Minimum amount of token0 to borrow
    /// @param minToken1Borrow_ Minimum amount of token1 to borrow
    /// @return token0Amt_ Estimated amount of token0 to be borrowed
    /// @return token1Amt_ Estimated amount of token1 to be borrowed
    function estimateBorrowPerfect(
        address dex_,
        uint shares_,
        uint minToken0Borrow_,
        uint minToken1Borrow_
    ) public returns (uint token0Amt_, uint token1Amt_) {
        try IFluidDexT1(dex_).borrowPerfect(shares_, minToken0Borrow_, minToken1Borrow_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (token0Amt_, token1Amt_) = _decodeLowLevelUint2x(
                lowLevelData_,
                IFluidDexT1.FluidDexPerfectLiquidityOutput.selector
            );
        }
    }

    /// @dev Estimate paying back borrowed tokens in equal proportion to the current debt pool ratio
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to pay back
    /// @param maxToken0Payback_ Maximum amount of token0 to pay back
    /// @param maxToken1Payback_ Maximum amount of token1 to pay back
    /// @return token0Amt_ Estimated amount of token0 to be paid back
    /// @return token1Amt_ Estimated amount of token1 to be paid back
    function estimatePaybackPerfect(
        address dex_,
        uint shares_,
        uint maxToken0Payback_,
        uint maxToken1Payback_
    ) public payable returns (uint token0Amt_, uint token1Amt_) {
        try
            IFluidDexT1(dex_).paybackPerfect{ value: msg.value }(shares_, maxToken0Payback_, maxToken1Payback_, true)
        {} catch (bytes memory lowLevelData_) {
            (token0Amt_, token1Amt_) = _decodeLowLevelUint2x(
                lowLevelData_,
                IFluidDexT1.FluidDexPerfectLiquidityOutput.selector
            );
        }
    }

    /// @dev Estimate deposit of tokens
    /// @param dex_ The address of the DEX contract
    /// @param token0Amt_ Amount of token0 to deposit
    /// @param token1Amt_ Amount of token1 to deposit
    /// @param minSharesAmt_ Minimum amount of shares to receive
    /// @return shares_ Estimated amount of shares to be minted
    function estimateDeposit(
        address dex_,
        uint token0Amt_,
        uint token1Amt_,
        uint minSharesAmt_
    ) public payable returns (uint shares_) {
        try IFluidDexT1(dex_).deposit{ value: msg.value }(token0Amt_, token1Amt_, minSharesAmt_, true) {} catch (
            bytes memory lowLevelData_
        ) {
            (shares_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexLiquidityOutput.selector);
        }
    }

    /// @dev Estimate withdrawal of tokens
    /// @param dex_ The address of the DEX contract
    /// @param token0Amt_ Amount of token0 to withdraw
    /// @param token1Amt_ Amount of token1 to withdraw
    /// @param maxSharesAmt_ Maximum amount of shares to burn
    /// @return shares_ Estimated amount of shares to be burned
    function estimateWithdraw(
        address dex_,
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_
    ) public returns (uint shares_) {
        try IFluidDexT1(dex_).withdraw(token0Amt_, token1Amt_, maxSharesAmt_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (shares_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexLiquidityOutput.selector);
        }
    }

    /// @dev Estimate borrowing of tokens
    /// @param dex_ The address of the DEX contract
    /// @param token0Amt_ Amount of token0 to borrow
    /// @param token1Amt_ Amount of token1 to borrow
    /// @param maxSharesAmt_ Maximum amount of shares to mint
    /// @return shares_ Estimated amount of shares to be minted
    function estimateBorrow(
        address dex_,
        uint token0Amt_,
        uint token1Amt_,
        uint maxSharesAmt_
    ) public returns (uint shares_) {
        try IFluidDexT1(dex_).borrow(token0Amt_, token1Amt_, maxSharesAmt_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (shares_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexLiquidityOutput.selector);
        }
    }

    /// @dev Estimate paying back of borrowed tokens
    /// @param dex_ The address of the DEX contract
    /// @param token0Amt_ Amount of token0 to pay back
    /// @param token1Amt_ Amount of token1 to pay back
    /// @param minSharesAmt_ Minimum amount of shares to burn
    /// @return shares_ Estimated amount of shares to be burned
    function estimatePayback(
        address dex_,
        uint token0Amt_,
        uint token1Amt_,
        uint minSharesAmt_
    ) public payable returns (uint shares_) {
        try IFluidDexT1(dex_).payback{ value: msg.value }(token0Amt_, token1Amt_, minSharesAmt_, true) {} catch (
            bytes memory lowLevelData_
        ) {
            (shares_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexLiquidityOutput.selector);
        }
    }

    /// @dev Estimate withdrawal of a perfect amount of collateral liquidity in one token
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to withdraw
    /// @param minToken0_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1_ The minimum amount of token1 the user is willing to accept
    /// @return withdrawAmt_ Estimated amount of tokens to be withdrawn
    function estimateWithdrawPerfectInOneToken(
        address dex_,
        uint shares_,
        uint minToken0_,
        uint minToken1_
    ) public returns (uint withdrawAmt_) {
        try IFluidDexT1(dex_).withdrawPerfectInOneToken(shares_, minToken0_, minToken1_, ADDRESS_DEAD) {} catch (
            bytes memory lowLevelData_
        ) {
            (withdrawAmt_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexLiquidityOutput.selector);
        }
    }

    /// @dev Estimate paying back of a perfect amount of borrowed tokens in one token
    /// @param dex_ The address of the DEX contract
    /// @param shares_ The number of shares to pay back
    /// @param maxToken0_ Maximum amount of token0 to pay back
    /// @param maxToken1_ Maximum amount of token1 to pay back
    /// @return paybackAmt_ Estimated amount of tokens to be paid back
    function estimatePaybackPerfectInOneToken(
        address dex_,
        uint shares_,
        uint maxToken0_,
        uint maxToken1_
    ) public payable returns (uint paybackAmt_) {
        try
            IFluidDexT1(dex_).paybackPerfectInOneToken{ value: msg.value }(shares_, maxToken0_, maxToken1_, true)
        {} catch (bytes memory lowLevelData_) {
            (paybackAmt_) = _decodeLowLevelUint1x(lowLevelData_, IFluidDexT1.FluidDexSingleTokenOutput.selector);
        }
    }

    function _decodeLowLevelUint2x(
        bytes memory lowLevelData_,
        bytes4 targetErrorSelector_
    ) internal pure returns (uint value1_, uint value2_) {
        if (lowLevelData_.length < 68) {
            return (0, 0);
        }

        bytes4 errorSelector_;
        assembly {
            // Extract the selector from the error data
            errorSelector_ := mload(add(lowLevelData_, 0x20))
        }
        if (errorSelector_ == targetErrorSelector_) {
            assembly {
                value1_ := mload(add(lowLevelData_, 36))
                value2_ := mload(add(lowLevelData_, 68))
            }
        }
        // else => values remain 0
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

abstract contract DexConstantsViews {
    /// @notice returns all Dex constants
    function getDexConstantsView(address dex_) public view returns (IFluidDexT1.ConstantViews memory constantsView_) {
        return IFluidDexT1(dex_).constantsView();
    }

    /// @notice returns all Dex constants 2
    function getDexConstantsView2(
        address dex_
    ) public view returns (IFluidDexT1.ConstantViews2 memory constantsView2_) {
        return IFluidDexT1(dex_).constantsView2();
    }

    /// @notice Get the addresses of the tokens in a DEX
    /// @param dex_ The address of the DEX
    /// @return token0_ The address of token0 in the DEX
    /// @return token1_ The address of token1 in the DEX
    function getDexTokens(address dex_) public view returns (address token0_, address token1_) {
        IFluidDexT1.ConstantViews memory constantsView_ = IFluidDexT1(dex_).constantsView();
        return (constantsView_.token0, constantsView_.token1);
    }
}

abstract contract DexPublicViews is DexStorageVars, DexConstantsViews {
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

    /// @notice Get the collateral reserves for a DEX
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing collateral reserve information
    /// @dev expected to be called via callStatic
    function getDexCollateralReserves(address dex_) public returns (IFluidDexT1.CollateralReserves memory reserves_) {
        return _getDexCollateralReserves(dex_, getDexConstantsView2(dex_));
    }

    /// @notice Get the debt reserves for a DEX
    /// @param dex_ The address of the DEX
    /// @return reserves_ A struct containing debt reserve information
    /// @dev expected to be called via callStatic
    function getDexDebtReserves(address dex_) public returns (IFluidDexT1.DebtReserves memory reserves_) {
        return _getDexDebtReserves(dex_, getDexConstantsView2(dex_));
    }

    /// @notice get Dex oracle price TWAP data
    /// @param secondsAgos_ array of seconds ago for which TWAP is needed. If user sends [10, 30, 60] then twaps_ will return [10-0, 30-10, 60-30]
    /// @return twaps_ twap price, lowest price (aka minima) & highest price (aka maxima) between secondsAgo checkpoints
    /// @return currentPrice_ price of pool after the most recent swap
    function getDexOraclePrice(
        address dex_,
        uint[] memory secondsAgos_
    ) external view returns (IFluidDexT1.Oracle[] memory twaps_, uint currentPrice_) {
        return IFluidDexT1(dex_).oraclePrice(secondsAgos_);
    }

    /// @dev Get the collateral reserves for a DEX scaled to token decimals
    function _getDexCollateralReserves(
        address dex_,
        IFluidDexT1.ConstantViews2 memory constantsView2_
    ) internal returns (IFluidDexT1.CollateralReserves memory reserves_) {
        uint256 dexVariables2_ = getDexVariables2Raw(dex_);
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
                reserves_.token0RealReserves =
                    (colReserves_.token0RealReserves * constantsView2_.token0DenominatorPrecision) /
                    constantsView2_.token0NumeratorPrecision;
                reserves_.token0ImaginaryReserves =
                    (colReserves_.token0ImaginaryReserves * constantsView2_.token0DenominatorPrecision) /
                    constantsView2_.token0NumeratorPrecision;
                reserves_.token1RealReserves =
                    (colReserves_.token1RealReserves * constantsView2_.token1DenominatorPrecision) /
                    constantsView2_.token1NumeratorPrecision;
                reserves_.token1ImaginaryReserves =
                    (colReserves_.token1ImaginaryReserves * constantsView2_.token1DenominatorPrecision) /
                    constantsView2_.token1NumeratorPrecision;
            } catch {
                reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
            }
        } catch {
            reserves_ = IFluidDexT1.CollateralReserves(0, 0, 0, 0);
        }
    }

    /// @dev Get the debt reserves for a DEX scaled to token decimals
    function _getDexDebtReserves(
        address dex_,
        IFluidDexT1.ConstantViews2 memory constantsView2_
    ) internal returns (IFluidDexT1.DebtReserves memory reserves_) {
        uint256 dexVariables2_ = getDexVariables2Raw(dex_);
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
                reserves_.token0Debt =
                    (debtReserves_.token0Debt * constantsView2_.token0DenominatorPrecision) /
                    constantsView2_.token0NumeratorPrecision;
                reserves_.token0RealReserves =
                    (debtReserves_.token0RealReserves * constantsView2_.token0DenominatorPrecision) /
                    constantsView2_.token0NumeratorPrecision;
                reserves_.token0ImaginaryReserves =
                    (debtReserves_.token0ImaginaryReserves * constantsView2_.token0DenominatorPrecision) /
                    constantsView2_.token0NumeratorPrecision;
                reserves_.token1Debt =
                    (debtReserves_.token1Debt * constantsView2_.token1DenominatorPrecision) /
                    constantsView2_.token1NumeratorPrecision;
                reserves_.token1RealReserves =
                    (debtReserves_.token1RealReserves * constantsView2_.token1DenominatorPrecision) /
                    constantsView2_.token1NumeratorPrecision;
                reserves_.token1ImaginaryReserves =
                    (debtReserves_.token1ImaginaryReserves * constantsView2_.token1DenominatorPrecision) /
                    constantsView2_.token1NumeratorPrecision;
            } catch {
                reserves_ = IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
            }
        } catch {
            reserves_ = IFluidDexT1.DebtReserves(0, 0, 0, 0, 0, 0);
        }
    }
}

abstract contract DexUserViews is Variables, Structs, DexConstantsViews, DexPublicViews {
    /// @notice Get user supply data for a specific DEX and user
    /// @param dex_ The address of the DEX
    /// @param user_ The address of the user
    /// @return userSupplyData_ Struct containing user supply data
    function getUserSupplyData(
        address dex_,
        address user_
    ) public view returns (UserSupplyData memory userSupplyData_) {
        uint256 userSupply_ = getUserSupplyDataRaw(dex_, user_);

        if (userSupply_ > 0) {
            // if userSupply_ == 0 -> user not configured yet
            userSupplyData_.isAllowed = userSupply_ & 1 == 1;
            userSupplyData_.supply = BigMathMinified.fromBigNumber(
                (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) & DexCalcs.X64,
                DexCalcs.DEFAULT_EXPONENT_SIZE,
                DexCalcs.DEFAULT_EXPONENT_MASK
            );

            // get updated expanded withdrawal limit
            userSupplyData_.withdrawalLimit = DexCalcs.calcWithdrawalLimitBeforeOperate(
                userSupply_,
                userSupplyData_.supply
            );

            userSupplyData_.lastUpdateTimestamp =
                (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) &
                DexCalcs.X33;
            userSupplyData_.expandPercent =
                (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) &
                DexCalcs.X14;
            userSupplyData_.expandDuration =
                (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) &
                DexCalcs.X24;
            userSupplyData_.baseWithdrawalLimit = BigMathMinified.fromBigNumber(
                (userSupply_ >> DexSlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & DexCalcs.X18,
                DexCalcs.DEFAULT_EXPONENT_SIZE,
                DexCalcs.DEFAULT_EXPONENT_MASK
            );

            userSupplyData_.withdrawableUntilLimit = userSupplyData_.supply > userSupplyData_.withdrawalLimit
                ? userSupplyData_.supply - userSupplyData_.withdrawalLimit
                : 0;

            userSupplyData_.withdrawable = userSupplyData_.withdrawableUntilLimit;

            (address token0_, address token1_) = getDexTokens(dex_);
            (userSupplyData_.liquidityUserSupplyDataToken0, userSupplyData_.liquidityTokenData0) = LIQUIDITY_RESOLVER
                .getUserSupplyData(dex_, token0_);
            (userSupplyData_.liquidityUserSupplyDataToken1, userSupplyData_.liquidityTokenData1) = LIQUIDITY_RESOLVER
                .getUserSupplyData(dex_, token1_);
        }
    }

    /// @notice Get user supply data for multiple users in a specific DEX
    /// @param dex_ The address of the DEX
    /// @param users_ Array of user addresses
    /// @return userSuppliesData_ Array of UserSupplyData structs for each user
    function getUserSupplyDatas(
        address dex_,
        address[] calldata users_
    ) public view returns (UserSupplyData[] memory userSuppliesData_) {
        uint256 length_ = users_.length;
        userSuppliesData_ = new UserSupplyData[](length_);

        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i]) = getUserSupplyData(dex_, users_[i]);
        }
    }

    /// @notice Get user borrow data for a specific DEX and user
    /// @param dex_ The address of the DEX
    /// @param user_ The address of the user
    /// @return userBorrowData_ Struct containing user borrow data
    function getUserBorrowData(
        address dex_,
        address user_
    ) public view returns (UserBorrowData memory userBorrowData_) {
        uint256 userBorrow_ = getUserBorrowDataRaw(dex_, user_);

        if (userBorrow_ > 0) {
            // if userBorrow_ == 0 -> user not configured yet

            userBorrowData_.isAllowed = userBorrow_ & 1 == 1;

            userBorrowData_.borrow = BigMathMinified.fromBigNumber(
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_AMOUNT) & DexCalcs.X64,
                DexCalcs.DEFAULT_EXPONENT_SIZE,
                DexCalcs.DEFAULT_EXPONENT_MASK
            );

            // get updated expanded borrow limit
            userBorrowData_.borrowLimit = DexCalcs.calcBorrowLimitBeforeOperate(userBorrow_, userBorrowData_.borrow);

            userBorrowData_.lastUpdateTimestamp =
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP) &
                DexCalcs.X33;
            userBorrowData_.expandPercent =
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) &
                DexCalcs.X14;
            userBorrowData_.expandDuration =
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) &
                DexCalcs.X24;
            userBorrowData_.baseBorrowLimit = BigMathMinified.fromBigNumber(
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & DexCalcs.X18,
                DexCalcs.DEFAULT_EXPONENT_SIZE,
                DexCalcs.DEFAULT_EXPONENT_MASK
            );
            userBorrowData_.maxBorrowLimit = BigMathMinified.fromBigNumber(
                (userBorrow_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & DexCalcs.X18,
                DexCalcs.DEFAULT_EXPONENT_SIZE,
                DexCalcs.DEFAULT_EXPONENT_MASK
            );

            userBorrowData_.borrowableUntilLimit = userBorrowData_.borrowLimit > userBorrowData_.borrow
                ? userBorrowData_.borrowLimit - userBorrowData_.borrow
                : 0;

            userBorrowData_.borrowable = userBorrowData_.borrowableUntilLimit;

            (address token0_, address token1_) = getDexTokens(dex_);
            (userBorrowData_.liquidityUserBorrowDataToken0, userBorrowData_.liquidityTokenData0) = LIQUIDITY_RESOLVER
                .getUserBorrowData(dex_, token0_);
            (userBorrowData_.liquidityUserBorrowDataToken1, userBorrowData_.liquidityTokenData1) = LIQUIDITY_RESOLVER
                .getUserBorrowData(dex_, token1_);
        }
    }

    /// @notice Get user borrow data for multiple users in a specific DEX
    /// @param dex_ The address of the DEX
    /// @param users_ Array of user addresses
    /// @return userBorrowingsData_ Array of UserBorrowData structs for each user
    function getUserBorrowDatas(
        address dex_,
        address[] calldata users_
    ) public view returns (UserBorrowData[] memory userBorrowingsData_) {
        uint256 length_ = users_.length;
        userBorrowingsData_ = new UserBorrowData[](length_);

        for (uint256 i; i < length_; i++) {
            (userBorrowingsData_[i]) = getUserBorrowData(dex_, users_[i]);
        }
    }

    /// @notice Get both user supply and borrow data for multiple users in a specific DEX
    /// @param dex_ The address of the DEX
    /// @param users_ Array of user addresses
    /// @return userSuppliesData_ Array of UserSupplyData structs for each user
    /// @return userBorrowingsData_ Array of UserBorrowData structs for each user
    function getUserBorrowSupplyDatas(
        address dex_,
        address[] calldata users_
    ) public view returns (UserSupplyData[] memory userSuppliesData_, UserBorrowData[] memory userBorrowingsData_) {
        uint256 length_ = users_.length;
        userSuppliesData_ = new UserSupplyData[](length_);
        userBorrowingsData_ = new UserBorrowData[](length_);
        for (uint256 i; i < length_; i++) {
            (userSuppliesData_[i]) = getUserSupplyData(dex_, users_[i]);
            (userBorrowingsData_[i]) = getUserBorrowData(dex_, users_[i]);
        }
    }
}

/// @notice Fluid Dex protocol resolver
/// Implements various view-only methods to give easy access to Dex protocol data.
contract FluidDexResolver is Variables, DexFactoryViews, DexActionEstimates, DexUserViews {
    constructor(
        address factory_,
        address liquidity_,
        address liquidityResolver_,
        address deployer_
    ) Variables(factory_, liquidity_, liquidityResolver_, deployer_) {}

    /// @notice Get the current state of a DEX
    /// @param dex_ The address of the DEX
    /// @return state_ A struct containing the current state of the DEX
    /// @dev expected to be called via callStatic
    function getDexState(address dex_) public returns (DexState memory state_) {
        return _getDexState(dex_, getDexCollateralReserves(dex_), getDexDebtReserves(dex_));
    }

    /// @notice Get the current configurations of a DEX
    /// @param dex_ The address of the DEX
    /// @return configs_ A struct containing the current configurations of the DEX
    function getDexConfigs(address dex_) public view returns (Configs memory configs_) {
        uint256 dexVariables2_ = getDexVariables2Raw(dex_);

        configs_.isSmartCollateralEnabled = (dexVariables2_ & 1) == 1;
        configs_.isSmartDebtEnabled = (dexVariables2_ & 2) == 2;
        configs_.fee = (dexVariables2_ >> 2) & X17;
        configs_.revenueCut = (dexVariables2_ >> 19) & X7;
        configs_.upperRange = (dexVariables2_ >> 27) & X20;
        configs_.lowerRange = (dexVariables2_ >> 47) & X20;
        configs_.upperShiftThreshold = (dexVariables2_ >> 68) & X10;
        configs_.lowerShiftThreshold = (dexVariables2_ >> 78) & X10;
        configs_.shiftingTime = (dexVariables2_ >> 88) & X24;

        configs_.maxSupplyShares = getTotalSupplySharesRaw(dex_) >> 128;
        configs_.maxBorrowShares = getTotalBorrowSharesRaw(dex_) >> 128;

        uint256 addressNonce_ = (dexVariables2_ >> 112) & X30;
        if (addressNonce_ > 0) {
            configs_.centerPriceAddress = AddressCalcs.addressCalc(DEPLOYER_CONTRACT, addressNonce_);
        }

        addressNonce_ = (dexVariables2_ >> 142) & X30;
        if (addressNonce_ > 0) {
            configs_.hookAddress = AddressCalcs.addressCalc(DEPLOYER_CONTRACT, addressNonce_);
        }

        configs_.maxCenterPrice = BigMathMinified.fromBigNumber(
            (dexVariables2_ >> 172) & X28,
            DexCalcs.DEFAULT_EXPONENT_SIZE,
            DexCalcs.DEFAULT_EXPONENT_MASK
        );
        configs_.minCenterPrice = BigMathMinified.fromBigNumber(
            (dexVariables2_ >> 200) & X28,
            DexCalcs.DEFAULT_EXPONENT_SIZE,
            DexCalcs.DEFAULT_EXPONENT_MASK
        );

        configs_.utilizationLimitToken0 = (dexVariables2_ >> 228) & X10;
        configs_.utilizationLimitToken1 = (dexVariables2_ >> 238) & X10;
    }

    /// @notice Get the swap limits and availability for a DEX
    /// @param dex_ The address of the DEX
    /// @return limitsAndAvailability_ A struct containing the swap limits and availability for the DEX
    function getDexSwapLimitsAndAvailability(
        address dex_
    ) public view returns (SwapLimitsAndAvailability memory limitsAndAvailability_) {
        (address token0_, address token1_) = getDexTokens(dex_);

        uint256 dexVariables2_ = getDexVariables2Raw(dex_);
        uint256 utilizationLimitToken0_ = (dexVariables2_ >> 228) & X10;
        uint256 utilizationLimitToken1_ = (dexVariables2_ >> 238) & X10;

        return
            _getDexSwapLimitsAndAvailability(dex_, token0_, token1_, utilizationLimitToken0_, utilizationLimitToken1_);
    }

    /// @notice Get the entire data for a DEX
    /// @param dex_ The address of the DEX
    /// @return data_ A struct containing all the data for the DEX
    /// @dev expected to be called via callStatic
    function getDexEntireData(address dex_) public returns (DexEntireData memory data_) {
        data_.dex = dex_;
        data_.constantViews = getDexConstantsView(dex_);
        data_.constantViews2 = getDexConstantsView2(dex_);
        data_.configs = getDexConfigs(dex_);
        data_.pex = getDexPricesAndExchangePrices(dex_);
        data_.colReserves = _getDexCollateralReserves(dex_, data_.constantViews2);
        data_.debtReserves = _getDexDebtReserves(dex_, data_.constantViews2);
        data_.dexState = _getDexState(dex_, data_.colReserves, data_.debtReserves);
        data_.limitsAndAvailability = _getDexSwapLimitsAndAvailability(
            dex_,
            data_.constantViews.token0,
            data_.constantViews.token1,
            data_.configs.utilizationLimitToken0,
            data_.configs.utilizationLimitToken1
        );
    }

    /// @notice Get the entire data for multiple DEXes
    /// @param dexes_ An array of DEX addresses
    /// @return datas_ An array of structs containing all the data for each DEX
    /// @dev expected to be called via callStatic
    function getDexEntireDatas(address[] memory dexes_) public returns (DexEntireData[] memory datas_) {
        uint256 length_ = dexes_.length;
        datas_ = new DexEntireData[](length_);

        for (uint256 i; i < length_; i++) {
            datas_[i] = getDexEntireData(dexes_[i]);
        }
    }

    /// @notice Get the entire data for all DEXes
    /// @return datas_ An array of structs containing all the data for all DEXes
    /// @dev expected to be called via callStatic
    function getAllDexEntireDatas() external returns (DexEntireData[] memory datas_) {
        return getDexEntireDatas(getAllDexAddresses());
    }

    /// @dev get the swap limits and availability for a DEX
    /// @param dex_ The address of the DEX
    /// @param token0_ The address of token0
    /// @param token1_ The address of token1
    /// @param utilizationLimitToken0Percent_ The utilization limit percentage for token0
    /// @param utilizationLimitToken1Percent_ The utilization limit percentage for token1
    /// @return limitsAndAvailability_ A struct containing the swap limits and availability for the DEX
    function _getDexSwapLimitsAndAvailability(
        address dex_,
        address token0_,
        address token1_,
        uint256 utilizationLimitToken0Percent_,
        uint256 utilizationLimitToken1Percent_
    ) internal view returns (SwapLimitsAndAvailability memory limitsAndAvailability_) {
        (
            limitsAndAvailability_.liquidityUserSupplyDataToken0,
            limitsAndAvailability_.liquidityTokenData0
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(dex_, token0_);
        (
            limitsAndAvailability_.liquidityUserSupplyDataToken1,
            limitsAndAvailability_.liquidityTokenData1
        ) = LIQUIDITY_RESOLVER.getUserSupplyData(dex_, token1_);

        (limitsAndAvailability_.liquidityUserBorrowDataToken0, ) = LIQUIDITY_RESOLVER.getUserBorrowData(dex_, token0_);
        (limitsAndAvailability_.liquidityUserBorrowDataToken1, ) = LIQUIDITY_RESOLVER.getUserBorrowData(dex_, token1_);

        limitsAndAvailability_.liquiditySupplyToken0 = limitsAndAvailability_.liquidityTokenData0.totalSupply;
        limitsAndAvailability_.liquiditySupplyToken1 = limitsAndAvailability_.liquidityTokenData1.totalSupply;
        limitsAndAvailability_.liquidityBorrowToken0 = limitsAndAvailability_.liquidityTokenData0.totalBorrow;
        limitsAndAvailability_.liquidityBorrowToken1 = limitsAndAvailability_.liquidityTokenData1.totalBorrow;

        limitsAndAvailability_.liquidityWithdrawableToken0 = limitsAndAvailability_
            .liquidityUserSupplyDataToken0
            .withdrawable;
        limitsAndAvailability_.liquidityWithdrawableToken1 = limitsAndAvailability_
            .liquidityUserSupplyDataToken1
            .withdrawable;

        limitsAndAvailability_.liquidityBorrowableToken0 = limitsAndAvailability_
            .liquidityUserBorrowDataToken0
            .borrowable;
        limitsAndAvailability_.liquidityBorrowableToken1 = limitsAndAvailability_
            .liquidityUserBorrowDataToken1
            .borrowable;

        limitsAndAvailability_.utilizationLimitToken0 =
            (limitsAndAvailability_.liquiditySupplyToken0 * utilizationLimitToken0Percent_) /
            1e3;
        limitsAndAvailability_.utilizationLimitToken1 =
            (limitsAndAvailability_.liquiditySupplyToken1 * utilizationLimitToken1Percent_) /
            1e3;

        if (limitsAndAvailability_.liquidityBorrowToken0 < limitsAndAvailability_.utilizationLimitToken0) {
            limitsAndAvailability_.withdrawableUntilUtilizationLimitToken0 =
                (1e3 * limitsAndAvailability_.liquidityBorrowToken0) /
                utilizationLimitToken0Percent_;
            limitsAndAvailability_.withdrawableUntilUtilizationLimitToken0 = limitsAndAvailability_
                .liquiditySupplyToken0 > limitsAndAvailability_.withdrawableUntilUtilizationLimitToken0
                ? limitsAndAvailability_.liquiditySupplyToken0 -
                    limitsAndAvailability_.withdrawableUntilUtilizationLimitToken0
                : 0;

            limitsAndAvailability_.borrowableUntilUtilizationLimitToken0 =
                limitsAndAvailability_.utilizationLimitToken0 -
                limitsAndAvailability_.liquidityBorrowToken0;
        }

        if (limitsAndAvailability_.liquidityBorrowToken1 < limitsAndAvailability_.utilizationLimitToken1) {
            limitsAndAvailability_.withdrawableUntilUtilizationLimitToken1 =
                (1e3 * limitsAndAvailability_.liquidityBorrowToken1) /
                utilizationLimitToken1Percent_;
            limitsAndAvailability_.withdrawableUntilUtilizationLimitToken1 = limitsAndAvailability_
                .liquiditySupplyToken1 > limitsAndAvailability_.withdrawableUntilUtilizationLimitToken1
                ? limitsAndAvailability_.liquiditySupplyToken1 -
                    limitsAndAvailability_.withdrawableUntilUtilizationLimitToken1
                : 0;

            limitsAndAvailability_.borrowableUntilUtilizationLimitToken1 =
                limitsAndAvailability_.utilizationLimitToken1 -
                limitsAndAvailability_.liquidityBorrowToken1;
        }
    }

    /// @dev Get the current state of a DEX
    function _getDexState(
        address dex_,
        IFluidDexT1.CollateralReserves memory colReserves_,
        IFluidDexT1.DebtReserves memory debtReserves_
    ) internal view returns (DexState memory state_) {
        uint256 storageVar_ = getDexVariablesRaw(dex_);

        /// Next 40 bits => 1-40 => last to last stored price. BigNumber (32 bits precision, 8 bits exponent)
        /// Next 40 bits => 41-80 => last stored price of pool. BigNumber (32 bits precision, 8 bits exponent)
        /// Next 40 bits => 81-120 => center price. Center price from where the ranges will be calculated. BigNumber (32 bits precision, 8 bits exponent)
        state_.lastToLastStoredPrice = (storageVar_ >> 1) & X40;
        state_.lastToLastStoredPrice = (state_.lastToLastStoredPrice >> 8) << (state_.lastToLastStoredPrice & X8);
        state_.lastStoredPrice = (storageVar_ >> 41) & X40;
        state_.lastStoredPrice = (state_.lastStoredPrice >> 8) << (state_.lastStoredPrice & X8);
        state_.centerPrice = (storageVar_ >> 81) & X40;
        state_.centerPrice = (state_.centerPrice >> 8) << (state_.centerPrice & X8);

        state_.lastUpdateTimestamp = (storageVar_ >> 121) & X33;
        state_.lastPricesTimeDiff = (storageVar_ >> 154) & X22;
        state_.oracleCheckPoint = (storageVar_ >> 176) & X3;
        state_.oracleMapping = (storageVar_ >> 179) & X16;

        state_.totalSupplyShares = getTotalSupplySharesRaw(dex_) & X128;
        state_.totalBorrowShares = getTotalBorrowSharesRaw(dex_) & X128;

        storageVar_ = getDexVariables2Raw(dex_);
        state_.isSwapAndArbitragePaused = storageVar_ >> 255 == 1;

        state_.shifts.isRangeChangeActive = (storageVar_ >> 26) & 1 == 1;
        state_.shifts.isThresholdChangeActive = (storageVar_ >> 67) & 1 == 1;
        state_.shifts.isCenterPriceShiftActive = (storageVar_ >> 248) & 1 == 1;

        storageVar_ = getRangeShiftRaw(dex_);
        state_.shifts.rangeShift.oldUpper = storageVar_ & X20;
        state_.shifts.rangeShift.oldLower = (storageVar_ >> 20) & X20;
        state_.shifts.rangeShift.duration = (storageVar_ >> 40) & X20;
        state_.shifts.rangeShift.startTimestamp = (storageVar_ >> 60) & X33;

        storageVar_ = getThresholdShiftRaw(dex_);
        state_.shifts.thresholdShift.oldUpper = storageVar_ & X10;
        state_.shifts.thresholdShift.oldLower = (storageVar_ >> 20) & X10;
        state_.shifts.thresholdShift.duration = (storageVar_ >> 40) & X20;
        state_.shifts.thresholdShift.startTimestamp = (storageVar_ >> 60) & X33;
        state_.shifts.thresholdShift.oldTime = (storageVar_ >> 93) & X24;

        storageVar_ = getCenterPriceShiftRaw(dex_);
        state_.shifts.centerPriceShift.startTimestamp = storageVar_ & X33;
        state_.shifts.centerPriceShift.shiftPercentage = (storageVar_ >> 33) & X20;
        state_.shifts.centerPriceShift.duration = (storageVar_ >> 53) & X20;

        if (state_.totalSupplyShares > 0) {
            state_.token0PerSupplyShare = (colReserves_.token0RealReserves * 1e18) / state_.totalSupplyShares;
            state_.token1PerSupplyShare = (colReserves_.token1RealReserves * 1e18) / state_.totalSupplyShares;
        }
        if (state_.totalBorrowShares > 0) {
            state_.token0PerBorrowShare = (debtReserves_.token0Debt * 1e18) / state_.totalBorrowShares;
            state_.token1PerBorrowShare = (debtReserves_.token1Debt * 1e18) / state_.totalBorrowShares;
        }
    }
}
