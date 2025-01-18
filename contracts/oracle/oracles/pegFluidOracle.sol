// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "../interfaces/iFluidOracle.sol";
import { FluidOracle } from "../fluidOracle.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title Peg oracle for pegged assets with an existing Fluid Oracle (e.g. Fluid ContractRate)
/// @notice  This contract is used to get the exchange rate between pegged assets like WEETH / WSTETH or RSETH / WSTETH.
///          Price is adjusted for token decimals and optionally a Fluid oracle source feed can be set (e.g. Fluid ContractRate).
///          e.g. for RSETH / WSTETH: RSETH contract rate / WSTETH contract rate
contract PegFluidOracle is FluidOracle {
    IFluidOracle internal immutable _COL_FLUID_ORACLE;
    IFluidOracle internal immutable _DEBT_FLUID_ORACLE;

    constructor(
        string memory infoName_,
        IFluidOracle colFluidOracle_,
        IFluidOracle debtFluidOracle_
    ) FluidOracle(infoName_) {
        if (address(colFluidOracle_) == address(0) || address(debtFluidOracle_) == address(0)) {
            revert FluidOracleError(ErrorTypes.PegOracle__InvalidParams);
        }

        _COL_FLUID_ORACLE = colFluidOracle_;
        _DEBT_FLUID_ORACLE = debtFluidOracle_;
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        // e.g. weEth -> wstETH
        exchangeRate_ =
            (_COL_FLUID_ORACLE.getExchangeRateOperate() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) /
            _DEBT_FLUID_ORACLE.getExchangeRateOperate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        // e.g. weEth -> wstETH
        exchangeRate_ =
            (_COL_FLUID_ORACLE.getExchangeRateLiquidate() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) /
            _DEBT_FLUID_ORACLE.getExchangeRateLiquidate();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }

    /// @notice returns the configured col and debt fluid oracles
    function pegFluidOracleData() public view returns (IFluidOracle colFluidOracle_, IFluidOracle debtFluidOracle_) {
        return (_COL_FLUID_ORACLE, _DEBT_FLUID_ORACLE);
    }
}
