// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { DexKey, TransferParams } from "../../../protocols/dexLite/other/structs.sol";

struct ConstantViews {
    address liquidity;
    address deployer;
}

struct Prices {
    uint256 poolPrice;
    uint256 centerPrice;
    uint256 upperRangePrice;
    uint256 lowerRangePrice;
    uint256 upperThresholdPrice;
    uint256 lowerThresholdPrice;
}

struct Reserves {
    uint256 token0RealReserves;
    uint256 token1RealReserves;
    uint256 token0ImaginaryReserves;
    uint256 token1ImaginaryReserves;
}

struct DexVariables {
    uint256 fee;
    uint256 revenueCut;
    uint256 rebalancingStatus;
    bool isCenterPriceShiftActive;
    uint256 centerPrice;
    address centerPriceAddress;
    bool isRangePercentShiftActive;
    uint256 upperRangePercent;
    uint256 lowerRangePercent;
    bool isThresholdPercentShiftActive;
    uint256 upperShiftThresholdPercent;
    uint256 lowerShiftThresholdPercent;
    uint256 token0Decimals;
    uint256 token1Decimals;
    uint256 totalToken0AdjustedAmount;
    uint256 totalToken1AdjustedAmount;
}

struct CenterPriceShift {
    uint256 lastInteractionTimestamp;
    // REBALANCING RELATED THINGS
    uint256 rebalancingShiftingTime;
    uint256 maxCenterPrice;
    uint256 minCenterPrice;
    // CENTER PRICE SHIFT RELATED THINGS
    uint256 shiftPercentage;
    uint256 centerPriceShiftingTime;
    uint256 startTimestamp;
}

struct RangeShift {
    uint256 oldUpperRangePercent;
    uint256 oldLowerRangePercent;
    uint256 shiftingTime;
    uint256 startTimestamp;
}

struct ThresholdShift {
    uint256 oldUpperThresholdPercent;
    uint256 oldLowerThresholdPercent;
    uint256 shiftingTime;
    uint256 startTimestamp;
}

struct DexState {
    DexVariables dexVariables;
    CenterPriceShift centerPriceShift;
    RangeShift rangeShift;
    ThresholdShift thresholdShift;
}

struct DexEntireData {
    bytes8 dexId;
    DexKey dexKey;
    ConstantViews constantViews;
    Prices prices;
    Reserves reserves;
    DexState dexState;
}