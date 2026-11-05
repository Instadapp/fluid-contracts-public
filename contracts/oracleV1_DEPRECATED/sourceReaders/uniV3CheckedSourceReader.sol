// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UniV3CheckCLRSOracle } from "../oracles/uniV3CheckCLRSOracle.sol";

abstract contract UniV3CheckedSourceReader is UniV3CheckCLRSOracle {
    constructor(
        string memory infoName_,
        uint8 targetDecimals_,
        UniV3CheckCLRSConstructorParams memory params_
    ) UniV3CheckCLRSOracle(infoName_, targetDecimals_, params_) {}

    function _readUniV3CheckedSource(bool isOperate_) internal view returns (uint256 rate_) {
        if (isOperate_) {
            return super.getExchangeRateOperate();
        } else {
            return super.getExchangeRateLiquidate();
        }
    }
}
