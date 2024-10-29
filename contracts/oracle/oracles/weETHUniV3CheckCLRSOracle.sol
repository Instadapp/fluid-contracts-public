// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { UniV3CheckCLRSOracle } from "./uniV3CheckCLRSOracle.sol";
import { WeETHOracleImpl } from "../implementations/weETHOracleImpl.sol";
import { IWeETH } from "../interfaces/external/IWeETH.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   weETHOracle combined with a uniV3CheckCLRSOracle.
/// @notice  Gets the exchange rate between the underlying asset and the peg asset by using:
///          1. weETH Oracle price for weETH -> eETH = ETH (pegged)
///          2. result from 1. combined with a uniV3CheckCLRSOracle to get someToken (e.g. ETH) -> someToken2.
///          e.g. when going from weETH to USDC:
///          1. weETH -> eETH = ETH via weETH Oracle
///          2. ETH -> USDC via UniV3 ETH <> USDC pool checked against ETH -> USDC Chainlink feed.
contract WeETHUniV3CheckCLRSOracle is FluidOracle, WeETHOracleImpl, UniV3CheckCLRSOracle {
    /// @notice                       constructs a WeETHUniV3CheckCLRSOracle with all inherited contracts
    /// @param infoName_         Oracle identify helper name.
    /// @param weETH_                address of the weETH contract
    /// @param uniV3CheckCLRSParams_ UniV3CheckCLRSOracle constructor params
    constructor(
        string memory infoName_,
        IWeETH weETH_,
        UniV3CheckCLRSConstructorParams memory uniV3CheckCLRSParams_
    ) WeETHOracleImpl(weETH_) UniV3CheckCLRSOracle(infoName_, uniV3CheckCLRSParams_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate()
        public
        view
        override(FluidOracle, UniV3CheckCLRSOracle)
        returns (uint256 exchangeRate_)
    {
        //    get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0.
        //    (super.getExchangeRate() returns UniV3CheckCLRSOracle rate, no other inherited contract has this.)
        //    Combine this rate with the weETH -> eETH = ETH rate.
        exchangeRate_ =
            (super.getExchangeRateOperate() * _getWeETHExchangeRate()) /
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate()
        public
        view
        override(FluidOracle, UniV3CheckCLRSOracle)
        returns (uint256 exchangeRate_)
    {
        //    get rate from UniV3Check Oracle (likely uniV3 / Chainlink checked against for delta). This always returns
        //    a price if some rate is valid, with multiple fallbacks. Can not return 0.
        //    (super.getExchangeRate() returns UniV3CheckCLRSOracle rate, no other inherited contract has this.)
        //    Combine this rate with the weETH -> eETH = ETH rate.
        exchangeRate_ =
            (super.getExchangeRateLiquidate() * _getWeETHExchangeRate()) /
            (10 ** OracleUtils.RATE_OUTPUT_DECIMALS);
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() public view override(FluidOracle, UniV3CheckCLRSOracle) returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
