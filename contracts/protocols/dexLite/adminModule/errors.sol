// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./structs.sol";

error InvalidParams();
error OnlyDelegateCallAllowed();
error AddressNotAContract(address addr);
error InvalidTokenOrder(address token0, address token1);
error DexNotInitialized(bytes32 dexId);
error DexAlreadyInitialized(bytes32 dexId);
error InvalidRevenueCut(uint256 revenueCut);
error InsufficientMsgValue(uint256 msgValue, uint256 requiredAmount);
error SlippageLimitExceeded(uint256 price, uint256 priceMax, uint256 priceMin);