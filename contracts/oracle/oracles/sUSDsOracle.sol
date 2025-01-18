// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { FluidOracle } from "../fluidOracle.sol";
import { SUSDsOracleImpl } from "../implementations/sUSDsOracleImpl.sol";

/// @title   SUSDsOracle
/// @notice  Gets the exchange rate between sUSDs and USDs directly from the sUSDs contract, adjusted for decimals
///          of a debt token (get amount of debt token for 1 sUSDs).
contract SUSDsOracle is FluidOracle, SUSDsOracleImpl {
    /// @notice constructor sets the sUSDs `sUSDs_` token address and calculates scaling for exchange rate based on
    /// `debtTokenDecimals_` (token decimals of debt token, e.g. of USDC / USDT = 6)
    constructor(
        string memory infoName_,
        IERC4626 sUSDs_,
        uint8 debtTokenDecimals_
    ) SUSDsOracleImpl(sUSDs_, debtTokenDecimals_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        return _getSUSDsExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        return _getSUSDsExchangeRate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return _getSUSDsExchangeRate();
    }
}
