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
/// @notice This contract is designed to adjust the supply rate magnifier for a vault based on the current collateral supply & supply rate.
/// The adjustment aims to dynamically scale the rewards given to lenders as the TVL in the vault changes.
///
/// The magnifier is adjusted based on a regular most used reward type where rewardRate = totalRewardsAnnually / totalSupply.
/// Reward rate is applied by adjusting the supply magnifier on vault.
/// Adjustments are made via the rebalance function, which is restricted to be called by designated rebalancers only.
contract FluidVaultRewards is Variables, Events, Error {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultRewards__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidVaultError(ErrorTypes.VaultRewards__Unauthorized);
        }
        _;
    }

    /// @notice Constructs the FluidVaultRewards contract.
    /// @param reserveContract_ The address of the reserve contract where rebalancers are defined.
    /// @param vault_ The vault to which this contract will apply new magnifier parameter.
    /// @param liquidity_ Fluid liquidity address
    /// @param rewardsAmt_ Amounts of rewards to distribute
    /// @param duration_ rewards duration
    /// @param initiator_ address that can start rewards with `start()`
    /// @param collateralToken_ vault collateral token address
    /// @param governance_ governance address
    constructor(
        IFluidReserveContract reserveContract_,
        IFluidVaultT1 vault_,
        IFluidLiquidity liquidity_,
        uint256 rewardsAmt_,
        uint256 duration_,
        address initiator_,
        address collateralToken_,
        address governance_
    )
        validAddress(address(reserveContract_))
        validAddress(address(liquidity_))
        validAddress(address(vault_))
        validAddress(initiator_)
        validAddress(address(collateralToken_))
        validAddress(governance_)
    {
        if (rewardsAmt_ == 0 || duration_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultRewards__InvalidParams);
        }
        RESERVE_CONTRACT = reserveContract_;
        VAULT = vault_;
        rewardsAmount = uint128(rewardsAmt_);
        rewardsAmountPerYear = (rewardsAmt_ * SECONDS_PER_YEAR) / duration_;
        duration = uint40(duration_);
        INITIATOR = initiator_;
        LIQUIDITY = liquidity_;
        VAULT_COLLATERAL_TOKEN = collateralToken_;
        GOVERNANCE = governance_;

        LIQUIDITY_TOTAL_AMOUNTS_COLLATERAL_TOKEN_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT,
            collateralToken_
        );
        LIQUIDITY_EXCHANGE_PRICE_COLLATERAL_TOKEN_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            collateralToken_
        );
    }

    /// @notice Rebalances the supply rate magnifier based on the current collateral supply.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external onlyRebalancer {
        (uint256 newMagnifier_, bool ended_) = calculateMagnifier();
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
                (newMagnifier_, ended_) = calculateMagnifier();
            }
        }
        if (newMagnifier_ == currentMagnifier()) {
            if (ended_) {
                return;
            }
            revert FluidVaultError(ErrorTypes.VaultRewards__NewMagnifierSameAsOldMagnifier);
        }

        FluidVaultT1Admin(address(VAULT)).updateSupplyRateMagnifier(newMagnifier_);
        emit LogUpdateMagnifier(address(VAULT), newMagnifier_);
    }

    /// @notice Calculates the new supply rate magnifier based on the current collateral supply (`vaultTVL()`).
    /// @return magnifier_ The calculated magnifier value.
    function calculateMagnifier() public view returns (uint256 magnifier_, bool ended_) {
        uint256 currentTVL_ = vaultTVL();
        uint256 startTime_ = uint256(startTime);
        uint256 endTime_ = uint256(endTime);

        if (startTime_ == 0 || endTime_ == 0 || ended) {
            revert FluidVaultError(ErrorTypes.VaultRewards__RewardsNotStartedOrEnded);
        }

        if (block.timestamp > endTime_) {
            return (FOUR_DECIMALS, true);
        }

        uint supplyRate_ = getSupplyRate();
        uint rewardsRate_ = (rewardsAmountPerYear * FOUR_DECIMALS) / currentTVL_;

        magnifier_ = FOUR_DECIMALS + (supplyRate_ == 0 ? rewardsRate_ : ((rewardsRate_ * FOUR_DECIMALS) / supplyRate_));
        if (magnifier_ > X16) {
            magnifier_ = X16;
        }
    }

    /// @notice returns the currently configured supply magnifier at the `VAULT`.
    function currentMagnifier() public view returns (uint256) {
        // read supply rate magnifier from Vault `vaultVariables2` located in storage slot 1, first 16 bits
        return VAULT.readFromStorage(bytes32(uint256(1))) & X16;
    }

    /// @notice returns the current total value locked as collateral (TVL) in the `VAULT`.
    function vaultTVL() public view returns (uint256 tvl_) {
        // read total supply raw in vault from storage slot 0 `vaultVariables`, 64 bits 82-145
        tvl_ = (VAULT.readFromStorage(bytes32(0)) >> 82) & 0xFFFFFFFFFFFFFFFF;

        // Converting bignumber into normal number
        tvl_ = (tvl_ >> 8) << (tvl_ & 0xFF);

        // get updated supply exchange price, which takes slot 1 `vaultVariables2` as input param
        (, , uint256 vaultSupplyExPrice_, ) = VAULT.updateExchangePrices(VAULT.readFromStorage(bytes32(uint256(1))));

        // converting raw total supply into normal amount
        tvl_ = (tvl_ * vaultSupplyExPrice_) / 1e12;
    }

    function getSupplyRate() public view returns (uint supplyRate_) {
        uint256 exchangePriceAndConfig_ = LIQUIDITY.readFromStorage(LIQUIDITY_EXCHANGE_PRICE_COLLATERAL_TOKEN_SLOT);
        uint256 totalAmounts_ = LIQUIDITY.readFromStorage(LIQUIDITY_TOTAL_AMOUNTS_COLLATERAL_TOKEN_SLOT);

        uint borrowRate_ = exchangePriceAndConfig_ & X16;
        uint fee_ = (exchangePriceAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14;
        uint supplyExchangePrice_ = ((exchangePriceAndConfig_ >>
            LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64);
        uint borrowExchangePrice_ = ((exchangePriceAndConfig_ >>
            LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64);

        // Extract supply raw interest
        uint256 supplyWithInterest_ = totalAmounts_ & X64;
        supplyWithInterest_ =
            (supplyWithInterest_ >> DEFAULT_EXPONENT_SIZE) <<
            (supplyWithInterest_ & DEFAULT_EXPONENT_MASK);

        // Extract borrow raw interest
        uint256 borrowWithInterest_ = (totalAmounts_ >> LiquiditySlotsLink.BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST) &
            X64;
        borrowWithInterest_ =
            (borrowWithInterest_ >> DEFAULT_EXPONENT_SIZE) <<
            (borrowWithInterest_ & DEFAULT_EXPONENT_MASK);

        if (supplyWithInterest_ > 0) {
            // use old exchange prices for supply rate to be at same level as borrow rate from storage.
            // Note the rate here can be a tiny bit with higher precision because we use borrowWithInterest_ / supplyWithInterest_
            // which has higher precision than the utilization used from storage in LiquidityCalcs
            supplyWithInterest_ = (supplyWithInterest_ * supplyExchangePrice_) / EXCHANGE_PRICES_PRECISION; // normalized from raw
            borrowWithInterest_ = (borrowWithInterest_ * borrowExchangePrice_) / EXCHANGE_PRICES_PRECISION; // normalized from raw

            supplyRate_ =
                (borrowRate_ * (FOUR_DECIMALS - fee_) * borrowWithInterest_) /
                (supplyWithInterest_ * FOUR_DECIMALS);
        }
    }

    function start() external {
        startAt(block.timestamp);
    }

    function startAt(uint256 startTime_) public {
        if (msg.sender != INITIATOR) {
            revert FluidVaultError(ErrorTypes.VaultRewards__NotTheInitiator);
        }
        if (startTime > 0 || endTime > 0) {
            revert FluidVaultError(ErrorTypes.VaultRewards__AlreadyStarted);
        }
        if (startTime_ < block.timestamp || startTime_ > block.timestamp + 2 weeks) {
            revert FluidVaultError(ErrorTypes.VaultRewards__InvalidStartTime);
        }
        startTime = uint40(startTime_);
        endTime = uint40(startTime_ + duration);
        emit LogRewardsStarted(startTime, endTime);
    }

    function queueNextRewards(uint256 rewardsAmount_, uint256 duration_) external {
        if (msg.sender != GOVERNANCE) {
            revert FluidVaultError(ErrorTypes.VaultRewards__NotTheGovernance);
        }
        if (rewardsAmount_ == 0 || duration_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultRewards__InvalidParams);
        }
        if (block.timestamp > endTime || ended) {
            revert FluidVaultError(ErrorTypes.VaultRewards__AlreadyEnded);
        }
        nextRewardsAmount = uint128(rewardsAmount_);
        nextDuration = uint40(duration_);
        emit LogNextRewardsQueued(rewardsAmount_, duration_);
    }
}
