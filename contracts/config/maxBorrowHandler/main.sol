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

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
}

abstract contract Events {
    /// @notice emitted when borrow max limit is updated
    event LogUpdateBorrowMaxDebtCeiling(
        uint256 totalSupplyNormal,
        uint256 oldMaxDebtCeilingRaw,
        uint256 maxDebtCeilingRaw,
        uint256 borrowExchangePrice
    );
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

    /// @notice returns `BORROW_TOKEN` total supply at Liquidity (in normal).
    function getTotalSupply() public view returns (uint256 totalSupplyNormal_) {
        (totalSupplyNormal_, ) = _getTotalSupply();
    }

    /// @notice returns the currently set max debt ceiling (in raw for mode with interest!).
    function currentMaxDebtCeiling() public view returns (uint256 maxDebtCeiling_) {
        return
            BigMathMinified.fromBigNumber(
                (LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT) >>
                    LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            );
    }

    /// @notice returns the max debt ceiling that should be set according to current state (in normal).
    function calcMaxDebtCeilingNormal() public view returns (uint256 maxDebtCeilingNormal_) {
        (uint256 maxDebtCeilingRaw_, , uint256 borrowExchangePrice_, , ) = _calcMaxDebtCeiling();
        // convert to normal
        maxDebtCeilingNormal_ = (maxDebtCeilingRaw_ * borrowExchangePrice_) / EXCHANGE_PRICES_PRECISION;
    }

    /// @notice returns the max debt ceiling that should be set according to current state (in raw for mode with interest!).
    function calcMaxDebtCeiling() public view returns (uint256 maxDebtCeiling_) {
        (maxDebtCeiling_, , , , ) = _calcMaxDebtCeiling();
    }

    /// @notice returns how much new config would be different from current config in percent (100 = 1%, 1 = 0.01%).
    function configPercentDiff() public view returns (uint256 configPercentDiff_) {
        (uint256 maxDebtCeilingRaw_, , , uint256 userBorrowData_, ) = _calcMaxDebtCeiling();

        (configPercentDiff_, ) = _configPercentDiff(userBorrowData_, maxDebtCeilingRaw_);
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

    function _getTotalSupply() internal view returns (uint256 totalSupplyNormal_, uint256 borrowExchangePrice_) {
        uint256 supplyExchangePrice_;

        (supplyExchangePrice_, borrowExchangePrice_) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY_RESOLVER.getExchangePricesAndConfig(BORROW_TOKEN)
        );

        totalSupplyNormal_ = LiquidityCalcs.getTotalSupply(
            LIQUIDITY_RESOLVER.getTotalAmounts(BORROW_TOKEN),
            supplyExchangePrice_
        );
    }

    function _calcMaxDebtCeiling()
        internal
        view
        returns (
            uint256 maxDebtCeilingRaw_,
            uint256 totalSupplyNormal_,
            uint256 borrowExchangePrice_,
            uint256 userBorrowData_,
            uint256 baseDebtCeilingRaw_
        )
    {
        (totalSupplyNormal_, borrowExchangePrice_) = _getTotalSupply();

        uint256 maxDebtCeilingNormal_ = (MAX_UTILIZATION * totalSupplyNormal_) / MAX_UTILIZATION_PRECISION;

        // turn into maxDebtCeiling Raw
        maxDebtCeilingRaw_ = (maxDebtCeilingNormal_ * EXCHANGE_PRICES_PRECISION) / borrowExchangePrice_;

        userBorrowData_ = LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT); // total storage slot

        baseDebtCeilingRaw_ = BigMathMinified.fromBigNumber(
            (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (baseDebtCeilingRaw_ > maxDebtCeilingRaw_) {
            // max debt ceiling can never be < base debt ceiling
            maxDebtCeilingRaw_ = baseDebtCeilingRaw_;
        }
    }

    function _configPercentDiff(
        uint256 userBorrowData_,
        uint256 maxDebtCeilingRaw_
    ) internal pure returns (uint256 configPercentDiff_, uint256 oldMaxDebtCeilingRaw_) {
        oldMaxDebtCeilingRaw_ = BigMathMinified.fromBigNumber(
            (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (oldMaxDebtCeilingRaw_ == maxDebtCeilingRaw_) {
            return (0, oldMaxDebtCeilingRaw_);
        }

        if (oldMaxDebtCeilingRaw_ > maxDebtCeilingRaw_) {
            // % of how much new max debt ceiling would be smaller
            configPercentDiff_ = oldMaxDebtCeilingRaw_ - maxDebtCeilingRaw_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 10 -> 2000 (20%)
        } else {
            // % of how much new max debt ceiling would be bigger
            configPercentDiff_ = maxDebtCeilingRaw_ - oldMaxDebtCeilingRaw_;
            // e.g. 10 - 8 = 2. 2 * 10000 / 8 -> 2500 (25%)
        }

        configPercentDiff_ = (configPercentDiff_ * 1e4) / oldMaxDebtCeilingRaw_;
    }

    function _updateBorrowLimits() internal returns (bool updated_) {
        (
            uint256 maxDebtCeilingRaw_,
            uint256 totalSupplyNormal_,
            uint256 borrowExchangePrice_,
            uint256 userBorrowData_,
            uint256 baseDebtCeilingRaw_
        ) = _calcMaxDebtCeiling();

        (uint256 configPercentDiff_, uint256 oldMaxDebtCeilingRaw_) = _configPercentDiff(
            userBorrowData_,
            maxDebtCeilingRaw_
        );

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
            baseDebtCeiling: baseDebtCeilingRaw_, // set same as old
            maxDebtCeiling: maxDebtCeilingRaw_
        });
        LIQUIDITY.updateUserBorrowConfigs(userBorrowConfigs_);

        emit LogUpdateBorrowMaxDebtCeiling(
            totalSupplyNormal_,
            oldMaxDebtCeilingRaw_,
            maxDebtCeilingRaw_,
            borrowExchangePrice_
        );

        return true;
    }
}
