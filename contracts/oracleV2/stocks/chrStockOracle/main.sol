// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidOracle } from "../../common/fluidOracle.sol";
import { IFluidOracle } from "../../interfaces/iFluidOracle.sol";
import { IFluidOracleWithDebt } from "../../interfaces/iFluidOracleWithDebt.sol";
import { IFluidOracleWrite } from "../../interfaces/iFluidOracleWrite.sol";
import { IFluidCHRStockOracle } from "../interfaces/iFluidCHRStockOracle.sol";
import { IRealityToken } from "../interfaces/external/IRealityToken.sol";
import { IRealityTokenTrade } from "../interfaces/external/IRealityTokenTrade.sol";
import { IFluidUsEquityMarketHours } from "../interfaces/iFluidUsEquityMarketHours.sol";
import { IFluidAuthGateLiquidity } from "../../../config/authGate/interfaces/iAuthGate.sol";
import { Helpers } from "./helpers.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @dev Pause, latch and anchor admin surface (SPEC §7, §8).
abstract contract FluidCHRStockOracleAdmin is IFluidCHRStockOracle, Helpers {
    /// @notice AuthGate MID.
    function pause() external {
        AUTH_GATE.requireAuthLevelMid(msg.sender);

        if (_paused != 0) return;
        _paused = 1;
        emit LogPause(msg.sender);
    }

    /// @notice AuthGate MID. Reverts `LatchCauseActive` while a latch cause holds, and if a cause cannot be read.
    function unpause() external {
        AUTH_GATE.requireAuthLevelMid(msg.sender);

        if (_paused == 0) return;
        if (_causes() != 0) revert FluidStockOracleError(ErrorTypes.CHRStockOracle__LatchCauseActive);

        _paused = 0;
        emit LogUnpause(msg.sender);
    }

    /// @notice Permissionless: pauses while the issuer has halted the rtoken or changed its multiplier.
    function latchPause() external returns (uint256 causes_) {
        // a reverting read is not a cause
        try REALITY_TOKEN_TRADE.tradePaused(address(RTOKEN)) returns (bool tradePaused_) {
            if (tradePaused_) causes_ |= CAUSE_TRADE_PAUSED;
        } catch {}

        try RTOKEN.paused() returns (bool rtokenPaused_) {
            if (rtokenPaused_) causes_ |= CAUSE_RTOKEN_PAUSED;
        } catch {}

        try RTOKEN.uiMultiplier() returns (uint256 multiplier_) {
            if (multiplier_ != _acceptedMultiplier) causes_ |= CAUSE_MULTIPLIER_CHANGED;
        } catch {}

        if (causes_ != 0 && _paused == 0) {
            _paused = 1;
            emit LogPauseLatched(causes_);
        }
    }

    /// @notice AuthGate HIGH: accepts the live price and multiplier as the new anchor; no continuity check.
    function setAnchor(uint256 expectedMultiplier_) external {
        AUTH_GATE.requireAuthLevelHigh(msg.sender);

        _revertIfRealityFlag();

        if (
            expectedMultiplier_ == 0 ||
            expectedMultiplier_ > type(uint104).max ||
            RTOKEN.uiMultiplier() != expectedMultiplier_
        ) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__InvalidParams);
        }

        (bool valid_, uint256 age_, uint256 liveValue_) = _readLive(expectedMultiplier_);
        if (!valid_ || liveValue_ > type(uint128).max) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__InvalidPrice);
        }

        // a valid print has age_ <= block.timestamp
        unchecked {
            if (block.timestamp - age_ > MAX_OPERATE_AGE) {
                revert FluidStockOracleError(ErrorTypes.CHRStockOracle__StalePrice);
            }
        }

        emit LogSetAnchor(_anchorValue, liveValue_, _acceptedMultiplier, expectedMultiplier_);

        _anchorValue = uint128(liveValue_);
        _anchorTime = uint32(age_);
        _acceptedMultiplier = uint104(expectedMultiplier_);
        _clearHint();
    }
}

/// @title FluidCHRStockOracle
/// @notice Chronicle equity price × Reality rtoken `uiMultiplier` (1e27), guarded by a stored regular-session anchor
///         (cap: operate reverts, liquidate clamps; break: every guarded read reverts), a multiplier freeze, Reality's
///         halt flags, a latchable pause and the L2 sequencer gate. See SPEC.md.
contract FluidCHRStockOracle is FluidOracle, FluidCHRStockOracleAdmin {
    constructor(CHRStockOracleConstructorParams memory p_) FluidOracle(p_.infoName, p_.targetDecimals) Helpers(p_) {
        if (
            p_.chronicle.code.length == 0 ||
            p_.rtoken.code.length == 0 ||
            p_.realityTokenTrade.code.length == 0 ||
            p_.marketHours.code.length == 0 ||
            p_.authGate.code.length == 0 ||
            IFluidAuthGateLiquidity(p_.authGate).LIQUIDITY() == address(0) ||
            p_.maxCapPercent == 0 ||
            p_.maxCapPercent >= p_.maxBreakPercent ||
            p_.maxBreakPercent >= FOUR_DECIMALS ||
            p_.maxOperateAge == 0 ||
            p_.maxOperateAge > p_.maxLiquidateAge ||
            p_.maxLiquidateAge > MAX_PRICE_AGE
        ) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__InvalidParams);
        }

        uint256 multiplier_ = IRealityToken(p_.rtoken).uiMultiplier();
        if (multiplier_ == 0 || multiplier_ > type(uint104).max) {
            revert FluidStockOracleError(ErrorTypes.CHRStockOracle__InvalidParams);
        }

        // probes: a dependency that cannot answer reverts the deploy
        IRealityTokenTrade(p_.realityTokenTrade).tradePaused(p_.rtoken);
        IFluidUsEquityMarketHours(p_.marketHours).getSessionInfo(block.timestamp);

        _acceptedMultiplier = uint104(multiplier_);
    }

    /// @inheritdoc IFluidOracle
    /// @dev `getExchangeRateRaw()` behind the guarded-read hook (the L2 sequencer gate in `mainL2.sol`).
    function getExchangeRate() external view returns (uint256) {
        _beforeGuardedPriceRead();
        return getExchangeRateRaw();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, , ) = _getPrice(true, false);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, , ) = _getPrice(false, false);
    }

    /// @inheritdoc IFluidOracleWithDebt
    function getExchangeRateOperateDebt() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, , ) = _getPrice(true, true);
    }

    /// @inheritdoc IFluidOracleWithDebt
    function getExchangeRateLiquidateDebt() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, , ) = _getPrice(false, true);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateOperateWrite() external returns (uint256) {
        return _getPriceWrite(true, false);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateLiquidateWrite() external returns (uint256) {
        return _getPriceWrite(false, false);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateOperateDebtWrite() external returns (uint256) {
        return _getPriceWrite(true, true);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateLiquidateDebtWrite() external returns (uint256) {
        return _getPriceWrite(false, true);
    }

    /// @inheritdoc IFluidOracle
    /// @dev No checks; collateral capped up at the cap like CLX's directional raw.
    function getExchangeRateOperateRaw() external view returns (uint256) {
        return _getRawValue(true, false);
    }

    /// @inheritdoc IFluidOracle
    /// @dev No checks; collateral floored at the cap like CLX's directional raw.
    function getExchangeRateLiquidateRaw() external view returns (uint256) {
        return _getRawValue(false, true);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateRaw() public view returns (uint256) {
        return _getRawValue(false, false);
    }

    /// @inheritdoc IFluidCHRStockOracle
    function updateRegularHoursAnchor() external returns (bool stored_) {
        _beforeGuardedPriceRead();

        stored_ = _sealIfSealable();

        // recording a hint needs the same conditions a guarded read checks (SPEC §7)
        if (_paused != 0 || _causes() != 0) return stored_;

        (bool valid_, uint256 age_, uint256 liveValue_) = _readLive(_acceptedMultiplier);
        if (!valid_) return stored_;

        if (_isAnchorArmed(_anchorTime) && _isBeyondBreak(_anchorValue, liveValue_)) return stored_;

        if (_recordHint(liveValue_, age_)) stored_ = true;
    }

    /// @inheritdoc IFluidCHRStockOracle
    function getConfig() external view returns (CHRStockOracleConfig memory config_) {
        config_ = CHRStockOracleConfig({
            chronicle: address(CHRONICLE),
            rtoken: address(RTOKEN),
            realityTokenTrade: address(REALITY_TOKEN_TRADE),
            marketHours: address(MARKET_HOURS),
            authGate: address(AUTH_GATE),
            maxCapPercent: MAX_CAP_PERCENT,
            maxBreakPercent: MAX_BREAK_PERCENT,
            maxOperateAge: MAX_OPERATE_AGE,
            maxLiquidateAge: MAX_LIQUIDATE_AGE,
            acceptedMultiplier: _acceptedMultiplier,
            paused: _paused != 0,
            anchorValue: _anchorValue,
            anchorTime: _anchorTime,
            hintValue: _hintValue,
            hintAge: _hintAge,
            hintRegularEnd: _hintRegularEnd
        });
    }
}
