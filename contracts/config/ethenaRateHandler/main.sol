// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { FluidVaultT1Admin } from "../../protocols/vault/vaultT1/adminModule/main.sol";
import { IStakedUSDe } from "./interfaces/iStakedUSDe.sol";
import { Variables } from "./variables.sol";
import { Events } from "./events.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Sets borrow rate for sUSDe/debtToken vaults based on sUSDe yield rate, by adjusting the borrowRateMagnifier
contract FluidEthenaRateConfigHandler is Variables, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.EthenaRateConfigHandler__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.EthenaRateConfigHandler__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        IFluidLiquidity liquidity_,
        IFluidVaultT1 vault_,
        IStakedUSDe stakedUSDe_,
        address borrowToken_,
        uint256 ratePercentMargin_,
        uint256 maxRewardsDelay_,
        uint256 utilizationPenaltyStart_,
        uint256 utilization100PenaltyPercent_
    )
        validAddress(address(reserveContract_))
        validAddress(address(liquidity_))
        validAddress(address(vault_))
        validAddress(address(stakedUSDe_))
        validAddress(borrowToken_)
    {
        if (
            ratePercentMargin_ == 0 ||
            ratePercentMargin_ >= 1e4 ||
            maxRewardsDelay_ == 0 ||
            utilizationPenaltyStart_ >= 1e4 ||
            utilization100PenaltyPercent_ == 0
        ) {
            revert FluidConfigError(ErrorTypes.EthenaRateConfigHandler__InvalidParams);
        }

        RESERVE_CONTRACT = reserveContract_;
        LIQUIDITY = liquidity_;
        SUSDE = stakedUSDe_;
        VAULT = vault_;
        BORROW_TOKEN = borrowToken_;

        _LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            borrowToken_
        );

        RATE_PERCENT_MARGIN = ratePercentMargin_;
        MAX_REWARDS_DELAY = maxRewardsDelay_;

        UTILIZATION_PENALTY_START = utilizationPenaltyStart_;
        UTILIZATION100_PENALTY_PERCENT = utilization100PenaltyPercent_;
    }

    /// @notice Rebalances the borrow rate magnifier for `VAULT` based on borrow rate at Liquidity in relation to
    /// sUSDe yield rate (`getSUSDEYieldRate()`).
    /// Emits `LogUpdateBorrowRateMagnifier` in case of update. Reverts if no update is needed.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external onlyRebalancer {
        uint256 targetMagnifier_ = calculateMagnifier();
        uint256 currentMagnifier_ = currentMagnifier();

        // execute update on vault if necessary
        if (targetMagnifier_ == currentMagnifier_) {
            revert FluidConfigError(ErrorTypes.EthenaRateConfigHandler__NoUpdate);
        }

        FluidVaultT1Admin(address(VAULT)).updateBorrowRateMagnifier(targetMagnifier_);

        emit LogUpdateBorrowRateMagnifier(currentMagnifier_, targetMagnifier_);
    }

    /// @notice Calculates the new borrow rate magnifier based on sUSDe yield rate and utilization
    /// @return magnifier_ the calculated magnifier value.
    function calculateMagnifier() public view returns (uint256 magnifier_) {
        uint256 sUSDeYieldRate_ = getSUSDeYieldRate();
        uint256 exchangePriceAndConfig_ = LIQUIDITY.readFromStorage(_LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT);

        uint256 utilization_ = (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) & X14;

        // calculate target borrow rate. scaled by 1e18.
        // borrow rate is based on sUSDeYieldRate_ and a margin that goes to lenders
        // e.g. when RATE_PERCENT_MARGIN = 1000 (10%), then borrow rate will be 90% of the sUSDe yield rate
        // e.g. when sUSDe yield is 60%, borrow rate would be 54%
        uint256 targetBorrowRate_ = (sUSDeYieldRate_ * (1e4 - RATE_PERCENT_MARGIN)) / 1e4;

        if (utilization_ > UTILIZATION_PENALTY_START) {
            // above UTILIZATION_PENALTY_START (e.g. 90%), penalty should rise linearly according to UTILIZATION100_PENALTY_PERCENT
            // e.g. from 10% margin at 90% utilization to -3% penalty at 100% utilization
            // so from +RATE_PERCENT_MARGIN at UTILIZATION_PENALTY_START to -UTILIZATION100_PENALTY_PERCENT at 100%
            if (utilization_ < 1e4) {
                uint256 utilizationAbovePenaltyStart_ = utilization_ - UTILIZATION_PENALTY_START;
                uint256 penaltyUtilizationDiff_ = 1e4 - UTILIZATION_PENALTY_START;
                uint256 penaltyRateDiff_ = RATE_PERCENT_MARGIN + UTILIZATION100_PENALTY_PERCENT;

                // e.g. when current utilization = 96%, start penalty utilization = 90%, penalty at 100 = 3%, rate margin = 90%:
                // utilizationAbovePenaltyStart_ = 600 (6%)
                // penaltyUtilizationDiff_ = 1000 (10%)
                // penaltyRateDiff_ = 1000 + 300 = 1300 (13%)
                // marginAfterPenalty_ = 1300 * 600 / 1000 = 780 (7.8%)
                uint256 marginAfterPenalty_ = (penaltyRateDiff_ * utilizationAbovePenaltyStart_) /
                    penaltyUtilizationDiff_;

                // e.g. when sUSDe yield is 60%, borrow rate would become 58.68% (from 60% * (90% + 7.8%) / 100% )
                targetBorrowRate_ = (sUSDeYieldRate_ * ((1e4 - RATE_PERCENT_MARGIN) + marginAfterPenalty_)) / 1e4;
            } else {
                // above 100% utilization, cap at -UTILIZATION100_PENALTY_PERCENT penalty
                targetBorrowRate_ = (sUSDeYieldRate_ * (1e4 + UTILIZATION100_PENALTY_PERCENT)) / 1e4;
            }
        }

        // get current neutral borrow rate at Liquidity (without any magnifier).
        // exchangePriceAndConfig slot at Liquidity, first 16 bits
        uint256 liquidityBorrowRate_ = exchangePriceAndConfig_ & X16;

        if (liquidityBorrowRate_ == 0) {
            return 1e4;
        }

        // calculate magnifier needed to reach target borrow rate.
        // liquidityBorrowRate_ * x = targetBorrowRate_. so x = targetBorrowRate_ / liquidityBorrowRate_.
        // must scale liquidityBorrowRate_ from 1e2 to 1e18 as targetBorrowRate_ is in 1e18. magnifier itself is scaled
        // by 1e4 (1x = 10000)
        magnifier_ = (1e4 * targetBorrowRate_) / (liquidityBorrowRate_ * 1e16);

        // make sure magnifier is within allowed limits
        if (magnifier_ < _MIN_MAGNIFIER) {
            return _MIN_MAGNIFIER;
        }
        if (magnifier_ > _MAX_MAGNIFIER) {
            return _MAX_MAGNIFIER;
        }
    }

    /// @notice returns the currently configured borrow magnifier at the `VAULT`.
    function currentMagnifier() public view returns (uint256) {
        // read borrow rate magnifier from Vault `vaultVariables2` located in storage slot 1, 16 bits from 16-31
        return (VAULT.readFromStorage(bytes32(uint256(1))) >> 16) & X16;
    }

    /// @notice calculates updated vesting yield rate based on `vestingAmount` and `totalAssets` of StakedUSDe contract
    /// @return rate_ sUSDe yearly yield rate scaled by 1e18 (1e18 = 1%, 1e20 = 100%)
    function getSUSDeYieldRate() public view returns (uint256 rate_) {
        if (block.timestamp > SUSDE.lastDistributionTimestamp() + _SUSDE_VESTING_PERIOD + MAX_REWARDS_DELAY) {
            // if rewards update on StakedUSDe contract is delayed by more than `MAX_REWARDS_DELAY`, we use rate as 0
            // as we can't know if e.g. funding would have gone negative and there are indeed no rewards.
            return 0;
        }

        // vestingAmount is yield per 8 hours (`SUSDE_VESTING_PERIOD`)
        rate_ = (SUSDE.vestingAmount() * 1e20) / SUSDE.totalAssets(); // 8 hours rate
        // turn into yearly yield
        rate_ = (rate_ * 365 * 24 hours) / _SUSDE_VESTING_PERIOD; // 365 days * 24 hours / 8 hours -> rate_ * 1095
    }
}
