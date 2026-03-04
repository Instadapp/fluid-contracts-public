// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../../../../oracle/fluidOracle.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { HelpersOperate } from "./helpersOperate.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { AddressCalcs } from "../../../../libraries/addressCalcs.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";

/// @dev Fluid vault protocol main operate contract base.
abstract contract FluidVaultOperate is HelpersOperate {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

    modifier _delegateCallCheck() {
        if (address(this) == OPERATE_IMPLEMENTATION) {
            revert FluidVaultError(ErrorTypes.Vault__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev Single function which handles supply, withdraw, borrow & payback
    /// @param nftId_ NFT ID for interaction. If 0 then create new NFT/position.
    /// @param newCol_ new collateral. If positive then deposit, if negative then withdraw, if 0 then do nohing
    /// @param newDebt_ new debt. If positive then borrow, if negative then payback, if 0 then do nohing
    /// @param to_ address where withdraw or borrow should go. If address(0) then msg.sender
    /// @param vaultVariables_ the current state of the vaultVariables from storage
    /// @return nftId_ if 0 then this returns the newly created NFT Id else returns the same NFT ID
    /// @return newCol_ final supply amount. Mainly if max withdraw using type(int).min then this is useful to get perfect amount else remain same as newCol_
    /// @return newDebt_ final borrow amount. Mainly if max payback using type(int).min then this is useful to get perfect amount else remain same as newDebt_
    /// @return vaultVariables_ the updated state of the vaultVariables
    function _operate(
        uint256 nftId_, // if 0 then new position
        int256 newCol_, // if negative then withdraw
        int256 newDebt_, // if negative then payback
        address to_, // address at which the borrow & withdraw amount should go to. If address(0) then it'll go to msg.sender
        uint256 vaultVariables_
    )
        internal
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256, // final borrow amount. if - then payback
            uint256 // vaultVariables_
        )
    {
        if (
            (newCol_ == 0 && newDebt_ == 0) ||
            // withdrawal or deposit cannot be too small
            ((newCol_ != 0) && (newCol_ > -10000 && newCol_ < 10000)) ||
            // borrow or payback cannot be too small
            ((newDebt_ != 0) && (newDebt_ > -10000 && newDebt_ < 10000))
        ) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidOperateAmount);
        }

        OperateMemoryVars memory o_;
        // Temporary variables used as helpers at many places
        uint256 temp_;
        uint256 temp2_;
        int256 temp3_;

        o_.vaultVariables2 = vaultVariables2;

        temp_ = (vaultVariables_ >> 2) & X20;
        unchecked {
            o_.topTick = (temp_ == 0)
                ? type(int).min
                : ((temp_ & 1) == 1)
                    ? int((temp_ >> 1) & X19)
                    : -int((temp_ >> 1) & X19);
        }

        {
            // Fetching user's position
            if (nftId_ == 0) {
                // creating new position.
                o_.tick = type(int).min;
                // minting new NFT vault for user.
                nftId_ = VAULT_FACTORY.mint(VAULT_ID, msg.sender);
                // Adding 1 in total positions. Total positions cannot exceed 32bits as NFT minting checks for that
                unchecked {
                    vaultVariables_ = vaultVariables_ + (1 << 210);
                }
            } else {
                // Updating existing position

                // checking owner only in case of withdraw or borrow
                temp_ = nftId_;
                if ((newCol_ < 0 || newDebt_ > 0) && (VAULT_FACTORY.ownerOf(temp_) != msg.sender)) {
                    revert FluidVaultError(ErrorTypes.Vault__NotAnOwner);
                }

                // temp_ => user's position data
                temp_ = positionData[nftId_];

                if (temp_ == 0) {
                    revert FluidVaultError(ErrorTypes.Vault__NftNotOfThisVault);
                }
                // temp2_ => user's supply amount
                temp2_ = (temp_ >> 45) & X64;
                // Converting big number into normal number
                o_.colRaw = (temp2_ >> 8) << (temp2_ & X8);
                // temp2_ => user's  dust debt amount
                temp2_ = (temp_ >> 109) & X64;
                // Converting big number into normal number
                o_.dustDebtRaw = (temp2_ >> 8) << (temp2_ & X8);

                // 1 is supply & 0 is borrow
                if (temp_ & 1 == 1) {
                    // only supply position (has no debt)
                    o_.tick = type(int).min;
                } else {
                    // borrow position (has collateral & debt)
                    unchecked {
                        o_.tick = temp_ & 2 == 2 ? int((temp_ >> 2) & X19) : -int((temp_ >> 2) & X19);
                    }
                    o_.tickId = (temp_ >> 21) & X24;
                }
            }
        }

        // Get latest updated Position's debt & supply (if position is with debt -> not new / supply position)
        if (o_.tick > type(int).min) {
            // if entering this if statement then temp_ here will always be user's position data
            // extracting collateral exponent
            temp_ = (temp_ >> 45) & X8;
            // if exponent is > 0 then rounding up the collateral just for calculating debt
            unchecked {
                temp_ = temp_ == 0 ? (o_.colRaw + 1) : o_.colRaw + (1 << temp_);
            }
            // fetch current debt
            o_.debtRaw = ((TickMath.getRatioAtTick(int24(o_.tick)) * temp_) >> 96) + 1;

            // Tick data from user's tick
            temp_ = tickData[o_.tick];

            // Checking if tick is liquidated (first bit 1) OR if the total IDs of tick is greater than user's tick ID
            if (((temp_ & 1) == 1) || (((temp_ >> 1) & X24) > o_.tickId)) {
                // User got liquidated
                (
                    // returns the position of the user if the user got liquidated.
                    o_.tick,
                    o_.debtRaw,
                    o_.colRaw,
                    temp2_, // final branchId from liquidation where position exist right now
                    o_.branchData
                ) = fetchLatestPosition(o_.tick, o_.tickId, o_.debtRaw, temp_);

                if (o_.debtRaw > o_.dustDebtRaw) {
                    // temp_ => branch's Debt
                    temp_ = (o_.branchData >> 52) & X64;
                    temp_ = (temp_ >> 8) << (temp_ & X8);

                    // o_.debtRaw should always be < branch's Debt (temp_).
                    // Taking margin (0.01%) in fetchLatestPosition to make sure it's always less
                    temp_ -= o_.debtRaw;
                    if (temp_ < 100) {
                        // explicitly making sure that branch debt/liquidity doesn't get super low.
                        temp_ = 100;
                    }
                    // Inserting updated branch's debt
                    branchData[temp2_] =
                        (o_.branchData & 0xfffffffffffffffffffffffffffffffffff0000000000000000fffffffffffff) |
                        (temp_.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 52);

                    unchecked {
                        // Converted positionRawDebt_ in net position debt
                        o_.debtRaw -= o_.dustDebtRaw;
                    }
                } else {
                    // Liquidated 100% or almost 100%
                    // absorbing dust debt
                    absorbedDustDebt = absorbedDustDebt + o_.dustDebtRaw - o_.debtRaw;
                    o_.debtRaw = 0;
                    o_.colRaw = 0;
                }
            } else {
                // User didn't got liquidated
                // Removing user's debt from tick data
                // temp2_ => debt in tick
                temp2_ = (temp_ >> 25) & X64;
                // below require can fail when a user liquidity is extremely low (talking about way less than even $1)
                // adding require meaning this vault user won't be able to interact unless someone makes the liquidity in tick as non 0.
                // reason of adding is the tick has already removed from everywhere. Can removing it again break something? Better to simply remove that case entirely
                if (temp2_ == 0) {
                    revert FluidVaultError(ErrorTypes.Vault__TickIsEmpty);
                }
                // Converting big number into normal number
                temp2_ = (temp2_ >> 8) << (temp2_ & X8);
                // debtInTick (temp2_) < debtToRemove (o_.debtRaw) that means minor precision error. Hence make the debtInTick as 0.
                // The precision error can be caused with Bigmath library limiting the precision to 2**56.
                unchecked {
                    temp2_ = o_.debtRaw < temp2_ ? temp2_ - o_.debtRaw : 0;
                }

                if (temp2_ < 10000) {
                    temp2_ = 0;
                    // if debt becomes 0 then remove from tick has debt

                    if (o_.tick == o_.topTick) {
                        // if tick is top tick then current top tick is perfect tick -> fetch & set new top tick

                        // Updating new top tick in vaultVariables_ and topTick_
                        (vaultVariables_, o_.topTick) = _setNewTopTick(o_.topTick, vaultVariables_);
                    }

                    // Removing from tickHasDebt
                    _updateTickHasDebt(o_.tick, false);
                }

                tickData[o_.tick] = (temp_ & X25) | (temp2_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 25);

                // Converted positionRawDebt_ in net position debt
                o_.debtRaw -= o_.dustDebtRaw;
            }
            o_.dustDebtRaw = 0;
        }

        // Setting the current tick into old tick as the position tick is going to change now.
        o_.oldTick = o_.tick;
        o_.oldColRaw = o_.colRaw;
        o_.oldNetDebtRaw = o_.debtRaw;

        {
            (o_.liquidityExPrice, , o_.supplyExPrice, o_.borrowExPrice) = updateExchangePrices(o_.vaultVariables2);

            {
                // supply or withdraw
                if (newCol_ > 0) {
                    // supply new col, rounding down
                    o_.colRaw += (uint256(newCol_) * EXCHANGE_PRICES_PRECISION) / o_.supplyExPrice;
                    // final user's collateral should not be above 2**128 bits
                    if (o_.colRaw > X128) {
                        revert FluidVaultError(ErrorTypes.Vault__UserCollateralDebtExceed);
                    }
                } else if (newCol_ < 0) {
                    // if withdraw equals type(int).min then max withdraw
                    if (newCol_ > type(int128).min) {
                        // partial withdraw, rounding up removing extra wei from collateral
                        temp3_ = ((newCol_ * int(EXCHANGE_PRICES_PRECISION)) / int256(o_.supplyExPrice)) - 1;
                        unchecked {
                            if (uint256(-temp3_) > o_.colRaw) {
                                revert FluidVaultError(ErrorTypes.Vault__ExcessCollateralWithdrawal);
                            }
                            o_.colRaw -= uint256(-temp3_);
                        }
                    } else if (newCol_ == type(int).min) {
                        // max withdraw, rounding up:
                        // adding +1 to negative withdrawAmount newCol_ for safe rounding (reducing withdraw)
                        newCol_ = -(int256((o_.colRaw * o_.supplyExPrice) / EXCHANGE_PRICES_PRECISION)) + 1;
                        o_.colRaw = 0;
                    } else {
                        revert FluidVaultError(ErrorTypes.Vault__UserCollateralDebtExceed);
                    }
                }
            }
            {
                // borrow or payback
                if (newDebt_ > 0) {
                    // borrow new debt, rounding up adding extra wei in debt
                    temp_ = ((uint(newDebt_) * EXCHANGE_PRICES_PRECISION) / o_.borrowExPrice) + 1;
                    // if borrow fee is 0 then it'll become temp_ + 0.
                    // Only adding fee in o_.debtRaw and not in newDebt_ as newDebt_ is debt that needs to be borrowed from Liquidity
                    // as we have added fee in debtRaw hence it will get added in user's position & vault's total borrow.
                    // It can be collected with rebalance function.
                    o_.debtRaw += temp_ + (temp_ * ((o_.vaultVariables2 >> 82) & X10)) / 10000;
                    // final user's debt should not be above 2**128 bits
                    if (o_.debtRaw > X128) {
                        revert FluidVaultError(ErrorTypes.Vault__UserCollateralDebtExceed);
                    }
                } else if (newDebt_ < 0) {
                    // if payback equals type(int).min then max payback
                    if (newDebt_ > type(int128).min) {
                        // partial payback.
                        // temp3_ => newDebt_ in raw terms, safe rounding up negative amount to rounding reduce payback
                        temp3_ = (newDebt_ * int256(EXCHANGE_PRICES_PRECISION)) / int256(o_.borrowExPrice) + 1;
                        unchecked {
                            temp3_ = -temp3_;
                            if (uint256(temp3_) > o_.debtRaw) {
                                revert FluidVaultError(ErrorTypes.Vault__ExcessDebtPayback);
                            }
                            o_.debtRaw -= uint256(temp3_);
                        }
                    } else if (newDebt_ == type(int).min) {
                        // max payback, rounding up amount that will be transferred in to pay back full debt:
                        // subtracting -1 of negative debtAmount newDebt_ for safe rounding (increasing payback)
                        newDebt_ = -(int256((o_.debtRaw * o_.borrowExPrice) / EXCHANGE_PRICES_PRECISION)) - 1;
                        o_.debtRaw = 0;
                    } else {
                        revert FluidVaultError(ErrorTypes.Vault__UserCollateralDebtExceed);
                    }
                }
            }
        }

        // if position has no collateral or debt and user sends type(int).min for withdraw and payback then this results in 0
        // there's is no issue if it stays 0 but better to throw here to avoid checking for potential issues if there could be
        if (newCol_ == 0 && newDebt_ == 0) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidOperateAmount);
        }

        // Assign new tick
        if (o_.debtRaw > 0) {
            // updating tickHasDebt in the below function if required
            // o_.debtRaw here is updated to new debt raw incl. dust debt (not net debt)
            unchecked {
                (o_.tick, o_.tickId, o_.debtRaw, o_.dustDebtRaw) = _addDebtToTickWrite(
                    o_.colRaw,
                    ((o_.debtRaw * 1000000001) / 1000000000) + 1
                );
            }

            if (newDebt_ < 0) {
                // anyone can payback debt of any position
                // hence, explicitly checking the debt should decrease
                if ((o_.debtRaw - o_.dustDebtRaw) > o_.oldNetDebtRaw) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidPaybackOrDeposit);
                }
            }
            if ((newCol_ > 0) && (newDebt_ == 0)) {
                // anyone can deposit collateral in any position
                // Hence, explicitly checking that new ratio should be less than old ratio
                if (
                    (((o_.debtRaw - o_.dustDebtRaw) * TickMath.ZERO_TICK_SCALED_RATIO) / o_.colRaw) >
                    ((o_.oldNetDebtRaw * TickMath.ZERO_TICK_SCALED_RATIO) / o_.oldColRaw)
                ) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidPaybackOrDeposit);
                }
            }

            if (o_.tick >= o_.topTick) {
                // Updating topTick in storage
                // temp_ => tick to insert in vault variables
                unchecked {
                    temp_ = o_.tick < 0 ? uint(-o_.tick) << 1 : (uint(o_.tick) << 1) | 1;
                }
                if (vaultVariables_ & 2 == 0) {
                    // Current branch not liquidated. Hence, just update top tick
                    vaultVariables_ =
                        (vaultVariables_ & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc00000) |
                        (temp_ << 2);
                } else {
                    // Current branch liquidated
                    // Initialize a new branch
                    // temp2_ => totalBranchId_
                    unchecked {
                        temp2_ = ((vaultVariables_ >> 52) & X30) + 1; // would take 34 years to overflow if a new branch is created every second
                    }
                    // Connecting new active branch with current active branch which is now base branch
                    // Current top tick is now base branch's minima tick
                    branchData[temp2_] =
                        (((vaultVariables_ >> 22) & X30) << 166) | // current branch id set as base branch id
                        (((vaultVariables_ >> 2) & X20) << 196); // current top tick set as base branch minima tick
                    // Updating new vault variables in memory with new branch
                    vaultVariables_ =
                        (vaultVariables_ & 0xfffffffffffffffffffffffffffffffffffffffffffc00000000000000000000) |
                        (temp_ << 2) | // new top tick
                        (temp2_ << 22) | // new branch id
                        (temp2_ << 52); // total branch ids
                }
            }
        } else {
            // debtRaw_ remains 0 in this situation
            // This kind of position will not have any tick. Meaning it'll be a supply position.
            o_.tick = type(int).min;
        }

        {
            if (newCol_ < 0 || newDebt_ > 0) {
                // withdraw or borrow
                if (to_ == address(0)) {
                    to_ = msg.sender;
                }

                unchecked {
                    // if debt is greater than 0 & transaction includes borrow or withdraw (incl. combinations such as deposit + borrow etc.)
                    // -> check collateral factor
                    // calc for net debt can be unchecked as o_.dustDebtRaw can not be > o_.debtRaw:
                    // o_.dustDebtRaw is the result of o_.debtRaw - x where x > 0 see _addDebtToTickWrite()

                    // Only fetch oracle if position is getting riskier or if borrowing is involved
                    // if user is withdrawing and paying back in the same transaction such that the final ratio
                    // is lower than initial then as well no need to check oracle aka user is doing payback & withdraw or deleverage
                    if (
                        o_.debtRaw > 0 &&
                        (o_.oldTick <= o_.tick ||
                            (o_.debtRaw - o_.dustDebtRaw) > (((o_.oldNetDebtRaw * 1000000001) / 1000000000) + 1))
                    ) {
                        // Oracle returns price at 100% ratio.
                        // converting oracle 160 bits into oracle address
                        // temp_ => debt price w.r.t to col in 1e27
                        temp_ = IFluidOracle(
                            AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((o_.vaultVariables2 >> 92) & X30))
                        ).getExchangeRateOperate();
                        // Note if price would come back as 0 `getTickAtRatio` will fail

                        // reverting if oracle price is too high or lower than 1e9 to avoid precision issues
                        if (temp_ > 1e54 || temp_ < 1e9) {
                            revert FluidVaultError(ErrorTypes.Vault__InvalidOraclePrice);
                        }

                        // Converting price in terms of raw amounts
                        temp_ = (temp_ * o_.supplyExPrice) / o_.borrowExPrice;

                        // capping oracle pricing to 1e45 (#487RGF783GF: id reference for other similar cases in codebase)
                        // This means we are restricting collateral price to never go above 1e45
                        // Above 1e45 precisions gets too low for calculations
                        // This can will never happen for all good token pairs (for example, WBTC/DAI pair when WBTC price is $1M, oracle price will come as 1e43)
                        // Restricting oracle price doesn't pose any risk to protocol as we are capping collateral price, meaning if price is above 1e45
                        // user is simply not able to borrow more
                        if (temp_ > 1e45) {
                            temp_ = 1e45;
                        }

                        // temp2_ => ratio at CF. CF is in 3 decimals. 900 = 90%
                        temp2_ = ((temp_ * ((o_.vaultVariables2 >> 32) & X10)) / 1000);

                        // Price from oracle is in 1e27 decimals. Converting it into (1 << 96) decimals
                        temp2_ = ((temp2_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27);

                        // temp3_ => tickAtCF_
                        (temp3_, ) = TickMath.getTickAtRatio(temp2_);
                        if (o_.tick > temp3_) {
                            // Above CF, user should only be allowed to reduce ratio either by paying debt or by depositing more collateral
                            // Not comparing collateral as user can potentially use safe/deleverage to reduce tick & debt.
                            // On use of safe/deleverage, collateral will decrease but debt will decrease as well making the overall position safer.
                            revert FluidVaultError(ErrorTypes.Vault__PositionAboveCF);
                        }
                    }
                }
            }
        }

        {
            // Updating user's new position on storage
            // temp_ => tick to insert as user position tick
            if (o_.tick > type(int).min) {
                unchecked {
                    temp_ = o_.tick < 0 ? (uint(-o_.tick) << 1) : ((uint(o_.tick) << 1) | 1);
                }
            } else {
                // if positionTick_ = type(int).min OR positionRawDebt_ == 0 then that means it's only supply position
                // (for case of positionRawDebt_ == 0, tick is set to type(int).min further up)
                temp_ = 0;
            }

            positionData[nftId_] =
                ((temp_ == 0) ? 1 : 0) | // setting if supply only position (1) or not (first bit)
                (temp_ << 1) |
                (o_.tickId << 21) |
                (o_.colRaw.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 45) |
                // dust debt is rounded down because user debt = debt - dustDebt. rounding up would mean we reduce user debt
                (o_.dustDebtRaw.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 109);
        }

        // Withdrawal gap to make sure there's always liquidity for liquidation
        // For example if withdrawal allowance is 15% on liquidity then we can limit operate's withdrawal allowance to 10%
        // this will allow liquidate function to get extra 5% buffer for potential liquidations.
        if (newCol_ < 0) {
            // extracting withdrawal gap which is in 0.1% precision.
            temp_ = (o_.vaultVariables2 >> 62) & X10;
            if (temp_ > 0) {
                // fetching user's supply slot data
                o_.userSupplyLiquidityData = SUPPLY.readFromStorage(USER_SUPPLY_SLOT);

                // converting current user's supply from big number to normal
                temp2_ = (o_.userSupplyLiquidityData >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
                temp2_ = (temp2_ >> 8) << (temp2_ & X8);

                // fetching liquidity's withdrawal limit
                temp3_ = int(LiquidityCalcs.calcWithdrawalLimitBeforeOperate(o_.userSupplyLiquidityData, temp2_));

                unchecked {
                    // max the number could go is vault's supply * 1000. Overflowing is almost impossible.
                    if (
                        TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                        TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
                    ) {
                        // withdrawal already happened in smart col so checking according to that
                        if (
                            (temp3_ > 0) &&
                            // userSupply * (100% - withdrawalGap) < withdrawalLimit
                            // i.e. if limit for next tx is not below userSupply - withdrawalGap -> revert
                            (((int(temp2_ * (1000 - temp_)) / 1000)) < temp3_)
                        ) {
                            revert FluidVaultError(ErrorTypes.Vault__WithdrawMoreThanOperateLimit);
                        }
                    } else {
                        // (liquidityUserSupply - withdrawalGap - liquidityWithdrawaLimit) should NOT be less than user's withdrawal
                        if (
                            (temp3_ > 0) &&
                            // userSupply * (100% - withdrawalGap) - withdrawalLimit < withdrawColRaw
                            // i.e. if withdrawableRaw < withdrawColRaw -> revert
                            (((int(temp2_ * (1000 - temp_)) / 1000)) - temp3_) <
                            (((-newCol_) * int(EXCHANGE_PRICES_PRECISION)) / int(o_.liquidityExPrice))
                        ) {
                            revert FluidVaultError(ErrorTypes.Vault__WithdrawMoreThanOperateLimit);
                        }
                    }
                }
            }
        }

        {
            // with TYPE we are checking if we should interact with Liquidity Layer or interaction will happen with DEX

            // execute actions at Liquidity: deposit & payback is first and then withdraw & borrow
            if (
                newCol_ > 0 &&
                !(TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                    TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ) {
                // deposit
                LIQUIDITY.operate{ value: SUPPLY_TOKEN == NATIVE_TOKEN ? uint256(newCol_) : 0 }(
                    SUPPLY_TOKEN,
                    newCol_,
                    0,
                    address(0),
                    address(0),
                    abi.encode(msg.sender)
                );
            }
            if (
                newDebt_ < 0 &&
                !(TYPE == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
                    TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ) {
                if (BORROW_TOKEN == NATIVE_TOKEN) {
                    unchecked {
                        temp_ = uint(-newDebt_);
                    }
                } else {
                    temp_ = 0;
                }
                // payback
                LIQUIDITY.operate{ value: temp_ }(
                    BORROW_TOKEN,
                    0,
                    newDebt_,
                    address(0),
                    address(0),
                    abi.encode(msg.sender)
                );
            }
            if (
                newCol_ < 0 &&
                !(TYPE == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                    TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ) {
                // withdraw
                LIQUIDITY.operate(SUPPLY_TOKEN, newCol_, 0, to_, address(0), new bytes(0));
            }
            if (
                newDebt_ > 0 &&
                !(TYPE == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
                    TYPE == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE)
            ) {
                // borrow
                LIQUIDITY.operate(BORROW_TOKEN, 0, newDebt_, address(0), to_, new bytes(0));
            }
        }

        {
            // Updating vault variables on storage

            // Calculating new total collateral & total debt.
            temp_ = (vaultVariables_ >> 82) & X64;
            temp_ = ((temp_ >> 8) << (temp_ & X8)) + o_.colRaw - o_.oldColRaw;
            temp2_ = (vaultVariables_ >> 146) & X64;
            temp2_ = ((temp2_ >> 8) << (temp2_ & X8)) + (o_.debtRaw - o_.dustDebtRaw) - o_.oldNetDebtRaw;
            // Updating vault variables on storage. This will also reentrancy 0 back again
            // Converting total supply & total borrow in 64 bits (56 | 8) bignumber
            vaultVariables_ =
                (vaultVariables_ & 0xfffffffffffc00000000000000000000000000000003ffffffffffffffffffff) |
                (temp_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 82) | // total supply
                (temp2_.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 146); // total borrow
        }

        emit LogOperate(msg.sender, nftId_, newCol_, newDebt_, to_);

        return (nftId_, newCol_, newDebt_, vaultVariables_);
    }

    constructor(ConstantViews memory constants_) HelpersOperate(constants_) {}
}
