//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.36;

import { ViewStructs } from "../usdOracle/structs.sol";

// NOTE: 1 unit of base currency means 1e27
// Eg: If base currency is USD, then 1 USD of value means 1e27
interface IUSDOracle {
    /// @notice Returns whether the given address is an enabled guardian.
    function isGuardian(address addr_) external view returns (bool);

    /// @notice Returns token-level metadata used by pricing.
    function getTokenConfig(
        address token_
    ) external view returns (bool operatePaused_, bool liquidatePaused_, uint8 tokenType_, uint8 decimals_);

    /// @notice Returns whether token-level source config is governance-approved.
    function isTokenConfigGovernanceApproved(address token_) external view returns (bool);

    /// @notice Returns the price for a given token key. Intended for DexV2 and MoneyMarket.
    /// @dev Intentionally non-view for future flexibility. Use `getPriceView()` for read-only consumers.
    function getPrice(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external returns (uint256 price_);

    /// @notice View-only variant of `getPrice()` for read-only consumers.
    function getPriceView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_);

    /// @notice Returns detailed pricing: full getPrice() result, token decimals, and token peg type.
    ///         Reverts with the same errors as `getPrice()` when pricing fails.
    ///         Intended for V1 vault wrappers (T1-T4) that need both the price and token decimals.
    /// @dev Intentionally non-view for future flexibility. Use `getPriceDetailedView()` for read-only consumers.
    function getPriceDetailed(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external returns (uint256 price_, uint8 decimals_, uint8 tokenType_);

    /// @notice View-only variant of `getPriceDetailed()` for read-only consumers such as vault oracles.
    ///         Reverts with the same errors as `getPriceView()` when pricing fails.
    function getPriceDetailedView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_);

    /// @notice Same as `getPriceDetailedView()`, for resolver/UI reads only. May bypass checks that can revert on the guarded getter.
    /// @dev Example today: L2 sequencer uptime / grace-period. Additional bypasses may be added here over time.
    function getPriceDetailedViewRaw(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_);

    /// @notice Returns the raw composed price for a token and price mode, plus token metadata.
    ///         No caps, no deviation, no reverts (returns 0 on failure). Includes alt-source fallback when configured.
    ///         Intended for limit handlers, auth contracts, and other consumers that always need a resolved price.
    ///         Capped rate sources use getExchangeRate() (uncapped, no operate/liquidate/collateral/debt distinction).
    ///         Chainlink uses the liquidate (lenient) staleness timespan.
    function getPriceRawForMode(
        address token_,
        uint8 priceMode_
    ) external view returns (uint256 priceRaw_, uint8 decimals_, uint8 tokenType_);

    /// @notice Multi-token `getPriceRawForMode()`, same per-token semantics. Guard (L2 sequencer) checked once per batch.
    /// @param priceModes_ One mode per token; length mismatch reverts `UsdOracle__InvalidParams`.
    /// @dev Returns three parallel arrays, one entry per token in `tokens_` order.
    function getPricesRawForMode(
        address[] calldata tokens_,
        uint8[] calldata priceModes_
    ) external view returns (uint256[] memory pricesRaw_, uint8[] memory decimals_, uint8[] memory tokenTypes_);

    /// @notice True if `configsMap[token_]` lists at least one key with this eMode.
    function isEmodeValid(uint256 emode_, address token_) external view returns (bool);

    /// @notice Returns every oracle key row for `token_` with best-effort primary (and alt) leg rates and composed prices.
    /// @dev Uses non-reverting source reads (`doRevert_ = false`); failed legs surface as `rate == 0` and may zero the composed `price`.
    /// @param token_ Token to enumerate.
    /// @return infos_ One struct per configured `(eMode, isOperate, isCollateral)` row in `configsMap[token_]`.
    function getConfiguredTokenOracles(
        address token_
    ) external view returns (ViewStructs.ConfiguredTokenOracle[] memory infos_);
}
