// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidVaultT1Admin } from "../vaultT1/adminModule/main.sol";
import { IFluidVaultT1 } from "../interfaces/iVaultT1.sol";
import { IFluidReserveContract } from "../../../reserve/interfaces/iReserveContract.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { Events } from "./events.sol";
import { Variables } from "./variables.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

/// @title VaultRewards
/// @notice This contract is designed to adjust the borrow rate magnifier for a vault based on the current debt borrow & borrow rate.
/// The adjustment aims to dynamically scale the rewards given to lenders as the TVL in the vault changes
///
/// The magnifier is adjusted based on a regular most used reward type where rewardRate = totalRewardsAnnually / totalborrow.
/// Reward rate is applied by adjusting the borrow magnifier on vault.
/// Adjustments are made via the rebalance function, which is restricted to be called by designated rebalancers only.
contract FluidVaultBorrowRewards is Variables, Events, Error {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__Unauthorized);
        }
        _;
    }

    /// @notice Constructs the FluidVaultBorrowRewards contract.
    /// @param reserveContract_ The address of the reserve contract where rebalancers are defined.
    /// @param vault_ The vault to which this contract will apply new magnifier parameter.
    /// @param liquidity_ Fluid liquidity address
    /// @param rewardsAmt_ Amounts of rewards to distribute
    /// @param duration_ rewards duration
    /// @param initiator_ address that can start rewards with `start()`
    /// @param debtToken_ vault debt token address
    /// @param governance_ governance address
    constructor(
        IFluidReserveContract reserveContract_,
        IFluidVaultT1 vault_,
        IFluidLiquidity liquidity_,
        uint256 rewardsAmt_,
        uint256 duration_,
        address initiator_,
        address debtToken_,
        address governance_
    )
        validAddress(address(reserveContract_))
        validAddress(address(liquidity_))
        validAddress(address(vault_))
        validAddress(initiator_)
        validAddress(address(debtToken_))
        validAddress(governance_)
    {
        if (rewardsAmt_ == 0 || duration_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__InvalidParams);
        }
        RESERVE_CONTRACT = reserveContract_;
        VAULT = vault_;
        rewardsAmount = uint128(rewardsAmt_);
        rewardsAmountPerYear = (rewardsAmt_ * SECONDS_PER_YEAR) / duration_;
        duration = uint40(duration_);
        INITIATOR = initiator_;
        LIQUIDITY = liquidity_;
        VAULT_DEBT_TOKEN = debtToken_;
        GOVERNANCE = governance_;

        LIQUIDITY_TOTAL_AMOUNTS_DEBT_TOKEN_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            debtToken_
        );
        LIQUIDITY_EXCHANGE_PRICE_DEBT_TOKEN_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            debtToken_
        );
    }

    /// @notice Rebalances the borrow rate magnifier based on the current debt borrow.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external onlyRebalancer {
        (uint256 newMagnifier_, bool ended_) = calculateBorrowMagnifier();
        if (ended_ && newMagnifier_ == FOUR_DECIMALS) {
            if (nextDuration == 0 || nextRewardsAmount == 0) {
                ended = true;
            } else {
                rewardsAmount = nextRewardsAmount;
                rewardsAmountPerYear = (nextRewardsAmount * SECONDS_PER_YEAR) / nextDuration;
                duration = nextDuration;
                nextRewardsAmount = 0;
                nextDuration = 0;
                startTime = uint40(block.timestamp);
                endTime = uint40(block.timestamp + duration);
                (newMagnifier_, ended_) = calculateBorrowMagnifier();
            }
        }
        if (newMagnifier_ == currentBorrowMagnifier()) {
            if (ended_) {
                return;
            }
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier);
        }

        FluidVaultT1Admin(address(VAULT)).updateBorrowRateMagnifier(newMagnifier_);
        emit LogUpdateMagnifier(address(VAULT), newMagnifier_);
    }

    /// @notice Calculates the new borrow rate magnifier based on the current debt borrow (`vaultTVL()`).
    /// @return magnifier_ The calculated magnifier value.
    function calculateBorrowMagnifier() public view returns (uint256 magnifier_, bool ended_) {
        uint256 currentTVL_ = vaultBorrowTVL();
        uint256 startTime_ = uint256(startTime);
        uint256 endTime_ = uint256(endTime);

        if (startTime_ == 0 || endTime_ == 0 || ended) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__RewardsNotStartedOrEnded);
        }

        if (block.timestamp > endTime_) {
            return (FOUR_DECIMALS, true);
        }

        uint borrowRate_ = getBorrowRate();
        uint rewardsRate_ = (rewardsAmountPerYear * FOUR_DECIMALS) / currentTVL_;

        if (borrowRate_ > 0) {
            uint256 rewardsDelta_ = (rewardsRate_ * FOUR_DECIMALS) / borrowRate_;
            magnifier_ = (rewardsDelta_ < FOUR_DECIMALS) ? FOUR_DECIMALS - rewardsDelta_ : 0;
        } else {
            magnifier_ = FOUR_DECIMALS;
        }
    }

    /// @notice returns the currently configured borrow magnifier at the `VAULT`.
    function currentBorrowMagnifier() public view returns (uint256) {
        // read borrow rate magnifier from Vault `vaultVariables2` located in storage slot 1, first 16 bits
        return (VAULT.readFromStorage(bytes32(uint256(1))) >> 16) & X16;
    }

    /// @notice returns the current total value locked as debt (TVL) in the `VAULT`.
    function vaultBorrowTVL() public view returns (uint256 tvl_) {
        // read total borrow raw in vault from storage slot 0 `vaultVariables`, 64 bits 146-209
        tvl_ = (VAULT.readFromStorage(bytes32(0)) >> 146) & 0xFFFFFFFFFFFFFFFF;

        // Converting bignumber into normal number
        tvl_ = (tvl_ >> 8) << (tvl_ & 0xFF);

        // get updated borrow exchange price, which takes slot 1 `vaultVariables2` as input param
        (, , , uint256 vaultBorrowExPrice_) = VAULT.updateExchangePrices(VAULT.readFromStorage(bytes32(uint256(1))));

        // converting raw total borrow into normal amount
        tvl_ = (tvl_ * vaultBorrowExPrice_) / 1e12;
    }

    /// @notice Returns the current borrow rate from the liquidity contract.
    /// @return The borrow rate as a uint256.
    function getBorrowRate() public view returns (uint256) {
        uint256 exchangePriceAndConfig_ = LIQUIDITY.readFromStorage(LIQUIDITY_EXCHANGE_PRICE_DEBT_TOKEN_SLOT);
        return exchangePriceAndConfig_ & X16;
    }

    /// @notice Starts the rewards at the current block timestamp.
    function start() external {
        startAt(block.timestamp);
    }

    /// @notice Starts the rewards at a specified timestamp.
    /// @param startTime_ The timestamp at which to start the rewards.
    function startAt(uint256 startTime_) public {
        if (msg.sender != INITIATOR) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__NotTheInitiator);
        }
        if (startTime > 0 || endTime > 0) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__AlreadyStarted);
        }
        if (startTime_ < block.timestamp || startTime_ > block.timestamp + 2 weeks) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__InvalidStartTime);
        }
        startTime = uint40(startTime_);
        endTime = uint40(startTime_ + duration);
        emit LogRewardsStarted(startTime, endTime);
    }

    /// @notice Queues the next rewards with specified amount and duration.
    /// @param rewardsAmount_ The amount of rewards to be distributed.
    /// @param duration_ The duration of the rewards program.
    /// @dev This function can only be called by the governance address.
    /// @dev Reverts if the current rewards period has already ended.
    function queueNextRewards(uint256 rewardsAmount_, uint256 duration_) external {
        if (msg.sender != GOVERNANCE) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__NotTheGovernance);
        }
        if (rewardsAmount_ == 0 || duration_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__InvalidParams);
        }
        if (block.timestamp > endTime || ended) {
            revert FluidVaultError(ErrorTypes.VaultBorrowRewards__AlreadyEnded);
        }
        nextRewardsAmount = uint128(rewardsAmount_);
        nextDuration = uint40(duration_);
        emit LogNextRewardsQueued(rewardsAmount_, duration_);
    }
}
