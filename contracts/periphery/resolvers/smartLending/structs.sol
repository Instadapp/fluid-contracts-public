// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Structs as DexResolverStructs } from "../dex/structs.sol";

abstract contract Structs {
    struct SmartLendingEntireData {
        // address of the smart lending
        address smartLending;
        // The name of the SmartLending token.
        string name;
        // The symbol of the SmartLending token.
        string symbol;
        // The number of decimal places for the SmartLending token.
        uint8 decimals;
        // The total supply of the SmartLending token.
        uint256 totalSupply;
        // total dex shares according to smart lending exchange rate
        uint256 totalUnderlyingShares;
        // total token0 amount built with dex token0PerSupplyShare. (!!) this is not set when calling the view method
        uint256 totalUnderlyingAssetsToken0;
        // total token1 amount built with dex token1PerSupplyShare. (!!) this is not set when calling the view method
        uint256 totalUnderlyingAssetsToken1;
        // The address of the first token in the underlying dex pool.
        address token0;
        // The address of the second token in the underlying dex pool.
        address token1;
        // The address of the underlying dex pool.
        address dex;
        // The last timestamp when the exchange price was updated in storage.
        uint256 lastTimestamp;
        // The fee or reward rate for the SmartLending. If positive then rewards, if negative then fee. 1e6 = 100%, 1e4 = 1%, minimum 0.0001% fee or reward.
        int256 feeOrReward;
        // The current exchange price of the SmartLending updated to block.timestamp.
        uint256 exchangePrice;
        // The address of the rebalancer.
        address rebalancer;
        // exchange rate for x assets per 1 underlying pool share
        uint256 assetsPerShare;
        // exchange rate for x underlying pool shares per 1 SmartLending asset (=exchangePrice)
        uint256 sharesPerAsset;
        // The difference in balance for rebalancing. difference between the total smart lending shares on the DEX and the total smart lending shares calculated.
        // A positive value indicates fees to collect, while a negative value indicates rewards to be rebalanced.
        uint256 rebalanceDiff;
        // structs fetched directly from DexResolver:
        DexResolverStructs.DexEntireData dexEntireData; // (!!) this is not set when calling the view method
        DexResolverStructs.UserSupplyData dexUserSupplyData; // supply data of the SmartLending at the dex
    }

    struct UserPosition {
        address user;
        uint256 smartLendingAssets; // ERC20 smart lending assets that the user owns
        uint256 underlyingShares; // dex shares according to smart lending exchange rate
        uint256 underlyingAssetsToken0; // position token0 amount built with dex token0PerSupplyShare. (!!) this is not set when calling the view method
        uint256 underlyingAssetsToken1; // position token1 amount built with dex token1PerSupplyShare. (!!) this is not set when calling the view method
        uint256 underlyingBalanceToken0; // token0 user balance
        uint256 underlyingBalanceToken1; // token1 user balance
        uint256 allowanceToken0; // allowance of token0 for user to the smartLending
        uint256 allowanceToken1; // allowance of token1 for user to the smartLending
    }

    struct SmartLendingEntireDataUserPosition {
        SmartLendingEntireData smartLendingEntireData;
        UserPosition userPosition;
    }
}
