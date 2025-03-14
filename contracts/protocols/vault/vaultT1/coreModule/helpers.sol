// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "../common/variables.sol";
import { ConstantVariables } from "./constantVariables.sol";
import { Events } from "./events.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";

import { ErrorTypes } from "../../errorTypes.sol";
import { Error } from "../../error.sol";

/// @dev Fluid vault protocol helper methods. Mostly used for `operate()` and `liquidate()` methods of CoreModule.
abstract contract Helpers is Variables, ConstantVariables, Events, Error {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

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

        (liqSupplyExPrice_, ) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT)
        );
        (, liqBorrowExPrice_) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT)
        );

        uint256 oldLiqSupplyExPrice_ = (rates_ & X64);
        uint256 oldLiqBorrowExPrice_ = ((rates_ >> 64) & X64);
        if (liqSupplyExPrice_ < oldLiqSupplyExPrice_ || liqBorrowExPrice_ < oldLiqBorrowExPrice_) {
            // new liquidity exchange price is < than the old one. liquidity exchange price should only ever increase.
            // If not, something went wrong and avoid proceeding with unknown outcome.
            revert FluidVaultError(ErrorTypes.Vault__LiquidityExchangePriceUnexpected);
        }

        // liquidity Exchange Prices always increases in next block. Hence substraction with old will never be negative
        // uint64 * 1e18 is the max the number that could be
        unchecked {
            // Calculating increase in supply exchange price w.r.t last stored liquidity's exchange price
            // vaultSupplyExPrice_ => supplyIncreaseInPercent_
            vaultSupplyExPrice_ = ((((liqSupplyExPrice_ * 1e18) / oldLiqSupplyExPrice_) - 1e18) *
                (vaultVariables2_ & X16)) / 10000; // supply rate magnifier

            // Calculating increase in borrow exchange price w.r.t last stored liquidity's exchange price
            // vaultBorrowExPrice_ => borrowIncreaseInPercent_
            vaultBorrowExPrice_ = ((((liqBorrowExPrice_ * 1e18) / oldLiqBorrowExPrice_) - 1e18) *
                ((vaultVariables2_ >> 16) & X16)) / 10000; // borrow rate magnifier

            // It's extremely hard the exchange prices to overflow even in 100 years but if it does it's not an
            // issue here as we are not updating on storage
            // (rates_ >> 128) & X64) -> last stored vault's supply token exchange price
            vaultSupplyExPrice_ = (((rates_ >> 128) & X64) * (1e18 + vaultSupplyExPrice_)) / 1e18;
            // (rates_ >> 192) -> last stored vault's borrow token exchange price (no need to mask with & X64 as it is anyway max 64 bits)
            vaultBorrowExPrice_ = ((rates_ >> 192) * (1e18 + vaultBorrowExPrice_)) / 1e18;
        }
    }

    /// note admin module is also calling this function self call
    /// @dev updating exchange price on storage. Only need to update on storage when changing supply or borrow magnifier
    function updateExchangePricesOnStorage()
        public
        returns (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        )
    {
        (liqSupplyExPrice_, liqBorrowExPrice_, vaultSupplyExPrice_, vaultBorrowExPrice_) = updateExchangePrices(
            vaultVariables2
        );

        if (
            liqSupplyExPrice_ > X64 || liqBorrowExPrice_ > X64 || vaultSupplyExPrice_ > X64 || vaultBorrowExPrice_ > X64
        ) {
            revert FluidVaultError(ErrorTypes.Vault__ExchangePriceOverFlow);
        }

        // Updating in storage
        rates =
            liqSupplyExPrice_ |
            (liqBorrowExPrice_ << 64) |
            (vaultSupplyExPrice_ << 128) |
            (vaultBorrowExPrice_ << 192);

        emit LogUpdateExchangePrice(vaultSupplyExPrice_, vaultBorrowExPrice_);
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

    /// @dev sets `tick_` as having debt or no debt in storage `tickHasDebt` depending on `addOrRemove_`
    /// @param tick_ tick to add or remove from tickHasDebt
    /// @param addOrRemove_ if true then add else remove
    function _updateTickHasDebt(int tick_, bool addOrRemove_) internal {
        // Positive mapID_ starts from 0 & above and negative starts below 0.
        // tick 0 to 255 will have mapId_ as 0 while tick -256 to -1 will have mapId_ as -1.
        unchecked {
            int mapId_ = tick_ < 0 ? ((tick_ + 1) / 256) - 1 : tick_ / 256;

            // in case of removing:
            // (tick == 255) tickHasDebt[mapId_] - 1 << 255
            // (tick == 0) tickHasDebt[mapId_] - 1 << 0
            // (tick == -1) tickHasDebt[mapId_] - 1 << 255
            // (tick == -256) tickHasDebt[mapId_] - 1 << 0
            // in case of adding:
            // (tick == 255) tickHasDebt[mapId_] - 1 << 255
            // (tick == 0) tickHasDebt[mapId_] - 1 << 0
            // (tick == -1) tickHasDebt[mapId_] - 1 << 255
            // (tick == -256) tickHasDebt[mapId_] - 1 << 0
            uint position_ = uint(tick_ - (mapId_ * 256));

            tickHasDebt[mapId_] = addOrRemove_
                ? tickHasDebt[mapId_] | (1 << position_)
                : tickHasDebt[mapId_] & ~(1 << position_);
        }
    }

    /// @dev gets next perfect top tick (tick which is not liquidated)
    /// @param topTick_ current top tick which will no longer be top tick
    /// @return nextTick_ next top tick which will become the new top tick
    function _fetchNextTopTick(int topTick_) internal view returns (int nextTick_) {
        int mapId_;
        uint tickHasDebt_;

        unchecked {
            mapId_ = topTick_ < 0 ? ((topTick_ + 1) / 256) - 1 : topTick_ / 256;
            uint bitsToRemove_ = uint(-topTick_ + (mapId_ * 256 + 256));
            // Removing current top tick from tickHasDebt
            tickHasDebt_ = (tickHasDebt[mapId_] << bitsToRemove_) >> bitsToRemove_;

            // For last user remaining in vault there could be a lot of iterations in the while loop.
            // Chances of this to happen is extremely low (like ~0%)
            while (true) {
                if (tickHasDebt_ > 0) {
                    nextTick_ = mapId_ * 256 + int(tickHasDebt_.mostSignificantBit()) - 1;
                    break;
                }

                // Reducing mapId_ by 1 in every loop; if it reaches to -129 then no filled tick exist, meaning it's the last tick
                if (--mapId_ == -129) {
                    nextTick_ = type(int).min;
                    break;
                }

                tickHasDebt_ = tickHasDebt[mapId_];
            }
        }
    }

    /// @dev adding debt to a particular tick
    /// @param totalColRaw_ total raw collateral of position
    /// @param netDebtRaw_ net raw debt (total debt - dust debt)
    /// @return tick_ tick where the debt is being added
    /// @return tickId_ tick current id
    /// @return userRawDebt_ user's total raw debt
    /// @return rawDust_ dust debt used for adjustment
    function _addDebtToTickWrite(
        uint256 totalColRaw_,
        uint256 netDebtRaw_ // debtRaw - dust
    ) internal returns (int256 tick_, uint256 tickId_, uint256 userRawDebt_, uint256 rawDust_) {
        if (netDebtRaw_ < 10000) {
            // thrown if user's debt is too low
            revert FluidVaultError(ErrorTypes.Vault__UserDebtTooLow);
        }
        // tick_ & ratio_ returned from library is round down. Hence increasing it by 1 and increasing ratio by 1 tick.
        uint ratio_ = (netDebtRaw_ * TickMath.ZERO_TICK_SCALED_RATIO) / totalColRaw_;
        (tick_, ratio_) = TickMath.getTickAtRatio(ratio_);
        unchecked {
            ++tick_;
            ratio_ = (ratio_ * 10015) / 10000;
        }
        userRawDebt_ = (ratio_ * totalColRaw_) >> 96;
        rawDust_ = userRawDebt_ - netDebtRaw_;

        // Current state of tick
        uint256 tickData_ = tickData[tick_];
        tickId_ = (tickData_ >> 1) & X24;

        uint tickNewDebt_;
        if (tickId_ > 0 && tickData_ & 1 == 0) {
            // Current debt in the tick
            uint256 tickExistingRawDebt_ = (tickData_ >> 25) & X64;
            tickExistingRawDebt_ = (tickExistingRawDebt_ >> 8) << (tickExistingRawDebt_ & X8);

            // Tick's already initialized and not liquidated. Hence simply add the debt
            tickNewDebt_ = tickExistingRawDebt_ + userRawDebt_;
            if (tickExistingRawDebt_ == 0) {
                // Adding tick into tickHasDebt
                _updateTickHasDebt(tick_, true);
            }
        } else {
            // Liquidation happened or tick getting initialized for the very first time.
            if (tickId_ > 0) {
                // Meaning a liquidation happened. Hence move the data to tickID
                unchecked {
                    uint tickMap_ = (tickId_ + 2) / 3;
                    // Adding 2 in ID so we can get right mapping ID. For example for ID 1, 2 & 3 mapping should be 1 and so on..
                    // For example shift for id 1 should be 0, for id 2 should be 85, for id 3 it should be 170 and so on..
                    tickId[tick_][tickMap_] =
                        tickId[tick_][tickMap_] |
                        ((tickData_ >> 25) << (((tickId_ + 2) % 3) * 85));
                }
            }
            // Increasing total ID by one
            unchecked {
                ++tickId_;
            }
            tickNewDebt_ = userRawDebt_;

            // Adding tick into tickHasDebt
            _updateTickHasDebt(tick_, true);
        }
        if (tickNewDebt_ < 10000) {
            // thrown if tick's debt/liquidity is too low
            revert FluidVaultError(ErrorTypes.Vault__TickDebtTooLow);
        }
        tickData[tick_] = (tickId_ << 1) | (tickNewDebt_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 25);
    }

    /// @dev sets new top tick. If it comes to this function then that means current top tick is perfect tick.
    /// if next top tick is liquidated then unitializes the current non liquidated branch and make the liquidated branch as current branch
    /// @param topTick_ current top tick
    /// @param vaultVariables_ vaultVariables of storage but with newer updates
    /// @return newVaultVariables_ newVaultVariables_ updated vault variable internally to this function
    /// @return newTopTick_ new top tick
    function _setNewTopTick(
        int topTick_,
        uint vaultVariables_
    ) internal returns (uint newVaultVariables_, int newTopTick_) {
        // This function considers that the current top tick was not liquidated
        // Overall flow of function:
        // if new top tick liquidated (aka base branch's minima tick) -> Close the current branch and make base branch as current branch
        // if new top tick not liquidated -> update things in current branch.
        // if new top tick is not liquidated and same tick exist in base branch then tick is considered as not liquidated.

        uint branchId_ = (vaultVariables_ >> 22) & X30; // branch id of current branch

        uint256 branchData_ = branchData[branchId_];
        int256 baseBranchMinimaTick_;
        if ((branchData_ >> 196) & 1 == 1) {
            baseBranchMinimaTick_ = int((branchData_ >> 197) & X19);
        } else {
            unchecked {
                baseBranchMinimaTick_ = -int((branchData_ >> 197) & X19);
            }
            if (baseBranchMinimaTick_ == 0) {
                // meaning the current branch is the master branch
                baseBranchMinimaTick_ = type(int).min;
            }
        }

        // Returns type(int).min if no top tick exist
        int nextTopTickNotLiquidated_ = _fetchNextTopTick(topTick_);

        newTopTick_ = baseBranchMinimaTick_ > nextTopTickNotLiquidated_
            ? baseBranchMinimaTick_
            : nextTopTickNotLiquidated_;

        if (newTopTick_ == type(int).min) {
            // if this happens that means this was the last user of the vault :(
            vaultVariables_ = vaultVariables_ & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc00001;
        } else if (newTopTick_ == nextTopTickNotLiquidated_) {
            // New top tick exist in current non liquidated branch
            if (newTopTick_ < 0) {
                unchecked {
                    vaultVariables_ =
                        (vaultVariables_ & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc00001) |
                        (uint(-newTopTick_) << 3);
                }
            } else {
                vaultVariables_ =
                    (vaultVariables_ & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc00001) |
                    4 | // setting top tick as positive
                    (uint(newTopTick_) << 3);
            }
        } else {
            // if this happens that means base branch exists & is the next top tick
            // Remove current non liquidated branch as active.
            // Not deleting here as it's going to get initialize again whenever a new top tick comes
            branchData[branchId_] = 0;
            // Inserting liquidated branch's minima tick
            unchecked {
                vaultVariables_ =
                    (vaultVariables_ & 0xfffffffffffffffffffffffffffffffffffffffffffc00000000000000000001) |
                    2 | // Setting top tick as liquidated
                    (((branchData_ >> 196) & X20) << 2) | // new current top tick = base branch minima tick
                    (((branchData_ >> 166) & X30) << 22) | // new current branch id = base branch id
                    ((branchId_ - 1) << 52); // reduce total branch id by 1
            }
        }

        newVaultVariables_ = vaultVariables_;
    }

    constructor(ConstantViews memory constants_) ConstantVariables(constants_) {}
}
