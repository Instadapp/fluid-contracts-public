// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IFluidUsEquityMarketHours } from "../interfaces/iFluidUsEquityMarketHours.sol";
import { IBackedWrapper } from "../interfaces/external/IBackedWrapper.sol";
import { LiquidityGovernanceAuth } from "../../../libraries/access/liquidityGovernanceAuth.sol";
import { SessionTypes } from "../usEquityMarketHours/sessionTypes.sol";
import { Structs } from "./structs.sol";

abstract contract Constants is LiquidityGovernanceAuth, SessionTypes, Structs {
    /// @dev Auth class: 0 = none, 1 = pause-only, 2 = pause + unpause, 3 = + confirm multiplier.
    uint8 internal constant AUTH_CLASS_PAUSE = 1;
    uint8 internal constant AUTH_CLASS_PAUSE_UNPAUSE = 2;
    uint8 internal constant AUTH_CLASS_CONFIRM_MULTIPLIER = 3;

    /// @dev Scale for extended-hours cap percent (100% = 1e6).
    uint256 internal constant SIX_DECIMALS = 1e6;
    /// @dev Scale for multiplier-band percent (100% = 1e4).
    uint256 internal constant FOUR_DECIMALS = 1e4;
    /// @dev Backed multiplier precision; also the shares arg for the deploy-time `convertToAssets` assert.
    uint256 internal constant MULTIPLIER_PRECISION = 1e18;

    /// @dev CL feed heartbeat (24h `deltaC` in feed OCR config, not readable on-chain) + 20 min grace.
    uint256 internal constant MIN_CHAINLINK_HEARTBEAT = 24 hours + 20 minutes;
    /// @dev Liquidate; operate on Holiday/Unknown; fallback when clamp skipped.
    uint256 internal constant MAX_UPDATE_TIMESPAN_EXTENDED = 5 days;

    /// @dev How long the multiplier band accrues linearly before it stops growing.
    uint256 internal constant MULTIPLIER_BAND_PERIOD = 30 days;
    /// @dev Constructor ceiling for `maxMultiplierChangePercent` (1e2/1e4: 10% = 1000).
    ///      `0` is allowed: freeze mode — any live ≠ accepted needs confirm; exact match does not revert.
    uint256 internal constant MAX_ALLOWED_MULTIPLIER_CHANGE_PERCENT = 1000;
    /// @dev Optional deploy guard for `rateMultiplier` (e.g. 8-dec CL → 1e27 uses `1e19`).
    uint256 internal constant MAX_RATE_MULTIPLIER = 1e27;

    /// @dev Max CL rounds to walk when discovering the last RTH print.
    uint256 internal constant MAX_REGULAR_HOURS_ROUND_LOOKBACK = 300;
    /// @dev Stale hint sync / MH `regularEnd` → ignore hint or skip clamp (matches extended staleness).
    uint256 internal constant REGULAR_HOURS_HINT_MAX_AGE = 5 days;
    /// @dev Extra after official close still counted as RTH: `updatedAt ∈ [start, end + this]`.
    uint256 internal constant REGULAR_HOURS_ANCHOR_BUFFER = 15 minutes;
    /// @dev Freeze pricing when a scheduled multiplier outside the band activates within this window.
    uint256 internal constant SCHEDULED_MULTIPLIER_FREEZE_BUFFER = 24 hours;
    /// @dev Gap reference older than this is skipped (fail-open; spans long weekends).
    uint256 internal constant PRICE_GAP_REFERENCE_MAX_AGE = 5 days;
    /// @dev Min age of the stored reference round before a different round may replace it; also no roll
    ///      this early into REGULAR. Stops walking the gap guard through a multi-round split print.
    uint256 internal constant PRICE_GAP_REFERENCE_ROLL_DELAY = 20 minutes;
    /// @dev Chainlink AggregatorV3 equity feed.
    address internal immutable CHAINLINK_FEED;
    /// @dev Backed wrapper; deploy-time passthrough assert only (pricing reads the underlying).
    address internal immutable BACKED_WRAPPER;
    /// @dev Backed rebasing underlying (`wrapper.asset()`): live multiplier + schedule source.
    address internal immutable BACKED_UNDERLYING;
    /// @dev Shared US equity session schedule.
    IFluidUsEquityMarketHours internal immutable MARKET_HOURS;
    /// @dev Scales CL×multiplier into Fluid oracle decimals (e.g. 8-dec → 1e27).
    uint256 internal immutable RATE_MULTIPLIER;

    /// @dev Max accepted↔live drift over `MULTIPLIER_BAND_PERIOD` (1e2: 1% = 100).
    uint256 internal immutable MAX_MULTIPLIER_CHANGE_PERCENT;
    /// @dev ± vs RTH anchor in non-REGULAR (1e6: 1% = 1e4).
    uint256 internal immutable MAX_EXTENDED_HOURS_CAP_PERCENT;
    /// @dev Strict lower price-gap bound vs anchor reference (1e4: 42% = 4200); required, < 100%.
    uint256 internal immutable MAX_PRICE_GAP_DOWN_PERCENT;
    /// @dev Strict upper price-gap bound vs anchor reference (1e4: 68% = 6800; mirror `4 * down - 1`).
    uint256 internal immutable MAX_PRICE_GAP_UP_PERCENT;

    // struct, not separate fields: reading all of them in the base-constructor list blows the stack at 0.8.36.
    constructor(CLXStockOracleConstructorParams memory p_) LiquidityGovernanceAuth(p_.liquidity) {
        CHAINLINK_FEED = p_.chainlinkFeed;
        BACKED_WRAPPER = p_.backedWrapper;
        // zero wrapper defers to `InvalidParams` in the main constructor
        BACKED_UNDERLYING = p_.backedWrapper == address(0) ? address(0) : IBackedWrapper(p_.backedWrapper).asset();
        MARKET_HOURS = IFluidUsEquityMarketHours(p_.marketHours);
        RATE_MULTIPLIER = p_.rateMultiplier;
        MAX_MULTIPLIER_CHANGE_PERCENT = p_.maxMultiplierChangePercent;
        MAX_EXTENDED_HOURS_CAP_PERCENT = p_.maxExtendedHoursCapPercent;
        MAX_PRICE_GAP_DOWN_PERCENT = p_.maxPriceGapDownPercent;
        MAX_PRICE_GAP_UP_PERCENT = p_.maxPriceGapUpPercent;
    }
}

abstract contract Variables is Constants {
    // ----------------------- slot 0 ---------------------------
    /// @dev Layout: `acceptedMultiplier:104 | paused:8 | lastMultiplierUpdateTime:32 |
    ///      lastRegularHoursRoundId:80 | lastVerifiedRegularHoursEnd:32` (= 256).
    /// @dev Band reference for live wrapper multiplier (in-band sync / team confirm).
    uint104 internal _acceptedMultiplier;
    /// @dev 1 = paused (pricing reverts).
    uint8 internal _paused;
    /// @dev Timestamp when `_acceptedMultiplier` was last written (band accrual start).
    uint32 internal _lastMultiplierUpdateTime;
    /// @dev Last known RTH / walk-hint CL proxy round id (`phaseId << 64 | aggregatorRoundId`).
    uint80 internal _lastRegularHoursRoundId;
    /// @dev Sync marker for `_lastRegularHoursRoundId`: `regularEnd` after full find (cache hit),
    ///      or `block.timestamp` on REGULAR write (hint only — not a close claim).
    uint32 internal _lastVerifiedRegularHoursEnd;

    // ----------------------- slot 1 ---------------------------
    /// @dev Auth class for `BasicAuth` hooks (`0` none, `1` pause, `2` pause+unpause, `3` +confirm).
    mapping(address => uint256) internal _auths;
}
