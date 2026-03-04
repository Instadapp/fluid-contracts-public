// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FluidCenterPrice } from "../fluidCenterPrice.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error as OracleError } from "../error.sol";

/// @title returns the inverted center price from an existing FluidCappedRate
/// @dev used when there are 2 dexes for the same token where it is once token0 and for the other dex token1
/// e.g. when both LBTC / CBBTC and WBTC / LBTC dexes exist, the center price must once be BTC per LBTC and once
/// it must be LBTC per BTC.
contract FluidCappedRateInvertCenterPrice is FluidCenterPrice {
    /// @notice external exchange rate source contract FluidCappedRate
    address public immutable FLUID_CAPPED_RATE;

    constructor(string memory infoName_, address fluidCappedRate_) FluidCenterPrice(infoName_) {
        if (fluidCappedRate_ == address(0)) {
            revert FluidOracleError(ErrorTypes.CenterPrice__InvalidParams);
        }
        FLUID_CAPPED_RATE = fluidCappedRate_;
    }

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external override returns (uint256 price_) {
        return 1e54 / FluidCenterPrice(FLUID_CAPPED_RATE).centerPrice();
    }
}
