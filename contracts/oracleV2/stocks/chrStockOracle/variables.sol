// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IChronicle } from "../interfaces/external/IChronicle.sol";
import { IRealityToken } from "../interfaces/external/IRealityToken.sol";
import { IRealityTokenTrade } from "../interfaces/external/IRealityTokenTrade.sol";
import { IFluidUsEquityMarketHours } from "../interfaces/iFluidUsEquityMarketHours.sol";
import { IFluidAuthGate } from "../../../config/authGate/interfaces/iAuthGate.sol";
import { Structs } from "./structs.sol";

abstract contract Constants is Structs {
    /// @dev Chronicle price (18 decimals) × rtoken `uiMultiplier` (1e18 = 1x) is a 36-decimal value; dividing by
    ///      this gives Fluid's 27-decimal rate.
    uint256 internal constant PRICE_TIMES_MULTIPLIER_TO_RATE = 1e9;
    /// @dev 100% for cap / break percents.
    uint256 internal constant FOUR_DECIMALS = 1e4;
    /// @dev Upper bound for `maxLiquidateAge`.
    uint256 internal constant MAX_PRICE_AGE = 5 days;
    /// @dev An anchor older than this disarms cap and break (fail-open, as CLX's gap reference). Spans close to
    ///      next close across a 4-day closure: unlike CLX, the cap also applies through the next session.
    uint256 internal constant ANCHOR_MAX_AGE = 5 days + 12 hours;
    /// @dev Prints up to this long after the bell still count as regular-session prints (the close lands late), and a
    ///      session's hint seals only once it has passed. Same 2 minutes as CLX's `REGULAR_HOURS_ANCHOR_BUFFER`.
    uint256 internal constant REGULAR_HOURS_ANCHOR_BUFFER = 2 minutes;

    uint256 internal constant CAUSE_TRADE_PAUSED = 1;
    uint256 internal constant CAUSE_RTOKEN_PAUSED = 2;
    uint256 internal constant CAUSE_MULTIPLIER_CHANGED = 4;

    IChronicle internal immutable CHRONICLE;
    IRealityToken internal immutable RTOKEN;
    IRealityTokenTrade internal immutable REALITY_TOKEN_TRADE;
    IFluidUsEquityMarketHours internal immutable MARKET_HOURS;
    IFluidAuthGate internal immutable AUTH_GATE;
    uint256 internal immutable MAX_CAP_PERCENT;
    uint256 internal immutable MAX_BREAK_PERCENT;
    uint256 internal immutable MAX_OPERATE_AGE;
    uint256 internal immutable MAX_LIQUIDATE_AGE;

    constructor(CHRStockOracleConstructorParams memory p_) {
        CHRONICLE = IChronicle(p_.chronicle);
        RTOKEN = IRealityToken(p_.rtoken);
        REALITY_TOKEN_TRADE = IRealityTokenTrade(p_.realityTokenTrade);
        MARKET_HOURS = IFluidUsEquityMarketHours(p_.marketHours);
        AUTH_GATE = IFluidAuthGate(p_.authGate);
        MAX_CAP_PERCENT = p_.maxCapPercent;
        MAX_BREAK_PERCENT = p_.maxBreakPercent;
        MAX_OPERATE_AGE = p_.maxOperateAge;
        MAX_LIQUIDATE_AGE = p_.maxLiquidateAge;
    }
}

abstract contract Variables is Constants {
    // ----------------------- slot 0 ---------------------------
    /// @dev Layout: `acceptedMultiplier:104 | paused:8 | anchorTime:32 | hintAge:32 | hintRegularEnd:32` (= 208).
    /// @dev Multiplier the oracle prices with; any other live value freezes guarded reads until `setAnchor`.
    uint104 internal _acceptedMultiplier;
    /// @dev 1 = paused (guarded reads revert).
    uint8 internal _paused;
    /// @dev Timestamp of the print the anchor came from; 0 = no anchor yet.
    uint32 internal _anchorTime;
    /// @dev Timestamp of the hinted print; 0 = no hint.
    uint32 internal _hintAge;
    /// @dev `regularEnd` of the session the hint belongs to.
    uint32 internal _hintRegularEnd;

    // ----------------------- slot 1 ---------------------------
    /// @dev Sealed anchor value (1e27).
    uint128 internal _anchorValue;
    /// @dev Latest in-session value seen (1e27).
    uint128 internal _hintValue;
}
