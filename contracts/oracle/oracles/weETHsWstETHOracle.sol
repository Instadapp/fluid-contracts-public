// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidOracle } from "../fluidOracle.sol";
import { WstETHOracleImpl } from "../implementations/wstETHOracleImpl.sol";
import { WeETHsOracleImpl } from "../implementations/weETHsOracleImpl.sol";
import { IWstETH } from "../interfaces/external/IWstETH.sol";
import { IWeETHsAccountant } from "../interfaces/external/IWeETHsAccountant.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   Oracle for weETHs (Symbiotic Etherfi's wrapped eETH) to wstETH.
///          wstETH is the debt token here (get amount of wstETH for 1 weETHs)
contract WeETHsWstETHOracle is FluidOracle, WstETHOracleImpl, WeETHsOracleImpl {
    /// @param infoName_         Oracle identify helper name.
    /// @param wstETH_           address of the wstETH contract
    /// @param weETHsAccountant_ address of the weETHs accountant contract
    /// @param weETHs_           address of the weETHs token vault contract
    constructor(
        string memory infoName_,
        IWstETH wstETH_,
        IWeETHsAccountant weETHsAccountant_,
        address weETHs_
    ) WstETHOracleImpl(wstETH_) WeETHsOracleImpl(weETHsAccountant_, weETHs_) FluidOracle(infoName_) {}

    /// @inheritdoc FluidOracle
    function getExchangeRateOperate() public view override returns (uint256 exchangeRate_) {
        // weEths -> wstETH
        exchangeRate_ =
            (_WEETHS_ACCOUNTANT.getRateSafe() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) /
            _WSTETH.stEthPerToken();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRateLiquidate() external view override returns (uint256 exchangeRate_) {
        // weEths -> wstETH
        exchangeRate_ =
            (_WEETHS_ACCOUNTANT.getRate() * (10 ** OracleUtils.RATE_OUTPUT_DECIMALS)) /
            _WSTETH.stEthPerToken();
    }

    /// @inheritdoc FluidOracle
    function getExchangeRate() external view override returns (uint256 exchangeRate_) {
        return getExchangeRateOperate();
    }
}
