// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IPendleMarketV3 } from "../interfaces/external/IPendleMarketV3.sol";
import { IPendlePYLpOracle } from "../interfaces/external/IPendlePYLpOracle.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   Pendle Oracle implementation
/// @notice  This contract is used to get the exchange rate for a Pendle market (PT-Asset).
abstract contract PendleOracleImpl is OracleError {
    /// @dev Pendle pyYtLpOracle address, see Pendle docs for deployment address.
    IPendlePYLpOracle internal immutable _PENDLE_ORACLE;

    /// @dev Pendle market address for which this Oracle is intended for.
    IPendleMarketV3 internal immutable _PENDLE_MARKET;

    /// @dev timestamp when PT reaches maturity. read and stored from Immutable at the `_PENDLE_MARKET` contract.
    uint256 internal immutable _EXPIRY;

    /// @dev TWAP duration for the pendle AMM oracle rate fetch.
    /// The recommended duration is 15 mins (900 secs) or 30 mins (1800 secs), but it can vary depending on the market.
    /// See https://docs.pendle.finance/Developers/Oracles/HowToIntegratePtAndLpOracle#second-choose-a-market--duration
    uint32 internal immutable _TWAP_DURATION;

    /// @dev maximum expected borrow rate for the borrow asset at the Fluid vault. Affects the increasing price for
    /// operate(), creating an effective CF at the vault that increases as we get closer to maturity.
    uint256 internal immutable _MAX_EXPECTED_BORROW_RATE;

    /// @dev minimum ever expected yield rate at Pendle for the PT asset. If TWAP price is outside of this range,
    /// the oracle will revert, stopping any new borrows during a time of unexpected state of the Pendle market.
    uint256 internal immutable _MIN_YIELD_RATE;

    /// @dev maximum ever expected yield rate at Pendle for the PT asset. If TWAP price is outside of this range,
    /// the oracle will revert, stopping any new borrows during a time of unexpected state of the Pendle market.
    uint256 internal immutable _MAX_YIELD_RATE;

    /// @dev decimals of the debt token for correct scaling out the output rate
    uint8 internal immutable _DEBT_TOKEN_DECIMALS;

    uint8 internal constant _PENDLE_DECIMALS = 18;

    constructor(
        IPendlePYLpOracle pendleOracle_,
        IPendleMarketV3 pendleMarket_,
        uint32 twapDuration_,
        uint256 maxExpectedBorrowRate_,
        uint256 minYieldRate_,
        uint256 maxYieldRate_,
        uint8 debtTokenDecimals_
    ) {
        if (
            address(pendleOracle_) == address(0) ||
            address(pendleMarket_) == address(0) ||
            twapDuration_ == 0 ||
            // human input sanity checks:
            // max expected yield / borrow rate values should be >0 and below 300% (<100% for min yield rate)
            maxExpectedBorrowRate_ == 0 ||
            maxExpectedBorrowRate_ > 300 * 1e2 ||
            minYieldRate_ == 0 ||
            minYieldRate_ > 100 * 1e2 ||
            maxYieldRate_ == 0 ||
            maxYieldRate_ > 300 * 1e2 ||
            minYieldRate_ > maxYieldRate_ ||
            debtTokenDecimals_ < 6
        ) {
            revert FluidOracleError(ErrorTypes.PendleOracle__InvalidParams);
        }

        {
            (bool increaseCardinalityRequired_, , bool oldestObservationSatisfied_) = pendleOracle_.getOracleState(
                address(pendleMarket_),
                twapDuration_
            );
            if (increaseCardinalityRequired_ || !oldestObservationSatisfied_) {
                // ensure pendle market Oracle is ready and initialized see
                // https://docs.pendle.finance/Developers/Oracles/HowToIntegratePtAndLpOracle
                revert FluidOracleError(ErrorTypes.PendleOracle__MarketNotInitialized);
            }
        }

        if (
            pendleMarket_.decimals() != _PENDLE_DECIMALS ||
            // getPtToAssetRate should be returned in 1e18, otherwise this oracle will be faulty.
            // if the returned price is < 1e15, decimals are off and the issue should be investigated.
            pendleOracle_.getPtToAssetRate(address(pendleMarket_), twapDuration_) < 1e15
        ) {
            // pendle market should have 18 decimals, other markets currently don't exist. If different, might have to adjust
            // code so better to sanity check & revert.
            revert FluidOracleError(ErrorTypes.PendleOracle__MarketInvalidDecimals);
        }

        _PENDLE_ORACLE = pendleOracle_;
        _PENDLE_MARKET = pendleMarket_;
        _EXPIRY = pendleMarket_.expiry();
        _TWAP_DURATION = twapDuration_;
        _MAX_EXPECTED_BORROW_RATE = maxExpectedBorrowRate_;
        _MIN_YIELD_RATE = minYieldRate_;
        _MAX_YIELD_RATE = maxYieldRate_;

        // debt token decimals is used to make sure the returned exchange rate is scaled correctly e.g.
        // for an exchange rate between PT-sUSDe and USDC (this Oracle returning amount of USDC for 1e18 PT-sUSDe).
        _DEBT_TOKEN_DECIMALS = debtTokenDecimals_;
    }

    /// @dev returns the pendle oracle exchange rate for operate() scaled by `OracleUtils.RATE_OUTPUT_DECIMALS`.
    /// checks that the AMM TWAP rate at Pendle is within the allowed yield ranges, and returns
    /// the `rate_` based on maturity and a maximum expected borrow rate at Fluid, resulting into an automatically
    /// with block.timestamp adjusting effective CF at the vault, increasing as we get closer to maturity.
    function _getPendleExchangeRateOperate() internal view returns (uint256 rate_) {
        uint256 timeToMaturity_;
        unchecked {
            timeToMaturity_ = _EXPIRY > block.timestamp ? _EXPIRY - block.timestamp : 0;
        }
        if (timeToMaturity_ == 0) {
            // at maturity, 1PT is always 1 underlying.
            return (10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + _DEBT_TOKEN_DECIMALS)) / (10 ** _PENDLE_DECIMALS);
        }

        // get TWAP price from Pendle AMM.
        // Note getPtToAssetRate() gives the price of PT to the underlying asset at maturity.
        // For PT-sUSDe this would be USDe, not sUSDe (sUSDe -> USDe fetched from contract pricing)!
        rate_ =
            _PENDLE_ORACLE.getPtToAssetRate(address(_PENDLE_MARKET), _TWAP_DURATION) *
            (10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - _PENDLE_DECIMALS)); // * 1e9 to scale to 1e27
        // check if within allowed ranges
        // 1PT can never be more than 1:1 to asset,
        if (rate_ > 10 ** OracleUtils.RATE_OUTPUT_DECIMALS) {
            // this should never happen, even at maturity the max price would be 1:1
            revert FluidOracleError(ErrorTypes.PendleOracle__InvalidPrice);
        }

        // price should be within _MIN_YIELD_RATE & _MAX_YIELD_RATE for time to maturity.
        // Note max yield results in a smaller price for the PT asset and vice versa for min.
        uint256 minExpectedPrice_ = _priceAtRateToMaturity(_MAX_YIELD_RATE, timeToMaturity_);
        uint256 maxExpectedPrice_ = _priceAtRateToMaturity(_MIN_YIELD_RATE, timeToMaturity_);

        if (rate_ < minExpectedPrice_ || rate_ > maxExpectedPrice_) {
            revert FluidOracleError(ErrorTypes.PendleOracle__InvalidPrice);
        }

        // for operate return peg price based on maturity and a maximum expected borrow rate at Fluid. This results in
        // an effective decreased CF at the vault depending on time to maturity.
        // example for a Fluid vault PT-SUSDE / USDC, as we assume price at maturity:
        // 1 PT-SUSDE = 1 USDE and 1 USDE = 1 USDC. where this oracle is responsible for the 1 PT-SUSDE = 1 USDE part.
        // with a CF of 85% at the vault, that means a user can borrow 0.85 USDC for 1 PT-SUSDE.
        // Our goal is to guarantee there is no possibility for bad debt at maturity. So effective CF should be time dependent to maturity
        // based on a max expected borrow rate.
        // e.g. at 50% max borrow rate and maturity in 100 days, _priceAtRateToMaturity would return:
        // x = 1e20 * 1e27 / (1e20 + (5000 * 1e16 * 100 days / 365 days)) = 879518072289156626

        // now this oracle reports instead of 1 PT-SUSDE = 1 USDE, 1 PT-SUSDE = 0.879518072289156626 USDE.
        // which leads to a user can borrow 0.879518072289156626 USDE * 0.85 CF = 0.747590361445783132 USDC for 1 PT-SUSDE.

        // this automatically adjusts the closer we get to maturity. E.g. at 1 day to maturity:
        // x = 1e20 * 1e27 / (1e20 + (5000 * 1e16 * 1 days / 365 days)) = 998632010943912448
        // -> user can borrow 0.998632010943912448 USDE * 0.85 CF = 0.848837209302325581 USDC for 1 PT-SUSDE.

        rate_ = _priceAtRateToMaturity(_MAX_EXPECTED_BORROW_RATE, timeToMaturity_);
        // scale result:
        // e.g. for PT-SUSDE -> USDC: rate * 10^6 / 10^18 = result will be in 1e15
        // e.g. for PT-SUSDE -> DAI: rate * 10^18 / 10^18 = result will be in 1e27
        rate_ = (rate_ * (10 ** _DEBT_TOKEN_DECIMALS)) / (10 ** _PENDLE_DECIMALS);
    }

    /// @dev returns the pendle oracle exchange rate for liquidate(): 1PT = 1 underlying (e.g. 1PT-sUSDE = 1 USDE).
    /// scaled by `OracleUtils.RATE_OUTPUT_DECIMALS`.
    function _getPendleExchangeRateLiquidate() internal view returns (uint256 rate_) {
        // for liquidate, peg at maturity is assumed: 1PT = 1 underlying (e.g. 1PT-sUSDE = 1 USDE).
        // this avoids unnecessary liquidation cascades. Any bad debt would be temporary until maturity only.
        // see scaling info in `_getPendleExchangeRateOperate()`
        return (10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + _DEBT_TOKEN_DECIMALS)) / (10 ** _PENDLE_DECIMALS);
    }

    /// @notice returns all Pendle oracle related data as utility for easy off-chain use / block explorer in a single view method
    function pendleOracleData()
        public
        view
        returns (
            IPendlePYLpOracle pendleOracle_,
            IPendleMarketV3 pendleMarket_,
            uint256 expiry_,
            uint32 twapDuration_,
            uint256 maxExpectedBorrowRate_,
            uint256 minYieldRate_,
            uint256 maxYieldRate_,
            uint8 debtTokenDecimals_,
            uint256 exchangeRateOperate_,
            uint256 exchangeRateLiquidate_,
            uint256 ptToAssetRateTWAP_
        )
    {
        return (
            _PENDLE_ORACLE,
            _PENDLE_MARKET,
            _EXPIRY,
            _TWAP_DURATION,
            _MAX_EXPECTED_BORROW_RATE,
            _MIN_YIELD_RATE,
            _MAX_YIELD_RATE,
            _DEBT_TOKEN_DECIMALS,
            _getPendleExchangeRateOperate(),
            _getPendleExchangeRateLiquidate(),
            _PENDLE_ORACLE.getPtToAssetRate(address(_PENDLE_MARKET), _TWAP_DURATION)
        );
    }

    /// @dev returns the `price_` in 1e27, given a `yearlyRatePercent_`  yield in percent (1e2 = 1%) and a `timeToMaturity_`.
    function _priceAtRateToMaturity(
        uint256 yearlyRatePercent_,
        uint256 timeToMaturity_
    ) internal pure returns (uint256 price_) {
        // formula: x = 100% / (100% + (yearlyRatePercent * timeToMaturity / 1year)
        // with scaling (100% = 1e20, result scaled to 1e27):
        // x = 1e20 * 1e27 / (1e20 +(yearlyRatePercent * 1e16 * timeToMaturity / 1year))
        // e.g. when 100 days to maturity and yield rate is 4%
        // x = 1e20 * 1e27 / (1e20 + (400 * 1e16 * 100 days /365 days))
        return
            (1e20 * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) /
            (1e20 + ((yearlyRatePercent_ * 1e16 * timeToMaturity_) / 365 days));
    }
}
