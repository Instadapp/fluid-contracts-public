// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { VaultOracleBase } from "../base.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title VaultT4Oracle
/// @notice Per-vault oracle for T4 vaults (smart collateral + smart debt).
///         Supports both same-pool and different-pool T4 vaults by always storing
///         separate col and debt DEX params. When supply == borrow, immutables are
///         simply duplicated (negligible extra cost: ~24 gas from 8 extra PUSHes).
contract VaultT4Oracle is VaultOracleBase {
    address internal immutable USD_ORACLE;

    // --- Collateral (supply) side DEX data ---
    address internal immutable COL_DEX_POOL;
    address internal immutable COL_TOKEN_0;
    address internal immutable COL_TOKEN_1;
    bytes32 internal immutable COL_SUPPLY_TOKEN_0_SLOT;
    bytes32 internal immutable COL_SUPPLY_TOKEN_1_SLOT;
    bytes32 internal immutable COL_EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable COL_EXCHANGE_PRICE_TOKEN_1_SLOT;
    uint256 internal immutable COL_TOKEN_0_NUM_PRECISION;
    uint256 internal immutable COL_TOKEN_0_DEN_PRECISION;
    uint256 internal immutable COL_TOKEN_1_NUM_PRECISION;
    uint256 internal immutable COL_TOKEN_1_DEN_PRECISION;

    // --- Debt (borrow) side DEX data ---
    address internal immutable DEBT_DEX_POOL;
    address internal immutable DEBT_TOKEN_0;
    address internal immutable DEBT_TOKEN_1;
    bytes32 internal immutable DEBT_BORROW_TOKEN_0_SLOT;
    bytes32 internal immutable DEBT_BORROW_TOKEN_1_SLOT;
    bytes32 internal immutable DEBT_EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable DEBT_EXCHANGE_PRICE_TOKEN_1_SLOT;
    uint256 internal immutable DEBT_TOKEN_0_NUM_PRECISION;
    uint256 internal immutable DEBT_TOKEN_0_DEN_PRECISION;
    uint256 internal immutable DEBT_TOKEN_1_NUM_PRECISION;
    uint256 internal immutable DEBT_TOKEN_1_DEN_PRECISION;

    constructor(
        address usdOracle_,
        DexParams memory colDex_,
        DexParams memory debtDex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) VaultOracleBase(supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_) {
        if (usdOracle_ == address(0) || colDex_.dexPool == address(0) || debtDex_.dexPool == address(0)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__AddressZero);
        }
        USD_ORACLE = usdOracle_;

        COL_DEX_POOL = colDex_.dexPool;
        COL_TOKEN_0 = colDex_.token0;
        COL_TOKEN_1 = colDex_.token1;
        COL_SUPPLY_TOKEN_0_SLOT = colDex_.supplyToken0Slot;
        COL_SUPPLY_TOKEN_1_SLOT = colDex_.supplyToken1Slot;
        COL_EXCHANGE_PRICE_TOKEN_0_SLOT = colDex_.exchangePriceToken0Slot;
        COL_EXCHANGE_PRICE_TOKEN_1_SLOT = colDex_.exchangePriceToken1Slot;
        COL_TOKEN_0_NUM_PRECISION = colDex_.token0NumeratorPrecision;
        COL_TOKEN_0_DEN_PRECISION = colDex_.token0DenominatorPrecision;
        COL_TOKEN_1_NUM_PRECISION = colDex_.token1NumeratorPrecision;
        COL_TOKEN_1_DEN_PRECISION = colDex_.token1DenominatorPrecision;

        DEBT_DEX_POOL = debtDex_.dexPool;
        DEBT_TOKEN_0 = debtDex_.token0;
        DEBT_TOKEN_1 = debtDex_.token1;
        DEBT_BORROW_TOKEN_0_SLOT = debtDex_.borrowToken0Slot;
        DEBT_BORROW_TOKEN_1_SLOT = debtDex_.borrowToken1Slot;
        DEBT_EXCHANGE_PRICE_TOKEN_0_SLOT = debtDex_.exchangePriceToken0Slot;
        DEBT_EXCHANGE_PRICE_TOKEN_1_SLOT = debtDex_.exchangePriceToken1Slot;
        DEBT_TOKEN_0_NUM_PRECISION = debtDex_.token0NumeratorPrecision;
        DEBT_TOKEN_0_DEN_PRECISION = debtDex_.token0DenominatorPrecision;
        DEBT_TOKEN_1_NUM_PRECISION = debtDex_.token1NumeratorPrecision;
        DEBT_TOKEN_1_DEN_PRECISION = debtDex_.token1DenominatorPrecision;
    }

    function _getExchangeRate(bool isOperate_, bool isRaw_) internal view override returns (uint256 exchangeRate_) {
        uint256 pegBufferPpm_ = _dexSharePegBufferPpm(isOperate_);
        (uint256 colPrice_, uint256 colDec_) = _resolveColShare(
            USD_ORACLE,
            SUPPLY_E_MODE,
            isOperate_,
            _colDexParams(),
            pegBufferPpm_,
            isRaw_
        );
        (uint256 debtPrice_, uint256 debtDec_) = _resolveDebtShare(
            USD_ORACLE,
            BORROW_E_MODE,
            isOperate_,
            _debtDexParams(),
            pegBufferPpm_,
            isRaw_
        );
        return _computeExchangeRate(colPrice_, colDec_, debtPrice_, debtDec_);
    }

    function _colDexParams() private view returns (DexParams memory) {
        return
            DexParams({
                dexPool: COL_DEX_POOL,
                token0: COL_TOKEN_0,
                token1: COL_TOKEN_1,
                supplyToken0Slot: COL_SUPPLY_TOKEN_0_SLOT,
                supplyToken1Slot: COL_SUPPLY_TOKEN_1_SLOT,
                borrowToken0Slot: bytes32(0),
                borrowToken1Slot: bytes32(0),
                exchangePriceToken0Slot: COL_EXCHANGE_PRICE_TOKEN_0_SLOT,
                exchangePriceToken1Slot: COL_EXCHANGE_PRICE_TOKEN_1_SLOT,
                token0NumeratorPrecision: COL_TOKEN_0_NUM_PRECISION,
                token0DenominatorPrecision: COL_TOKEN_0_DEN_PRECISION,
                token1NumeratorPrecision: COL_TOKEN_1_NUM_PRECISION,
                token1DenominatorPrecision: COL_TOKEN_1_DEN_PRECISION
            });
    }

    function _debtDexParams() private view returns (DexParams memory) {
        return
            DexParams({
                dexPool: DEBT_DEX_POOL,
                token0: DEBT_TOKEN_0,
                token1: DEBT_TOKEN_1,
                supplyToken0Slot: bytes32(0),
                supplyToken1Slot: bytes32(0),
                borrowToken0Slot: DEBT_BORROW_TOKEN_0_SLOT,
                borrowToken1Slot: DEBT_BORROW_TOKEN_1_SLOT,
                exchangePriceToken0Slot: DEBT_EXCHANGE_PRICE_TOKEN_0_SLOT,
                exchangePriceToken1Slot: DEBT_EXCHANGE_PRICE_TOKEN_1_SLOT,
                token0NumeratorPrecision: DEBT_TOKEN_0_NUM_PRECISION,
                token0DenominatorPrecision: DEBT_TOKEN_0_DEN_PRECISION,
                token1NumeratorPrecision: DEBT_TOKEN_1_NUM_PRECISION,
                token1DenominatorPrecision: DEBT_TOKEN_1_DEN_PRECISION
            });
    }

    function _collateralName() internal view override returns (string memory) {
        return _dexPairName(COL_TOKEN_0, COL_TOKEN_1);
    }

    function _debtName() internal view override returns (string memory) {
        return _dexPairName(DEBT_TOKEN_0, DEBT_TOKEN_1);
    }

    function _collateralDecimals() internal pure override returns (uint256) {
        return DEX_SHARE_DECIMALS;
    }

    function _debtDecimals() internal pure override returns (uint256) {
        return DEX_SHARE_DECIMALS;
    }

    function _oracleConfigAddresses()
        internal
        view
        override
        returns (
            address usdOracle_,
            address supplyToken0_,
            address supplyToken1_,
            address borrowToken0_,
            address borrowToken1_,
            address supplyDexPool_,
            address borrowDexPool_
        )
    {
        return (USD_ORACLE, COL_TOKEN_0, COL_TOKEN_1, DEBT_TOKEN_0, DEBT_TOKEN_1, COL_DEX_POOL, DEBT_DEX_POOL);
    }
}
