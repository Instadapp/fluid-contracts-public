// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWeETHsAccountant } from "../interfaces/external/IWeETHsAccountant.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";
import { OracleUtils } from "../libraries/oracleUtils.sol";

/// @title   weETHs Oracle Implementation
/// @notice  This contract is used to get the exchange rate between weETHs and ETH
abstract contract WeETHsOracleImpl is OracleError {
    /// @notice constant value for price scaling to reduce gas usage
    uint256 internal immutable _WEETHS_PRICE_SCALER_MULTIPLIER;

    /// @notice WEETHS contract accountant, e.g. on mainnet 0xbe16605B22a7faCEf247363312121670DFe5afBE
    IWeETHsAccountant internal immutable _WEETHS_ACCOUNTANT;

    /// @notice constructor sets the weETHs (Symbiotic Etherfi's wrapped eETH) `weETHs_` token address.
    constructor(IWeETHsAccountant weETHsAccountant_, address pricedAsset_) {
        if (address(weETHsAccountant_) == address(0)) {
            revert FluidOracleError(ErrorTypes.WeETHsOracle__InvalidParams);
        }
        if (weETHsAccountant_.vault() != pricedAsset_) {
            // sanity check to make sure no human error in passing in the correct accountant address
            revert FluidOracleError(ErrorTypes.WeETHsOracle__InvalidParams);
        }

        _WEETHS_ACCOUNTANT = weETHsAccountant_;

        _WEETHS_PRICE_SCALER_MULTIPLIER = 10 ** (OracleUtils.RATE_OUTPUT_DECIMALS - 18); // e.g. 1e9
    }

    /// @dev            Get the exchange rate for operate() for the weETHs contract.
    ///                 reverts if the accountant contract is paused.
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getWeETHsExchangeRateOperate() internal view returns (uint256 rate_) {
        return _WEETHS_ACCOUNTANT.getRateSafe() * _WEETHS_PRICE_SCALER_MULTIPLIER;
    }

    /// @dev            Get the exchange rate for liquidate() for the weETHs contract
    /// @return rate_   The exchange rate in `OracleUtils.RATE_OUTPUT_DECIMALS`
    function _getWeETHsExchangeRateLiquidate() internal view returns (uint256 rate_) {
        return _WEETHS_ACCOUNTANT.getRate() * _WEETHS_PRICE_SCALER_MULTIPLIER;
    }

    /// @notice returns all weETHs oracle related data as utility for easy off-chain use / block explorer in a single view method
    function weETHsOracleData()
        public
        view
        returns (
            uint256 weETHsExchangeRateOperate_,
            bool operateRateReverts_,
            uint256 weETHsExchangeRateLiquidate_,
            IWeETHsAccountant weETHsAccountant_
        )
    {
        try _WEETHS_ACCOUNTANT.getRateSafe() returns (uint256) {
            weETHsExchangeRateOperate_ = _getWeETHsExchangeRateOperate();
        } catch {
            operateRateReverts_ = true;
        }
        weETHsAccountant_ = _WEETHS_ACCOUNTANT;
        weETHsExchangeRateLiquidate_ = _getWeETHsExchangeRateLiquidate();
    }
}
