// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import "../other/commonImport.sol";

// --- Custom Errors ---
error EstimateSwap(uint256 amountUnspecified);
error AmountLimitExceeded(uint256 amountUnspecified, uint256 amountLimit);
error AmountLimitNotMet(uint256 amountUnspecified, uint256 amountLimit);
error EmptyDexKeysArray();
error InvalidPathLength(uint256 pathLength, uint256 dexKeysLength);
error InvalidAmountLimitsLength(uint256 dexKeysLength, uint256 amountLimitsLength);
error InvalidPathTokenOrder();
error UnauthorizedCaller(address caller);
error DexNotInitialized(bytes32 dexId);
error AdjustedSupplyOverflow(bytes32 dexId, uint256 token0AdjustedSupply, uint256 token1AdjustedSupply);
error ZeroAddress();
error InvalidPower(uint256 power);
error InvalidSwapAmounts(uint256 adjustedAmount);
error ExcessiveSwapAmount(uint256 adjustedAmount, uint256 imaginaryReserve);
error TokenReservesTooLow(uint256 adjustedAmount, uint256 realReserve);
error TokenReservesRatioTooHigh(uint256 token0RealReserve, uint256 token1RealReserve);
error InvalidMsgValue();
error InsufficientNativeTokenReceived(uint256 receivedAmount, uint256 requiredAmount);
error InsufficientERC20Received(uint256 receivedAmount, uint256 requiredAmount);
error DelegateCallFailed();