// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Variables } from "../common/variables.sol";
import { TickMath } from "../../../../libraries/tickMath.sol";
import { BigMathMinified } from "../../../../libraries/bigMathMinified.sol";
import { Error } from "../../error.sol";
import { ErrorTypes } from "../../errorTypes.sol";
import { IFluidVault } from "../../interfaces/iVault.sol";
import { Structs } from "./structs.sol";
import { Events } from "./events.sol";
import { LiquiditySlotsLink } from "../../../../libraries/liquiditySlotsLink.sol";
import { LiquidityCalcs } from "../../../../libraries/liquidityCalcs.sol";
import { ILiquidityDexCommon } from "../../interfaces/iLiquidityDexCommon.sol";
import { SafeTransfer } from "../../../../libraries/safeTransfer.sol";
import { TokenTransfers } from "../common/tokenTransfers.sol";
import { FluidProtocolTypes } from "../../../../libraries/fluidProtocolTypes.sol";

/// @notice Fluid Vault protocol secondary methods contract.
///         Implements `absorb()` and `rebalance()` methods, extracted from main contract due to contract size limits.
///         Methods are limited to be called via delegateCall only (as done by Vault CoreModule contract).
contract FluidVaultSecondary is Variables, Error, Structs, Events, TokenTransfers {
    using BigMathMinified for uint;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // 30 bits (used for partials mainly)
    uint internal constant X8 = 0xff;
    uint internal constant X10 = 0x3ff;
    uint internal constant X16 = 0xffff;
    uint internal constant X19 = 0x7ffff;
    uint internal constant X20 = 0xfffff;
    uint internal constant X24 = 0xffffff;
    uint internal constant X25 = 0x1ffffff;
    uint internal constant X30 = 0x3fffffff;
    uint internal constant X35 = 0x7ffffffff;
    uint internal constant X50 = 0x3ffffffffffff;
    uint internal constant X64 = 0xffffffffffffffff;
    uint internal constant X96 = 0xffffffffffffffffffffffff;
    uint internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    address private immutable addressThis;

    constructor() {
        addressThis = address(this);
    }

    modifier _verifyCaller() {
        if (address(this) == addressThis) {
            revert FluidVaultError(ErrorTypes.Vault__OnlyDelegateCallAllowed);
        }
        _;
    }

    /// @dev absorb function absorbs the bad debt if the bad debt is above max limit. The main use of it is
    /// if the bad debt didn't got liquidated in time maybe due to sudden price drop or bad debt was extremely small to liquidate
    /// and the bad debt goes above 100% ratio then there's no incentive for anyone to liquidate now
    /// hence absorb functions absorbs that bad debt to allow newer bad debt to liquidate seamlessly.
    /// if absorbing were to happen after this it's on governance on how to deal with it
    /// although it can still be removed through liquidate via liquidator if the price goes back up and liquidation becomes beneficial
    /// upon absorbed user position gets 100% liquidated.
    function absorb(uint vaultVariables_, int maxTick_) public payable _verifyCaller returns (uint) {
        AbsorbMemoryVariables memory a_;

        // Temporary holder variables, used many times for different small few liner things
        uint temp_;
        uint temp2_;

        TickHasDebt memory tickHasDebt_;

        {
            // liquidating ticks above max ratio

            // temp_ -> top tick
            temp_ = ((vaultVariables_ >> 2) & X20);
            // increasing startingTick_ by 1 so the current tick comes into looping equation
            a_.startingTick = (temp_ & 1) == 1 ? (int(temp_ >> 1) + 1) : (-int(temp_ >> 1) + 1);

            tickHasDebt_.mapId = a_.startingTick < 0 ? ((a_.startingTick + 1) / 256) - 1 : a_.startingTick / 256;

            tickHasDebt_.tickHasDebt = tickHasDebt[tickHasDebt_.mapId];

            {
                // For last user remaining in vault there could be a lot of while loop.
                // Chances of this to happen is extremely low (like ~0%)
                tickHasDebt_.nextTick = TickMath.MAX_TICK;
                while (true) {
                    if (tickHasDebt_.tickHasDebt > 0) {
                        a_.mostSigBit = tickHasDebt_.tickHasDebt.mostSignificantBit();
                        tickHasDebt_.nextTick = tickHasDebt_.mapId * 256 + int(a_.mostSigBit) - 1;

                        while (tickHasDebt_.nextTick > maxTick_) {
                            // storing tickData into temp_
                            temp_ = tickData[tickHasDebt_.nextTick];
                            // temp2_ -> tick's debt
                            temp2_ = (temp_ >> 25) & X64;
                            // converting big number into normal number
                            temp2_ = (temp2_ >> 8) << (temp2_ & X8);
                            // Absorbing tick's debt & collateral
                            a_.debtAbsorbed += temp2_;
                            // calculating collateral from debt & ratio and adding to a_.colAbsorbed
                            a_.colAbsorbed += ((temp2_ * TickMath.ZERO_TICK_SCALED_RATIO) /
                                TickMath.getRatioAtTick(int24(tickHasDebt_.nextTick)));
                            // Update tick data on storage. Making tick as 100% liquidated
                            tickData[tickHasDebt_.nextTick] = 1 | (temp_ & 0x1fffffe) | (1 << 25); // set as 100% liquidated

                            // temp_ = bits to remove
                            temp_ = 257 - a_.mostSigBit;
                            tickHasDebt_.tickHasDebt = (tickHasDebt_.tickHasDebt << temp_) >> temp_;
                            if (tickHasDebt_.tickHasDebt == 0) break;

                            a_.mostSigBit = tickHasDebt_.tickHasDebt.mostSignificantBit();
                            tickHasDebt_.nextTick = tickHasDebt_.mapId * 256 + int(a_.mostSigBit) - 1;
                        }
                        // updating tickHasDebt on storage
                        tickHasDebt[tickHasDebt_.mapId] = tickHasDebt_.tickHasDebt;
                    }

                    // tickHasDebt_.tickHasDebt == 0 from here.

                    if (tickHasDebt_.nextTick <= maxTick_) {
                        break;
                    }

                    if (tickHasDebt_.mapId < -129) {
                        tickHasDebt_.nextTick = type(int).min;
                        break;
                    }

                    // Fetching next tickHasDebt by decreasing tickHasDebt_.mapId first
                    tickHasDebt_.tickHasDebt = tickHasDebt[--tickHasDebt_.mapId];
                }
            }
        }

        // After the above loop we will get nextTick stored in tickHasDebt_ which we will use to compare & set things in the end

        {
            TickData memory tickInfo_;
            BranchData memory branch_;
            // if this remains 0 that means create a new branch over the end
            uint newBranchId_;

            {
                // Liquidate branches in a loop and store the end branch
                branch_.id = (vaultVariables_ >> 22) & X30;
                branch_.data = branchData[branch_.id];
                // Checking if current branch is liquidated
                if ((vaultVariables_ & 2) == 0) {
                    // current branch is not liquidated hence it can be used as a new branch if needed
                    newBranchId_ = branch_.id;

                    // Checking the base branch minima tick. temp_ = base branch minima tick
                    temp_ = (branch_.data >> 196) & X20;
                    if (temp_ > 0) {
                        // Setting the base branch as current liquidatable branch
                        branch_.id = (branch_.data >> 166) & X30;
                        branch_.data = branchData[branch_.id];
                        branch_.minimaTick = (temp_ & 1) == 1 ? int(temp_ >> 1) : -int(temp_ >> 1);
                    } else {
                        // the current branch is base branch, hence need to setup a new base branch
                        branch_.id = 0;
                        branch_.data = 0;
                        branch_.minimaTick = type(int).min;
                    }
                } else {
                    // current branch is liquidated
                    temp_ = (branch_.data >> 2) & X20;
                    branch_.minimaTick = (temp_ & 1) == 1 ? int(temp_ >> 1) : -int(temp_ >> 1);
                }
                while (branch_.minimaTick > maxTick_) {
                    // Check base branch, if exists then check if minima tick is above max tick then liquidate it.
                    tickInfo_.ratio = TickMath.getRatioAtTick(int24(branch_.minimaTick));
                    tickInfo_.ratioOneLess = (tickInfo_.ratio * 10000) / 10015;
                    tickInfo_.length = tickInfo_.ratio - tickInfo_.ratioOneLess;

                    // partials
                    tickInfo_.partials = (branch_.data >> 22) & X30;

                    tickInfo_.currentRatio = tickInfo_.ratioOneLess + ((tickInfo_.length * tickInfo_.partials) / X30);

                    // debt in branch
                    temp2_ = (branch_.data >> 52) & X64;
                    // converting big number into normal number
                    temp2_ = (temp2_ >> 8) << (temp2_ & X8);
                    // Absorbing branch's debt & collateral
                    a_.debtAbsorbed += temp2_;
                    // calculating branch's collateral using debt & ratio and adding it to a_.colAbsorbed
                    a_.colAbsorbed += (temp2_ * TickMath.ZERO_TICK_SCALED_RATIO) / tickInfo_.currentRatio;

                    // Closing branch
                    branchData[branch_.id] = branch_.data | 3;

                    // Setting new branch
                    temp_ = (branch_.data >> 196) & X20; // temp_ -> minima tick of connected branch
                    if (temp_ > 0) {
                        // Setting the base branch as current liquidatable branch
                        branch_.id = (branch_.data >> 166) & X30;
                        branch_.data = branchData[branch_.id];
                        branch_.minimaTick = (temp_ & 1) == 1 ? int(temp_ >> 1) : -int(temp_ >> 1);
                    } else {
                        // the current branch is base branch, hence need to setup a new base branch
                        branch_.id = 0;
                        branch_.data = 0;
                        branch_.minimaTick = type(int).min;
                    }
                }
            }

            if (tickHasDebt_.nextTick >= branch_.minimaTick) {
                // new top tick is not liquidated
                // temp2_ = tick to insert
                if (tickHasDebt_.nextTick > type(int).min) {
                    temp2_ = tickHasDebt_.nextTick < 0
                        ? (uint(-tickHasDebt_.nextTick) << 1)
                        : ((uint(tickHasDebt_.nextTick) << 1) | 1);
                } else {
                    temp2_ = 0;
                }
                if (newBranchId_ == 0) {
                    // initializing a new branch
                    // newBranchId_ = total current branches + 1
                    unchecked {
                        newBranchId_ = ((vaultVariables_ >> 52) & X30) + 1;
                    }
                    vaultVariables_ =
                        ((vaultVariables_ >> 82) << 82) |
                        (temp2_ << 2) |
                        (newBranchId_ << 22) |
                        (newBranchId_ << 52);
                } else {
                    // using already initialized non liquidated branch
                    vaultVariables_ = ((vaultVariables_ >> 22) << 22) | (temp2_ << 2);
                }

                if (branch_.minimaTick > type(int).min) {
                    temp2_ = branch_.minimaTick < 0
                        ? (uint(-branch_.minimaTick) << 1)
                        : ((uint(branch_.minimaTick) << 1) | 1);
                    // set base branch id and minima tick
                    branchData[newBranchId_] = (branch_.id << 166) | (temp2_ << 196);
                } else {
                    // new base branch does not have any connected branch
                    branchData[newBranchId_] = 0;
                }
            } else {
                // new top tick is liquidated
                temp2_ = branch_.minimaTick < 0
                    ? (uint(-branch_.minimaTick) << 1)
                    : ((uint(branch_.minimaTick) << 1) | 1);
                if (newBranchId_ == 0) {
                    vaultVariables_ = ((vaultVariables_ >> 52) << 52) | 2 | (temp2_ << 2) | (branch_.id << 22);
                } else {
                    // uninitializing the non liquidated branch
                    vaultVariables_ =
                        ((vaultVariables_ >> 82) << 82) |
                        2 |
                        (temp2_ << 2) |
                        (branch_.id << 22) |
                        ((newBranchId_ - 1) << 52); // decreasing total branch by 1
                    branchData[newBranchId_] = 0;
                }
            }
        }

        // updating absorbed liquidity on storage
        absorbedLiquidity = absorbedLiquidity + a_.debtAbsorbed + (a_.colAbsorbed << 128);

        emit LogAbsorb(a_.colAbsorbed, a_.debtAbsorbed);

        // returning updated vault variables
        return vaultVariables_;
    }

    /// @dev Checks total supply of vault's in Liquidity Layer & Vault contract and rebalance it accordingly
    /// if vault supply is more than Liquidity Layer then deposit difference through reserve/rebalance contract
    /// if vault supply is less than Liquidity Layer then withdraw difference to reserve/rebalance contract
    /// if vault borrow is more than Liquidity Layer then borrow difference to reserve/rebalance contract
    /// if vault borrow is less than Liquidity Layer then payback difference through reserve/rebalance contract
    function rebalance(
        int colToken0MinMax_,
        int colToken1MinMax_,
        int debtToken0MinMax_,
        int debtToken1MinMax_
    ) external payable _verifyCaller returns (int supplyAmt_, int borrowAmt_) {
        if (msg.sender != rebalancer) {
            revert FluidVaultError(ErrorTypes.Vault__NotRebalancer);
        }

        uint vaultVariables_ = vaultVariables;
        // ############# turning re-entrancy bit on #############
        if (vaultVariables_ & 1 == 0) {
            // Updating on storage
            vaultVariables = vaultVariables_ | 1;
        } else {
            revert FluidVaultError(ErrorTypes.Vault__AlreadyEntered);
        }

        RebalanceMemoryVariables memory r_;
        // note: any of the excess ETH sent will be returned back by checking initial and final balance
        r_.initialEth = address(this).balance - msg.value;

        IFluidVault.ConstantViews memory c_ = IFluidVault(address(this)).constantsView();

        // if supply is smart col then it's DEX address else liquidity address
        ILiquidityDexCommon supply_ = ILiquidityDexCommon(c_.supply);
        // if borrow is smart debt then it's DEX address else liquidity address
        ILiquidityDexCommon borrow_ = ILiquidityDexCommon(c_.borrow);

        (r_.liqSupplyExPrice, r_.liqBorrowExPrice, r_.vaultSupplyExPrice, r_.vaultBorrowExPrice) = IFluidVault(
            address(this)
        ).updateExchangePrices(vaultVariables2);

        // extract vault supply at Liquidity -> 64 bits starting from bit 1 (first bit is interest mode)
        r_.totalSupply =
            (supply_.readFromStorage(c_.userSupplySlot) >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) &
            X64;
        r_.totalSupply = (r_.totalSupply >> 8) << (r_.totalSupply & X8);
        r_.totalSupply = (r_.totalSupply * r_.liqSupplyExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // extract vault borrowings at Liquidity -> 64 bits starting from bit 1 (first bit is interest mode)
        r_.totalBorrow =
            (borrow_.readFromStorage(c_.userBorrowSlot) >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) &
            X64;
        r_.totalBorrow = (r_.totalBorrow >> 8) << (r_.totalBorrow & X8);
        r_.totalBorrow = (r_.totalBorrow * r_.liqBorrowExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        r_.totalSupplyVault = (vaultVariables_ >> 82) & X64;
        r_.totalSupplyVault = (r_.totalSupplyVault >> 8) << (r_.totalSupplyVault & X8);
        r_.totalSupplyVault = (r_.totalSupplyVault * r_.vaultSupplyExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        r_.totalBorrowVault = (vaultVariables_ >> 146) & X64;
        r_.totalBorrowVault = (r_.totalBorrowVault >> 8) << (r_.totalBorrowVault & X8);
        r_.totalBorrowVault = (r_.totalBorrowVault * r_.vaultBorrowExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        uint value_;

        if (r_.totalSupplyVault > r_.totalSupply) {
            // Fetch tokens from revenue/rebalance contract and supply in liquidity/dex contract
            // This is the scenario when the supply rewards are going in vault, hence
            // the vault total supply is increasing at a higher pace than Liquidity/DEX contract.
            // We are not transferring rewards right when we set the rewards to keep things clean.
            // Also, this can also happen in case when supply rate magnifier is greater than 1.

            supplyAmt_ = int(r_.totalSupplyVault) - int(r_.totalSupply);

            if (
                c_.vaultType == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                c_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
            ) {
                if (colToken0MinMax_ <= 0 || colToken1MinMax_ <= 0) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidMinMaxInRebalance);
                }

                try
                    supply_.depositPerfect{
                        value: (c_.supplyToken.token0 == NATIVE_TOKEN)
                            ? uint(colToken0MinMax_)
                            : (c_.supplyToken.token1 == NATIVE_TOKEN)
                                ? uint(colToken1MinMax_)
                                : 0
                    }(uint(supplyAmt_), uint(colToken0MinMax_), uint(colToken1MinMax_), false)
                returns (uint, uint) {
                    // if success then do nothing
                } catch {
                    supplyAmt_ = 0;
                }
            } else {
                if (c_.supplyToken.token0 == NATIVE_TOKEN) {
                    value_ = uint(supplyAmt_);
                } else {
                    value_ = 0;
                }

                try
                    supply_.operate{ value: value_ }(
                        c_.supplyToken.token0,
                        supplyAmt_,
                        0,
                        address(0),
                        address(0),
                        abi.encode(msg.sender)
                    )
                {
                    // if success then do nothing
                } catch {
                    supplyAmt_ = 0;
                }
            }
        } else if (r_.totalSupply > r_.totalSupplyVault) {
            // Withdraw from Liquidity/DEX contract and send it to revenue contract.
            // This is the scenario when the vault user's are getting less APR than what's going on Liquidity contract.
            // When supply rate magnifier is less than 1.

            supplyAmt_ = int(r_.totalSupplyVault) - int(r_.totalSupply);

            if (
                c_.vaultType == FluidProtocolTypes.VAULT_T2_SMART_COL_TYPE ||
                c_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
            ) {
                if (colToken0MinMax_ >= 0 || colToken1MinMax_ >= 0) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidMinMaxInRebalance);
                }

                try
                    supply_.withdrawPerfect(
                        uint(-supplyAmt_),
                        uint(-colToken0MinMax_),
                        uint(-colToken1MinMax_),
                        msg.sender
                    )
                returns (uint, uint) {
                    // if success then do nothing
                } catch {
                    supplyAmt_ = 0;
                }
            } else {
                try supply_.operate(c_.supplyToken.token0, supplyAmt_, 0, msg.sender, address(0), new bytes(0)) {
                    // if success then do nothing
                } catch {
                    supplyAmt_ = 0;
                }
            }
        }

        if (r_.totalBorrowVault > r_.totalBorrow) {
            // Borrow from Liquidity/DEX contract and send to revenue/rebalance contract
            // This is the scenario when the vault is charging more borrow to user than the Liquidity contract.
            // When borrow rate magnifier is greater than 1.

            borrowAmt_ = int(r_.totalBorrowVault) - int(r_.totalBorrow);

            if (
                c_.vaultType == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
                c_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
            ) {
                if (debtToken0MinMax_ <= 0 || debtToken1MinMax_ <= 0) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidMinMaxInRebalance);
                }

                try
                    borrow_.borrowPerfect(
                        uint(borrowAmt_),
                        uint(debtToken0MinMax_),
                        uint(debtToken1MinMax_),
                        msg.sender
                    )
                returns (uint, uint) {
                    // if success then do nothing
                } catch {
                    borrowAmt_ = 0;
                }
            } else {
                try borrow_.operate(c_.borrowToken.token0, 0, borrowAmt_, address(0), msg.sender, new bytes(0)) {
                    // if success then do nothing
                } catch {
                    borrowAmt_ = 0;
                }
            }
        } else if (r_.totalBorrow > r_.totalBorrowVault) {
            // Transfer from revenue/rebalance contract and payback on Liquidity contract
            // This is the scenario when vault protocol is earning rewards so effective borrow rate for users is low.
            // Or the case where borrow rate magnifier is less than 1

            borrowAmt_ = int(r_.totalBorrow) - int(r_.totalBorrowVault);

            if (
                c_.vaultType == FluidProtocolTypes.VAULT_T3_SMART_DEBT_TYPE ||
                c_.vaultType == FluidProtocolTypes.VAULT_T4_SMART_COL_SMART_DEBT_TYPE
            ) {
                if (debtToken0MinMax_ >= 0 || debtToken1MinMax_ >= 0) {
                    revert FluidVaultError(ErrorTypes.Vault__InvalidMinMaxInRebalance);
                }

                try
                    borrow_.paybackPerfect{
                        value: (c_.borrowToken.token0 == NATIVE_TOKEN)
                            ? uint(-debtToken0MinMax_)
                            : (c_.borrowToken.token1 == NATIVE_TOKEN)
                                ? uint(-debtToken1MinMax_)
                                : 0
                    }(
                        uint(borrowAmt_), // not doing -borrowAmt_ because we already calculated it positively
                        uint(-debtToken0MinMax_),
                        uint(-debtToken1MinMax_),
                        false
                    )
                returns (uint, uint) {
                    // if success then do nothing
                    borrowAmt_ = -borrowAmt_;
                } catch {
                    borrowAmt_ = 0;
                }
            } else {
                if (c_.borrowToken.token0 == NATIVE_TOKEN) {
                    value_ = uint(borrowAmt_);
                } else {
                    value_ = 0;
                }

                borrowAmt_ = -borrowAmt_;

                try
                    borrow_.operate{ value: value_ }(
                        c_.borrowToken.token0,
                        0,
                        borrowAmt_,
                        address(0),
                        address(0),
                        abi.encode(msg.sender)
                    )
                {
                    // if success then do nothing
                } catch {
                    borrowAmt_ = 0;
                }
            }
        }

        if (supplyAmt_ == 0 && borrowAmt_ == 0) {
            revert FluidVaultError(ErrorTypes.Vault__NothingToRebalance);
        }

        // Updating vault variable on storage to turn off the reentrancy bit
        vaultVariables = vaultVariables_;

        _validateEth(r_.initialEth);

        emit LogRebalance(supplyAmt_, borrowAmt_);
    }
}
