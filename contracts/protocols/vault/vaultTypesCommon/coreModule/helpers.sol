// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "../common/variables.sol";
import { TokenTransfers } from "../common/tokenTransfers.sol";
import { ConstantVariables } from "./constantVariables.sol";
import { Events } from "./events.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";

/// @dev Fluid vault protocol helper methods. Mostly used for `operate()` and `liquidate()` methods of CoreModule.
abstract contract Helpers is Variables, ConstantVariables, Events, TokenTransfers {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

    modifier _dexFromAddress() {
        if (dexFromAddress != DEAD_ADDRESS) revert FluidVaultError(ErrorTypes.Vault__DexFromAddressAlreadySet);
        dexFromAddress = msg.sender;
        _;
        dexFromAddress = DEAD_ADDRESS;
    }

    /// @notice Calculates new vault exchange prices. Does not update values in storage.
    /// @param vaultVariables2_ exactly same as vaultVariables2 from storage
    /// @return liqSupplyExPrice_ latest liquidity's supply token supply exchange price
    /// @return liqBorrowExPrice_ latest liquidity's borrow token borrow exchange price
    /// @return vaultSupplyExPrice_ latest vault's supply token exchange price
    /// @return vaultBorrowExPrice_ latest vault's borrow token exchange price
    function updateExchangePrices(
        uint256 vaultVariables2_
    )
        public
        view
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        // Fetching last stored rates
        uint rates_ = rates;

        // in case of smart collateral oldLiqSupplyExPrice_ will be 0
        uint256 oldLiqSupplyExPrice_ = (rates_ & X64);
        // in case of smart debt oldLiqBorrowExPrice_ will be 0
        uint256 oldLiqBorrowExPrice_ = ((rates_ >> 64) & X64);

        uint timeStampDiff_ = block.timestamp - ((vaultVariables2_ >> 122) & X33);

        if (
            TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
            TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            liqSupplyExPrice_ = EXCHANGE_PRICES_PRECISION;
            // in case of smart collateral supply magnifier bits stores, supply interest rate positive or negative
            // negative meaning charging users, positive means incentivizing users
            vaultSupplyExPrice_ = ((rates_ >> 128) & X64);
            // if 1 then positive else negative
            if ((vaultVariables2_ & 1) == 1) {
                vaultSupplyExPrice_ =
                    vaultSupplyExPrice_ +
                    (vaultSupplyExPrice_ * timeStampDiff_ * ((vaultVariables2_ >> 1) & X15)) /
                    (10000 * LiquidityCalcs.SECONDS_PER_YEAR);
            } else {
                vaultSupplyExPrice_ =
                    vaultSupplyExPrice_ -
                    (vaultSupplyExPrice_ * timeStampDiff_ * ((vaultVariables2_ >> 1) & X15)) /
                    (10000 * LiquidityCalcs.SECONDS_PER_YEAR);
            }
        } else {
            (liqSupplyExPrice_, ) = LiquidityCalcs.calcExchangePrices(
                LIQUIDITY.readFromStorage(SUPPLY_EXCHANGE_PRICE_SLOT)
            );
            if (liqSupplyExPrice_ < oldLiqSupplyExPrice_) {
                // new liquidity exchange price is < than the old one. liquidity exchange price should only ever increase.
                // If not, something went wrong and avoid proceeding with unknown outcome.
                revert FluidVaultError(ErrorTypes.Vault__LiquidityExchangePriceUnexpected);
            }

            // liquidity Exchange Prices always increases in next block. Hence substraction with old will never be negative
            // uint64 * 1e18 is the max the number that could be
            unchecked {
                // Calculating increase in supply exchange price w.r.t last stored liquidity's exchange price
                // vaultSupplyExPrice_ => supplyIncreaseInPercent_
                vaultSupplyExPrice_ =
                    ((((liqSupplyExPrice_ * 1e18) / oldLiqSupplyExPrice_) - 1e18) * (vaultVariables2_ & X16)) /
                    10000; // supply rate magnifier

                // It's extremely hard the exchange prices to overflow even in 100 years but if it does it's not an
                // issue here as we are not updating on storage
                // (rates_ >> 128) & X64) -> last stored vault's supply token exchange price
                vaultSupplyExPrice_ = (((rates_ >> 128) & X64) * (1e18 + vaultSupplyExPrice_)) / 1e18;                
            }
        }

        if (
            TYPE == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
            TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            liqBorrowExPrice_ = EXCHANGE_PRICES_PRECISION;
            // in case of smart debt borrow magnifier bits stores, borrow interest rate positive or negative
            // negative meaning incentivizing users, positive means charging users
            vaultBorrowExPrice_ = ((rates_ >> 192) & X64);
            // if 1 then positive else negative
            if (((vaultVariables2_ >> 16) & 1) == 1) {
                vaultBorrowExPrice_ =
                    vaultBorrowExPrice_ +
                    (vaultBorrowExPrice_ * timeStampDiff_ * (((vaultVariables2_ >> 17) & X15))) /
                    (10000 * LiquidityCalcs.SECONDS_PER_YEAR);
            } else {
                vaultBorrowExPrice_ =
                    vaultBorrowExPrice_ -
                    (vaultBorrowExPrice_ * timeStampDiff_ * (((vaultVariables2_ >> 17) & X15))) /
                    (10000 * LiquidityCalcs.SECONDS_PER_YEAR);
            }
        } else {
            (, liqBorrowExPrice_) = LiquidityCalcs.calcExchangePrices(
                LIQUIDITY.readFromStorage(BORROW_EXCHANGE_PRICE_SLOT)
            );
            if (liqBorrowExPrice_ < oldLiqBorrowExPrice_) {
                // new liquidity exchange price is < than the old one. liquidity exchange price should only ever increase.
                // If not, something went wrong and avoid proceeding with unknown outcome.
                revert FluidVaultError(ErrorTypes.Vault__LiquidityExchangePriceUnexpected);
            }
            // liquidity Exchange Prices always increases in next block. Hence substraction with old will never be negative
            // uint64 * 1e18 is the max the number that could be
            unchecked {
                // Calculating increase in borrow exchange price w.r.t last stored liquidity's exchange price
                // vaultBorrowExPrice_ => borrowIncreaseInPercent_
                vaultBorrowExPrice_ =
                    ((((liqBorrowExPrice_ * 1e18) / oldLiqBorrowExPrice_) - 1e18) * ((vaultVariables2_ >> 16) & X16)) /
                    10000; // borrow rate magnifier

                // It's extremely hard the exchange prices to overflow even in 100 years but if it does it's not an
                // issue here as we are not updating on storage
                // (rates_ >> 192) -> last stored vault's borrow token exchange price (no need to mask with & X64 as it is anyway max 64 bits)
                vaultBorrowExPrice_ = ((rates_ >> 192) * (1e18 + vaultBorrowExPrice_)) / 1e18;
            }
        }
    }

    /// @dev fetches new user's position after liquidation. The new liquidated position's debt is decreased by 0.01%
    /// to make sure that branch's liquidity never becomes 0 as if it would have gotten 0 then there will be multiple cases that we would need to tackle.
    /// @param positionTick_ position's tick when it was last updated through operate
    /// @param positionTickId_ position's tick Id. This stores the debt factor and branch to make the first connection
    /// @param positionRawDebt_ position's raw debt when it was last updated through operate
    /// @param tickData_ position's tick's tickData just for minor comparison to know if data is moved to tick Id or is still in tick data
    /// @return final tick position after all the liquidation
    /// @return final debt of position after all the liquidation
    /// @return positionRawCol_ final collateral of position after all the liquidation
    /// @return branchId_ final branch's ID where the position is at currently
    /// @return branchData_ final branch's data where the position is at currently
    function fetchLatestPosition(
        int256 positionTick_,
        uint256 positionTickId_,
        uint256 positionRawDebt_,
        uint256 tickData_
    )
        public
        view
        returns (
            int256, // positionTick_
            uint256, // positionRawDebt_
            uint256 positionRawCol_,
            uint256 branchId_,
            uint256 branchData_
        )
    {
        uint256 initialPositionRawDebt_ = positionRawDebt_;
        uint256 connectionFactor_;
        bool isFullyLiquidated_;

        // Checking if tick's total ID = user's tick ID
        if (((tickData_ >> 1) & X24) == positionTickId_) {
            // fetching from tick data itself
            isFullyLiquidated_ = ((tickData_ >> 25) & 1) == 1;
            branchId_ = (tickData_ >> 26) & X30;
            connectionFactor_ = (tickData_ >> 56) & X50;
        } else {
            {
                uint256 tickLiquidationData_;
                unchecked {
                    // Fetching tick's liquidation data. One variable contains data of 3 IDs. Tick Id mapping is starting from 1.
                    tickLiquidationData_ =
                        tickId[positionTick_][(positionTickId_ + 2) / 3] >>
                        (((positionTickId_ + 2) % 3) * 85);
                }

                isFullyLiquidated_ = (tickLiquidationData_ & 1) == 1;
                branchId_ = (tickLiquidationData_ >> 1) & X30;
                connectionFactor_ = (tickLiquidationData_ >> 31) & X50;
            }
        }

        // data of branch
        branchData_ = branchData[branchId_];

        if (isFullyLiquidated_) {
            positionTick_ = type(int).min;
            positionRawDebt_ = 0;
        } else {
            // Below information about connection debt factor
            // If branch is merged, Connection debt factor is used to multiply in order to get perfect liquidation of user
            // For example: Considering user was at the top.
            // In first branch, the user liquidated to debt factor 0.5 and then branch got merged (branching starting from 1)
            // In second branch, it got liquidated to 0.4 but when the above branch merged the debt factor on this branch was 0.6
            // Meaning on 1st branch, user got liquidated by 50% & on 2nd by 33.33%. So a total of 66.6%.
            // What we will set a connection factor will be 0.6/0.5 = 1.2
            // So now to get user's position, this is what we'll do:
            // finalDebt = (0.4 / (1 * 1.2)) * debtBeforeLiquidation
            // 0.4 is current active branch's minima debt factor
            // 1 is debt factor from where user started
            // 1.2 is connection factor which we found out through 0.6 / 0.5
            while ((branchData_ & 3) == 2) {
                // If true then the branch is merged

                // userTickDebtFactor * connectionDebtFactor *... connectionDebtFactor aka adjustmentDebtFactor
                connectionFactor_ = connectionFactor_.mulBigNumber(((branchData_ >> 116) & X50));
                if (connectionFactor_ == BigMathVault.MAX_MASK_DEBT_FACTOR) break; // user ~100% liquidated
                // Note we don't need updated branch data in case of 100% liquidated so saving gas for fetching it

                // Fetching new branch data
                branchId_ = (branchData_ >> 166) & X30; // Link to base branch of current branch
                branchData_ = branchData[branchId_];
            }
            // When the while loop breaks meaning the branch now has minima Debt Factor or is a closed branch;

            if (((branchData_ & 3) == 3) || (connectionFactor_ == BigMathVault.MAX_MASK_DEBT_FACTOR)) {
                // Branch got closed (or user liquidated ~100%). Hence make the user's position 0
                // Rare cases to get into this situation
                // Branch can get close often but once closed it's tricky that some user might come iterating through there
                // If a user comes then that user will be very mini user like some cents probably
                positionTick_ = type(int).min;
                positionRawDebt_ = 0;
            } else {
                // If branch is not merged, the main branch it's connected to then it'll have minima debt factor

                // position debt = debt * base branch minimaDebtFactor / connectionFactor
                positionRawDebt_ = positionRawDebt_.mulDivNormal(
                    (branchData_ >> 116) & X50, // minimaDebtFactor
                    connectionFactor_
                );

                unchecked {
                    // Reducing user's liquidity by 0.01% if user got liquidated.
                    // As this will make sure that the branch always have some debt even if all liquidated user left
                    // This saves a lot more logics & consideration on Operate function
                    // if we don't do this then we have to add logics related to closing the branch and factor connections accordingly.
                    if (positionRawDebt_ > (initialPositionRawDebt_ / 100)) {
                        positionRawDebt_ = (positionRawDebt_ * 9999) / 10000;
                    } else {
                        // if user debt reduced by more than 99% in liquidation then making user as fully liquidated
                        positionRawDebt_ = 0;
                    }
                }

                {
                    if (positionRawDebt_ > 0) {
                        // positionTick_ -> read minima tick of branch
                        unchecked {
                            positionTick_ = branchData_ & 4 == 4
                                ? int((branchData_ >> 3) & X19)
                                : -int((branchData_ >> 3) & X19);
                        }
                        // Calculating user's collateral
                        uint256 ratioAtTick_ = TickMath.getRatioAtTick(int24(positionTick_));
                        uint256 ratioOneLess_;
                        unchecked {
                            ratioOneLess_ = (ratioAtTick_ * 10000) / 10015;
                        }
                        // formula below for better readability:
                        // length = ratioAtTick_ - ratioOneLess_
                        // ratio = ratioOneLess_ + (length * positionPartials_) / X30
                        // positionRawCol_ = (positionRawDebt_ * (1 << 96)) / ratio_
                        positionRawCol_ =
                            (positionRawDebt_ * TickMath.ZERO_TICK_SCALED_RATIO) /
                            (ratioOneLess_ + ((ratioAtTick_ - ratioOneLess_) * ((branchData_ >> 22) & X30)) / X30);
                    } else {
                        positionTick_ = type(int).min;
                    }
                }
            }
        }
        return (positionTick_, positionRawDebt_, positionRawCol_, branchId_, branchData_);
    }

    constructor(ConstantViews memory constants_) ConstantVariables(constants_) {}
}
