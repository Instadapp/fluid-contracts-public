// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../../../../oracle/fluidOracle.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { HelpersLiquidate } from "./helpersLiquidate.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { AddressCalcs } from "../../../../libraries/addressCalcs.sol";

/// @notice Fluid vault protocol main contract base.
///         Fluid Vault protocol is a borrow / lending protocol, allowing users to create collateral / borrow positions.
///         All funds are deposited into / borrowed from Fluid Liquidity layer.
///         Positions are represented through NFTs minted by the VaultFactory.
///         Deployed by "VaultFactory" and linked together with Vault AdminModule `ADMIN_IMPLEMENTATION` and
///         FluidVaultSecondary (main2.sol) `SECONDARY_IMPLEMENTATION`.
///         AdminModule & FluidVaultSecondary methods are delegateCalled, if the msg.sender has the required authorization.
///         This contract links to an Oracle, which is used to assess collateral / debt value. Oracles implement the
///         "FluidOracle" base contract and return the price in 1e27 precision.
/// @dev    For view methods / accessing data, use the "VaultResolver" periphery contract.
//
// vaults can only be deployed for tokens that are listed at Liquidity (constructor reverts otherwise
// if either the exchange price for the supply token or the borrow token is still not set at Liquidity).
abstract contract FluidVault is HelpersLiquidate {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

    function simulateLiquidate(uint debtAmt_, bool absorb_) external {
        uint vaultVariables_ = vaultVariables;
        // ############# turning re-entrancy bit on #############
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        debtAmt_ = debtAmt_ == 0 ? X128 : debtAmt_;

        _liquidate(X128, 0, DEAD_ADDRESS, absorb_, vaultVariables_);

        // this revert will never reach as the revert is inside the liquidate function due to to_ = DEAD_ADDRESS
        // but still added just to be extra safe
        revert();
    }

    /// @dev allows to liquidate all bad debt of all users at once. Liquidator can also liquidate partially any amount they want.
    /// @param debtAmt_ total debt to liquidate (aka debt token to swap into collateral token)
    /// @param colPerUnitDebt_ minimum collateral token per unit of debt in 1e18 decimals
    /// @param to_ address at which collateral token should go to.
    ///            If dead address (DEAD_ADDRESS) then reverts with custom error "FluidLiquidateResult"
    ///            returning the actual collateral and actual debt liquidated. Useful to find max liquidatable amounts via try / catch.
    /// @param absorb_ if true then liquidate from absorbed first
    /// @param vaultVariables_ the current state of the vaultVariables from storage
    /// @return bytes with 3 uints, r_[0] = actualDebtAmt, r_[1] = actualColAmt, r_[2] = vaultVariables_
    ///         actualDebtAmt if liquidator sends debtAmt_ more than debt remaining to liquidate then actualDebtAmt changes from debtAmt_ else remains same
    ///         actualColAmt total liquidated collateral which liquidator will get
    function _liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // min collateral needed per unit of debt in 1e18
        address to_,
        bool absorb_,
        uint vaultVariables_
    ) internal returns (bytes memory) {
        LiquidateMemoryVars memory memoryVars_;

        memoryVars_.vaultVariables2 = vaultVariables2;

        if (((vaultVariables_ >> 2) & X20) == 0) {
            revert FluidVaultError(ErrorTypes.Vault__TopTickDoesNotExist);
        }

        // Below are exchange prices of vaults
        (, , memoryVars_.supplyExPrice, memoryVars_.borrowExPrice) = updateExchangePrices(memoryVars_.vaultVariables2);

        CurrentLiquidity memory currentData_;
        BranchData memory branch_;
        // Temporary holder variables, used many times for different small things
        uint temp_;
        uint temp2_;

        {
            // ############# Oracle related stuff #############
            // Col price w.r.t debt. For example: 1 ETH = 1000 DAI
            // temp_ -> debtPerCol
            temp_ = IFluidOracle(
                AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((memoryVars_.vaultVariables2 >> 92) & X30))
            ).getExchangeRateLiquidate(); // Price in 27 decimals

            // not reverting if oracle price is lower than 1e9 as it can pause potential liquidation in this edge case situations
            if (temp_ > 1e54 || temp_ == 0) {
                revert FluidVaultError(ErrorTypes.Vault__InvalidOraclePrice);
            }

            unchecked {
                // temp_ -> debtPerCol Converting in terms of raw amount
                temp_ = (temp_ * memoryVars_.supplyExPrice) / memoryVars_.borrowExPrice;

                // capping oracle pricing to 1e45
                // Reason mentioned at (search: #487RGF783GF)
                if (temp_ > 1e45) {
                    temp_ = 1e45;
                }
                // temp2_ -> Raw colPerDebt_ in 27 decimals
                temp2_ = 1e54 / temp_;

                // temp2_ can never be > 1e54
                // Oracle price should never be > 1e54
                // Liquidation penalty in 4 decimals (1e2 = 1%) (max: 10.23%) -> (vaultVariables2_ >> 72) & X10
                currentData_.colPerDebt = (temp2_ * (10000 + ((memoryVars_.vaultVariables2 >> 72) & X10))) / 10000;

                // get liquidiation tick (tick at liquidation threshold ratio)
                // Liquidation threshold in 3 decimals (900 = 90%) -> (vaultVariables2_ >> 42) & X10
                // Dividing by 1e27 to convert temp_ into normal number
                temp_ = ((temp_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27);
                // temp2_ -> liquidationRatio_
                temp2_ = (temp_ * ((memoryVars_.vaultVariables2 >> 42) & X10)) / 1000;
            }
            (memoryVars_.liquidationTick, ) = TickMath.getTickAtRatio(temp2_);

            // get liquidiation max limit tick (tick at liquidation max limit ratio)
            // Max limit in 3 decimals (900 = 90%) -> (vaultVariables2_ >> 52) & X10
            // temp2_ -> maxRatio_
            unchecked {
                temp2_ = (temp_ * ((memoryVars_.vaultVariables2 >> 52) & X10)) / 1000;
            }
            (memoryVars_.maxTick, ) = TickMath.getTickAtRatio(temp2_);
        }

        // extracting top tick as top tick will be the current tick
        unchecked {
            currentData_.tick = (vaultVariables_ & 4) == 4
                ? int256((vaultVariables_ >> 3) & X19)
                : -int256((vaultVariables_ >> 3) & X19);
        }

        if (currentData_.tick > memoryVars_.maxTick) {
            // absorbing all the debt above maxTick if available
            vaultVariables_ = (
                abi.decode(
                    _spell(
                        SECONDARY_IMPLEMENTATION,
                        abi.encodeWithSignature("absorb(uint256,int256)", vaultVariables_, memoryVars_.maxTick)
                    ),
                    (uint256)
                )
            );

            // updating current tick to new topTick after absorb
            unchecked {
                currentData_.tick = (vaultVariables_ & 4) == 4
                    ? int256((vaultVariables_ >> 3) & X19)
                    : -int256((vaultVariables_ >> 3) & X19);
            }
            if (debtAmt_ == 0) {
                // updating vault variables on storage as the transaction was for only absorb
                // Vault variables is getting updated through liquidate function
                return abi.encode(0, 0, vaultVariables_);
            }
        }

        if (debtAmt_ < 10000 || debtAmt_ > X128) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidationAmt);
        }

        // setting up status if top tick is liquidated or not
        currentData_.tickStatus = vaultVariables_ & 2 == 0 ? 1 : 2;
        // Tick info is mainly used as a place holder to store temporary tick related data
        // (it can be current or ref using same memory variable)
        TickData memory tickInfo_;
        tickInfo_.tick = currentData_.tick;

        {
            // ############# Setting current branch in memory #############

            // Updating branch related data
            branch_.id = (vaultVariables_ >> 22) & X30;
            branch_.data = branchData[branch_.id];
            branch_.debtFactor = (branch_.data >> 116) & X50;
            if (branch_.debtFactor == 0) {
                // Initializing branch debt factor. 35 | 15 bit number. Where full 35 bits and 15th bit is occupied.
                // Making the total number as (2**35 - 1) << 2**14.
                // note: initial debt factor can be any number.
                branch_.debtFactor = ((X35 << 15) | (1 << 14));
            }
            // fetching base branch's minima tick. if 0 that means it's a master branch
            temp_ = (branch_.data >> 196) & X20;
            if (temp_ > 0) {
                unchecked {
                    branch_.minimaTick = (temp_ & 1) == 1 ? int256((temp_ >> 1) & X19) : -int256((temp_ >> 1) & X19);
                }
            } else {
                branch_.minimaTick = type(int).min;
            }
        }

        // debtAmt_ should be less than 2**128 & EXCHANGE_PRICES_PRECISION is 1e12
        unchecked {
            currentData_.debtRemaining = (debtAmt_ * EXCHANGE_PRICES_PRECISION) / memoryVars_.borrowExPrice;
        }

        // extracting total debt
        temp2_ = (vaultVariables_ >> 146) & X64;
        temp2_ = ((temp2_ >> 8) << (temp2_ & X8));

        if ((temp2_ / 1e9) > currentData_.debtRemaining) {
            // if liquidation amount is less than 1e9 of total debt then revert
            // so if total debt is $1B then minimum liquidation limit = $1
            // so if total debt is $1T then minimum liquidation limit = $1000
            // partials precision is slightlty above 1e9 so this will make sure that on every liquidation atleast 1 partial gets liquidated
            // not sure if it can result in any issue but restricting amount further more to remove very low amount scenarios totally
            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidationAmt);
        }

        if (absorb_) {
            temp_ = absorbedLiquidity;
            // temp2_ -> absorbed col
            temp2_ = (temp_ >> 128) & X128;
            // temp_ -> absorbed debt
            temp_ = temp_ & X128;

            if (temp_ > currentData_.debtRemaining) {
                // Removing collateral in equal proportion as debt
                currentData_.totalColLiq = ((temp2_ * currentData_.debtRemaining) / temp_);
                temp2_ -= currentData_.totalColLiq;
                // Removing debt
                currentData_.totalDebtLiq = currentData_.debtRemaining;
                unchecked {
                    temp_ -= currentData_.debtRemaining;
                }
                currentData_.debtRemaining = 0;

                // updating on storage
                absorbedLiquidity = temp_ | (temp2_ << 128);
            } else {
                // updating on storage
                absorbedLiquidity = 0;
                unchecked {
                    currentData_.debtRemaining -= temp_;
                }
                currentData_.totalDebtLiq = temp_;
                currentData_.totalColLiq = temp2_;
            }
        }

        // current tick should be greater than liquidationTick and it cannot be greater than maxTick as absorb will run
        if (currentData_.tick > memoryVars_.liquidationTick) {
            if (currentData_.debtRemaining > 0) {
                // Stores liquidated debt & collateral in each loop
                uint debtLiquidated_;
                uint colLiquidated_;
                uint debtFactor_ = BigMathVault.TWO_POWER_64;

                TickHasDebt memory tickHasDebt_;
                unchecked {
                    tickHasDebt_.mapId = (currentData_.tick < 0)
                        ? (((currentData_.tick + 1) / 256) - 1)
                        : (currentData_.tick / 256);
                }

                tickInfo_.ratio = TickMath.getRatioAtTick(tickInfo_.tick);

                if (currentData_.tickStatus == 1) {
                    // top tick is not liquidated. Hence it's a perfect tick.
                    currentData_.ratio = tickInfo_.ratio;
                    // if current tick in liquidation is a perfect tick then it is also the next tick that has debt.
                    tickHasDebt_.nextTick = currentData_.tick;
                } else {
                    // top tick is liquidated. Hence it has partials.
                    // next tick that has debt liquidity will have to be fetched from tickHasDebt
                    unchecked {
                        tickInfo_.ratioOneLess = (tickInfo_.ratio * 10000) / 10015;
                        tickInfo_.length = tickInfo_.ratio - tickInfo_.ratioOneLess;
                        tickInfo_.partials = (branch_.data >> 22) & X30;
                        currentData_.ratio = tickInfo_.ratioOneLess + ((tickInfo_.length * tickInfo_.partials) / X30);

                        if ((memoryVars_.liquidationTick + 1) == tickInfo_.tick && (tickInfo_.partials == 1)) {
                            if (to_ == DEAD_ADDRESS) {
                                // revert with liquidated amounts if to_ address is the dead address.
                                // this can be used in a resolver to find the max liquidatable amounts.
                                revert FluidLiquidateResult(0, 0);
                            }
                            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidation);
                        }
                    }
                }

                while (true) {
                    if (currentData_.tickStatus == 1) {
                        // not liquidated -> Getting the debt from tick data itself
                        temp2_ = tickData[currentData_.tick];
                        // temp_ => tick debt
                        temp_ = (temp2_ >> 25) & X64;
                        // Converting big number into normal number
                        temp_ = (temp_ >> 8) << (temp_ & X8);
                        // Updating tickData on storage with removing debt & adding connection to branch
                        tickData[currentData_.tick] =
                            1 | // set tick as liquidated
                            (temp2_ & 0x1fffffe) | // set same total tick ids
                            (branch_.id << 26) | // branch id where this tick got liquidated
                            (branch_.debtFactor << 56);
                    } else {
                        // already liquidated -> Get the debt from branch data in big number
                        // temp_ => tick debt
                        temp_ = (branch_.data >> 52) & X64;
                        // Converting big number into normal number
                        temp_ = (temp_ >> 8) << (temp_ & X8);
                        // Branch is getting updated over the end
                    }

                    // Adding new debt into active debt for liquidation
                    currentData_.debt += temp_;

                    // Adding new col into active col for liquidation
                    // Ratio is in 2**96 decimals hence multiplying debt with 2**96 to get proper collateral
                    currentData_.col += (temp_ * TickMath.ZERO_TICK_SCALED_RATIO) / currentData_.ratio;

                    if (
                        (tickHasDebt_.nextTick == currentData_.tick && currentData_.tickStatus == 1) ||
                        tickHasDebt_.tickHasDebt == 0
                    ) {
                        // Fetching next perfect tick with liquidity
                        // tickHasDebt_.tickHasDebt == 0 will only happen in the first while loop
                        // in the very first perfect tick liquidation it'll be 0
                        if (tickHasDebt_.tickHasDebt == 0) {
                            tickHasDebt_.tickHasDebt = tickHasDebt[tickHasDebt_.mapId];
                        }

                        // in 1st loop tickStatus can be 2. Meaning not a perfect current tick
                        if (currentData_.tickStatus == 1) {
                            unchecked {
                                tickHasDebt_.bitsToRemove = uint(-currentData_.tick + (tickHasDebt_.mapId * 256 + 256));
                            }
                            // Removing current top tick from tickHasDebt
                            tickHasDebt_.tickHasDebt =
                                (tickHasDebt_.tickHasDebt << tickHasDebt_.bitsToRemove) >>
                                tickHasDebt_.bitsToRemove;
                            // Updating in storage if tickHasDebt becomes 0.
                            if (tickHasDebt_.tickHasDebt == 0) {
                                tickHasDebt[tickHasDebt_.mapId] = 0;
                            }
                        }

                        // For last user remaining in vault there could be a lot of while loop.
                        // Chances of this to happen is extremely low (like ~0%)
                        while (true) {
                            if (tickHasDebt_.tickHasDebt > 0) {
                                unchecked {
                                    tickHasDebt_.nextTick =
                                        tickHasDebt_.mapId *
                                        256 +
                                        int(tickHasDebt_.tickHasDebt.mostSignificantBit()) -
                                        1;
                                }
                                break;
                            }

                            // tickHasDebt_.tickHasDebt == 0. Checking if minimum tick of this mapID is less than liquidationTick_
                            // if true that means now the next tick is not needed as liquidation gets over minimum at liquidationTick_
                            unchecked {
                                if ((tickHasDebt_.mapId * 256) < memoryVars_.liquidationTick) {
                                    tickHasDebt_.nextTick = type(int).min;
                                    break;
                                }

                                // Fetching next tick has debt by decreasing tickHasDebt_.mapId first
                                tickHasDebt_.tickHasDebt = tickHasDebt[--tickHasDebt_.mapId];
                            }
                        }
                    }

                    // Fetching refTick. refTick is the biggest tick of these 3:
                    // 1. Next tick with liquidity (from tickHasDebt)
                    // 2. Minima tick of current branch
                    // 3. Liquidation threshold tick
                    {
                        // Setting currentData_.refTick & currentData_.refTickStatus
                        if (
                            branch_.minimaTick > tickHasDebt_.nextTick &&
                            branch_.minimaTick > memoryVars_.liquidationTick
                        ) {
                            // next tick will be of base branch (merge)
                            currentData_.refTick = branch_.minimaTick;
                            currentData_.refTickStatus = 2;
                        } else if (tickHasDebt_.nextTick > memoryVars_.liquidationTick) {
                            // next tick will be next tick from perfect tick
                            currentData_.refTick = tickHasDebt_.nextTick;
                            currentData_.refTickStatus = 1;
                        } else {
                            // next tick is threshold tick
                            currentData_.refTick = memoryVars_.liquidationTick;
                            currentData_.refTickStatus = 3; // leads to end of liquidation loop
                        }
                    }

                    // using tickInfo variable again for ref tick as we don't have the need for it any more
                    tickInfo_.ratio = TickMath.getRatioAtTick(int24(currentData_.refTick));
                    if (currentData_.refTickStatus == 2) {
                        // merge current branch with base branch
                        unchecked {
                            tickInfo_.ratioOneLess = (tickInfo_.ratio * 10000) / 10015;
                            tickInfo_.length = tickInfo_.ratio - tickInfo_.ratioOneLess;
                            // Fetching base branch data to get the base branch's partial
                            branch_.baseBranchData = branchData[((branch_.data >> 166) & X30)];
                            tickInfo_.partials = (branch_.baseBranchData >> 22) & X30;
                            tickInfo_.currentRatio =
                                tickInfo_.ratioOneLess +
                                ((tickInfo_.length * tickInfo_.partials) / X30);
                            currentData_.refRatio = tickInfo_.currentRatio;
                        }
                    } else {
                        // refTickStatus can only be 1 (next tick from perfect tick) or 3 (liquidation threshold tick)
                        tickInfo_.currentRatio = tickInfo_.ratio;
                        currentData_.refRatio = tickInfo_.ratio;
                        tickInfo_.partials = X30;
                    }

                    // Formula: (debt_ - x) / (col_ - (x * colPerDebt_)) = ratioEnd_
                    // x = ((ratioEnd_ * col) - debt_) / ((colPerDebt_ * ratioEnd_) - 1)
                    // x is debtToLiquidate_
                    // col_ = debt_ / ratioStart_ -> (currentData_.debt / currentData_.ratio)
                    // ratioEnd_ is currentData_.refRatio
                    //
                    // Calculation results of numerator & denominator is always negative
                    // which will cancel out to give positive output in the end so we can safely cast to uint.
                    // for nominator:
                    // ratioStart can only be >= ratioEnd so first part can only be reducing currentData_.debt leading to
                    // currentData_.debt reduced - currentData_.debt original * 1e27 -> can only be a negative number
                    // for denominator:
                    // currentData_.colPerDebt and currentData_.refRatio are inversely proportional to each other.
                    // the maximum value they can ever be is ~9.97e26 which is the 0.3% away from 100% because liquidation
                    // threshold + liquidation penalty can never be > 99.7%. This can also be verified by going back from
                    // min / max ratio values further up where we fetch oracle price etc.
                    // as optimization we can inverse nominator and denominator subtraction to directly get a positive number.

                    debtLiquidated_ =
                        // nominator
                        ((currentData_.debt - (currentData_.refRatio * currentData_.debt) / currentData_.ratio) *
                            1e27) /
                        // denominator
                        (1e27 - ((currentData_.colPerDebt * currentData_.refRatio) / TickMath.ZERO_TICK_SCALED_RATIO));

                    colLiquidated_ = (debtLiquidated_ * currentData_.colPerDebt) / 1e27;

                    if (currentData_.debt == debtLiquidated_) {
                        debtLiquidated_ -= 1;
                    }

                    if (debtLiquidated_ >= currentData_.debtRemaining || currentData_.refTickStatus == 3) {
                        // End of liquidation as full amount to liquidate or liquidation threshold tick has been reached;

                        // Updating tickHasDebt on storage.
                        tickHasDebt[tickHasDebt_.mapId] = tickHasDebt_.tickHasDebt;

                        if (debtLiquidated_ >= currentData_.debtRemaining) {
                            // Liquidation ended between currentTick & refTick.
                            // Not all of liquidatable debt is actually liquidated -> recalculate
                            debtLiquidated_ = currentData_.debtRemaining;
                            colLiquidated_ = (debtLiquidated_ * currentData_.colPerDebt) / 1e27;
                            // Liquidating to debt. temp_ => final ratio after liquidation
                            // liquidatable debt - debtLiquidated / liquidatable col - colLiquidated
                            temp_ =
                                ((currentData_.debt - debtLiquidated_) * TickMath.ZERO_TICK_SCALED_RATIO) /
                                (currentData_.col - colLiquidated_);
                            // Fetching tick of where liquidation ended
                            (tickInfo_.tick, tickInfo_.ratioOneLess) = TickMath.getTickAtRatio(temp_);
                            if ((tickInfo_.tick < currentData_.refTick) && (tickInfo_.partials == X30)) {
                                // this situation might never happen
                                // if this happens then there might be some very edge case precision of few weis which is returning 1 tick less
                                // if the above were to ever happen then tickInfo_.tick only be currentData_.refTick - 1
                                // in this case the partial will be very very near to full (X30)
                                // increasing tick by 2 and making partial as 1 which is basically very very near to currentData_.refTick
                                unchecked {
                                    tickInfo_.tick += 2;
                                }
                                tickInfo_.partials = 1;
                            } else {
                                unchecked {
                                    // Increasing tick by 1 as final ratio will probably be a partial
                                    ++tickInfo_.tick;

                                    // if ref tick is old liquidated tick then storing partials in temp2_
                                    // tickInfo_.partials contains partial of branch which is the current ref tick
                                    temp2_ = (currentData_.refTickStatus == 2 && tickInfo_.tick == currentData_.refTick)
                                        ? tickInfo_.partials
                                        : 0;

                                    tickInfo_.ratio = (tickInfo_.ratioOneLess * 10015) / 10000;
                                    tickInfo_.length = tickInfo_.ratio - tickInfo_.ratioOneLess;
                                    tickInfo_.partials = ((temp_ - tickInfo_.ratioOneLess) * X30) / tickInfo_.length;

                                    // Taking edge cases where partial comes as 0 or X30 meaning perfect tick.
                                    // Hence, increasing or reducing it by 1 as liquidation tick cannot be perfect tick.
                                    tickInfo_.partials = tickInfo_.partials == 0
                                        ? 1
                                        : tickInfo_.partials >= X30
                                            ? X30 - 1
                                            : tickInfo_.partials;
                                }
                                if (temp2_ > 0 && temp2_ >= tickInfo_.partials) {
                                    // if refTick is liquidated tick and hence contains partials then checking that
                                    // current liquidation tick's partial should not be less than last liquidation refTick

                                    // not sure if this is even possible to happen but adding checks to avoid it fully
                                    // if it reverts here then next liquidation on next block should go through fine
                                    revert FluidVaultError(ErrorTypes.Vault__LiquidationReverts);
                                }
                            }
                        } else {
                            // End in liquidation threshold.
                            // finalRatio_ = currentData_.refRatio;
                            // Increasing liquidation threshold tick by 1 partial. With 1 partial it'll reach to the next tick.
                            // Ratio change will be negligible. Doing this as liquidation threshold tick can also be a perfect non-liquidated tick.
                            unchecked {
                                tickInfo_.tick = currentData_.refTick + 1;
                            }
                            // Making partial as 1 so it doesn't stay perfect tick
                            tickInfo_.partials = 1;
                            // length is not needed as only partials are written to storage
                        }

                        // debtFactor = debtFactor * (liquidatableDebt - debtLiquidated) / liquidatableDebt
                        // -> debtFactor * leftOverDebt / liquidatableDebt
                        debtFactor_ = (debtFactor_ * (currentData_.debt - debtLiquidated_)) / currentData_.debt;
                        currentData_.totalDebtLiq += debtLiquidated_;
                        currentData_.debt -= debtLiquidated_; // currentData_.debt => leftOverDebt after debtLiquidated_
                        currentData_.totalColLiq += colLiquidated_;
                        currentData_.col -= colLiquidated_; // currentData_.col => leftOverCol after colLiquidated_

                        // Updating branch's debt factor & write to storage as liquidation is over
                        branch_.debtFactor = branch_.debtFactor.mulDivBigNumber(debtFactor_);

                        if (currentData_.debt < 100) {
                            // this can happen when someone tries to create a dust tick
                            revert FluidVaultError(ErrorTypes.Vault__BranchDebtTooLow);
                        }

                        unchecked {
                            // Tick to insert
                            temp2_ = tickInfo_.tick < 0
                                ? (uint(-tickInfo_.tick) << 1)
                                : ((uint(tickInfo_.tick) << 1) | 1);
                        }

                        // Updating Branch data with debt factor, debt, partials, minima tick & assigning is liquidated
                        branchData[branch_.id] =
                            ((branch_.data >> 166) << 166) |
                            1 | // set as liquidated
                            (temp2_ << 2) | // minima tick of branch
                            (tickInfo_.partials << 22) |
                            (currentData_.debt.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 52) | // branch debt
                            (branch_.debtFactor << 116);

                        // Updating vault variables with current branch & tick
                        vaultVariables_ =
                            ((vaultVariables_ >> 52) << 52) |
                            2 | // set as liquidated
                            (temp2_ << 2) | // top tick
                            (branch_.id << 22);
                        break;
                    }

                    unchecked {
                        // debtLiquidated_ >= currentData_.debtRemaining leads to loop break in if statement above
                        // so this can be unchecked
                        currentData_.debtRemaining -= debtLiquidated_;
                    }

                    // debtFactor = debtFactor * (liquidatableDebt - debtLiquidated) / liquidatableDebt
                    // -> debtFactor * leftOverDebt / liquidatableDebt
                    debtFactor_ = (debtFactor_ * (currentData_.debt - debtLiquidated_)) / currentData_.debt;
                    currentData_.totalDebtLiq += debtLiquidated_;
                    currentData_.debt -= debtLiquidated_;
                    currentData_.totalColLiq += colLiquidated_;
                    currentData_.col -= colLiquidated_;

                    // updating branch's debt factor
                    branch_.debtFactor = branch_.debtFactor.mulDivBigNumber(debtFactor_);
                    // Setting debt factor as 1 << 64 again
                    debtFactor_ = BigMathVault.TWO_POWER_64;

                    if (currentData_.refTickStatus == 2) {
                        // ref tick is base branch's minima hence merging current branch to base branch
                        // and making base branch as current branch.

                        // read base branch related data
                        temp_ = (branch_.data >> 166) & X30; // temp_ -> base branch id
                        temp2_ = branch_.baseBranchData;
                        {
                            uint newBranchDebtFactor_ = (temp2_ >> 116) & X50;

                            // connectionFactor_ = baseBranchDebtFactor / currentBranchDebtFactor
                            uint connectionFactor_ = newBranchDebtFactor_.divBigNumber(branch_.debtFactor);
                            // Updating current branch in storage
                            branchData[branch_.id] =
                                ((branch_.data >> 166) << 166) | // deleting debt / partials / minima tick
                                2 | // setting as merged
                                (connectionFactor_ << 116); // set new connectionFactor

                            // Storing base branch in memory
                            // Updating branch ID to base branch ID
                            branch_.id = temp_;
                            // Updating branch data with base branch data
                            branch_.data = temp2_;
                            // Remove next branch connection from base branch
                            branch_.debtFactor = newBranchDebtFactor_;
                            // temp_ => minima tick of base branch
                            temp_ = (temp2_ >> 196) & X20;
                            if (temp_ > 0) {
                                unchecked {
                                    branch_.minimaTick = (temp_ & 1) == 1
                                        ? int256((temp_ >> 1) & X19)
                                        : -int256((temp_ >> 1) & X19);
                                }
                            } else {
                                branch_.minimaTick = type(int).min;
                            }
                        }
                    }

                    // Making refTick as currentTick
                    currentData_.tick = currentData_.refTick;
                    currentData_.tickStatus = currentData_.refTickStatus;
                    currentData_.ratio = currentData_.refRatio;
                }
            }
        }

        // calculating net token amounts using exchange price
        memoryVars_.actualDebtAmt = (currentData_.totalDebtLiq * memoryVars_.borrowExPrice) / EXCHANGE_PRICES_PRECISION;
        memoryVars_.actualColAmt = (currentData_.totalColLiq * memoryVars_.supplyExPrice) / EXCHANGE_PRICES_PRECISION;

        // Chances of this to happen are in few wei
        if (memoryVars_.actualDebtAmt > debtAmt_) {
            // calc new memoryVars_.actualColAmt via ratio.
            memoryVars_.actualColAmt = memoryVars_.actualColAmt * (debtAmt_ / memoryVars_.actualDebtAmt);
            memoryVars_.actualDebtAmt = debtAmt_;
        }

        if (memoryVars_.actualDebtAmt == 0) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidation);
        }

        if (((memoryVars_.actualColAmt * 1e18) / memoryVars_.actualDebtAmt) < colPerUnitDebt_) {
            revert FluidVaultError(ErrorTypes.Vault__ExcessSlippageLiquidation);
        }

        if (to_ == DEAD_ADDRESS) {
            // revert with liquidated amounts if to_ address is the dead address.
            // this can be used in a resolver to find the max liquidatable amounts.
            revert FluidLiquidateResult(memoryVars_.actualColAmt, memoryVars_.actualDebtAmt);
        }

        if (
            !(TYPE == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
                TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
        ) {
            // payback at Liquidity
            if (BORROW_TOKEN == NATIVE_TOKEN) {
                temp_ = memoryVars_.actualDebtAmt;
            } else {
                temp_ = 0;
            }

            // payback at liquidity
            LIQUIDITY.operate{ value: temp_ }(
                BORROW_TOKEN,
                0,
                -int(memoryVars_.actualDebtAmt),
                address(0),
                address(0),
                abi.encode(msg.sender)
            );
        }

        if (
            !(TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
        ) {
            // withdraw at liquidity
            LIQUIDITY.operate(SUPPLY_TOKEN, -int(memoryVars_.actualColAmt), 0, to_, address(0), new bytes(0));
        }

        // Calculating new total collateral & total debt.
        // temp_ -> total supply
        temp_ = (vaultVariables_ >> 82) & X64;
        temp_ = ((temp_ >> 8) << (temp_ & X8)) - currentData_.totalColLiq;
        // temp2_ -> total borrow
        temp2_ = (vaultVariables_ >> 146) & X64;
        temp2_ = ((temp2_ >> 8) << (temp2_ & X8)) - currentData_.totalDebtLiq;
        // Updating vault variables on storage
        // Converting total supply & total borrow in 64 bits (56 | 8) bignumber
        vaultVariables_ =
            (vaultVariables_ & 0xfffffffffffc00000000000000000000000000000003ffffffffffffffffffff) |
            (temp_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 82) | // total supply
            (temp2_.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 146); // total borrow

        emit LogLiquidate(msg.sender, memoryVars_.actualColAmt, memoryVars_.actualDebtAmt, to_);

        return abi.encode(memoryVars_.actualDebtAmt, memoryVars_.actualColAmt, vaultVariables_);
    }

    /// @dev Checks total supply of vault's in Liquidity Layer & Vault contract and rebalance it accordingly
    /// if vault supply is more than LiquidityLayer/DEX then deposit difference through reserve/rebalance contract
    /// if vault supply is less than LiquidityLayer/DEX then withdraw difference to reserve/rebalance contract
    /// if vault borrow is more than LiquidityLayer/DEX then borrow difference to reserve/rebalance contract
    /// if vault borrow is less than LiquidityLayer/DEX then payback difference through reserve/rebalance contract
    function rebalance(int, int, int, int) external payable _dexFromAddress returns (int supplyAmt_, int borrowAmt_) {
        (supplyAmt_, borrowAmt_) = abi.decode(_spell(SECONDARY_IMPLEMENTATION, msg.data), (int, int));
    }

    /// @dev liquidity callback for cheaper token transfers in case of deposit or payback.
    /// only callable by Liquidity during an operation.
    function liquidityCallback(address token_, uint amount_, bytes calldata data_) external {
        if (msg.sender != address(LIQUIDITY)) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidityCallbackAddress);
        }
        if (vaultVariables & 1 == 0) revert FluidVaultError(ErrorTypes.Vault__NotEntered);

        SafeTransfer.safeTransferFrom(token_, abi.decode(data_, (address)), address(LIQUIDITY), amount_);
    }

    /// @dev dex callback for cheaper token transfers in case of deposit or payback.
    /// only callable by dex during an operation.
    function dexCallback(address token_, uint amount_) external {
        if (!(msg.sender == address(SUPPLY) || msg.sender == address(BORROW))) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidDexCallbackAddress);
        }
        if (vaultVariables & 1 == 0) revert FluidVaultError(ErrorTypes.Vault__NotEntered);

        SafeTransfer.safeTransferFrom(token_, dexFromAddress, address(LIQUIDITY), amount_);
    }

    /// @notice returns all Vault constants
    function constantsView() external view returns (ConstantViews memory constantsView_) {
        constantsView_.liquidity = address(LIQUIDITY);
        constantsView_.factory = address(VAULT_FACTORY);
        constantsView_.operateImplementation = OPERATE_IMPLEMENTATION;
        constantsView_.adminImplementation = ADMIN_IMPLEMENTATION;
        constantsView_.secondaryImplementation = SECONDARY_IMPLEMENTATION;
        constantsView_.deployer = DEPLOYER_CONTRACT;
        constantsView_.supply = address(SUPPLY);
        constantsView_.borrow = address(BORROW);
        constantsView_.supplyToken.token0 = SUPPLY_TOKEN0;
        constantsView_.supplyToken.token1 = SUPPLY_TOKEN1;
        constantsView_.borrowToken.token0 = BORROW_TOKEN0;
        constantsView_.borrowToken.token1 = BORROW_TOKEN1;
        constantsView_.vaultId = VAULT_ID;
        constantsView_.vaultType = TYPE;
        constantsView_.supplyExchangePriceSlot = SUPPLY_EXCHANGE_PRICE_SLOT;
        constantsView_.borrowExchangePriceSlot = BORROW_EXCHANGE_PRICE_SLOT;
        constantsView_.userSupplySlot = USER_SUPPLY_SLOT;
        constantsView_.userBorrowSlot = USER_BORROW_SLOT;
    }

    constructor(ConstantViews memory constants_) HelpersLiquidate(constants_) {
        // Note that vaults are deployed by VaultFactory so we somewhat trust the values being passed in

        // Setting branch in vault.
        vaultVariables = (vaultVariables) | (1 << 22) | (1 << 52);

        dexFromAddress = DEAD_ADDRESS;

        // If smart collateral then liqSupplyExchangePrice_ will always be EXCHANGE_PRICES_PRECISION
        uint liqSupplyExchangePrice_ = (constants_.vaultType == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
            constants_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ? EXCHANGE_PRICES_PRECISION
            : ((SUPPLY.readFromStorage(SUPPLY_EXCHANGE_PRICE_SLOT) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64);

        // If smart debt then liqBorrowExchangePrice_ will always be EXCHANGE_PRICES_PRECISION
        uint liqBorrowExchangePrice_ = (constants_.vaultType == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
            constants_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ? EXCHANGE_PRICES_PRECISION
            : ((BORROW.readFromStorage(BORROW_EXCHANGE_PRICE_SLOT) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64);

        if (
            liqSupplyExchangePrice_ < EXCHANGE_PRICES_PRECISION || liqBorrowExchangePrice_ < EXCHANGE_PRICES_PRECISION
        ) {
            revert FluidVaultError(ErrorTypes.Vault__TokenNotInitialized);
        }

        if (constants_.operateImplementation == address(0)) {
            revert FluidVaultError(ErrorTypes.Vault__ImproperConstantsSetup);
        }

        // Updating initial rates in storage
        rates =
            liqSupplyExchangePrice_ |
            (liqBorrowExchangePrice_ << 64) |
            (EXCHANGE_PRICES_PRECISION << 128) |
            (EXCHANGE_PRICES_PRECISION << 192);

        vaultVariables2 =
            (vaultVariables2 & 0xfffffffffffffffffffffffff800000003ffffffffffffffffffffffffffffff) |
            (block.timestamp << 122);
    }

    fallback() external {
        if (!(VAULT_FACTORY.isGlobalAuth(msg.sender) || VAULT_FACTORY.isVaultAuth(address(this), msg.sender))) {
            revert FluidVaultError(ErrorTypes.Vault__NotAnAuth);
        }

        // Delegate the current call to `implementation`.
        // This does not return to its internall call site, it will return directly to the external caller.
        // solhint-disable-next-line no-inline-assembly
        _spell(ADMIN_IMPLEMENTATION, msg.data);
    }

    receive() external payable {}

    function _spell(address target_, bytes memory data_) internal returns (bytes memory response_) {
        assembly {
            let succeeded := delegatecall(gas(), target_, add(data_, 0x20), mload(data_), 0, 0)
            let size := returndatasize()

            response_ := mload(0x40)
            mstore(0x40, add(response_, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response_, size)
            returndatacopy(add(response_, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }
}
