// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { FluidGenericOracleBase } from "./genericOracleBase.sol";

/// @notice generic configurable Oracle
/// combines up to 4 hops from sources such as
///  - an existing IFluidOracle (e.g. ContractRate)
///  - Redstone
///  - Chainlink
contract FluidGenericOracle is FluidOracle, FluidGenericOracleBase {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        OracleHopSource[] memory sources_
    ) FluidOracle(infoName_, targetDecimals_) FluidGenericOracleBase(sources_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(true);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view virtual override returns (uint256 exchangeRate_) {
        exchangeRate_ = _getHopsExchangeRate(false);
    }
}
