// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidOracle } from "../fluidOracle.sol";
import { SUSDeOracleImpl } from "../implementations/sUSDeOracleImpl.sol";

/// @title   SUSDeOracle
/// @notice  Gets the exchange rate between sUSDe and USDe directly from the sUSDe contract, adjusted for decimals
///          of a debt token (get amount of debt token for 1 sUSDe).
contract SUSDeOracle is FluidOracle, SUSDeOracleImpl {
    /// @notice constructor sets the sUSDe `sUSDe_` token address and calculates scaling for exchange rate based on
    /// `debtTokenDecimals_` (token decimals of debt token, e.g. of USDC / USDT = 6)
    constructor(
        string memory infoName_,
        IERC4626 sUSDe_,
        uint8 debtTokenDecimals_
    ) SUSDeOracleImpl(sUSDe_, debtTokenDecimals_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        return _getSUSDeExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        return _getSUSDeExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return _getSUSDeExchangeRate();
    }
}
