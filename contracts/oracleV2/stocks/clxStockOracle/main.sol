// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidOracle } from "../../common/fluidOracle.sol";
import { IFluidOracle } from "../../interfaces/iFluidOracle.sol";
import { IFluidOracleWrite } from "../../interfaces/iFluidOracleWrite.sol";
import { IFluidCLXStockOracle } from "../interfaces/iFluidCLXStockOracle.sol";
import { IBackedWrapper } from "../interfaces/external/IBackedWrapper.sol";
import { IBackedAutoFeeToken } from "../interfaces/external/IBackedAutoFeeToken.sol";
import { BasicAuth } from "../../../libraries/access/basicAuth.sol";
import { Helpers } from "./helpers.sol";
import { Structs } from "./structs.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { DeviationHelpers } from "../../../libraries/utils/deviationHelpers.sol";

/// @dev Governance / auth-class admin surface (`BasicAuth`).
abstract contract FluidCLXStockOracleAdmin is Helpers, BasicAuth {
    function _authClass(address auth_) internal view override returns (uint256) {
        return _auths[auth_];
    }

    function _setAuthClass(address auth_, uint256 authClass_) internal override {
        if (authClass_ > AUTH_CLASS_CONFIRM_MULTIPLIER) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }
        _auths[auth_] = authClass_;
    }

    /// @notice Set `acceptedMultiplier` to live after a jump. Live must be within absolute
    ///         `MAX_MULTIPLIER_CHANGE_PERCENT` of `expectedMultiplier_` (1e18 scale). Confirm only once
    ///         `CL_live × new ≈ CL_anchor × old` holds: the gap guard scales both sides by the live
    ///         multiplier, so it cannot catch a confirm issued before CL has repriced. If CL gapped too
    ///         (split), follow with an out-of-band `updateRegularHoursAnchor` to clear the price-gap guard.
    /// @dev Governance or auth class ≥ 3 (e.g. team set as class 3 via `updateAuth`).
    function confirmMultiplierChange(
        uint256 expectedMultiplier_
    ) external onlyAuthClassAbove(AUTH_CLASS_CONFIRM_MULTIPLIER) {
        (uint256 live_, , ) = IBackedAutoFeeToken(BACKED_UNDERLYING).getCurrentMultiplier();
        if (live_ == 0 || live_ > type(uint104).max || expectedMultiplier_ == 0) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }

        if (
            DeviationHelpers.isOutsideDeviation(
                expectedMultiplier_,
                live_,
                MAX_MULTIPLIER_CHANGE_PERCENT,
                FOUR_DECIMALS
            )
        ) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }

        _syncAcceptedMultiplier(live_);
    }

    /// @notice Pause pricing. Governance or auth class ≥ 1.
    function pause() external onlyAuthClassAbove(AUTH_CLASS_PAUSE) {
        if (_paused != 0) return;
        _paused = 1;
        emit LogPause();
    }

    /// @notice Unpause pricing. Governance or auth class ≥ 2.
    function unpause() external onlyAuthClassAbove(AUTH_CLASS_PAUSE_UNPAUSE) {
        if (_paused == 0) return;
        _paused = 0;
        emit LogUnpause();
    }
}

/// @title FluidCLXStockOracle
/// @notice CL 24/5 × Backed multiplier: session staleness, extended-hours caps, split guards, pause.
/// @dev Split/desync protections and how each freeze clears (details: SPEC §6):
///      band (live multiplier vs accepted, accrued) → gov/class-3 `confirmMultiplierChange`;
///      scheduled (pending multiplier ≤ 24h out, outside band) → Backed override, or activation hands to band;
///      price gap (live vs stored anchor round, strict −down%/+up%) → self-heals on transient prints,
///      else gov/class-3 out-of-band `updateRegularHoursAnchor` or 5d reference age-out (fail-open).
///      RTH round warmed by Write / `updateRegularHoursAnchor`. Policy + state via `getConfig()`.
contract FluidCLXStockOracle is FluidOracle, FluidCLXStockOracleAdmin, IFluidCLXStockOracle, IFluidOracleWrite {
    constructor(CLXStockOracleConstructorParams memory p_) FluidOracle(p_.infoName, p_.targetDecimals) Helpers(p_) {
        // `maxMultiplierChangePercent == 0` is intentional freeze: band rejects any drift, but
        // live == accepted stays priced (does not revert). Team can still `confirmMultiplierChange(live)`.
        if (
            p_.liquidity == address(0) ||
            p_.chainlinkFeed == address(0) ||
            BACKED_UNDERLYING == address(0) ||
            p_.marketHours == address(0) ||
            p_.rateMultiplier == 0 ||
            p_.rateMultiplier > MAX_RATE_MULTIPLIER ||
            p_.maxMultiplierChangePercent > MAX_ALLOWED_MULTIPLIER_CHANGE_PERCENT ||
            p_.maxExtendedHoursCapPercent == 0 ||
            p_.maxExtendedHoursCapPercent > SIX_DECIMALS ||
            p_.maxPriceGapDownPercent == 0 ||
            p_.maxPriceGapDownPercent >= FOUR_DECIMALS ||
            p_.maxPriceGapUpPercent == 0
        ) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }

        (uint256 price_, uint256 multiplier_, , ) = _readLatestPrice(false);
        if (price_ == 0 || multiplier_ == 0 || multiplier_ > type(uint104).max) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }

        // wrapper must be a pure multiplier passthrough; rejects v1
        if (IBackedWrapper(BACKED_WRAPPER).convertToAssets(MULTIPLIER_PRECISION) != multiplier_) {
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__InvalidParams);
        }
        _revertIfScheduledMultiplierOutsideBand(multiplier_);

        _acceptedMultiplier = uint104(multiplier_);
        _lastMultiplierUpdateTime = uint32(block.timestamp);
    }

    /// @inheritdoc IFluidCLXStockOracle
    function backedUnderlying() external view returns (address) {
        return BACKED_UNDERLYING;
    }

    /// @inheritdoc IFluidCLXStockOracle
    function getConfig() public view returns (CLXStockOracleConfig memory config_) {
        return
            CLXStockOracleConfig({
                chainlinkFeed: CHAINLINK_FEED,
                backedWrapper: BACKED_WRAPPER,
                marketHours: address(MARKET_HOURS),
                rateMultiplier: RATE_MULTIPLIER,
                maxMultiplierChangePercent: MAX_MULTIPLIER_CHANGE_PERCENT,
                maxExtendedHoursCapPercent: MAX_EXTENDED_HOURS_CAP_PERCENT,
                maxPriceGapDownPercent: MAX_PRICE_GAP_DOWN_PERCENT,
                maxPriceGapUpPercent: MAX_PRICE_GAP_UP_PERCENT,
                acceptedMultiplier: _acceptedMultiplier,
                lastMultiplierUpdateTime: _lastMultiplierUpdateTime,
                lastRegularHoursRoundId: _lastRegularHoursRoundId,
                lastVerifiedRegularHoursEnd: _lastVerifiedRegularHoursEnd,
                paused: _paused != 0
            });
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() external view returns (uint256) {
        return getExchangeRateOperate();
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() public view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(true, false, false);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() public view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(false, false, false);
    }

    /// @inheritdoc IFluidCLXStockOracle
    function getExchangeRateOperateDebt() public view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(true, true, false);
    }

    /// @inheritdoc IFluidCLXStockOracle
    function getExchangeRateLiquidateDebt() public view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(false, true, false);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateOperateWrite() public returns (uint256) {
        return _getPriceWrite(true, false);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateLiquidateWrite() public returns (uint256) {
        return _getPriceWrite(false, false);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateOperateDebtWrite() public returns (uint256) {
        return _getPriceWrite(true, true);
    }

    /// @inheritdoc IFluidOracleWrite
    function getExchangeRateLiquidateDebtWrite() public returns (uint256) {
        return _getPriceWrite(false, true);
    }

    /// @inheritdoc IFluidOracle
    /// @dev Skips band / staleness reverts; still applies extended-hours caps.
    function getExchangeRateOperateRaw() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(true, false, true);
    }

    /// @inheritdoc IFluidOracle
    /// @dev Skips band / staleness reverts; still applies extended-hours caps.
    function getExchangeRateLiquidateRaw() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(false, false, true);
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateRaw() external view returns (uint256 exchangeRate_) {
        (exchangeRate_, ) = _getPrice(true, false, true);
    }

    /// @inheritdoc IFluidCLXStockOracle
    function updateRegularHoursAnchor(uint80 roundId_) external {
        (uint256 sessionType_, uint32 latestRegularHoursStart_, uint32 latestRegularHoursEnd_) = MARKET_HOURS
            .getCurrentSession();

        if (!_isRegularWindowTrusted(latestRegularHoursStart_, latestRegularHoursEnd_)) {
            // During REGULAR this should not happen (end is still ahead). Outside REGULAR → alert warm bots.
            if (sessionType_ == SESSION_TYPE_REGULAR) return;
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound);
        }

        // Latest in-window RTH print; once the window is past, also the latest pre-window print within heartbeat.
        (bool found_, uint80 resolvedRoundId_, uint256 answer_) = _findLatestRegularHoursRound(
            latestRegularHoursStart_,
            latestRegularHoursEnd_,
            roundId_ == 0 ? _lastRegularHoursRoundId : roundId_,
            roundId_ == 0 ? _lastVerifiedRegularHoursEnd : 0
        );
        if (!found_ || answer_ == 0) {
            // REGULAR pricing is live and does not need this cache (e.g. early open before first CL print).
            // Outside REGULAR the anchor feeds clamp — revert so warm bots alert.
            if (sessionType_ == SESSION_TYPE_REGULAR) return;
            revert FluidStockOracleError(ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound);
        }

        // gov / class ≥ 3 may roll out-of-band (verified genuine gap, e.g. post-split re-anchor)
        if (!_isGovernance() && _authClass(msg.sender) < AUTH_CLASS_CONFIRM_MULTIPLIER) {
            uint256 referenceAnswer_ = _freshAnchorReferenceAnswer();
            if (referenceAnswer_ != 0 && _isPriceGapOutside(referenceAnswer_, answer_)) {
                revert FluidStockOracleError(ErrorTypes.CLXStockOracle__PriceGapBreak);
            }
            if (!_mayRollRegularHoursReference(resolvedRoundId_, sessionType_, latestRegularHoursStart_)) {
                return;
            }
        }

        // same marker semantics as `_getPriceWrite`: during REGULAR the close may still print, so store a hint
        // (`block.timestamp`), never the verified-for-close marker — otherwise reads cache-hit on a mid-session round.
        _storeRegularHoursReference(
            resolvedRoundId_,
            sessionType_ == SESSION_TYPE_REGULAR ? uint32(block.timestamp) : latestRegularHoursEnd_
        );
        emit LogUpdateRegularHoursAnchor(resolvedRoundId_);
    }
}
