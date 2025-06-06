// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IVedaAccountant } from "../interfaces/external/IVedaAccountant.sol";
import { FluidCappedRate } from "../fluidCappedRate.sol";

/// @notice Stores gas optimized and safety up and/or down capped exchange rate for a VedaAccountant, e.g. WEETHS / ETH or EBTC / BTC rate.
///
/// @dev e.g. EBTC accountant contract; 0x1b293DC39F94157fA0D1D36d7e0090C8B8B8c13F
/// @dev e.g. WEETHS accountant contract; 0xbe16605B22a7faCEf247363312121670DFe5afBE
contract FluidVedaCappedRate is IVedaAccountant, FluidCappedRate {
    constructor(FluidCappedRate.CappedRateConstructorParams memory params_) FluidCappedRate(params_) {}

    function _getNewRateRaw() internal view virtual override returns (uint256 exchangeRate_) {
        // rate for EBTC is in 1e8 e.g. 100000000, for WEETHS in 1e18
        return IVedaAccountant(_RATE_SOURCE).getRate();
    }

    /// @inheritdoc IVedaAccountant
    function vault() external view override returns (address) {
        return IVedaAccountant(_RATE_SOURCE).vault();
    }

    /// @inheritdoc IVedaAccountant
    function getRate() external view override returns (uint256) {
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e8
    }

    /// @inheritdoc IVedaAccountant
    function getRateSafe() external view override returns (uint256) {
        IVedaAccountant(_RATE_SOURCE).getRateSafe(); // will revert if paused
        // return actual rate of this contract to keep equivalency with getRate() and other methods.
        return uint256(_slot0.rate) / _RATE_MULTIPLIER; // scale to 1e8
    }
}
