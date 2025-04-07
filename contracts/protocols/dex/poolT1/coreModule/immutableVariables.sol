// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../../../liquidity/interfaces/iLiquidity.sol";
import { Structs } from "./structs.sol";
import { ConstantVariables } from "../common/constantVariables.sol";
import { IFluidDexFactory } from "../../interfaces/iDexFactory.sol";
import { Error } from "../../error.sol";
import { ErrorTypes } from "../../errorTypes.sol";

abstract contract ImmutableVariables is ConstantVariables, Structs, Error {
    /*//////////////////////////////////////////////////////////////
                          CONSTANTS / IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public immutable DEX_ID;

    /// @dev Address of token 0
    address internal immutable TOKEN_0;

    /// @dev Address of token 1
    address internal immutable TOKEN_1;

    address internal immutable THIS_CONTRACT;

    uint256 internal immutable TOKEN_0_NUMERATOR_PRECISION;
    uint256 internal immutable TOKEN_0_DENOMINATOR_PRECISION;
    uint256 internal immutable TOKEN_1_NUMERATOR_PRECISION;
    uint256 internal immutable TOKEN_1_DENOMINATOR_PRECISION;

    /// @dev Address of liquidity contract
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @dev Address of DEX factory contract
    IFluidDexFactory internal immutable DEX_FACTORY;

    /// @dev Address of Shift implementation
    address internal immutable SHIFT_IMPLEMENTATION;

    /// @dev Address of Admin implementation
    address internal immutable ADMIN_IMPLEMENTATION;

    /// @dev Address of Col Operations implementation
    address internal immutable COL_OPERATIONS_IMPLEMENTATION;

    /// @dev Address of Debt Operations implementation
    address internal immutable DEBT_OPERATIONS_IMPLEMENTATION;

    /// @dev Address of Perfect Operations and Swap Out implementation
    address internal immutable PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION;

    /// @dev Address of contract used for deploying center price & hook related contract
    address internal immutable DEPLOYER_CONTRACT;

    /// @dev Liquidity layer slots
    bytes32 internal immutable SUPPLY_TOKEN_0_SLOT;
    bytes32 internal immutable BORROW_TOKEN_0_SLOT;
    bytes32 internal immutable SUPPLY_TOKEN_1_SLOT;
    bytes32 internal immutable BORROW_TOKEN_1_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_1_SLOT;
    uint256 internal immutable TOTAL_ORACLE_MAPPING;

    function _calcNumeratorAndDenominator(
        address token_
    ) private view returns (uint256 numerator_, uint256 denominator_) {
        uint256 decimals_ = _decimals(token_);
        if (decimals_ > TOKENS_DECIMALS_PRECISION) {
            numerator_ = 1;
            denominator_ = 10 ** (decimals_ - TOKENS_DECIMALS_PRECISION);
        } else {
            numerator_ = 10 ** (TOKENS_DECIMALS_PRECISION - decimals_);
            denominator_ = 1;
        }
    }

    constructor(ConstantViews memory constants_) {
        THIS_CONTRACT = address(this);

        DEX_ID = constants_.dexId;
        LIQUIDITY = IFluidLiquidity(constants_.liquidity);
        DEX_FACTORY = IFluidDexFactory(constants_.factory);

        TOKEN_0 = constants_.token0;
        TOKEN_1 = constants_.token1;

        if (TOKEN_0 >= TOKEN_1) revert FluidDexError(ErrorTypes.DexT1__Token0ShouldBeSmallerThanToken1);

        (TOKEN_0_NUMERATOR_PRECISION, TOKEN_0_DENOMINATOR_PRECISION) = _calcNumeratorAndDenominator(TOKEN_0);
        (TOKEN_1_NUMERATOR_PRECISION, TOKEN_1_DENOMINATOR_PRECISION) = _calcNumeratorAndDenominator(TOKEN_1);

        if (constants_.implementations.shift != address(0)) {
            SHIFT_IMPLEMENTATION = constants_.implementations.shift;
        } else {
            SHIFT_IMPLEMENTATION = address(this);
        }
        if (constants_.implementations.admin != address(0)) {
            ADMIN_IMPLEMENTATION = constants_.implementations.admin;
        } else {
            ADMIN_IMPLEMENTATION = address(this);
        }
        if (constants_.implementations.colOperations != address(0)) {
            COL_OPERATIONS_IMPLEMENTATION = constants_.implementations.colOperations;
        } else {
            COL_OPERATIONS_IMPLEMENTATION = address(this);
        }
        if (constants_.implementations.debtOperations != address(0)) {
            DEBT_OPERATIONS_IMPLEMENTATION = constants_.implementations.debtOperations;
        } else {
            DEBT_OPERATIONS_IMPLEMENTATION = address(this);
        }
        if (constants_.implementations.perfectOperationsAndSwapOut != address(0)) {
            PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION = constants_.implementations.perfectOperationsAndSwapOut;
        } else {
            PERFECT_OPERATIONS_AND_SWAP_OUT_IMPLEMENTATION = address(this);
        }

        DEPLOYER_CONTRACT = constants_.deployerContract;

        SUPPLY_TOKEN_0_SLOT = constants_.supplyToken0Slot;
        BORROW_TOKEN_0_SLOT = constants_.borrowToken0Slot;
        SUPPLY_TOKEN_1_SLOT = constants_.supplyToken1Slot;
        BORROW_TOKEN_1_SLOT = constants_.borrowToken1Slot;
        EXCHANGE_PRICE_TOKEN_0_SLOT = constants_.exchangePriceToken0Slot;
        EXCHANGE_PRICE_TOKEN_1_SLOT = constants_.exchangePriceToken1Slot;

        if (constants_.oracleMapping > X16) revert FluidDexError(ErrorTypes.DexT1__OracleMappingOverflow);

        TOTAL_ORACLE_MAPPING = constants_.oracleMapping;
    }
}
