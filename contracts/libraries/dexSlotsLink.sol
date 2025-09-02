// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Dex.
/// @dev as all data for Fluid Dex is internal, any data must be fetched directly through manual
/// slot reading through this library or, if gas usage is less important, through the FluidDexResolver.
library DexSlotsLink {
    /// @dev storage slot for variables at Dex
    uint256 internal constant DEX_VARIABLES_SLOT = 0;
    /// @dev storage slot for variables2 at Dex
    uint256 internal constant DEX_VARIABLES2_SLOT = 1;
    /// @dev storage slot for total supply shares at Dex
    uint256 internal constant DEX_TOTAL_SUPPLY_SHARES_SLOT = 2;
    /// @dev storage slot for user supply mapping at Dex
    uint256 internal constant DEX_USER_SUPPLY_MAPPING_SLOT = 3;
    /// @dev storage slot for total borrow shares at Dex
    uint256 internal constant DEX_TOTAL_BORROW_SHARES_SLOT = 4;
    /// @dev storage slot for user borrow mapping at Dex
    uint256 internal constant DEX_USER_BORROW_MAPPING_SLOT = 5;
    /// @dev storage slot for oracle mapping at Dex
    uint256 internal constant DEX_ORACLE_MAPPING_SLOT = 6;
    /// @dev storage slot for range and threshold shifts at Dex
    uint256 internal constant DEX_RANGE_THRESHOLD_SHIFTS_SLOT = 7;
    /// @dev storage slot for center price shift at Dex
    uint256 internal constant DEX_CENTER_PRICE_SHIFT_SLOT = 8;

    // --------------------------------
    // @dev stacked uint256 storage slots bits position data for each:

    // UserSupplyData
    uint256 internal constant BITS_USER_SUPPLY_ALLOWED = 0;
    uint256 internal constant BITS_USER_SUPPLY_AMOUNT = 1;
    uint256 internal constant BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT = 65;
    uint256 internal constant BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP = 129;
    uint256 internal constant BITS_USER_SUPPLY_EXPAND_PERCENT = 162;
    uint256 internal constant BITS_USER_SUPPLY_EXPAND_DURATION = 176;
    uint256 internal constant BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT = 200;

    // UserBorrowData
    uint256 internal constant BITS_USER_BORROW_ALLOWED = 0;
    uint256 internal constant BITS_USER_BORROW_AMOUNT = 1;
    uint256 internal constant BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT = 65;
    uint256 internal constant BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP = 129;
    uint256 internal constant BITS_USER_BORROW_EXPAND_PERCENT = 162;
    uint256 internal constant BITS_USER_BORROW_EXPAND_DURATION = 176;
    uint256 internal constant BITS_USER_BORROW_BASE_BORROW_LIMIT = 200;
    uint256 internal constant BITS_USER_BORROW_MAX_BORROW_LIMIT = 218;

    // --------------------------------

    /// @notice Calculating the slot ID for Dex contract for single mapping at `slot_` for `key_`
    function calculateMappingStorageSlot(uint256 slot_, address key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Dex contract for double mapping at `slot_` for `key1_` and `key2_`
    function calculateDoubleMappingStorageSlot(
        uint256 slot_,
        address key1_,
        address key2_
    ) internal pure returns (bytes32) {
        bytes32 intermediateSlot_ = keccak256(abi.encode(key1_, slot_));
        return keccak256(abi.encode(key2_, intermediateSlot_));
    }
}
