// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { FluidCHRStockOracle } from "./main.sol";
import { FluidSequencerL2 } from "../../common/sequencerL2.sol";

/// @title FluidCHRStockOracleL2
/// @notice L2 variant of `FluidCHRStockOracle`: guarded reads, `getExchangeRate()` and `updateRegularHoursAnchor()`
///         also require the L2 sequencer to be up and its grace period passed.
contract FluidCHRStockOracleL2 is FluidCHRStockOracle, FluidSequencerL2 {
    constructor(
        CHRStockOracleConstructorParams memory p_,
        address sequencerUptimeFeed_
    ) FluidCHRStockOracle(p_) FluidSequencerL2(sequencerUptimeFeed_) {}

    function _beforeGuardedPriceRead() internal view override {
        _ensureSequencerUpAndValid();
    }
}
