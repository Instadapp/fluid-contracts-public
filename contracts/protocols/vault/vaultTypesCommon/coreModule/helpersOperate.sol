// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Helpers } from "./helpers.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { ErrorTypes } from "../../errorTypes.sol";

/// @dev Fluid vault protocol helper methods. Mostly used for `operate()` and `liquidate()` methods of CoreModule.
abstract contract HelpersOperate is Helpers {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

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

    constructor(ConstantViews memory constants_) Helpers(constants_) {}
}
