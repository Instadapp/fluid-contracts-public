// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IChainlinkAggregatorV3 } from "../interfaces/external/IChainlinkAggregatorV3.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract ERC4626ChainlinkCappedRateVariables {
    /// @notice external Chainlink rate source contract.
    address public immutable CHAINLINK_RATE_SOURCE;

    /// @notice Multiplier applied to the Chainlink rate after reading from latestRoundData.
    uint256 public immutable CHAINLINK_RATE_MULTIPLIER;

    constructor(address chainlinkRateSource_, uint256 chainlinkRateMultiplier_) {
        CHAINLINK_RATE_SOURCE = chainlinkRateSource_;
        CHAINLINK_RATE_MULTIPLIER = chainlinkRateMultiplier_;
    }
}

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a ERC4626 and Chainlink sources Oracle.
///
/// @dev e.g. ASBNB -> SLISBNB -> BNB
contract FluidERC4626ChainlinkCappedRate is ERC4626ChainlinkCappedRateVariables, FluidCappedRate {
    /// @notice Initializes the capped rate contract with Chainlink and ERC4626 rate sources.
    /// @param params_ CappedRateConstructorParams, the source applies to the ERC4626 rate source.
    ///                The normal rate multiplier in params_ must be set to 1.
    /// @param chainlinkRateSource_ Address for the Chainlink rate source.
    /// @param chainlinkRateMultiplier_ Multiplier to apply to the Chainlink rate to scale it to 1e27 decimals
    constructor(
        FluidCappedRate.CappedRateConstructorParams memory params_,
        address chainlinkRateSource_,
        uint256 chainlinkRateMultiplier_
    )
        validAddress(chainlinkRateSource_)
        ERC4626ChainlinkCappedRateVariables(chainlinkRateSource_, chainlinkRateMultiplier_)
        FluidCappedRate(params_)
    {
        if (_RATE_MULTIPLIER != 1 || chainlinkRateMultiplier_ == 0 || chainlinkRateMultiplier_ > 1e21) {
            revert FluidOracleError(ErrorTypes.CappedRate__InvalidParams);
        }
    }

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        (, int256 clRate_, , , ) = IChainlinkAggregatorV3(CHAINLINK_RATE_SOURCE).latestRoundData();
        exchangeRate_ =
            (IERC4626(_RATE_SOURCE).convertToAssets(1e27) * (uint256(clRate_) * CHAINLINK_RATE_MULTIPLIER)) /
            1e27;
    }
}
