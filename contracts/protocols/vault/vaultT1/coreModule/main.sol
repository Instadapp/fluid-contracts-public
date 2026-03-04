// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../../../../oracle/fluidOracle.sol";

import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { BigMathVault } from "../../../../libraries/bigMathVault.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";

import { Helpers } from "./helpers.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";

import { ErrorTypes } from "../../errorTypes.sol";

/// @notice Fluid "VaultT1" (Vault Type 1). Fluid vault protocol main contract.
///         Fluid Vault protocol is a borrow / lending protocol, allowing users to create collateral / borrow positions.
///         All funds are deposited into / borrowed from Fluid Liquidity layer.
///         Positions are represented through NFTs minted by the VaultFactory.
///         Deployed by "VaultFactory" and linked together with VaultT1 AdminModule `ADMIN_IMPLEMENTATION` and
///         FluidVaultT1Secondary (main2.sol) `SECONDARY_IMPLEMENTATION`.
///         AdminModule & FluidVaultT1Secondary methods are delegateCalled, if the msg.sender has the required authorization.
///         This contract links to an Oracle, which is used to assess collateral / debt value. Oracles implement the
///         "FluidOracle" base contract and return the price in 1e27 precision.
/// @dev    For view methods / accessing data, use the "VaultResolver" periphery contract.
//
// vaults can only be deployed for tokens that are listed at Liquidity (constructor reverts otherwise
// if either the exchange price for the supply token or the borrow token is still not set at Liquidity).
contract FluidVaultT1 is Helpers {
    using BigMathMinified for uint256;
    using BigMathVault for uint256;

    /// @dev Single function which handles supply, withdraw, borrow & payback
    /// @param nftId_ NFT ID for interaction. If 0 then create new NFT/position.
    /// @param newCol_ new collateral. If positive then deposit, if negative then withdraw, if 0 then do nohing
    /// @param newDebt_ new debt. If positive then borrow, if negative then payback, if 0 then do nohing
    /// @param to_ address where withdraw or borrow should go. If address(0) then msg.sender
    /// @return nftId_ if 0 then this returns the newly created NFT Id else returns the same NFT ID
    /// @return newCol_ final supply amount. Mainly if max withdraw using type(int).min then this is useful to get perfect amount else remain same as newCol_
    /// @return newDebt_ final borrow amount. Mainly if max payback using type(int).min then this is useful to get perfect amount else remain same as newDebt_
    function operate(
        uint256 nftId_, // if 0 then new position
        int256 newCol_, // if negative then withdraw
        int256 newDebt_, // if negative then payback
        address to_ // address at which the borrow & withdraw amount should go to. If address(0) then it'll go to msg.sender
    )
        public
        payable
        returns (
            uint256, // nftId_
            int256, // final supply amount. if - then withdraw
            int256 // final borrow amount. if - then payback
        )
    {
        uint256 vaultVariables_ = vaultVariables;
        // re-entrancy check
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        if (
            (newCol_ == 0 && newDebt_ == 0) ||
            // withdrawal or deposit cannot be too small
            ((newCol_ != 0) && (newCol_ > -10000 && newCol_ < 10000)) ||
            // borrow or payback cannot be too small
            ((newDebt_ != 0) && (newDebt_ > -10000 && newDebt_ < 10000))
        ) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidOperateAmount);
        }

        // Check msg.value aligns with input amounts if supply or borrow token is native token.
        // Note that it's not possible for a vault to have both supply token and borrow token as native token.
        if (SUPPLY_TOKEN == NATIVE_TOKEN && newCol_ > 0) {
            if (uint(newCol_) != msg.value) {
                revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueOperate);
            }
        } else if (msg.value > 0) {
            if (!(BORROW_TOKEN == NATIVE_TOKEN && newDebt_ < 0)) {
                // msg.value sent along for withdraw, borrow, or non-native token operations
                revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueOperate);
            }
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
                if ((newCol_ < 0 || newDebt_ > 0) && (VAULT_FACTORY.ownerOf(nftId_) != msg.sender)) {
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
                        temp_ = IFluidOracle(address(uint160(o_.vaultVariables2 >> 96))).getExchangeRateOperate();
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
                o_.userSupplyLiquidityData = LIQUIDITY.readFromStorage(LIQUIDITY_USER_SUPPLY_SLOT);

                // converting current user's supply from big number to normal
                temp2_ = (o_.userSupplyLiquidityData >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
                temp2_ = (temp2_ >> 8) << (temp2_ & X8);

                // fetching liquidity's withdrawal limit
                temp3_ = int(LiquidityCalcs.calcWithdrawalLimitBeforeOperate(o_.userSupplyLiquidityData, temp2_));

                // max the number could go is vault's supply * 1000. Overflowing is almost impossible.
                unchecked {
                    // (liquidityUserSupply - withdrawalGap - liquidityWithdrawaLimit) should NOT be less than user's withdrawal
                    if (
                        (temp3_ > 0) &&
                        (((int(temp2_ * (1000 - temp_)) / 1000)) - temp3_) <
                        (((-newCol_) * int(EXCHANGE_PRICES_PRECISION)) / int(o_.liquidityExPrice))
                    ) {
                        revert FluidVaultError(ErrorTypes.Vault__WithdrawMoreThanOperateLimit);
                    }
                }
            }
        }

        {
            // execute actions at Liquidity: deposit & payback is first and then withdraw & borrow
            if (newCol_ > 0) {
                // deposit
                LIQUIDITY.operate{ value: SUPPLY_TOKEN == NATIVE_TOKEN ? msg.value : 0 }(
                    SUPPLY_TOKEN,
                    newCol_,
                    0,
                    address(0),
                    address(0),
                    abi.encode(msg.sender)
                );
            }
            if (newDebt_ < 0) {
                if (BORROW_TOKEN == NATIVE_TOKEN) {
                    unchecked {
                        temp_ = uint(-newDebt_);
                        if (msg.value > temp_) {
                            SafeTransfer.safeTransferNative(msg.sender, msg.value - temp_);
                        } else if (msg.value < temp_) {
                            revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueOperate);
                        }
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
            if (newCol_ < 0) {
                // withdraw
                LIQUIDITY.operate(SUPPLY_TOKEN, newCol_, 0, to_, address(0), new bytes(0));
            }
            if (newDebt_ > 0) {
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
            vaultVariables =
                (vaultVariables_ & 0xfffffffffffc00000000000000000000000000000003ffffffffffffffffffff) |
                (temp_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 82) | // total supply
                (temp2_.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 146); // total borrow
        }

        emit LogOperate(msg.sender, nftId_, newCol_, newDebt_, to_);

        return (nftId_, newCol_, newDebt_);
    }

    /// @dev allows to liquidate all bad debt of all users at once. Liquidator can also liquidate partially any amount they want.
    /// @param debtAmt_ total debt to liquidate (aka debt token to swap into collateral token)
    /// @param colPerUnitDebt_ minimum collateral token per unit of debt in 1e18 decimals
    /// @param to_ address at which collateral token should go to.
    ///            If dead address (0x000000000000000000000000000000000000dEaD) then reverts with custom error "FluidLiquidateResult"
    ///            returning the actual collateral and actual debt liquidated. Useful to find max liquidatable amounts via try / catch.
    /// @param absorb_ if true then liquidate from absorbed first
    /// @return actualDebtAmt_ if liquidator sends debtAmt_ more than debt remaining to liquidate then actualDebtAmt_ changes from debtAmt_ else remains same
    /// @return actualColAmt_ total liquidated collateral which liquidator will get
    function liquidate(
        uint256 debtAmt_,
        uint256 colPerUnitDebt_, // min collateral needed per unit of debt in 1e18
        address to_,
        bool absorb_
    ) public payable returns (uint actualDebtAmt_, uint actualColAmt_) {
        LiquidateMemoryVars memory memoryVars_;

        uint vaultVariables_ = vaultVariables;

        // ############# turning re-entrancy bit on #############
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        if (BORROW_TOKEN == NATIVE_TOKEN) {
            if ((msg.value != debtAmt_) && (to_ != 0x000000000000000000000000000000000000dEaD)) {
                revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueLiquidate);
            }
        } else if (msg.value > 0) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidMsgValueLiquidate);
        }

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
            temp_ = IFluidOracle(address(uint160(memoryVars_.vaultVariables2 >> 96))).getExchangeRateLiquidate(); // Price in 27 decimals

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
                vaultVariables = vaultVariables_;
                return (0, 0);
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
                            if (to_ == 0x000000000000000000000000000000000000dEaD) {
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
        actualDebtAmt_ = (currentData_.totalDebtLiq * memoryVars_.borrowExPrice) / EXCHANGE_PRICES_PRECISION;
        actualColAmt_ = (currentData_.totalColLiq * memoryVars_.supplyExPrice) / EXCHANGE_PRICES_PRECISION;

        // Chances of this to happen are in few wei
        if (actualDebtAmt_ > debtAmt_) {
            // calc new actualColAmt_ via ratio.
            actualColAmt_ = actualColAmt_ * (debtAmt_ / actualDebtAmt_);
            actualDebtAmt_ = debtAmt_;
        }

        if (actualDebtAmt_ == 0) {
            revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidation);
        }

        if (((actualColAmt_ * 1e18) / actualDebtAmt_) < colPerUnitDebt_) {
            revert FluidVaultError(ErrorTypes.Vault__ExcessSlippageLiquidation);
        }

        if (to_ == 0x000000000000000000000000000000000000dEaD) {
            // revert with liquidated amounts if to_ address is the dead address.
            // this can be used in a resolver to find the max liquidatable amounts.
            revert FluidLiquidateResult(actualColAmt_, actualDebtAmt_);
        }

        // payback at Liquidity
        if (BORROW_TOKEN == NATIVE_TOKEN) {
            temp_ = actualDebtAmt_;
            if (actualDebtAmt_ < msg.value) {
                unchecked {
                    // subtraction can be unchecked because of if check above
                    SafeTransfer.safeTransferNative(msg.sender, msg.value - actualDebtAmt_);
                }
            }
            // else if actualDebtAmt_ > msg.value not possible as actualDebtAmt_ can maximally be debtAmt_ and
            // msg.value == debtAmt_ is checked in the beginning of function.
        } else {
            temp_ = 0;
        }
        unchecked {
            // payback at liquidity
            LIQUIDITY.operate{ value: temp_ }(
                BORROW_TOKEN,
                0,
                -int(actualDebtAmt_),
                address(0),
                address(0),
                abi.encode(msg.sender)
            );
            // withdraw at liquidity
            LIQUIDITY.operate(SUPPLY_TOKEN, -int(actualColAmt_), 0, to_, address(0), new bytes(0));
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
        vaultVariables =
            (vaultVariables_ & 0xfffffffffffc00000000000000000000000000000003ffffffffffffffffffff) |
            (temp_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN) << 82) | // total supply
            (temp2_.toBigNumber(56, 8, BigMathMinified.ROUND_UP) << 146); // total borrow

        emit LogLiquidate(msg.sender, actualColAmt_, actualDebtAmt_, to_);
    }

    /// @dev Checks total supply of vault's in Liquidity Layer & Vault contract and rebalance it accordingly
    /// if vault supply is more than Liquidity Layer then deposit difference through reserve/rebalance contract
    /// if vault supply is less than Liquidity Layer then withdraw difference to reserve/rebalance contract
    /// if vault borrow is more than Liquidity Layer then borrow difference to reserve/rebalance contract
    /// if vault borrow is less than Liquidity Layer then payback difference through reserve/rebalance contract
    function rebalance() external payable returns (int supplyAmt_, int borrowAmt_) {
        (supplyAmt_, borrowAmt_) = abi.decode(_spell(SECONDARY_IMPLEMENTATION, msg.data), (int, int));
    }

    /// @dev liquidity callback for cheaper token transfers in case of deposit or payback.
    /// only callable by Liquidity during an operation.
    function liquidityCallback(address token_, uint amount_, bytes calldata data_) external {
        if (msg.sender != address(LIQUIDITY)) revert FluidVaultError(ErrorTypes.Vault__InvalidLiquidityCallbackAddress);
        if (vaultVariables & 1 == 0) revert FluidVaultError(ErrorTypes.Vault__NotEntered);

        SafeTransfer.safeTransferFrom(token_, abi.decode(data_, (address)), address(LIQUIDITY), amount_);
    }

    constructor(ConstantViews memory constants_) Helpers(constants_) {
        // Note that vaults are deployed by VaultFactory so we somewhat trust the values being passed in

        // Setting branch in vault.
        vaultVariables = (vaultVariables) | (1 << 22) | (1 << 52);

        uint liqSupplyExchangePrice_ = (LIQUIDITY.readFromStorage(LIQUIDITY_SUPPLY_EXCHANGE_PRICE_SLOT) >>
            LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64;
        uint liqBorrowExchangePrice_ = (LIQUIDITY.readFromStorage(LIQUIDITY_BORROW_EXCHANGE_PRICE_SLOT) >>
            LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64;

        if (
            liqSupplyExchangePrice_ < EXCHANGE_PRICES_PRECISION || liqBorrowExchangePrice_ < EXCHANGE_PRICES_PRECISION
        ) {
            revert FluidVaultError(ErrorTypes.Vault__TokenNotInitialized);
        }
        // Updating initial rates in storage
        rates =
            liqSupplyExchangePrice_ |
            (liqBorrowExchangePrice_ << 64) |
            (EXCHANGE_PRICES_PRECISION << 128) |
            (EXCHANGE_PRICES_PRECISION << 192);
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

    function _spell(address target_, bytes memory data_) private returns (bytes memory response_) {
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
