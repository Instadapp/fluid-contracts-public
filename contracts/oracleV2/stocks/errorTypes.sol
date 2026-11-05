// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

library ErrorTypes {
    /***********************************|
    |      US Equity Market Hours       |
    |__________________________________*/

    uint256 internal constant UsEquityMarketHours__InvalidParams = 310301;
    uint256 internal constant UsEquityMarketHours__PinnedSessionMutated = 310302;

    /***********************************|
    |         CLX Stock Oracle          |
    |__________________________________*/

    uint256 internal constant CLXStockOracle__InvalidParams = 310311;
    uint256 internal constant CLXStockOracle__StalePrice = 310312;
    uint256 internal constant CLXStockOracle__InvalidPrice = 310313;
    uint256 internal constant CLXStockOracle__StorageOverflow = 310314;
    uint256 internal constant CLXStockOracle__MultiplierNeedsConfirmation = 310315;
    uint256 internal constant CLXStockOracle__RegularHoursReferenceNotFound = 310316;
    uint256 internal constant CLXStockOracle__Paused = 310317;
    uint256 internal constant CLXStockOracle__ScheduledMultiplierPending = 310318;
    uint256 internal constant CLXStockOracle__PriceGapBreak = 310319;
    uint256 internal constant CLXStockOracle__OutsideExtendedHoursCap = 310320;

    /***********************************|
    |         CHR Stock Oracle          |
    |__________________________________*/

    uint256 internal constant CHRStockOracle__InvalidParams = 310331;
    uint256 internal constant CHRStockOracle__Paused = 310332;
    uint256 internal constant CHRStockOracle__RtokenPaused = 310333;
    uint256 internal constant CHRStockOracle__TradePaused = 310334;
    uint256 internal constant CHRStockOracle__MultiplierChanged = 310335;
    uint256 internal constant CHRStockOracle__InvalidPrice = 310336;
    uint256 internal constant CHRStockOracle__StalePrice = 310337;
    uint256 internal constant CHRStockOracle__PriceBreak = 310338;
    uint256 internal constant CHRStockOracle__OutsideCap = 310339;
    uint256 internal constant CHRStockOracle__LatchCauseActive = 310340;
}
