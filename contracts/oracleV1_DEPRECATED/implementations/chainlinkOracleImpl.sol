// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ErrorTypes } from "../errorTypes.sol";
import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";
import { ChainlinkStructs } from "./structs.sol";

/// @title   Chainlink Oracle implementation
/// @notice  This contract is used to get the exchange rate via up to 3 hops at Chainlink price feeds.
///          The rate is multiplied with the previous rate at each hop.
///          E.g. to go from wBTC to USDC (assuming rates for example):
///          1. wBTC -> BTC https://data.chain.link/ethereum/mainnet/crypto-other/wbtc-btc, rate: 0.92.
///          2. BTC -> USD https://data.chain.link/ethereum/mainnet/crypto-usd/btc-usd rate: 30,000.
///          3. USD -> USDC https://data.chain.link/ethereum/mainnet/stablecoins/usdc-usd rate: 0.98. Must invert feed: 1.02
///          finale rate would be: 0.92 * 30,000 * 1.02 = 28,152
abstract contract ChainlinkOracleImpl is OracleError, ChainlinkStructs {
    /// @notice Chainlink price feed 1 to check for the exchange rate
    IChainlinkAggregatorV3 internal immutable _CHAINLINK_FEED1;
    /// @notice Chainlink price feed 2 to check for the exchange rate
    IChainlinkAggregatorV3 internal immutable _CHAINLINK_FEED2;
    /// @notice Chainlink price feed 3 to check for the exchange rate
    IChainlinkAggregatorV3 internal immutable _CHAINLINK_FEED3;

    /// @notice Flag to invert the price or not for feed 1 (to e.g. for WETH/USDC pool return prive of USDC per 1 WETH)
    bool internal immutable _CHAINLINK_INVERT_RATE1;
    /// @notice Flag to invert the price or not for feed 2 (to e.g. for WETH/USDC pool return prive of USDC per 1 WETH)
    bool internal immutable _CHAINLINK_INVERT_RATE2;
    /// @notice Flag to invert the price or not for feed 3 (to e.g. for WETH/USDC pool return prive of USDC per 1 WETH)
    bool internal immutable _CHAINLINK_INVERT_RATE3;

    /// @notice constant value for price scaling to reduce gas usage for feed 1
    uint256 internal immutable _CHAINLINK_PRICE_SCALER_MULTIPLIER1;
    /// @notice constant value for inverting price to reduce gas usage for feed 1
    uint256 internal immutable _CHAINLINK_INVERT_PRICE_DIVIDEND1;

    /// @notice constant value for price scaling to reduce gas usage for feed 2
    uint256 internal immutable _CHAINLINK_PRICE_SCALER_MULTIPLIER2;
    /// @notice constant value for inverting price to reduce gas usage for feed 2
    uint256 internal immutable _CHAINLINK_INVERT_PRICE_DIVIDEND2;

    /// @notice constant value for price scaling to reduce gas usage for feed 3
    uint256 internal immutable _CHAINLINK_PRICE_SCALER_MULTIPLIER3;
    /// @notice constant value for inverting price to reduce gas usage for feed 3
    uint256 internal immutable _CHAINLINK_INVERT_PRICE_DIVIDEND3;

    /// @notice constructor sets the Chainlink price feed and invertRate flag for each hop.
    /// E.g. `invertRate_` should be true if for the USDC/ETH pool it's expected that the oracle returns USDC per 1 ETH
    constructor(ChainlinkConstructorParams memory params_) {
        if (
            (params_.hops < 1 || params_.hops > 3) || // hops must be 1, 2 or 3
            (address(params_.feed1.feed) == address(0) || params_.feed1.token0Decimals == 0) || // first feed must always be defined
            (params_.hops > 1 && (address(params_.feed2.feed) == address(0) || params_.feed2.token0Decimals == 0)) || // if hops > 1, feed 2 must be defined
            (params_.hops > 2 && (address(params_.feed3.feed) == address(0) || params_.feed3.token0Decimals == 0)) // if hops > 2, feed 3 must be defined
        ) {
            revert FluidOracleError(ErrorTypes.ChainlinkOracle__InvalidParams);
        }

        _CHAINLINK_FEED1 = params_.feed1.feed;
        _CHAINLINK_FEED2 = params_.feed2.feed;
        _CHAINLINK_FEED3 = params_.feed3.feed;

        _CHAINLINK_INVERT_RATE1 = params_.feed1.invertRate;
        _CHAINLINK_INVERT_RATE2 = params_.feed2.invertRate;
        _CHAINLINK_INVERT_RATE3 = params_.feed3.invertRate;

        // Actual desired output rate example USDC/ETH (6 decimals / 18 decimals).
        // Note ETH has 12 decimals more than USDC.
        //    0.000515525322211842331991619857165357691 // 39 decimals.  ETH for 1 USDC
        // 1954.190000000000433             // 15 decimals. USDC for 1 ETH

        // to get to PRICE_SCLAER_MULTIPLIER and INVERT_PRICE_DIVIDEND:
        // fetched Chainlink price is in token1Decimals per 1 token0Decimals.
        // E.g. for an USDC/ETH price feed it's in ETH 18 decimals.
        //      for an  BTC/USD price feed it's in USD  8 decimals.
        // So to scale to 1e27 we need to multiply by 1e27 - token0Decimals.
        // E.g. for USDC/ETH it would be: fetchedPrice * 1e21
        //
        // or for inverted (x token0 per 1 token1), formula would be:
        //    = 1e27 * 10**token0Decimals / fetchedPrice
        // E.g. for USDC/ETH it would be: 1e33 / fetchedPrice

        // no support for token1Decimals with more than OracleUtils.RATE_OUTPUT_DECIMALS decimals for now as extremely unlikely case
        _CHAINLINK_PRICE_SCALER_MULTIPLIER1 = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - params_.feed1.token0Decimals);
        _CHAINLINK_INVERT_PRICE_DIVIDEND1 = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + params_.feed1.token0Decimals);

        _CHAINLINK_PRICE_SCALER_MULTIPLIER2 = params_.hops > 1
            ? 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - params_.feed2.token0Decimals)
            : 1;
        _CHAINLINK_INVERT_PRICE_DIVIDEND2 = params_.hops > 1
            ? 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + params_.feed2.token0Decimals)
            : 1;

        _CHAINLINK_PRICE_SCALER_MULTIPLIER3 = params_.hops > 2
            ? 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - params_.feed3.token0Decimals)
            : 1;
        _CHAINLINK_INVERT_PRICE_DIVIDEND3 = params_.hops > 2
            ? 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS + params_.feed3.token0Decimals)
            : 1;
    }

    /// @dev            Get the exchange rate from Chainlike oracle price feed(s)
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getChainlinkExchangeRate() internal view returns (uint256 rate_) {
        rate_ = _readFeedRate(
            _CHAINLINK_FEED1,
            _CHAINLINK_INVERT_RATE1,
            _CHAINLINK_PRICE_SCALER_MULTIPLIER1,
            _CHAINLINK_INVERT_PRICE_DIVIDEND1
        );
        if (rate_ == 0 || address(_CHAINLINK_FEED2) == address(0)) {
            // rate 0 or only 1 hop -> return rate of price feed 1
            return rate_;
        }
        rate_ =
            (rate_ *
                _readFeedRate(
                    _CHAINLINK_FEED2,
                    _CHAINLINK_INVERT_RATE2,
                    _CHAINLINK_PRICE_SCALER_MULTIPLIER2,
                    _CHAINLINK_INVERT_PRICE_DIVIDEND2
                )) /
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);

        if (rate_ == 0 || address(_CHAINLINK_FEED3) == address(0)) {
            // rate 0 or 2 hops -> return rate of feed 1 combined with feed 2
            return rate_;
        }

        // 3 hops -> return rate of feed 1 combined with feed 2 & feed 3
        rate_ =
            (rate_ *
                _readFeedRate(
                    _CHAINLINK_FEED3,
                    _CHAINLINK_INVERT_RATE3,
                    _CHAINLINK_PRICE_SCALER_MULTIPLIER3,
                    _CHAINLINK_INVERT_PRICE_DIVIDEND3
                )) /
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @dev reads the exchange `rate_` from a Chainlink price `feed_` taking into account scaling and `invertRate_`
    function _readFeedRate(
        IChainlinkAggregatorV3 feed_,
        bool invertRate_,
        uint256 priceMultiplier_,
        uint256 invertDividend_
    ) private view returns (uint256 rate_) {
        try feed_.latestRoundData() returns (uint80, int256 exchangeRate_, uint256, uint256, uint80) {
            // Return the price in `OracleUtils.RATE_OUTPUT_DECIMALS`
            if (invertRate_) {
                return invertDividend_ / uint256(exchangeRate_);
            } else {
                return uint256(exchangeRate_) * priceMultiplier_;
            }
        } catch {
            return 0;
        }
    }

    /// @notice returns all Chainlink oracle related data as utility for easy off-chain use / block explorer in a single view method
    function chainlinkOracleData()
        public
        view
        returns (
            uint256 chainlinkExchangeRate_,
            IChainlinkAggregatorV3 chainlinkFeed1_,
            bool chainlinkInvertRate1_,
            uint256 chainlinkExchangeRate1_,
            IChainlinkAggregatorV3 chainlinkFeed2_,
            bool chainlinkInvertRate2_,
            uint256 chainlinkExchangeRate2_,
            IChainlinkAggregatorV3 chainlinkFeed3_,
            bool chainlinkInvertRate3_,
            uint256 chainlinkExchangeRate3_
        )
    {
        return (
            _getChainlinkExchangeRate(),
            _CHAINLINK_FEED1,
            _CHAINLINK_INVERT_RATE1,
            _readFeedRate(
                _CHAINLINK_FEED1,
                _CHAINLINK_INVERT_RATE1,
                _CHAINLINK_PRICE_SCALER_MULTIPLIER1,
                _CHAINLINK_INVERT_PRICE_DIVIDEND1
            ),
            _CHAINLINK_FEED2,
            _CHAINLINK_INVERT_RATE2,
            address(_CHAINLINK_FEED2) == address(0)
                ? 0
                : _readFeedRate(
                    _CHAINLINK_FEED2,
                    _CHAINLINK_INVERT_RATE2,
                    _CHAINLINK_PRICE_SCALER_MULTIPLIER2,
                    _CHAINLINK_INVERT_PRICE_DIVIDEND2
                ),
            _CHAINLINK_FEED3,
            _CHAINLINK_INVERT_RATE3,
            address(_CHAINLINK_FEED3) == address(0)
                ? 0
                : _readFeedRate(
                    _CHAINLINK_FEED3,
                    _CHAINLINK_INVERT_RATE3,
                    _CHAINLINK_PRICE_SCALER_MULTIPLIER3,
                    _CHAINLINK_INVERT_PRICE_DIVIDEND3
                )
        );
    }
}
