// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidLiquidityResolver } from "../../periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { LiquidityCalcs } from "../../libraries/liquidityCalcs.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Constants {
    IFluidReserveContract public immutable RESERVE_CONTRACT;
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidLiquidityResolver public immutable LIQUIDITY_RESOLVER;
    address public immutable PROTOCOL;
    address public immutable BORROW_TOKEN;

    /// @dev max utilization of total supply that will be set as max borrow limit. In percent (100 = 1%, 1 = 0.01%)
    uint256 public immutable MAX_UTILIZATION;

    /// @dev minimum percent difference to trigger an update. In percent (100 = 1%, 1 = 0.01%)
    uint256 public immutable MIN_UPDATE_DIFF;

    bytes32 internal immutable _LIQUDITY_PROTOCOL_BORROW_SLOT;

    uint256 internal constant MAX_UTILIZATION_PRECISION = 1e4;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xff;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
}

abstract contract Events {
    /// @notice emitted when borrow max limit is updated
    event LogUpdateBorrowMaxDebtCeiling(uint256 totalSupply, uint256 oldMaxDebtCeiling, uint256 maxDebtCeiling);
}

/// @notice Sets max borrow limit for a protocol on Liquidity based on utilization of total supply of the same borrow token
contract FluidMaxBorrowConfigHandler is Constants, Error, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.MaxBorrowConfigHandler__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.MaxBorrowConfigHandler__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        IFluidLiquidity liquidity_,
        IFluidLiquidityResolver liquidityResolver_,
        address protocol_,
        address borrowToken_,
        uint256 maxUtilization_,
        uint256 minUpdateDiff_
    )
        validAddress(address(reserveContract_))
        validAddress(address(liquidity_))
        validAddress(address(liquidityResolver_))
        validAddress(protocol_)
        validAddress(borrowToken_)
    {
        RESERVE_CONTRACT = reserveContract_;
        LIQUIDITY = liquidity_;
        LIQUIDITY_RESOLVER = liquidityResolver_;
        PROTOCOL = protocol_;
        BORROW_TOKEN = borrowToken_;

        if (maxUtilization_ > MAX_UTILIZATION_PRECISION || minUpdateDiff_ == 0) {
            revert FluidConfigError(ErrorTypes.MaxBorrowConfigHandler__InvalidParams);
        }

        _LIQUDITY_PROTOCOL_BORROW_SLOT = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
            protocol_,
            borrowToken_
        );

        MAX_UTILIZATION = maxUtilization_;
        MIN_UPDATE_DIFF = minUpdateDiff_;
    }

    /// @notice returns `BORROW_TOKEN` total supply at Liquidity
    function getTotalSupply() public view returns (uint256 totalSupply_) {
        uint256 exchangePriceAndConfig_ = LIQUIDITY_RESOLVER.getExchangePricesAndConfig(BORROW_TOKEN);
        uint256 totalAmounts_ = LIQUIDITY_RESOLVER.getTotalAmounts(BORROW_TOKEN);

        (uint256 supplyExchangePrice_, ) = LiquidityCalcs.calcExchangePrices(exchangePriceAndConfig_);

        totalSupply_ = LiquidityCalcs.getTotalSupply(totalAmounts_, supplyExchangePrice_);
    }

    /// @notice returns the currently set max debt ceiling.
    function currentMaxDebtCeiling() public view returns (uint256 maxDebtCeiling_) {
        return
            BigMathMinified.fromBigNumber(
                (LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT) >>
                    LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );
    }

    /// @notice returns the max debt ceiling that should be set according to current state.
    function calcMaxDebtCeiling() public view returns (uint256 maxDebtCeiling_) {
        (maxDebtCeiling_, ) = _calcMaxDebtCeiling(
            getTotalSupply(),
            LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT)
        );
    }

    /// @notice returns how much new config would be different from current config in percent (100 = 1%, 1 = 0.01%).
    function configPercentDiff() public view returns (uint256 configPercentDiff_) {
        (configPercentDiff_, , , , , ) = _configPercentDiff();
    }

    /// @notice Rebalances the configs for `PROTOCOL` at Fluid Liquidity based on protocol total supply & total borrow.
    /// Emits `LogUpdateBorrowMaxDebtCeiling` if update is executed.
    /// Reverts if no update is needed.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external onlyRebalancer {
        if (!_updateBorrowLimits()) {
            revert FluidConfigError(ErrorTypes.MaxBorrowConfigHandler__NoUpdate);
        }
    }

    /***********************************|
    |            INTERNALS              | 
    |__________________________________*/

    function _calcMaxDebtCeiling(
        uint256 totalSupply_,
        uint256 userBorrowData_
    ) internal view returns (uint256 maxDebtCeiling_, uint256 baseDebtCeiling_) {
        maxDebtCeiling_ = (MAX_UTILIZATION * totalSupply_) / MAX_UTILIZATION_PRECISION;

        baseDebtCeiling_ = BigMathMinified.fromBigNumber(
            (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (baseDebtCeiling_ > maxDebtCeiling_) {
            // max debt ceiling can never be < base debt ceiling
            maxDebtCeiling_ = baseDebtCeiling_;
        }
    }

    function _configPercentDiff()
        internal
        view
        returns (
            uint256 configPercentDiff_,
            uint256 userBorrowData_,
            uint256 totalSupply_,
            uint256 oldMaxDebtCeiling_,
            uint256 maxDebtCeiling_,
            uint256 baseDebtCeiling_
        )
    {
        userBorrowData_ = LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT); // total storage slot

        oldMaxDebtCeiling_ = BigMathMinified.fromBigNumber(
            (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        totalSupply_ = getTotalSupply();
        (maxDebtCeiling_, baseDebtCeiling_) = _calcMaxDebtCeiling(totalSupply_, userBorrowData_);

        if (oldMaxDebtCeiling_ == maxDebtCeiling_) {
            return (0, userBorrowData_, totalSupply_, oldMaxDebtCeiling_, maxDebtCeiling_, baseDebtCeiling_);
        }

        if (oldMaxDebtCeiling_ > maxDebtCeiling_) {
            // % of how much new max debt ceiling would be smaller
            configPercentDiff_ = oldMaxDebtCeiling_ - maxDebtCeiling_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 10 -> 2000 (20%)
        } else {
            // % of how much new max debt ceiling would be bigger
            configPercentDiff_ = maxDebtCeiling_ - oldMaxDebtCeiling_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 8 -> 2500 (25%)
        }

        configPercentDiff_ = (configPercentDiff_ * 1e4) / oldMaxDebtCeiling_;
    }

    function _updateBorrowLimits() internal returns (bool updated_) {
        (
            uint256 configPercentDiff_,
            uint256 userBorrowData_,
            uint256 totalSupply_,
            uint256 oldMaxDebtCeiling_,
            uint256 maxDebtCeiling_,
            uint256 baseDebtCeiling_
        ) = _configPercentDiff();

        // check if min config deviation is reached
        if (configPercentDiff_ < MIN_UPDATE_DIFF) {
            return false;
        }

        // execute update at Liquidity
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: PROTOCOL,
            token: BORROW_TOKEN,
            mode: uint8(userBorrowData_ & 1), // first bit
            expandPercent: (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14, // set same as old
            expandDuration: (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24, // set same as old
            baseDebtCeiling: baseDebtCeiling_, // set same as old
            maxDebtCeiling: maxDebtCeiling_
        });
        LIQUIDITY.updateUserBorrowConfigs(userBorrowConfigs_);

        emit LogUpdateBorrowMaxDebtCeiling(totalSupply_, oldMaxDebtCeiling_, maxDebtCeiling_);

        return true;
    }
}
