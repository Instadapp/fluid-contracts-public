// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Dex Lite.
library DexLiteSlotsLink {
    /// @dev storage slot for is auth mapping
    uint256 internal constant DEX_LITE_IS_AUTH_SLOT = 0;
    /// @dev storage slot for dexes list
    uint256 internal constant DEX_LITE_DEXES_LIST_SLOT = 1;
    /// @dev storage slot for is dex variables
    uint256 internal constant DEX_LITE_DEX_VARIABLES_SLOT = 2;
    /// @dev storage slot for center price shift
    uint256 internal constant DEX_LITE_CENTER_PRICE_SHIFT_SLOT = 3;
    /// @dev storage slot for range shift
    uint256 internal constant DEX_LITE_RANGE_SHIFT_SLOT = 4;
    /// @dev storage slot for threshold shift
    uint256 internal constant DEX_LITE_THRESHOLD_SHIFT_SLOT = 5;

    // --------------------------------
    // @dev stacked uint256 storage slots bits position data for each:

    // DexVariables
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_FEE = 0;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT = 13;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS = 20;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE = 22;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE = 23;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS = 63;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE = 82;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT = 83;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT = 97;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE = 111;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT = 112;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT = 119;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS = 126;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS = 131;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED = 136;
    uint256 internal constant BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED = 196;

    // CenterPriceShift
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP = 0;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME = 33;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE = 57;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE = 85;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT = 113;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIME_TO_SHIFT = 133;
    uint256 internal constant BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIMESTAMP = 153;

    // RangeShift
    uint256 internal constant BITS_DEX_LITE_RANGE_SHIFT_OLD_UPPER_RANGE_PERCENT = 0;
    uint256 internal constant BITS_DEX_LITE_RANGE_SHIFT_OLD_LOWER_RANGE_PERCENT = 14;
    uint256 internal constant BITS_DEX_LITE_RANGE_SHIFT_TIME_TO_SHIFT = 28;
    uint256 internal constant BITS_DEX_LITE_RANGE_SHIFT_TIMESTAMP = 48;

    // ThresholdShift
    uint256 internal constant BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_UPPER_THRESHOLD_PERCENT = 0;
    uint256 internal constant BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_LOWER_THRESHOLD_PERCENT = 7;
    uint256 internal constant BITS_DEX_LITE_THRESHOLD_SHIFT_TIME_TO_SHIFT = 14;
    uint256 internal constant BITS_DEX_LITE_THRESHOLD_SHIFT_TIMESTAMP = 34;

    // --------------------------------
    // @dev stacked uint256 swapData for LogSwap event
    uint256 internal constant BITS_DEX_LITE_SWAP_DATA_DEX_ID = 0;
    uint256 internal constant BITS_DEX_LITE_SWAP_DATA_SWAP_0_TO_1 = 64;
    uint256 internal constant BITS_DEX_LITE_SWAP_DATA_AMOUNT_IN = 65;
    uint256 internal constant BITS_DEX_LITE_SWAP_DATA_AMOUNT_OUT = 125;

    /// @notice Calculating the slot ID for Dex contract for single mapping at `slot_` for `key_`
    function calculateMappingStorageSlot(uint256 slot_, bytes32 key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }
}
