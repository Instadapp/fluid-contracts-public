// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { FluidOracleL2 } from "../fluidOracleL2.sol";
import { PegOracle } from "../oracles/pegOracle.sol";

/// @title Peg oracle that returns price for pegged assets on a layer 2
/// @notice  This contract is used to get the exchange rate between pegged assets like sUSDE / USDC or USDE / USDC.
///          Price is adjusted for token decimals and optionally a IERC4626 source feed can be set (e.g. for sUSDE or sUSDS).
contract PegOracleL2 is FluidOracleL2, PegOracle {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        uint8 colTokenDecimals_,
        uint8 debtTokenDecimals_,
        IERC4626 erc4626Feed_,
        address sequencerUptimeFeed_
    )
        PegOracle(infoName_, targetDecimals_, colTokenDecimals_, debtTokenDecimals_, erc4626Feed_)
        FluidOracleL2(sequencerUptimeFeed_)
    {}

    /// @inheritdoc FluidOracleL2
    function getExchangeRateOperate() public view override(PegOracle, FluidOracleL2) returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRateLiquidate() public view override(PegOracle, FluidOracleL2) returns (uint256 exchangeRate_) {
        _ensureSequencerUpAndValid();
        return super.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracleL2
    function getExchangeRate() public view override(PegOracle, FluidOracleL2) returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
