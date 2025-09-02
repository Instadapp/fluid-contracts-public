// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { Structs as AdminModuleStructs } from "../../../liquidity/adminModule/structs.sol";

abstract contract Structs {
    struct RateData {
        uint256 version;
        AdminModuleStructs.RateDataV1Params rateDataV1;
        AdminModuleStructs.RateDataV2Params rateDataV2;
    }

    struct OverallTokenData {
        uint256 borrowRate;
        uint256 supplyRate;
        uint256 fee; // revenue fee
        uint256 lastStoredUtilization;
        uint256 storageUpdateThreshold;
        uint256 lastUpdateTimestamp;
        uint256 supplyExchangePrice;
        uint256 borrowExchangePrice;
        uint256 supplyRawInterest;
        uint256 supplyInterestFree;
        uint256 borrowRawInterest;
        uint256 borrowInterestFree;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 revenue;
        uint256 maxUtilization; // maximum allowed utilization
        RateData rateData;
    }

    // amounts are always in normal (for withInterest already multiplied with exchange price)
    struct UserSupplyData {
        bool modeWithInterest; // true if mode = with interest, false = without interest
        uint256 supply; // user supply amount
        // the withdrawal limit (e.g. if 10% is the limit, and 100M is supplied, it would be 90M)
        uint256 withdrawalLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent; // withdrawal limit expand percent in 1e2
        uint256 expandDuration; // withdrawal limit expand duration in seconds
        uint256 baseWithdrawalLimit;
        // the current actual max withdrawable amount (e.g. if 10% is the limit, and 100M is supplied, it would be 10M)
        uint256 withdrawableUntilLimit;
        uint256 withdrawable; // actual currently withdrawable amount (supply - withdrawal Limit) & considering balance
    }

    // amounts are always in normal (for withInterest already multiplied with exchange price)
    struct UserBorrowData {
        bool modeWithInterest; // true if mode = with interest, false = without interest
        uint256 borrow; // user borrow amount
        uint256 borrowLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseBorrowLimit;
        uint256 maxBorrowLimit;
        uint256 borrowableUntilLimit; // borrowable amount until any borrow limit (incl. max utilization limit)
        uint256 borrowable; // actual currently borrowable amount (borrow limit - already borrowed) & considering balance, max utilization
        uint256 borrowLimitUtilization; // borrow limit for `maxUtilization`
    }
}
