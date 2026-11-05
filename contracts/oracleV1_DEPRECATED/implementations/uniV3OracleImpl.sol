// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { IUniswapV3Pool } from "../interfaces/external/IUniswapV3Pool.sol";
import { Error as OracleError } from "../error.sol";

/// @title   Uniswap V3 Oracle implementation
/// @notice  This contract is used to get the exchange rate from from a Uniswap V3 Pool,
///          including logic to check against TWAP max deltas.
/// @dev     Uses 5 secondsAgos[] values and 3 TWAP maxDeltas:
///          e.g. [240, 60, 15, 1, 0] -> [price240to60, price60to15, price 15to1, currentPrice]
///          delta checks: price240to60 vs currentPrice, price60to15 vs currentPrice and 15to1 vs currentPrice.
abstract contract UniV3OracleImpl is OracleError {
    /// @dev Uniswap V3 Pool to check for the exchange rate
    IUniswapV3Pool internal immutable _POOL;

    /// @dev Flag to invert the price or not (to e.g. for WETH/USDC pool return prive of USDC per 1 WETH)
    bool internal immutable _UNIV3_INVERT_RATE;

    /// @dev Uniswap oracle delta for TWAP1 in 1e2 percent. If uniswap price TWAP1 is out of this delta,
    /// current price fetching reverts. E.g. for delta of TWAP 240 -> 60 vs current price
    uint256 internal immutable _UNI_TWAP1_MAX_DELTA_PERCENT;
    /// @dev Uniswap oracle delta for TWAP2 in 1e2 percent. If uniswap price TWAP2 is out of this delta,
    /// current price fetching reverts. E.g. for delta of TWAP 60 -> 15 vs current price
    uint256 internal immutable _UNI_TWAP2_MAX_DELTA_PERCENT;
    /// @dev Uniswap oracle delta for TWAP3 in 1e2 percent. If uniswap price TWAP3 is out of this delta,
    /// current price fetching reverts. E.g. for delta of TWAP 15 -> 1 vs current price
    uint256 internal immutable _UNI_TWAP3_MAX_DELTA_PERCENT;

    /// @dev Uniswap oracle seconds ago for twap, 1. value, e.g. 240
    uint256 internal immutable _UNI_SECONDS_AGO_1;
    /// @dev Uniswap oracle seconds ago for twap, 2. value, e.g. 60
    uint256 internal immutable _UNI_SECONDS_AGO_2;
    /// @dev Uniswap oracle seconds ago for twap, 3. value, e.g. 15
    uint256 internal immutable _UNI_SECONDS_AGO_3;
    /// @dev Uniswap oracle seconds ago for twap, 4. value, e.g. 1
    uint256 internal immutable _UNI_SECONDS_AGO_4;
    /// @dev Uniswap oracle seconds ago for twap, 5. value, e.g. 0
    uint256 internal immutable _UNI_SECONDS_AGO_5;

    /// @dev Uniswap TWAP1 interval duration.
    int256 internal immutable _UNI_TWAP1_INTERVAL;
    /// @dev Uniswap TWAP2 interval duration.
    int256 internal immutable _UNI_TWAP2_INTERVAL;
    /// @dev Uniswap TWAP3 interval duration.
    int256 internal immutable _UNI_TWAP3_INTERVAL;
    /// @dev Uniswap TWAP4 interval duration.
    int256 internal immutable _UNI_TWAP4_INTERVAL;

    /// @dev stored array lengths to optimize gas
    uint256 internal constant _SECONDS_AGOS_LENGTH = 5;
    uint256 internal constant _TWAP_DELTAS_LENGTH = 3;

    /// @dev constant value for price scaling to reduce gas usage
    uint256 internal immutable _UNIV3_PRICE_SCALER_MULTIPLIER;
    /// @dev constant value for inverting price to reduce gas usage
    uint256 internal immutable _UNIV3_INVERT_PRICE_DIVIDEND;

    struct UniV3ConstructorParams {
        /// @param pool                   Uniswap V3 Pool to check for the exchange rate
        IUniswapV3Pool pool;
        /// @param invertRate             Flag to invert the Uniswap price or not
        bool invertRate;
        /// @param tWAPMaxDeltaPercents Uniswap oracle delta for TWAP1-2-3 in 1e2 percent
        uint256[_TWAP_DELTAS_LENGTH] tWAPMaxDeltaPercents;
        /// @param secondsAgos          Uniswap oracle seconds ago for the 3 TWAP values, from oldest to newest, e.g. [240, 60, 15, 1, 0]
        uint32[_SECONDS_AGOS_LENGTH] secondsAgos;
    }

    /// @notice constructor sets the  Uniswap V3 `pool_` to check for the exchange rate and the `invertRate_` flag.
    /// E.g. `invertRate_` should be true if for the WETH/USDC pool it's expected that the oracle returns USDC per 1 WETH
    constructor(UniV3ConstructorParams memory params_) {
        if (address(params_.pool) == address(0)) {
            revert FluidOracleError(ErrorTypes.UniV3Oracle__InvalidParams);
        }
        // sanity check that seconds agos values are ordered ascending, e.g. [240, 60, 15, 1, 0]
        if (
            params_.secondsAgos[0] <= params_.secondsAgos[1] ||
            params_.secondsAgos[1] <= params_.secondsAgos[2] ||
            params_.secondsAgos[2] <= params_.secondsAgos[3] ||
            params_.secondsAgos[3] <= params_.secondsAgos[4]
        ) {
            revert FluidOracleError(ErrorTypes.UniV3Oracle__InvalidSecondsAgos);
        }
        // sanity check that deltas are less than 100% and decreasing (as timespan is closer to current price):
        // 1. delta must < 100%
        // all following deltas must be <= than the previous one
        if (
            params_.tWAPMaxDeltaPercents[0] >= OracleUtils.HUNDRED_PERCENT_DELTA_SCALER ||
            params_.tWAPMaxDeltaPercents[1] > params_.tWAPMaxDeltaPercents[0] ||
            params_.tWAPMaxDeltaPercents[2] > params_.tWAPMaxDeltaPercents[1]
        ) {
            revert FluidOracleError(ErrorTypes.UniV3Oracle__InvalidDeltas);
        }

        _UNI_SECONDS_AGO_1 = uint256(params_.secondsAgos[0]);
        _UNI_SECONDS_AGO_2 = uint256(params_.secondsAgos[1]);
        _UNI_SECONDS_AGO_3 = uint256(params_.secondsAgos[2]);
        _UNI_SECONDS_AGO_4 = uint256(params_.secondsAgos[3]);
        _UNI_SECONDS_AGO_5 = uint256(params_.secondsAgos[4]);

        _UNI_TWAP1_INTERVAL = int256(uint256(params_.secondsAgos[0] - params_.secondsAgos[1]));
        _UNI_TWAP2_INTERVAL = int256(uint256(params_.secondsAgos[1] - params_.secondsAgos[2]));
        _UNI_TWAP3_INTERVAL = int256(uint256(params_.secondsAgos[2] - params_.secondsAgos[3]));
        _UNI_TWAP4_INTERVAL = int256(uint256(params_.secondsAgos[3] - params_.secondsAgos[4]));

        _UNI_TWAP1_MAX_DELTA_PERCENT = params_.tWAPMaxDeltaPercents[0]; // e.g. for TWAP 240 -> 60 vs current price
        _UNI_TWAP2_MAX_DELTA_PERCENT = params_.tWAPMaxDeltaPercents[1]; // e.g. for TWAP  60 -> 15 vs current price
        _UNI_TWAP3_MAX_DELTA_PERCENT = params_.tWAPMaxDeltaPercents[2]; // e.g. for TWAP  15 ->  1 vs current price

        _POOL = params_.pool;
        _UNIV3_INVERT_RATE = params_.invertRate;

        // uniswapV3 returned price is already scaled to token decimals.
        _UNIV3_PRICE_SCALER_MULTIPLIER = 10 ** OracleUtils.RATE_OUTPUT_DECIMALS;
        // uniV3 invert price dividend happens on the already scaled by 1e27 result for price in token1 per 1 token0
        _UNIV3_INVERT_PRICE_DIVIDEND = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS * 2);
    }

    /// @dev                        Get the last exchange rate from the pool's last observed value without any checks
    /// @return exchangeRateUnsafe_ The exchange rate between the underlying asset and the peg asset in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getUniV3ExchangeRateUnsafe() internal view returns (uint256 exchangeRateUnsafe_) {
        (uint160 sqrtPriceX96_, , , , , , ) = _POOL.slot0();

        exchangeRateUnsafe_ = _UNIV3_INVERT_RATE
            ? _invertUniV3Price(_getPriceFromSqrtPriceX96(sqrtPriceX96_))
            : _getPriceFromSqrtPriceX96(sqrtPriceX96_);
    }

    /// @dev                   Get the last exchange rate from the pool's last observed value, checked against TWAP deviations.
    /// @return exchangeRate_  The exchange rate between the underlying asset and the peg asset in `OracleUtils.RATE_OUTPUT_DECIMALS`
    ///                        If 0 then the fetching the price failed or a delta was invalid.
    function _getUniV3ExchangeRate() internal view returns (uint256 exchangeRate_) {
        // build calldata bytes in a gas-optimized way without having to build an array / using abi.encode.
        // gas efficient work around for Solidity not supporting immutable non-value types.
        bytes memory data_ = abi.encodePacked(
            hex"883bdbfd", // pack function selector
            hex"0000000000000000000000000000000000000000000000000000000000000020", // pack start offset of dynamic array
            _SECONDS_AGOS_LENGTH, // pack length of dynamic array
            // pack seconds agos values:
            _UNI_SECONDS_AGO_1,
            _UNI_SECONDS_AGO_2,
            _UNI_SECONDS_AGO_3,
            _UNI_SECONDS_AGO_4,
            _UNI_SECONDS_AGO_5
        );

        // get the tickCumulatives from Pool.observe()
        (bool success_, bytes memory result_) = address(_POOL).staticcall(data_);

        if (!success_) {
            return 0;
        }
        int56[] memory tickCumulatives_ = abi.decode(result_, (int56[]));

        unchecked {
            int24 exchangeRateTick_;
            {
                int56 tickCumulativesDelta_ = (tickCumulatives_[_TWAP_DELTAS_LENGTH + 1] -
                    tickCumulatives_[_TWAP_DELTAS_LENGTH]);
                // _UNI_TWAP4_INTERVAL can not be 0 because of constructor sanity checks
                exchangeRateTick_ = int24(tickCumulativesDelta_ / _UNI_TWAP4_INTERVAL);
                // Always round to negative infinity, see UniV3 OracleLibrary
                // https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L36
                if (tickCumulativesDelta_ < 0 && (tickCumulativesDelta_ % _UNI_TWAP4_INTERVAL != 0)) {
                    exchangeRateTick_--;
                }
            }

            // Check the latest Uniswap price is within the acceptable delta from each TWAP range
            // TWAP 1 check
            if (
                _isInvalidTWAPDelta(
                    int256(exchangeRateTick_),
                    tickCumulatives_[1] - tickCumulatives_[0],
                    _UNI_TWAP1_INTERVAL,
                    int256(_UNI_TWAP1_MAX_DELTA_PERCENT)
                )
            ) {
                return 0;
            }

            // TWAP 2 check
            if (
                _isInvalidTWAPDelta(
                    int256(exchangeRateTick_),
                    tickCumulatives_[2] - tickCumulatives_[1],
                    _UNI_TWAP2_INTERVAL,
                    int256(_UNI_TWAP2_MAX_DELTA_PERCENT)
                )
            ) {
                return 0;
            }

            // TWAP 3 check
            if (
                _isInvalidTWAPDelta(
                    int256(exchangeRateTick_),
                    tickCumulatives_[3] - tickCumulatives_[2],
                    _UNI_TWAP3_INTERVAL,
                    int256(_UNI_TWAP3_MAX_DELTA_PERCENT)
                )
            ) {
                return 0;
            }

            // get the current uniswap price, which is the last tick cumulatives interval, usually [..., 1, 0]
            exchangeRate_ = _getPriceFromSqrtPriceX96(TickMath.getSqrtRatioAtTick(exchangeRateTick_));
            if (_UNIV3_INVERT_RATE) {
                exchangeRate_ = _invertUniV3Price(exchangeRate_);
            }
        }
    }

    /// @dev verifies that `exchangeRate_` is within `maxDelta_` for derived price from `tickCumulativesDelta_` and `interval_`.
    /// returns true if delta is invalid
    function _isInvalidTWAPDelta(
        int256 exchangeRateTick_,
        int256 tickCumulativesDelta_,
        int256 interval_, // can not be 0 because of constructor sanity checks
        int256 maxDelta_
    ) internal pure returns (bool) {
        unchecked {
            int256 arithmeticMeanTick_ = int256(tickCumulativesDelta_ / interval_);
            // Always round to negative infinity, see UniV3 OracleLibrary
            // https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L36
            if (tickCumulativesDelta_ < 0 && (tickCumulativesDelta_ % interval_ != 0)) {
                arithmeticMeanTick_--;
            }

            // Check that the uniswapPrice is within DELTA of the Uniswap TWAP (via tick)
            // each univ3 tick is 0.01% increase or decrease in price. `maxDelta_` has near to same precision.
            // Note: near to the same because each Uniswap tick is 0.01% away so price of ticks are if current one is 100 then next will be:
            // 100 + 100 * 0.01% = 100.01
            // 100.01 + 100.01 * 0.01% = 100.020001
            if (
                exchangeRateTick_ > (arithmeticMeanTick_ + maxDelta_) ||
                exchangeRateTick_ < (arithmeticMeanTick_ - maxDelta_)
            ) {
                // Uniswap last price is NOT within the delta
                return true;
            }
        }
        return false;
    }

    /// @notice returns all UniV3 oracle related data as utility for easy off-chain use / block explorer in a single view method
    function uniV3OracleData()
        public
        view
        returns (
            IUniswapV3Pool uniV3Pool_,
            bool uniV3InvertRate_,
            uint32[] memory uniV3secondsAgos_,
            uint256[] memory uniV3TwapDeltas_,
            uint256 uniV3exchangeRateUnsafe_,
            uint256 uniV3exchangeRate_
        )
    {
        // Get the latest TWAP prices from the Uniswap Oracle for second intervals
        uniV3secondsAgos_ = new uint32[](_SECONDS_AGOS_LENGTH);
        uniV3secondsAgos_[0] = uint32(_UNI_SECONDS_AGO_1);
        uniV3secondsAgos_[1] = uint32(_UNI_SECONDS_AGO_2);
        uniV3secondsAgos_[2] = uint32(_UNI_SECONDS_AGO_3);
        uniV3secondsAgos_[3] = uint32(_UNI_SECONDS_AGO_4);
        uniV3secondsAgos_[4] = uint32(_UNI_SECONDS_AGO_5);

        // Check the latest Uniswap price is within the acceptable delta from each TWAP range
        uniV3TwapDeltas_ = new uint256[](_TWAP_DELTAS_LENGTH);
        uniV3TwapDeltas_[0] = _UNI_TWAP1_MAX_DELTA_PERCENT;
        uniV3TwapDeltas_[1] = _UNI_TWAP2_MAX_DELTA_PERCENT;
        uniV3TwapDeltas_[2] = _UNI_TWAP3_MAX_DELTA_PERCENT;

        return (
            _POOL,
            _UNIV3_INVERT_RATE,
            uniV3secondsAgos_,
            uniV3TwapDeltas_,
            _getUniV3ExchangeRateUnsafe(),
            _getUniV3ExchangeRate()
        );
    }

    /// @dev                  Get the price from the sqrt price in `OracleUtils.RATE_OUTPUT_DECIMALS`
    ///                       (see https://blog.uniswap.org/uniswap-v3-math-primer)
    /// @param sqrtPriceX96_  The sqrt price to convert
    function _getPriceFromSqrtPriceX96(uint160 sqrtPriceX96_) private view returns (uint256 priceX96_) {
        return
            FullMath.mulDiv(
                uint256(sqrtPriceX96_) * uint256(sqrtPriceX96_),
                _UNIV3_PRICE_SCALER_MULTIPLIER,
                1 << 192 // 2^96 * 2
            );
    }

    /// @dev                     Invert the price
    /// @param price_            The price to invert
    /// @return invertedPrice_   The inverted price in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _invertUniV3Price(uint256 price_) private view returns (uint256 invertedPrice_) {
        return _UNIV3_INVERT_PRICE_DIVIDEND / price_;
    }
}
