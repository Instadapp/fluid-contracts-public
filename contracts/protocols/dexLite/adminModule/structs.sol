// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "../other/commonImport.sol";

struct InitializeParams {
    DexKey dexKey;
    uint256 fee;
    uint256 revenueCut;
    bool rebalancingStatus;
    uint256 centerPrice;
    uint256 centerPriceContract; // nonce
    uint256 upperPercent;
    uint256 lowerPercent;
    uint256 upperShiftThreshold;
    uint256 lowerShiftThreshold;
    uint256 shiftTime; // in seconds // for rebalancing
    uint256 minCenterPrice;
    uint256 maxCenterPrice;
    uint256 token0Amount;
    uint256 token1Amount;
}

struct InitializeVariables {
    bytes8 dexId;
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
}