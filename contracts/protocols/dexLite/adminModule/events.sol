// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./errors.sol";

event LogUpdateAuth(address auth, bool isAuth);

event LogInitialize(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 centerPriceShift, InitializeParams i);

event LogUpdateFeeAndRevenueCut(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 fee, uint256 revenueCut);

event LogUpdateRebalancingStatus(DexKey dexKey, bytes8 dexId, uint256 dexVariables, bool rebalancingStatus);

event LogUpdateRangePercents(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 rangeShift, uint256 upperPercent, uint256 lowerPercent, uint256 shiftTime);

event LogUpdateShiftTime(DexKey dexKey, bytes8 dexId, uint256 centerPriceShift, uint256 shiftTime);

event LogUpdateCenterPriceLimits(DexKey dexKey, bytes8 dexId, uint256 centerPriceShift, uint256 maxCenterPrice, uint256 minCenterPrice);

event LogUpdateThresholdPercent(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 thresholdShift, uint256 upperThresholdPercent, uint256 lowerThresholdPercent, uint256 shiftTime);

event LogUpdateCenterPriceAddress(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 centerPriceShift, uint256 centerPriceContract, uint256 percent, uint256 time);

event LogDeposit(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 token0Amount, uint256 token1Amount);

event LogWithdraw(DexKey dexKey, bytes8 dexId, uint256 dexVariables, uint256 token0Amount, uint256 token1Amount);

event LogCollectRevenue(address[] tokens, uint256[] amounts, address to);

event LogUpdateExtraDataAddress(address extraDataAddress);
