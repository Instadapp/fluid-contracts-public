// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { VaultOracleBase } from "../base.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title VaultT2Oracle
/// @notice Per-vault oracle for T2 vaults (smart collateral via DEX LP shares + normal debt).
///         All DEX data and borrow token are cached as immutables.
contract VaultT2Oracle is VaultOracleBase {
    address internal immutable USD_ORACLE;
    address internal immutable BORROW_TOKEN;

    address internal immutable DEX_POOL;
    address internal immutable TOKEN_0;
    address internal immutable TOKEN_1;
    bytes32 internal immutable SUPPLY_TOKEN_0_SLOT;
    bytes32 internal immutable SUPPLY_TOKEN_1_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_0_SLOT;
    bytes32 internal immutable EXCHANGE_PRICE_TOKEN_1_SLOT;
    uint256 internal immutable TOKEN_0_NUM_PRECISION;
    uint256 internal immutable TOKEN_0_DEN_PRECISION;
    uint256 internal immutable TOKEN_1_NUM_PRECISION;
    uint256 internal immutable TOKEN_1_DEN_PRECISION;

    constructor(
        address usdOracle_,
        address borrowToken_,
        DexParams memory dex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) VaultOracleBase(supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_) {
        if (usdOracle_ == address(0) || borrowToken_ == address(0) || dex_.dexPool == address(0)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__AddressZero);
        }
        USD_ORACLE = usdOracle_;
        BORROW_TOKEN = borrowToken_;

        DEX_POOL = dex_.dexPool;
        TOKEN_0 = dex_.token0;
        TOKEN_1 = dex_.token1;
        SUPPLY_TOKEN_0_SLOT = dex_.supplyToken0Slot;
        SUPPLY_TOKEN_1_SLOT = dex_.supplyToken1Slot;
        EXCHANGE_PRICE_TOKEN_0_SLOT = dex_.exchangePriceToken0Slot;
        EXCHANGE_PRICE_TOKEN_1_SLOT = dex_.exchangePriceToken1Slot;
        TOKEN_0_NUM_PRECISION = dex_.token0NumeratorPrecision;
        TOKEN_0_DEN_PRECISION = dex_.token0DenominatorPrecision;
        TOKEN_1_NUM_PRECISION = dex_.token1NumeratorPrecision;
        TOKEN_1_DEN_PRECISION = dex_.token1DenominatorPrecision;
    }

    function _getExchangeRate(bool isOperate_, bool isRaw_) internal view override returns (uint256 exchangeRate_) {
        (uint256 colPrice_, uint256 colDec_) = _resolveColShare(
            USD_ORACLE,
            SUPPLY_E_MODE,
            isOperate_,
            _colDexParams(),
            _dexSharePegBufferPpm(isOperate_),
            isRaw_
        );
        (uint256 debtPrice_, uint256 debtDec_) = _resolveNormal(USD_ORACLE, BORROW_TOKEN, isOperate_, false, isRaw_);
        return _computeExchangeRate(colPrice_, colDec_, debtPrice_, debtDec_);
    }

    function _colDexParams() private view returns (DexParams memory) {
        return
            DexParams({
                dexPool: DEX_POOL,
                token0: TOKEN_0,
                token1: TOKEN_1,
                supplyToken0Slot: SUPPLY_TOKEN_0_SLOT,
                supplyToken1Slot: SUPPLY_TOKEN_1_SLOT,
                borrowToken0Slot: bytes32(0),
                borrowToken1Slot: bytes32(0),
                exchangePriceToken0Slot: EXCHANGE_PRICE_TOKEN_0_SLOT,
                exchangePriceToken1Slot: EXCHANGE_PRICE_TOKEN_1_SLOT,
                token0NumeratorPrecision: TOKEN_0_NUM_PRECISION,
                token0DenominatorPrecision: TOKEN_0_DEN_PRECISION,
                token1NumeratorPrecision: TOKEN_1_NUM_PRECISION,
                token1DenominatorPrecision: TOKEN_1_DEN_PRECISION
            });
    }

    function _collateralName() internal view override returns (string memory) {
        return _dexPairName(TOKEN_0, TOKEN_1);
    }

    function _debtName() internal view override returns (string memory) {
        return _tokenSymbol(BORROW_TOKEN);
    }

    function _collateralDecimals() internal pure override returns (uint256) {
        return DEX_SHARE_DECIMALS;
    }

    function _debtDecimals() internal view override returns (uint256) {
        return _tokenDecimals(BORROW_TOKEN);
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
        return (USD_ORACLE, TOKEN_0, TOKEN_1, BORROW_TOKEN, address(0), DEX_POOL, address(0));
    }
}
