// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @notice library that helps in reading / working with storage slot data of Fluid Liquidity.
/// @dev as all data for Fluid Liquidity is internal, any data must be fetched directly through manual
/// slot reading through this library or, if gas usage is less important, through the FluidLiquidityResolver.
library LiquiditySlotsLink {
    /// @dev storage slot for status at Liquidity
    uint256 internal constant LIQUIDITY_STATUS_SLOT = 1;
    /// @dev storage slot for auths mapping at Liquidity
    uint256 internal constant LIQUIDITY_AUTHS_MAPPING_SLOT = 2;
    /// @dev storage slot for guardians mapping at Liquidity
    uint256 internal constant LIQUIDITY_GUARDIANS_MAPPING_SLOT = 3;
    /// @dev storage slot for user class mapping at Liquidity
    uint256 internal constant LIQUIDITY_USER_CLASS_MAPPING_SLOT = 4;
    /// @dev storage slot for exchangePricesAndConfig mapping at Liquidity
    uint256 internal constant LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT = 5;
    /// @dev storage slot for rateData mapping at Liquidity
    uint256 internal constant LIQUIDITY_RATE_DATA_MAPPING_SLOT = 6;
    /// @dev storage slot for totalAmounts mapping at Liquidity
    uint256 internal constant LIQUIDITY_TOTAL_AMOUNTS_MAPPING_SLOT = 7;
    /// @dev storage slot for user supply double mapping at Liquidity
    uint256 internal constant LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT = 8;
    /// @dev storage slot for user borrow double mapping at Liquidity
    uint256 internal constant LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT = 9;
    /// @dev storage slot for listed tokens array at Liquidity
    uint256 internal constant LIQUIDITY_LISTED_TOKENS_ARRAY_SLOT = 10;
    /// @dev storage slot for listed tokens array at Liquidity
    uint256 internal constant LIQUIDITY_CONFIGS2_MAPPING_SLOT = 11;

    // --------------------------------
    // @dev stacked uint256 storage slots bits position data for each:

    // ExchangePricesAndConfig
    uint256 internal constant BITS_EXCHANGE_PRICES_BORROW_RATE = 0;
    uint256 internal constant BITS_EXCHANGE_PRICES_FEE = 16;
    uint256 internal constant BITS_EXCHANGE_PRICES_UTILIZATION = 30;
    uint256 internal constant BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD = 44;
    uint256 internal constant BITS_EXCHANGE_PRICES_LAST_TIMESTAMP = 58;
    uint256 internal constant BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE = 91;
    uint256 internal constant BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE = 155;
    uint256 internal constant BITS_EXCHANGE_PRICES_SUPPLY_RATIO = 219;
    uint256 internal constant BITS_EXCHANGE_PRICES_BORROW_RATIO = 234;
    uint256 internal constant BITS_EXCHANGE_PRICES_USES_CONFIGS2 = 249;

    // RateData:
    uint256 internal constant BITS_RATE_DATA_VERSION = 0;
    // RateData: V1
    uint256 internal constant BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO = 4;
    uint256 internal constant BITS_RATE_DATA_V1_UTILIZATION_AT_KINK = 20;
    uint256 internal constant BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK = 36;
    uint256 internal constant BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX = 52;
    // RateData: V2
    uint256 internal constant BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_ZERO = 4;
    uint256 internal constant BITS_RATE_DATA_V2_UTILIZATION_AT_KINK1 = 20;
    uint256 internal constant BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK1 = 36;
    uint256 internal constant BITS_RATE_DATA_V2_UTILIZATION_AT_KINK2 = 52;
    uint256 internal constant BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_KINK2 = 68;
    uint256 internal constant BITS_RATE_DATA_V2_RATE_AT_UTILIZATION_MAX = 84;

    // TotalAmounts
    uint256 internal constant BITS_TOTAL_AMOUNTS_SUPPLY_WITH_INTEREST = 0;
    uint256 internal constant BITS_TOTAL_AMOUNTS_SUPPLY_INTEREST_FREE = 64;
    uint256 internal constant BITS_TOTAL_AMOUNTS_BORROW_WITH_INTEREST = 128;
    uint256 internal constant BITS_TOTAL_AMOUNTS_BORROW_INTEREST_FREE = 192;

    // UserSupplyData
    uint256 internal constant BITS_USER_SUPPLY_MODE = 0;
    uint256 internal constant BITS_USER_SUPPLY_AMOUNT = 1;
    uint256 internal constant BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT = 65;
    uint256 internal constant BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP = 129;
    uint256 internal constant BITS_USER_SUPPLY_EXPAND_PERCENT = 162;
    uint256 internal constant BITS_USER_SUPPLY_EXPAND_DURATION = 176;
    uint256 internal constant BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT = 200;
    uint256 internal constant BITS_USER_SUPPLY_IS_PAUSED = 255;

    // UserBorrowData
    uint256 internal constant BITS_USER_BORROW_MODE = 0;
    uint256 internal constant BITS_USER_BORROW_AMOUNT = 1;
    uint256 internal constant BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT = 65;
    uint256 internal constant BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP = 129;
    uint256 internal constant BITS_USER_BORROW_EXPAND_PERCENT = 162;
    uint256 internal constant BITS_USER_BORROW_EXPAND_DURATION = 176;
    uint256 internal constant BITS_USER_BORROW_BASE_BORROW_LIMIT = 200;
    uint256 internal constant BITS_USER_BORROW_MAX_BORROW_LIMIT = 218;
    uint256 internal constant BITS_USER_BORROW_IS_PAUSED = 255;

    // Configs2
    uint256 internal constant BITS_CONFIGS2_MAX_UTILIZATION = 0;

    // --------------------------------

    /// @notice Calculating the slot ID for Liquidity contract for single mapping at `slot_` for `key_`
    function calculateMappingStorageSlot(uint256 slot_, address key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    /// @notice Calculating the slot ID for Liquidity contract for double mapping at `slot_` for `key1_` and `key2_`
    function calculateDoubleMappingStorageSlot(
        uint256 slot_,
        address key1_,
        address key2_
    ) internal pure returns (bytes32) {
        bytes32 intermediateSlot_ = keccak256(abi.encode(key1_, slot_));
        return keccak256(abi.encode(key2_, intermediateSlot_));
    }
}
