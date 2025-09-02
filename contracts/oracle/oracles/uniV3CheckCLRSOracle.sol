// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { FallbackOracleImpl } from "../implementations/fallbackOracleImpl.sol";
import { UniV3OracleImpl } from "../implementations/uniV3OracleImpl.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @DEV DEPRECATED. USE GENERIC ORACLE INSTEAD. WILL BE REMOVED SOON.

/// @title   UniswapV3 checked against Chainlink / Redstone Oracle. Either one reported as exchange rate.
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          the price from a UniV3 pool (compared against 3 TWAPs) and (optionally) comparing it against a Chainlink
///          or Redstone price (one of Chainlink or Redstone being the main source and the other one the fallback source).
///          Alternatively it can also use Chainlink / Redstone as main price and use UniV3 as check price.
/// @dev     The process for getting the aggregate oracle price is:
///           1. Fetch the UniV3 TWAPS, the latest interval is used as the current price
///           2. Verify this price is within an acceptable DELTA from the Uniswap TWAPS e.g.:
///              a. 240 to 60s
///              b. 60 to 15s
///              c. 15 to 1s (last block)
///              d. 1 to 0s (current)
///           3. (unless UniV3 only mode): Verify this price is within an acceptable DELTA from the Chainlink / Redstone Oracle
///           4. If it passes all checks, return the price. Otherwise use fallbacks, usually to Chainlink. In extreme edge-cases revert.
/// @dev     For UniV3 with check mode, if fetching the check price fails, the UniV3 rate is used directly.
contract UniV3CheckCLRSOracle is FluidOracle, UniV3OracleImpl, FallbackOracleImpl {
    /// @dev Rate check oracle delta percent in 1e2 percent. If current uniswap price is out of this delta,
    /// current price fetching reverts.
    uint256 internal immutable _RATE_CHECK_MAX_DELTA_PERCENT;

    /// @dev which oracle to use as final rate source:
    ///      - 1 = UniV3 ONLY (no check),
    ///      - 2 = UniV3 with Chainlink / Redstone check
    ///      - 3 = Chainlink / Redstone with UniV3 used as check.
    uint8 internal immutable _RATE_SOURCE;

    struct UniV3CheckCLRSConstructorParams {
        /// @param uniV3Params                UniV3Oracle constructor params struct.
        UniV3ConstructorParams uniV3Params;
        /// @param chainlinkParams            ChainlinkOracle constructor params struct for UniV3CheckCLRSOracle.
        ChainlinkConstructorParams chainlinkParams;
        /// @param redstoneOracle             Redstone Oracle data for UniV3CheckCLRSOracle. (address can be set to zero address if using Chainlink only)
        RedstoneOracleData redstoneOracle;
        /// @param rateSource                 which oracle to use as final rate source for UniV3CheckCLRSOracle:
        ///                                         - 1 = UniV3 ONLY (no check),
        ///                                         - 2 = UniV3 with Chainlink / Redstone check
        ///                                         - 3 = Chainlink / Redstone with UniV3 used as check.
        uint8 rateSource;
        /// @param fallbackMainSource         which oracle to use as CL/RS main source for UniV3CheckCLRSOracle: see FallbackOracleImpl constructor `mainSource_`
        uint8 fallbackMainSource;
        /// @param rateCheckMaxDeltaPercent   Rate check oracle delta in 1e2 percent for UniV3CheckCLRSOracle
        uint256 rateCheckMaxDeltaPercent;
    }

    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        UniV3CheckCLRSConstructorParams memory params_
    )
        UniV3OracleImpl(params_.uniV3Params)
        FallbackOracleImpl(params_.fallbackMainSource, params_.chainlinkParams, params_.redstoneOracle)
        FluidOracle(infoName_, targetDecimals_)
    {
        if (
            params_.rateSource < 1 ||
            params_.rateSource > 3 ||
            params_.rateCheckMaxDeltaPercent > OracleUtils.HUNDRED_PERCENT_DELTA_SCALER ||
            // Chainlink only Oracle with UniV3 check. Delta would be ignored so revert this type of Oracle setup.
            (params_.fallbackMainSource == 1 && params_.rateSource == 3)
        ) {
            revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__InvalidParams);
        }

        _RATE_CHECK_MAX_DELTA_PERCENT = params_.rateCheckMaxDeltaPercent;
        _RATE_SOURCE = params_.rateSource;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        return _getExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        return _getExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        return _getExchangeRate();
    }

    /// @notice returns all oracle related data as utility for easy off-chain / block explorer use in a single view method
    function uniV3CheckOracleData()
        public
        view
        returns (uint256 rateCheckMaxDelta_, uint256 rateSource_, uint256 fallbackMainSource_)
    {
        return (_RATE_CHECK_MAX_DELTA_PERCENT, _RATE_SOURCE, _FALLBACK_ORACLE_MAIN_SOURCE);
    }

    function _getExchangeRate() internal view returns (uint256 exchangeRate_) {
        if (_RATE_SOURCE == 1) {
            // uniswap is the only main source without check:
            // 1. get uniV3 rate.
            // 2. If that fails (outside delta range) -> revert (no other Oracle configured).
            exchangeRate_ = _getUniV3ExchangeRate();

            if (exchangeRate_ == 0) {
                // fetching UniV3 failed or invalid delta -> revert
                revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);
            }

            return exchangeRate_;
        }

        uint256 checkRate_;
        bool fallback_;
        if (_RATE_SOURCE == 2) {
            // uniswap is main source, with Chainlink / Redstone as check
            // 1. get uniV3 rate

            // case uniV3 rate fails (outside delta range):
            // 2. get Chainlink rate. -> if successful, use Chainlink as result
            // 3. if Chainlink fails too, get Redstone -> if successful, use Redstone as result
            // 4. if Redstone fails too, revert

            // case if uniV3 rate is ok
            // 2. get Chainlink or Redstone rate for check (one is configured as main check source, other one is fallback source)
            //    -> if both fail to fetch, use uniV3 rate directly.
            // 3. check the delta for uniV3 rate against the check soure rate. -> if ok, return uniV3 rate
            // 4. if delta check fails, check delta against the fallback check source. -> if ok, return uniV3 rate
            // 5. if delta check fails for both sources, return Chainlink price

            exchangeRate_ = _getUniV3ExchangeRate();

            if (exchangeRate_ == 0) {
                // uniV3 failed or invalid delta -> use (Chainlink with Redstone as fallback)
                exchangeRate_ = _getChainlinkOrRedstoneAsFallback();
                if (exchangeRate_ == 0) {
                    // Chainlink / Redstone failed too -> revert
                    revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);
                }
                return exchangeRate_;
            }

            (checkRate_, fallback_) = _getRateWithFallback();
            if (checkRate_ == 0) {
                // check price source failed to fetch -> directly use uniV3 TWAP checked price
                // Note uniV3 price fetching was successful, would have been caught otherwise above.
                return exchangeRate_;
            }
        } else {
            // Chainlink / Redstone is main source, with uniV3 as check.
            // 1. get Chainlink / Redstone rate (one is configured as main source, other one is fallback source)

            // case when both Chainlink & Redstone fail:
            // 2. get uniV3 rate. if successful, use uniV3 rate. otherwise, revert (all oracles failed).

            // case when Chainlink / Redstone fetch is successful:
            // 2. get uniV3 rate for check.
            // 3. if uniV3 rate fails to fetch (outside delta), use Chainlink / Redstone directly (skip check).
            // 4. if uniV3 rate is ok, check the delta for Chainlink / Redstone rate against uniV3 rate.
            //    -> if ok, return Chainlink / Redstone (main) rate
            // 5. if delta check fails, check delta against the fallback main source.
            //    -> if ok, return fallback main rate
            // 6. if delta check fails for both sources, return Chainlink price.

            (exchangeRate_, fallback_) = _getRateWithFallback();
            checkRate_ = _getUniV3ExchangeRate();

            if (exchangeRate_ == 0) {
                if (checkRate_ == 0) {
                    // all oracles failed, revert
                    revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__ExchangeRateZero);
                }

                // Both Chainlink & Redstone failed -> directly use uniV3 TWAP checked price
                // Note uniV3 price fetching was successful, would have been caught otherwise above.
                return checkRate_;
            }

            if (checkRate_ == 0) {
                // uniV3 failed -> skip check against Uniswap price.

                return exchangeRate_;
            }
        }

        if (OracleUtils.isRateOutsideDelta(exchangeRate_, checkRate_, _RATE_CHECK_MAX_DELTA_PERCENT)) {
            if (fallback_) {
                // fallback already used, no other rate available to check.

                // if price is chainlink price -> return it.
                if (_FALLBACK_ORACLE_MAIN_SOURCE == 3) {
                    // redstone with Chainlink as fallback
                    return _RATE_SOURCE == 2 ? checkRate_ : exchangeRate_; // if rate source is 2, Chainlink rate is in checkRate_
                }

                // if price is redstone price -> revert
                revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__InvalidPrice);
            }

            if (_FALLBACK_ORACLE_MAIN_SOURCE == 1) {
                // 1 = only chainlink and UniV3 is configured and delta check failed. no fallback available.
                if (_RATE_SOURCE == 2) {
                    // case where uniV3 is main source with only Chainlink as check rate Oracle configured.
                    // delta check failed -> return Chainlink price (instead of uniV3 price).
                    return checkRate_;
                }

                // here: if (_FALLBACK_ORACLE_MAIN_SOURCE == 1 && _RATE_SOURCE == 3)
                // rate source is 3: Chainlink as main, uniV3 as delta. delta check failed.
                // this Oracle type would basically be a more expensive Chainlink-only Oracle because the delta check against UniV3 is ignored.
                // this setup is reverted in constructor, but in any case returning Chainlink price here even though this code should never be reached.
                return exchangeRate_; // exchangeRate_ here is chainlink price
            }

            // fallback not done yet -> check against fallback price.
            // So if originally Chainlink was fetched and delta failed, check against Redstone.
            // if originally Redstone was fetched and delta failed, check against Chainlink.
            if (_FALLBACK_ORACLE_MAIN_SOURCE == 2) {
                // 2 = Chainlink with Redstone Fallback. delta check against Chainlink failed. try against Redstone.
                uint256 redstoneRate_ = _getRedstoneExchangeRate();
                uint256 chainlinkRate_;
                if (_RATE_SOURCE == 2) {
                    // uniV3 main source. -> update checkRate_ with Redstone price
                    chainlinkRate_ = checkRate_;
                    checkRate_ = redstoneRate_;
                } else {
                    // uniV3 is check source. -> update exchangeRate_ with Redstone price
                    chainlinkRate_ = exchangeRate_;
                    exchangeRate_ = redstoneRate_;
                }

                if (redstoneRate_ == 0) {
                    // fetching Redstone failed. So delta UniV3 <> Chainlink failed, fetching Redstone as backup failed.
                    // -> return chainlink price (for both cases when Chainlink is main and when UniV3 is the main source).
                    return chainlinkRate_;
                }

                if (OracleUtils.isRateOutsideDelta(exchangeRate_, checkRate_, _RATE_CHECK_MAX_DELTA_PERCENT)) {
                    // delta check against Redstone failed too. return Chainlink price
                    return chainlinkRate_;
                }

                // delta check against Redstone passed. if uniV3 main source -> return uniV3, else return Redstone.
                // exchangeRate_ is already set correctly for this.
            } else {
                // 3 = Redstone with Chainlink Fallback. delta check against Redstone failed. try against Chainlink.
                uint256 chainlinkRate_ = _getChainlinkExchangeRate();
                if (chainlinkRate_ == 0) {
                    // fetching Chainlink failed. So delta UniV3 <> Redstone failed, fetching Chainlink as backup check failed.
                    // -> revert.
                    revert FluidOracleError(ErrorTypes.UniV3CheckCLRSOracle__InvalidPrice);
                }

                if (_RATE_SOURCE == 3) {
                    // uniV3 is check source. -> update exchangeRate_ with Chainlink price.
                    // Optimization: in this case we can directly return chainlink price, because if delta check between
                    // Chainlink (new main source) and uniV3 (check source) fails, we anyway return Chainlink price still.
                    return chainlinkRate_;
                }

                // uniV3 main source. -> update checkRate_ with Chainlink price and compare delta again
                checkRate_ = chainlinkRate_;

                if (OracleUtils.isRateOutsideDelta(exchangeRate_, checkRate_, _RATE_CHECK_MAX_DELTA_PERCENT)) {
                    // delta check against Chainlink failed too. case here can only be where uniV3 would have been
                    // main source and Chainlink check source. -> return Chainlink as price instead of uniV3
                    return checkRate_;
                }

                // delta check against Chainlink passed. if uniV3 main source -> return uniV3, else return Chainlink.
                // exchangeRate_ is already set correctly for this.
            }
        }
    }
}
