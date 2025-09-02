// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Constants {
    IFluidReserveContract public immutable RESERVE_CONTRACT;
    IFluidLiquidity public immutable LIQUIDITY;
    address public immutable PROTOCOL;
    address public immutable WITHDRAW_TOKEN;
    address public immutable BORROW_TOKEN;

    uint256 public immutable BORROW_CHECKPOINT1;
    uint256 public immutable BORROW_CHECKPOINT2;
    uint256 public immutable BORROW_CHECKPOINT3;
    uint256 public immutable BORROW_EXPAND_UNTIL_CHECKPOINT1;
    uint256 public immutable BORROW_EXPAND_UNTIL_CHECKPOINT2;
    uint256 public immutable BORROW_EXPAND_UNTIL_CHECKPOINT3;
    uint256 public immutable BORROW_EXPAND_ABOVE_CHECKPOINT3;

    uint256 public immutable WITHDRAW_CHECKPOINT1;
    uint256 public immutable WITHDRAW_CHECKPOINT2;
    uint256 public immutable WITHDRAW_CHECKPOINT3;
    uint256 public immutable WITHDRAW_EXPAND_UNTIL_CHECKPOINT1;
    uint256 public immutable WITHDRAW_EXPAND_UNTIL_CHECKPOINT2;
    uint256 public immutable WITHDRAW_EXPAND_UNTIL_CHECKPOINT3;
    uint256 public immutable WITHDRAW_EXPAND_ABOVE_CHECKPOINT3;

    bytes32 internal immutable _LIQUDITY_WITHDRAW_TOKEN_EXCHANGE_PRICES_SLOT;
    bytes32 internal immutable _LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT;

    bytes32 internal immutable _LIQUDITY_PROTOCOL_SUPPLY_SLOT;
    bytes32 internal immutable _LIQUDITY_PROTOCOL_BORROW_SLOT;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xff;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
}

abstract contract Events {
    /// @notice emitted when withdraw limit expand percent is updated
    event LogUpdateWithdrawLimitExpansion(uint256 supply, uint256 oldExpandPercent, uint256 newExpandPercent);

    /// @notice emitted when borrow limit expand percent is updated
    event LogUpdateBorrowLimitExpansion(uint256 borrow, uint256 oldExpandPercent, uint256 newExpandPercent);
}

abstract contract Structs {
    struct LimitCheckPoints {
        uint256 tvlCheckPoint1; // e.g. 20M
        uint256 expandPercentUntilCheckPoint1; // e.g. 25%
        uint256 tvlCheckPoint2; // e.g. 30M
        uint256 expandPercentUntilCheckPoint2; // e.g. 20%
        uint256 tvlCheckPoint3; // e.g. 40M
        uint256 expandPercentUntilCheckPoint3; // e.g. 15%
        uint256 expandPercentAboveCheckPoint3; // e.g. 10%
    }
}

/// @notice Sets limits on Liquidity for a protocol based on TVL checkpoints.
contract FluidExpandPercentConfigHandler is Constants, Error, Events, Structs {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__AddressZero);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract)
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        IFluidLiquidity liquidity_,
        address protocol_,
        address withdrawToken_, // can be unused in some cases (e.g. StETH)
        address borrowToken_, // can be unused in some cases (e.g. Lending)
        LimitCheckPoints memory withdrawCheckPoints_, // can be skipped if withdrawToken is not set.
        LimitCheckPoints memory borrowCheckPoints_ // can be skipped if borrowToken_ is not set.
    ) validAddress(address(reserveContract_)) validAddress(address(liquidity_)) validAddress(protocol_) {
        RESERVE_CONTRACT = reserveContract_;
        LIQUIDITY = liquidity_;
        PROTOCOL = protocol_;
        WITHDRAW_TOKEN = withdrawToken_;
        BORROW_TOKEN = borrowToken_;

        // set withdraw limit values
        if (withdrawToken_ == address(0)) {
            if (borrowToken_ == address(0)) {
                revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__InvalidParams);
            }

            _LIQUDITY_PROTOCOL_SUPPLY_SLOT = bytes32(0);
        } else {
            _LIQUDITY_PROTOCOL_SUPPLY_SLOT = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                protocol_,
                withdrawToken_
            );
            _LIQUDITY_WITHDRAW_TOKEN_EXCHANGE_PRICES_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                withdrawToken_
            );

            _validateLimitCheckPoints(withdrawCheckPoints_);

            WITHDRAW_CHECKPOINT1 = withdrawCheckPoints_.tvlCheckPoint1;
            WITHDRAW_CHECKPOINT2 = withdrawCheckPoints_.tvlCheckPoint2;
            WITHDRAW_CHECKPOINT3 = withdrawCheckPoints_.tvlCheckPoint3;
            WITHDRAW_EXPAND_UNTIL_CHECKPOINT1 = withdrawCheckPoints_.expandPercentUntilCheckPoint1;
            WITHDRAW_EXPAND_UNTIL_CHECKPOINT2 = withdrawCheckPoints_.expandPercentUntilCheckPoint2;
            WITHDRAW_EXPAND_UNTIL_CHECKPOINT3 = withdrawCheckPoints_.expandPercentUntilCheckPoint3;
            WITHDRAW_EXPAND_ABOVE_CHECKPOINT3 = withdrawCheckPoints_.expandPercentAboveCheckPoint3;
        }

        // set borrow limit values
        if (borrowToken_ == address(0)) {
            _LIQUDITY_PROTOCOL_BORROW_SLOT = bytes32(0);
        } else {
            _validateLimitCheckPoints(borrowCheckPoints_);

            _LIQUDITY_PROTOCOL_BORROW_SLOT = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                protocol_,
                borrowToken_
            );
            _LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                borrowToken_
            );

            BORROW_CHECKPOINT1 = borrowCheckPoints_.tvlCheckPoint1;
            BORROW_CHECKPOINT2 = borrowCheckPoints_.tvlCheckPoint2;
            BORROW_CHECKPOINT3 = borrowCheckPoints_.tvlCheckPoint3;
            BORROW_EXPAND_UNTIL_CHECKPOINT1 = borrowCheckPoints_.expandPercentUntilCheckPoint1;
            BORROW_EXPAND_UNTIL_CHECKPOINT2 = borrowCheckPoints_.expandPercentUntilCheckPoint2;
            BORROW_EXPAND_UNTIL_CHECKPOINT3 = borrowCheckPoints_.expandPercentUntilCheckPoint3;
            BORROW_EXPAND_ABOVE_CHECKPOINT3 = borrowCheckPoints_.expandPercentAboveCheckPoint3;
        }
    }

    /// @notice returns `PROTOCOL` total supply at Liquidity
    function getProtocolSupplyData()
        public
        view
        returns (uint256 supply_, uint256 oldExpandPercent_, uint256 userSupplyData_)
    {
        if (_LIQUDITY_PROTOCOL_SUPPLY_SLOT == bytes32(0)) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__SlotDoesNotExist);
        }
        userSupplyData_ = LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_SUPPLY_SLOT); // total storage slot

        oldExpandPercent_ = (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) & X14;

        // get supply in raw converted from BigNumber
        supply_ = BigMathMinified.fromBigNumber(
            (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (userSupplyData_ & 1 == 1) {
            uint256 exchangePrice_ = ((LIQUIDITY.readFromStorage(_LIQUDITY_WITHDRAW_TOKEN_EXCHANGE_PRICES_SLOT) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & X64);

            supply_ = (supply_ * exchangePrice_) / 1e12; // convert raw to normal amount
        }
    }

    /// @notice returns `PROTOCOL` total borrow at Liquidity
    function getProtocolBorrowData()
        public
        view
        returns (uint256 borrow_, uint256 oldExpandPercent_, uint256 userBorrowData_)
    {
        if (_LIQUDITY_PROTOCOL_BORROW_SLOT == bytes32(0)) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__SlotDoesNotExist);
        }
        userBorrowData_ = LIQUIDITY.readFromStorage(_LIQUDITY_PROTOCOL_BORROW_SLOT); // total storage slot

        oldExpandPercent_ = (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14;

        // get borrow in raw converted from BigNumber
        borrow_ = BigMathMinified.fromBigNumber(
            (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64,
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );

        if (userBorrowData_ & 1 == 1) {
            uint256 exchangePrice_ = ((LIQUIDITY.readFromStorage(_LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT) >>
                LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) & X64);

            borrow_ = (borrow_ * exchangePrice_) / 1e12; // convert raw to normal amount
        }
    }

    /// @notice Rebalances the configs for `PROTOCOL` at Fluid Liquidity based on protocol total supply & total borrow.
    /// Emits `LogUpdateWithdrawLimitExpansion` or `LogUpdateBorrowLimitExpansion` if any update is executed.
    /// Reverts if no update is needed.
    /// Can only be called by an authorized rebalancer.
    function rebalance() external onlyRebalancer {
        bool anyUpdateDone_;
        if (WITHDRAW_TOKEN != address(0)) {
            // check update withdrawal limits based on protocol supply
            anyUpdateDone_ = _updateWithdrawLimits();
        }

        if (BORROW_TOKEN != address(0)) {
            // check update borrow limits based on protocol borrow
            anyUpdateDone_ = _updateBorrowLimits() || anyUpdateDone_;
        }

        if (!anyUpdateDone_) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__NoUpdate);
        }
    }

    /***********************************|
    |            INTERNALS              | 
    |__________________________________*/

    function _updateWithdrawLimits() internal returns (bool updated_) {
        (uint256 supply_, uint256 oldExpandPercent_, uint256 userSupplyData_) = getProtocolSupplyData();

        // get current expand percent for supply_
        uint256 newExpandPercent_;
        if (supply_ < WITHDRAW_CHECKPOINT1) {
            newExpandPercent_ = WITHDRAW_EXPAND_UNTIL_CHECKPOINT1;
        } else if (supply_ < WITHDRAW_CHECKPOINT2) {
            newExpandPercent_ = WITHDRAW_EXPAND_UNTIL_CHECKPOINT2;
        } else if (supply_ < WITHDRAW_CHECKPOINT3) {
            newExpandPercent_ = WITHDRAW_EXPAND_UNTIL_CHECKPOINT3;
        } else {
            newExpandPercent_ = WITHDRAW_EXPAND_ABOVE_CHECKPOINT3;
        }

        // check if not already set to that value
        if (oldExpandPercent_ == newExpandPercent_) {
            return false;
        }

        // execute update at Liquidity
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: PROTOCOL,
            token: WITHDRAW_TOKEN,
            mode: uint8(userSupplyData_ & 1), // first bit
            expandPercent: newExpandPercent_,
            expandDuration: (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) & X24, // set same as old
            baseWithdrawalLimit: BigMathMinified.fromBigNumber(
                (userSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            ) // set same as old
        });
        LIQUIDITY.updateUserSupplyConfigs(userSupplyConfigs_);

        emit LogUpdateWithdrawLimitExpansion(supply_, oldExpandPercent_, newExpandPercent_);

        return true;
    }

    function _updateBorrowLimits() internal returns (bool updated_) {
        (uint256 borrow_, uint256 oldExpandPercent_, uint256 userBorrowData_) = getProtocolBorrowData();

        // get current expand percent for borrow_
        uint256 newExpandPercent_;
        if (borrow_ < BORROW_CHECKPOINT1) {
            newExpandPercent_ = BORROW_EXPAND_UNTIL_CHECKPOINT1;
        } else if (borrow_ < BORROW_CHECKPOINT2) {
            newExpandPercent_ = BORROW_EXPAND_UNTIL_CHECKPOINT2;
        } else if (borrow_ < BORROW_CHECKPOINT3) {
            newExpandPercent_ = BORROW_EXPAND_UNTIL_CHECKPOINT3;
        } else {
            newExpandPercent_ = BORROW_EXPAND_ABOVE_CHECKPOINT3;
        }

        // check if not already set to that value
        if (oldExpandPercent_ == newExpandPercent_) {
            return false;
        }

        // execute update at Liquidity
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: PROTOCOL,
            token: BORROW_TOKEN,
            mode: uint8(userBorrowData_ & 1), // first bit
            expandPercent: newExpandPercent_,
            expandDuration: (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24, // set same as old
            baseDebtCeiling: BigMathMinified.fromBigNumber(
                (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            ), // set same as old
            maxDebtCeiling: BigMathMinified.fromBigNumber(
                (userBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            ) // set same as old
        });
        LIQUIDITY.updateUserBorrowConfigs(userBorrowConfigs_);

        emit LogUpdateBorrowLimitExpansion(borrow_, oldExpandPercent_, newExpandPercent_);

        return true;
    }

    function _validateLimitCheckPoints(LimitCheckPoints memory checkPoints_) internal pure {
        if (
            checkPoints_.tvlCheckPoint1 == 0 ||
            checkPoints_.expandPercentUntilCheckPoint1 == 0 ||
            checkPoints_.tvlCheckPoint2 == 0 ||
            checkPoints_.expandPercentUntilCheckPoint2 == 0 ||
            checkPoints_.tvlCheckPoint3 == 0 ||
            checkPoints_.expandPercentUntilCheckPoint3 == 0 ||
            checkPoints_.expandPercentAboveCheckPoint3 == 0
        ) {
            revert FluidConfigError(ErrorTypes.ExpandPercentConfigHandler__InvalidParams);
        }
    }
}
