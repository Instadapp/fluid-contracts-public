// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { ChainlinkRateRead } from "../chainlinkRateRead.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

/// @notice Rate source that returns token amount for a given ASBNB amount.
interface IAsBnbRateSource {
    /// @param asBnbAmt ASBNB amount (e.g. 1e27)
    /// @return Token amount for the given ASBNB amount
    function convertToTokens(uint256 asBnbAmt) external view returns (uint256);
}

abstract contract AsBnbChainlinkCappedRateVariables {
    /// @notice external Chainlink rate source contract.
    address public immutable CHAINLINK_RATE_SOURCE;

    /// @notice Multiplier applied to the Chainlink rate after reading from latestRoundData.
    uint256 public immutable CHAINLINK_RATE_MULTIPLIER;

    constructor(address chainlinkRateSource_, uint256 chainlinkRateMultiplier_) {
        CHAINLINK_RATE_SOURCE = chainlinkRateSource_;
        CHAINLINK_RATE_MULTIPLIER = chainlinkRateMultiplier_;
    }
}

/// @notice Capped exchange rate for ASBNB -> (convertToTokens) -> Chainlink -> BNB.
///
/// @dev Rate source uses convertToTokens(uint256 asBnbAmt) instead of ERC4626 convertToAssets.
contract FluidASBNBCappedRate is AsBnbChainlinkCappedRateVariables, FluidCappedRate {
    /// @notice Initializes the capped rate with ASBNB rate source (convertToTokens) and Chainlink.
    /// @param params_ CappedRateConstructorParams; rateSource must implement convertToTokens(uint256). rateMultiplier must be 1.
    /// @param chainlinkRateSource_ Chainlink aggregator address.
    /// @param chainlinkRateMultiplier_ Multiplier to scale Chainlink rate to 1e27.
    constructor(
        FluidCappedRate.CappedRateConstructorParams memory params_,
        address chainlinkRateSource_,
        uint256 chainlinkRateMultiplier_
    )
        validAddress(chainlinkRateSource_)
        AsBnbChainlinkCappedRateVariables(chainlinkRateSource_, chainlinkRateMultiplier_)
        FluidCappedRate(params_)
    {
        if (_RATE_MULTIPLIER != 1 || chainlinkRateMultiplier_ == 0 || chainlinkRateMultiplier_ > 1e21) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        uint256 clRate_ = ChainlinkRateRead.positiveRateFromLatestRound(CHAINLINK_RATE_SOURCE);
        exchangeRate_ =
            (IAsBnbRateSource(_RATE_SOURCE).convertToTokens(1e27) * (clRate_ * CHAINLINK_RATE_MULTIPLIER)) /
            1e27;
    }
}
