// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { VaultOracleBase } from "../base.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @title VaultT1Oracle
/// @notice Per-vault oracle for T1 vaults (normal collateral + normal debt).
///         Supply and borrow token addresses are cached as immutables for maximum runtime gas efficiency.
/// @dev Peg buffers are passed as `0` because T1 has no DEX share leg to adjust.
contract VaultT1Oracle is VaultOracleBase {
    address internal immutable USD_ORACLE;
    address internal immutable SUPPLY_TOKEN;
    address internal immutable BORROW_TOKEN;

    constructor(
        address usdOracle_,
        address supplyToken_,
        address borrowToken_,
        uint256 supplyEMode_,
        uint256 borrowEMode_
    ) VaultOracleBase(supplyEMode_, borrowEMode_, 0, 0) {
        if (usdOracle_ == address(0) || supplyToken_ == address(0) || borrowToken_ == address(0)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracle__AddressZero);
        }
        USD_ORACLE = usdOracle_;
        SUPPLY_TOKEN = supplyToken_;
        BORROW_TOKEN = borrowToken_;
    }

    /// @notice Non-view operate rate (`IFluidOracleWrite`); may persist source state.
    function getExchangeRateOperateWrite() external returns (uint256 exchangeRate_) {
        return _getExchangeRateWrite(true);
    }

    /// @notice Non-view liquidate rate (`IFluidOracleWrite`); may persist source state.
    function getExchangeRateLiquidateWrite() external returns (uint256 exchangeRate_) {
        return _getExchangeRateWrite(false);
    }

    function _getExchangeRate(bool isOperate_, bool isRaw_) internal view override returns (uint256 exchangeRate_) {
        (uint256 colPrice_, uint256 colDec_) = _resolveNormal(USD_ORACLE, SUPPLY_TOKEN, isOperate_, true, isRaw_);
        (uint256 debtPrice_, uint256 debtDec_) = _resolveNormal(USD_ORACLE, BORROW_TOKEN, isOperate_, false, isRaw_);
        return _computeExchangeRate(colPrice_, colDec_, debtPrice_, debtDec_);
    }

    function _getExchangeRateWrite(bool isOperate_) internal returns (uint256 exchangeRate_) {
        (uint256 colPrice_, uint256 colDec_) = _resolveNormalWrite(USD_ORACLE, SUPPLY_TOKEN, isOperate_, true);
        (uint256 debtPrice_, uint256 debtDec_) = _resolveNormalWrite(USD_ORACLE, BORROW_TOKEN, isOperate_, false);
        return _computeExchangeRate(colPrice_, colDec_, debtPrice_, debtDec_);
    }

    function _collateralName() internal view override returns (string memory) {
        return _tokenSymbol(SUPPLY_TOKEN);
    }

    function _debtName() internal view override returns (string memory) {
        return _tokenSymbol(BORROW_TOKEN);
    }

    function _collateralDecimals() internal view override returns (uint256) {
        return _tokenDecimals(SUPPLY_TOKEN);
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
        return (USD_ORACLE, SUPPLY_TOKEN, address(0), BORROW_TOKEN, address(0), address(0), address(0));
    }
}
