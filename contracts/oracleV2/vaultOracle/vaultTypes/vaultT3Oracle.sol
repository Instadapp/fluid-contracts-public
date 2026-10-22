// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { VaultOracleBase } from "../base.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title VaultT3Oracle
/// @notice Per-vault oracle for T3 vaults (normal collateral + smart debt via DEX LP shares).
///         All DEX data and supply token are cached as immutables.
contract VaultT3Oracle is VaultOracleBase {
    address internal immutable USD_ORACLE;
    address internal immutable SUPPLY_TOKEN;

    address internal immutable DEX_POOL;
    address internal immutable TOKEN_0;
    address internal immutable TOKEN_1;
    bytes32 internal immutable BORROW_TOKEN_0_SLOT;
    bytes32 internal immutable BORROW_TOKEN_1_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_1_SLOT;
    uint256 internal immutable TOKEN_0_NUM_PRECISION;
    uint256 internal immutable TOKEN_0_DEN_PRECISION;
    uint256 internal immutable TOKEN_1_NUM_PRECISION;
    uint256 internal immutable TOKEN_1_DEN_PRECISION;

    constructor(
        address usdOracle_,
        address supplyToken_,
        DexParams memory dex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) VaultOracleBase(supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_) {
        if (usdOracle_ == address(0) || supplyToken_ == address(0) || dex_.dexPool == address(0)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__AddressZero);
        }
        USD_ORACLE = usdOracle_;
        SUPPLY_TOKEN = supplyToken_;

        DEX_POOL = dex_.dexPool;
        TOKEN_0 = dex_.token0;
        TOKEN_1 = dex_.token1;
        BORROW_TOKEN_0_SLOT = dex_.borrowToken0Slot;
        BORROW_TOKEN_1_SLOT = dex_.borrowToken1Slot;
        EXCHANGE_PRICE_TOKEN_0_SLOT = dex_.exchangePriceToken0Slot;
        EXCHANGE_PRICE_TOKEN_1_SLOT = dex_.exchangePriceToken1Slot;
        TOKEN_0_NUM_PRECISION = dex_.token0NumeratorPrecision;
        TOKEN_0_DEN_PRECISION = dex_.token0DenominatorPrecision;
        TOKEN_1_NUM_PRECISION = dex_.token1NumeratorPrecision;
        TOKEN_1_DEN_PRECISION = dex_.token1DenominatorPrecision;
    }

    function _getExchangeRate(bool isOperate_, bool isRaw_) internal view override returns (uint256 exchangeRate_) {
        (uint256 colPrice_, uint256 colDec_) = _resolveNormal(USD_ORACLE, SUPPLY_TOKEN, isOperate_, true, isRaw_);
        (uint256 debtPrice_, uint256 debtDec_) = _resolveDebtShare(
            USD_ORACLE,
            BORROW_E_MODE,
            isOperate_,
            _debtDexParams(),
            _dexSharePegBufferPpm(isOperate_),
            isRaw_
        );
        return _computeExchangeRate(colPrice_, colDec_, debtPrice_, debtDec_);
    }

    function _debtDexParams() private view returns (DexParams memory) {
        return
            DexParams({
                dexPool: DEX_POOL,
                token0: TOKEN_0,
                token1: TOKEN_1,
                supplyToken0Slot: bytes32(0),
                supplyToken1Slot: bytes32(0),
                borrowToken0Slot: BORROW_TOKEN_0_SLOT,
                borrowToken1Slot: BORROW_TOKEN_1_SLOT,
                exchangePriceToken0Slot: EXCHANGE_PRICE_TOKEN_0_SLOT,
                exchangePriceToken1Slot: EXCHANGE_PRICE_TOKEN_1_SLOT,
                token0NumeratorPrecision: TOKEN_0_NUM_PRECISION,
                token0DenominatorPrecision: TOKEN_0_DEN_PRECISION,
                token1NumeratorPrecision: TOKEN_1_NUM_PRECISION,
                token1DenominatorPrecision: TOKEN_1_DEN_PRECISION
            });
    }

    function _collateralName() internal view override returns (string memory) {
        return _tokenSymbol(SUPPLY_TOKEN);
    }

    function _debtName() internal view override returns (string memory) {
        return _dexPairName(TOKEN_0, TOKEN_1);
    }

    function _collateralDecimals() internal view override returns (uint256) {
        return _tokenDecimals(SUPPLY_TOKEN);
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
        return (USD_ORACLE, SUPPLY_TOKEN, address(0), TOKEN_0, TOKEN_1, address(0), DEX_POOL);
    }
}
