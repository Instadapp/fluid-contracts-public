//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { MockProtocol } from "../../../contracts/mocks/mockProtocol.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";

import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { AuthModule, FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { FluidLiquidityUserModule } from "../../../contracts/liquidity/userModule/main.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";

import "forge-std/console2.sol";

abstract contract LiquiditySimulateStorageSlot {
    // constants used for BigMath conversion from and to storage
    uint256 internal constant _SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant _DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant _DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant _DEFAULT_EXPONENT_MASK = 0xFF;

    function _simulateExchangePricesAndConfig(
        /// First 16 bits =>   0- 15 => borrow rate (in 1e2: 100% = 10_000; 1% = 100 -> max value 65535)
        uint256 borrowRate,
        /// Next  14 bits =>  16- 29 => fee on interest from borrowers to lenders (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
        uint256 fee,
        /// Next  14 bits =>  30- 43 => last stored utilization (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
        uint256 utilization,
        /// Next  14 bits =>  44- 57 => update on storage threshold (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
        uint256 updateOnStorageThreshold,
        /// Next  33 bits =>  58- 90 => last update timestamp (enough until 16 March 2242 -> max value 8589934591)
        uint256 lastUpdateTimestamp,
        /// Next  64 bits =>  91-154 => supply exchange price (1e12 -> max value 18_446_744,073709551615)
        uint256 supplyExchangePrice,
        /// Next  64 bits => 155-218 => borrow exchange price (1e12 -> max value 18_446_744,073709551615)
        uint256 borrowExchangePrice,
        /// Next   1 bit  => 219-219 => if 0 then ratio is supplyInterestFree / supplyWithInterest else ratio is supplyWithInterest / supplyInterestFree
        uint256 supplyRatioMode,
        /// Next  14 bits => 220-233 => supplyRatio: supplyInterestFree / supplyWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
        uint256 supplyRatio,
        /// Next   1 bit  => 234-234 => if 0 then ratio is borrowInterestFree / borrowWithInterest else ratio is borrowWithInterest / borrowInterestFree
        uint256 borrowRatioMode,
        /// Next  14 bits => 235-248 => borrowRatio: borrowInterestFree / borrowWithInterest (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
        uint256 borrowRatio
    ) internal pure returns (uint256 exchangePricesAndConfig) {
        // @dev input params need to be uint256 for the bitwise shifting to work, for smaller uint types it would act like an overflow

        exchangePricesAndConfig = borrowRate | (fee << 16) | (utilization << 30) | (updateOnStorageThreshold << 44);

        exchangePricesAndConfig =
            exchangePricesAndConfig |
            (lastUpdateTimestamp << 58) |
            (supplyExchangePrice << 91) |
            (borrowExchangePrice << 155);

        exchangePricesAndConfig =
            exchangePricesAndConfig |
            (supplyRatioMode << 219) |
            (supplyRatio << 220) |
            (borrowRatioMode << 234) |
            (borrowRatio << 235);
    }

    /// @dev total supply / borrow amounts for with / without interest per token: token -> amounts
    function _simulateTotalAmounts(
        /// First  64 bits =>   0- 63 => total supply with interest in raw (totalSupply = totalSupplyRaw * supplyExchangePrice); BigMath: 56 | 8
        uint256 supplyWithInterest,
        /// Next   64 bits =>  64-127 => total interest free supply in normal token amount (totalSupply = totalSupply); BigMath: 56 | 8
        uint256 supplyInterestFree,
        /// Next   64 bits => 128-191 => total borrow with interest in raw (totalBorrow = totalBorrowRaw * borrowExchangePrice); BigMath: 56 | 8
        uint256 borrowWithInterest,
        /// Next   64 bits => 192-255 => total interest free borrow in normal token amount (totalBorrow = totalBorrow); BigMath: 56 | 8
        uint256 borrowInterestFree
    ) internal pure returns (uint256 totalAmounts) {
        console2.log("_simulateTotalAmounts supplyWithInterest", supplyWithInterest);
        console2.log("_simulateTotalAmounts supplyInterestFree", supplyInterestFree);
        console2.log("_simulateTotalAmounts borrowWithInterest", borrowWithInterest);
        console2.log("_simulateTotalAmounts borrowInterestFree", borrowInterestFree);
        supplyWithInterest = BigMathMinified.toBigNumber(
            supplyWithInterest,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        supplyInterestFree = BigMathMinified.toBigNumber(
            supplyInterestFree,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        borrowWithInterest = BigMathMinified.toBigNumber(
            borrowWithInterest,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );
        borrowInterestFree = BigMathMinified.toBigNumber(
            borrowInterestFree,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );

        totalAmounts =
            supplyWithInterest |
            (supplyInterestFree << 64) |
            (borrowWithInterest << 128) |
            (borrowInterestFree << 192);
        console2.log("_simulateTotalAmounts totalAmounts");
        console2.logBytes32(bytes32(totalAmounts));
    }

    function _simulateExchangePricesWithRatesAndRatios(
        FluidLiquidityResolver resolver,
        address token,
        uint256 supplyExchangePrice,
        uint256 borrowExchangePrice,
        uint256 utilization,
        uint256 borrowRate,
        uint256 timestamp,
        uint256 supplyRatio,
        uint256 borrowRatio
    ) internal view returns (uint256 exchangePricesAndConfig) {
        exchangePricesAndConfig = resolver.getExchangePricesAndConfig(token);

        console2.log(
            "_simulateExchangePricesWithRatesAndRatios resolver.getExchangePricesAndConfig",
            exchangePricesAndConfig
        );
        console2.log("_simulateExchangePricesWithRatesAndRatios borrowRate", borrowRate);
        console2.log("_simulateExchangePricesWithRatesAndRatios utilization", utilization);
        console2.log("_simulateExchangePricesWithRatesAndRatios timestamp", timestamp);
        console2.log("_simulateExchangePricesWithRatesAndRatios supplyExchangePrice", supplyExchangePrice);
        console2.log("_simulateExchangePricesWithRatesAndRatios borrowExchangePrice", borrowExchangePrice);
        console2.log("_simulateExchangePricesWithRatesAndRatios supplyRatio", supplyRatio);
        console2.log("_simulateExchangePricesWithRatesAndRatios borrowRatio", borrowRatio);

        exchangePricesAndConfig =
            (exchangePricesAndConfig &
                // mask to update bits: 0-15 (borrow rate), 30-43 (utilization), 58-248 (timestamp, exchange prices, ratios)
                0xfe000000000000000000000000000000000000000000000003fff0003fff0000) |
            borrowRate | // borrow rate
            (utilization << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION) |
            (timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
            (supplyExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (borrowExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) |
            (supplyRatio << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) |
            (borrowRatio << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO);

        console2.log("_simulateExchangePricesWithRatesAndRatios exchangePricesAndConfig");
        console2.logBytes32(bytes32(exchangePricesAndConfig));
    }

    function _simulateExchangePricesWithRatios(
        FluidLiquidityResolver resolver,
        address token,
        uint256 supplyExchangePrice,
        uint256 borrowExchangePrice,
        uint256 supplyRatio,
        uint256 borrowRatio
    ) internal view returns (uint256 exchangePricesAndConfig) {
        exchangePricesAndConfig = resolver.getExchangePricesAndConfig(token);

        exchangePricesAndConfig =
            (exchangePricesAndConfig &
                // mask to update bits:  58-248 (timestamp, exchange prices, ratios)
                0xfe000000000000000000000000000000000000000000000003ffffffffffffff) |
            (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
            (supplyExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (borrowExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE) |
            (supplyRatio << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) |
            (borrowRatio << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO);
    }

    function _simulateExchangePrices(
        FluidLiquidityResolver resolver,
        address token,
        uint256 supplyExchangePrice,
        uint256 borrowExchangePrice
    ) internal view returns (uint256 exchangePricesAndConfig) {
        exchangePricesAndConfig = resolver.getExchangePricesAndConfig(token);

        exchangePricesAndConfig =
            (exchangePricesAndConfig &
                // mask to update bits:  58-218 (timestamp & exchange prices)
                0xfffffffffc0000000000000000000000000000000000000003ffffffffffffff) |
            (block.timestamp << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_LAST_TIMESTAMP) |
            (supplyExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (borrowExchangePrice << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE);
    }

    function _simulateUserSupplyData(
        FluidLiquidityResolver resolver,
        address user,
        address token,
        /// Next  64 bits =>   1- 64 => user supply amount (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 userSupply,
        /// Next  64 bits =>  65-128 => previous user withdrawal limit (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 previousLimit,
        /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
        uint256 lastTriggeredTimestamp
    ) internal view returns (uint256 userSupplyData) {
        userSupplyData = resolver.getUserSupply(user, token);

        console2.log("_simulateUserSupplyData userSupply before BigMath", userSupply);
        userSupply = BigMathMinified.toBigNumber(
            userSupply,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        previousLimit = BigMathMinified.toBigNumber(
            previousLimit,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        console2.log("_simulateUserSupplyData userSupply", userSupply);
        console2.log("_simulateUserSupplyData previousLimit", previousLimit);
        console2.log("_simulateUserSupplyData lastTriggeredTimestamp", lastTriggeredTimestamp);

        userSupplyData =
            // mask to update bits 1-161 (supply amount, withdrawal limit, timestamp)
            (userSupplyData & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userSupply << LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) |
            (previousLimit << LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) |
            (lastTriggeredTimestamp << LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP);

        console2.log("_simulateUserSupplyData userSupplyData");
        console2.logBytes32(bytes32(userSupplyData));

        return userSupplyData;
    }

    function _simulateUserSupplyDataFull(
        /// First  1 bit  =>       0 => mode: user supply with or without interest
        ///                             0 = without, amounts are in normal (i.e. no need to multiply with exchange price)
        ///                             1 = with interest, amounts are in raw (i.e. must multiply with exchange price to get actual token amounts)
        uint8 mode,
        /// Next  64 bits =>   1- 64 => user supply amount (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 userSupply,
        /// Next  64 bits =>  65-128 => previous user withdrawal limit (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 previousLimit,
        /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
        uint256 lastTriggeredTimestamp,
        /// Next  14 bits => 162-175 => expand withdrawal limit percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383).
        ///                             @dev shrinking is instant
        uint256 expandPercentage,
        /// Next  24 bits => 176-199 => withdrawal limit expand duration in seconds.(Max value 16_777_215; ~4_660 hours, ~194 days)
        uint256 expandDuration,
        /// Next  18 bits => 200-217 => base withdrawal limit: below this, 100% withdrawals can be done (normal or raw depends on 1st bit); BigMath: 10 | 8
        uint256 baseLimit,
        /// Last     bit  => 255-255 => is user paused (1 = paused, 0 = not paused)
        bool isUserPaused
    ) internal pure returns (uint256 userSupplyData) {
        userSupply = BigMathMinified.toBigNumber(
            userSupply,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        previousLimit = BigMathMinified.toBigNumber(
            previousLimit,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );
        baseLimit = BigMathMinified.toBigNumber(baseLimit, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);

        userSupplyData =
            mode |
            (userSupply << LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) |
            (previousLimit << LiquiditySlotsLink.BITS_USER_SUPPLY_PREVIOUS_WITHDRAWAL_LIMIT) |
            (lastTriggeredTimestamp << LiquiditySlotsLink.BITS_USER_SUPPLY_LAST_UPDATE_TIMESTAMP) |
            (expandPercentage << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) |
            (expandDuration << LiquiditySlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION) |
            (baseLimit << LiquiditySlotsLink.BITS_USER_SUPPLY_BASE_WITHDRAWAL_LIMIT) |
            (uint(isUserPaused ? 1 : 0) << LiquiditySlotsLink.BITS_USER_SUPPLY_IS_PAUSED);

        return userSupplyData;
    }

    function _simulateUserBorrowData(
        FluidLiquidityResolver resolver,
        address user,
        address token,
        /// Next  64 bits =>   1- 64 => user borrow amount (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 userBorrow,
        /// Next  64 bits =>  65-128 => previous user debt ceiling (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 previousLimit,
        /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
        uint256 lastTriggeredTimestamp
    ) internal view returns (uint256 userBorrowData) {
        userBorrowData = resolver.getUserBorrow(user, token);
        console2.log("_simulateUserBorrowData resolver.getUserBorrow", userBorrowData);

        console2.log("_simulateUserBorrowData userBorrow before BigMath", userBorrow);
        userBorrow = BigMathMinified.toBigNumber(
            userBorrow,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_UP
        );
        previousLimit = BigMathMinified.toBigNumber(
            previousLimit,
            _DEFAULT_COEFFICIENT_SIZE,
            _DEFAULT_EXPONENT_SIZE,
            BigMathMinified.ROUND_DOWN
        );

        console2.log("_simulateUserBorrowData userBorrow", userBorrow);
        console2.log("_simulateUserBorrowData previousLimit", previousLimit);
        console2.log("_simulateUserBorrowData lastTriggeredTimestamp", lastTriggeredTimestamp);
        userBorrowData =
            // mask to update bits 1-161 (borrow amount, borrow limit, timestamp)
            (userBorrowData & 0xfffffffffffffffffffffffc0000000000000000000000000000000000000001) |
            (userBorrow << LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) |
            (previousLimit << LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT) |
            (lastTriggeredTimestamp << LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP);

        console2.log("_simulateUserBorrowData userBorrowData");
        console2.logBytes32(bytes32(userBorrowData));

        return userBorrowData;
    }

    function _simulateUserBorrowDataFull(
        /// First  1 bit  =>       0 => mode: user borrow with or without interest
        ///                             0 = without, amounts are in normal (i.e. no need to multiply with exchange price)
        ///                             1 = with interest, amounts are in raw (i.e. must multiply with exchange price to get actual token amounts)
        uint8 mode,
        /// Next  64 bits =>   1- 64 => user borrow amount (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 userBorrow,
        /// Next  64 bits =>  65-128 => previous user debt ceiling (normal or raw depends on 1st bit); BigMath: 56 | 8
        uint256 previousLimit,
        /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
        uint256 lastTriggeredTimestamp,
        /// Next  14 bits => 162-175 => expand debt ceiling percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
        ///                             @dev shrinking is instant
        uint256 expandPercentage,
        /// Next  24 bits => 176-199 => debt ceiling expand duration in seconds (Max value 16_777_215; ~4_660 hours, ~194 days)
        uint256 expandDuration,
        /// Next  18 bits => 200-217 => base debt ceiling: below this, there's no debt ceiling limits (normal or raw depends on 1st bit); BigMath: 10 | 8
        uint256 baseLimit,
        /// Next  18 bits => 218-235 => max debt ceiling: absolute maximum debt ceiling can expand to (normal or raw depends on 1st bit); BigMath: 10 | 8
        uint256 maxLimit,
        /// Last     bit  => 255-255 => is user paused (1 = paused, 0 = not paused)
        bool isUserPaused
    ) internal pure returns (uint256 userBorrowData) {
        /// Next  37 bits => 218-254 => empty for future use
        {
            userBorrow = BigMathMinified.toBigNumber(
                userBorrow,
                _DEFAULT_COEFFICIENT_SIZE,
                _DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_UP
            );
            previousLimit = BigMathMinified.toBigNumber(
                previousLimit,
                _DEFAULT_COEFFICIENT_SIZE,
                _DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            );
            baseLimit = BigMathMinified.toBigNumber(baseLimit, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
            maxLimit = BigMathMinified.toBigNumber(maxLimit, 10, _DEFAULT_EXPONENT_SIZE, BigMathMinified.ROUND_DOWN);
        }

        userBorrowData = userBorrowData | mode;

        userBorrowData = userBorrowData | (userBorrow << LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT);

        userBorrowData = userBorrowData | (previousLimit << LiquiditySlotsLink.BITS_USER_BORROW_PREVIOUS_BORROW_LIMIT);

        userBorrowData =
            userBorrowData |
            (lastTriggeredTimestamp << LiquiditySlotsLink.BITS_USER_BORROW_LAST_UPDATE_TIMESTAMP);

        userBorrowData = userBorrowData | (expandPercentage << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_PERCENT);

        userBorrowData = userBorrowData | (expandDuration << LiquiditySlotsLink.BITS_USER_BORROW_EXPAND_DURATION);

        userBorrowData = userBorrowData | (baseLimit << LiquiditySlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT);

        userBorrowData = userBorrowData | (maxLimit << LiquiditySlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);

        userBorrowData = userBorrowData | (uint(isUserPaused ? 1 : 0) << LiquiditySlotsLink.BITS_USER_BORROW_IS_PAUSED);

        return userBorrowData;
    }
}

abstract contract TestHelpers is LiquiditySimulateStorageSlot, Test {
    /// @dev address that is mapped to the chain native token
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // must be adjusted depending on forked network.
    // currently set up for forking mainnet WETH
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant PASS_1YEAR_TIME = 365 days;

    uint256 constant EXCHANGE_PRICES_PRECISION = 1e12;

    // constants used for BigMath conversion from and to storage
    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 constant DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant DEFAULT_100_PERCENT = 1e4;

    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant TWELVE_DECIMALS = 1e12;
    uint256 internal constant X8 = 0xff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X15 = 0x7fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;

    uint256 constant MAX_TOKEN_AMOUNT_CAP = 1e38;

    uint256 constant DEFAULT_SUPPLY_AMOUNT = 1 ether;
    uint256 constant DEFAULT_WITHDRAW_AMOUNT = 0.5 ether;
    uint256 constant DEFAULT_BORROW_AMOUNT = 0.5 ether;
    uint256 constant DEFAULT_PAYBACK_AMOUNT = 0.3 ether;

    uint256 constant MAX_POSSIBLE_BORROW_RATE = 65535; // 16 bits

    uint256 constant DEFAULT_KINK = 80 * DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant DEFAULT_RATE_AT_ZERO = 4 * DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant DEFAULT_RATE_AT_KINK = 10 * DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant DEFAULT_RATE_AT_MAX = 150 * DEFAULT_PERCENT_PRECISION; // 150%
    // for rate data v2:
    uint256 constant DEFAULT_KINK2 = 90 * DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant DEFAULT_RATE_AT_KINK2 = 80 * DEFAULT_PERCENT_PRECISION; // 10% + half way to 150% = 80% for data compatibility with v1

    uint256 constant DEFAULT_TOKEN_FEE = 5 * DEFAULT_PERCENT_PRECISION; // 5%
    uint256 constant DEFAULT_STORAGE_UPDATE_THRESHOLD = 1 * DEFAULT_PERCENT_PRECISION; // 1%

    // set base debt ceiling high so that most tests, the ones that don't test borrow limits,
    // don't have to deal with a borrow limit
    uint256 constant DEFAULT_BASE_DEBT_CEILING = 100_000 ether;
    uint256 constant DEFAULT_MAX_DEBT_CEILING = 1_000_000 ether;
    uint256 constant DEFAULT_EXPAND_DEBT_CEILING_PERCENT = 20 * DEFAULT_PERCENT_PRECISION; // 20%
    uint256 constant DEFAULT_EXPAND_DEBT_CEILING_DURATION = 2 days;

    // set base withdrawal limit high so that most tests, the ones that don't test withdraw limits,
    // don't have to deal with a withdraw limit
    uint256 constant DEFAULT_BASE_WITHDRAWAL_LIMIT = 100_000 ether;
    uint256 constant DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT = 20 * DEFAULT_PERCENT_PRECISION; // 20%
    uint256 constant DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION = 2 days;

    // actual values for default values as read from storage for direct comparison in expected results.
    // once converting to BigMath and then back to get actual number after BigMath precision loss.
    uint256 immutable DEFAULT_BASE_WITHDRAWAL_LIMIT_AFTER_BIGMATH;
    uint256 immutable DEFAULT_SUPPLY_AMOUNT_AFTER_BIGMATH;
    uint256 immutable DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH;
    uint256 immutable DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH;

    constructor() {
        DEFAULT_BASE_DEBT_CEILING_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                DEFAULT_BASE_DEBT_CEILING,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        DEFAULT_SUPPLY_AMOUNT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                DEFAULT_SUPPLY_AMOUNT,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        DEFAULT_BORROW_AMOUNT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                DEFAULT_BORROW_AMOUNT,
                DEFAULT_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_UP
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        DEFAULT_BASE_WITHDRAWAL_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                DEFAULT_BASE_WITHDRAWAL_LIMIT,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
    }

    function _setApproval(IERC20 erc20, address target, address owner) internal {
        vm.prank(owner);
        erc20.approve(target, type(uint256).max);
    }

    function _setDefaultRateDataV2(address liquidityContract, address admin, address token) internal {
        AdminModuleStructs.RateDataV2Params[] memory rateData = new AdminModuleStructs.RateDataV2Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV2Params(
            token,
            DEFAULT_KINK,
            DEFAULT_KINK2,
            DEFAULT_RATE_AT_ZERO,
            DEFAULT_RATE_AT_KINK,
            DEFAULT_RATE_AT_KINK2,
            DEFAULT_RATE_AT_MAX
        );

        vm.prank(admin);
        AuthModule(liquidityContract).updateRateDataV2s(rateData);
    }

    function _setDefaultRateDataV1(address liquidityContract, address admin, address token) internal {
        AdminModuleStructs.RateDataV1Params[] memory rateData = new AdminModuleStructs.RateDataV1Params[](1);
        rateData[0] = AdminModuleStructs.RateDataV1Params(
            token,
            DEFAULT_KINK,
            DEFAULT_RATE_AT_ZERO,
            DEFAULT_RATE_AT_KINK,
            DEFAULT_RATE_AT_MAX
        );

        vm.prank(admin);
        AuthModule(liquidityContract).updateRateDataV1s(rateData);
    }

    function _setDefaultTokenConfigs(address liquidityContract, address admin, address token) internal {
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: token,
            fee: DEFAULT_TOKEN_FEE,
            threshold: DEFAULT_STORAGE_UPDATE_THRESHOLD,
            maxUtilization: 1e4 // 100%
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateTokenConfigs(tokenConfigs_);
    }

    function _setUserAllowancesDefaultInterestFree(
        address liquidityContract,
        address admin,
        address token,
        address user
    ) internal {
        _setUserAllowancesDefaultWithMode(liquidityContract, admin, token, user, false);
    }

    function _setUserAllowancesDefault(address liquidityContract, address admin, address token, address user) internal {
        _setUserAllowancesDefaultWithMode(liquidityContract, admin, token, user, true);
    }

    function _setUserAllowancesDefaultWithMode(
        address liquidityContract,
        address admin,
        address token,
        address user,
        bool withInterest
    ) internal {
        // Add supply config
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: user,
            token: token,
            mode: withInterest ? 1 : 0,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateUserSupplyConfigs(userSupplyConfigs_);

        // Add borrow config
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: user,
            token: token,
            mode: withInterest ? 1 : 0,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
            maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function _setUserAllowancesDefaultWithModeWithHighLimit(
        address liquidityContract,
        address admin,
        address token,
        address user,
        bool withInterest
    ) internal {
        // Add supply config
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: user,
            token: token,
            mode: withInterest ? 1 : 0,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT * 1e3
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateUserSupplyConfigs(userSupplyConfigs_);

        // Add borrow config
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: user,
            token: token,
            mode: withInterest ? 1 : 0,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING * 1e3,
            maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING * 1e3
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function _setAsAuth(address liquidityContract, address admin, address user) internal {
        // create params
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(user, true);
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateAuths(updateAuthsParams);
    }

    function _pauseUser(
        address liquidityContract,
        address admin,
        address user,
        address supplyToken,
        address borrowToken
    ) internal {
        // create params
        address[] memory supplyTokens;
        if (supplyToken != address(0)) {
            supplyTokens = new address[](1);
            supplyTokens[0] = supplyToken;
        } else {
            supplyTokens = new address[](0);
        }

        address[] memory borrowTokens;
        if (borrowToken != address(0)) {
            borrowTokens = new address[](1);
            borrowTokens[0] = borrowToken;
        } else {
            borrowTokens = new address[](0);
        }
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).pauseUser(user, supplyTokens, borrowTokens);
    }

    function _unpauseUser(
        address liquidityContract,
        address admin,
        address user,
        address supplyToken,
        address borrowToken
    ) internal {
        // create params
        address[] memory supplyTokens;
        if (supplyToken != address(0)) {
            supplyTokens = new address[](1);
            supplyTokens[0] = supplyToken;
        } else {
            supplyTokens = new address[](0);
        }

        address[] memory borrowTokens;
        if (borrowToken != address(0)) {
            borrowTokens = new address[](1);
            borrowTokens[0] = borrowToken;
        } else {
            borrowTokens = new address[](0);
        }
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).unpauseUser(user, supplyTokens, borrowTokens);
    }

    function _supply(MockProtocol mockProtocol, address token, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(token, int256(amount), 0, address(0), address(0), abi.encode(user));
    }

    function _supplyNative(MockProtocol mockProtocol, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate{ value: amount }(
            NATIVE_TOKEN_ADDRESS,
            int256(amount),
            0,
            address(0),
            address(0),
            new bytes(0)
        );
    }

    function _withdraw(MockProtocol mockProtocol, address token, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(token, -int256(amount), 0, user, address(0), new bytes(0));
    }

    function _withdraw(
        MockProtocol mockProtocol,
        address token,
        address user,
        address receiver,
        uint256 amount
    ) internal {
        vm.prank(user);
        mockProtocol.operate(token, -int256(amount), 0, receiver, address(0), new bytes(0));
    }

    function _withdrawNative(MockProtocol mockProtocol, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(NATIVE_TOKEN_ADDRESS, -int256(amount), 0, user, address(0), new bytes(0));
    }

    function _withdrawNative(MockProtocol mockProtocol, address user, address receiver, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(NATIVE_TOKEN_ADDRESS, -int256(amount), 0, receiver, address(0), new bytes(0));
    }

    function _borrow(MockProtocol mockProtocol, address token, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(token, 0, int256(amount), address(0), user, new bytes(0));
    }

    function _borrow(
        MockProtocol mockProtocol,
        address token,
        address user,
        address receiver,
        uint256 amount
    ) internal {
        vm.prank(user);
        mockProtocol.operate(token, 0, int256(amount), address(0), receiver, new bytes(0));
    }

    function _borrowNative(MockProtocol mockProtocol, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(NATIVE_TOKEN_ADDRESS, 0, int256(amount), address(0), user, new bytes(0));
    }

    function _borrowNative(MockProtocol mockProtocol, address user, address receiver, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(NATIVE_TOKEN_ADDRESS, 0, int256(amount), address(0), receiver, new bytes(0));
    }

    function _payback(MockProtocol mockProtocol, address token, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate(token, 0, -int256(amount), address(0), address(0), abi.encode(user));
    }

    function _paybackNative(MockProtocol mockProtocol, address user, uint256 amount) internal {
        vm.prank(user);
        mockProtocol.operate{ value: amount }(
            NATIVE_TOKEN_ADDRESS,
            0,
            -int256(amount),
            address(0),
            address(0),
            abi.encode(user)
        );
    }

    /// @dev warps `warpSeconds` but updates exchange prices every 30 days. So compound effect is enabled somewhat
    function _warpWithExchangePriceUpdates(
        address liquidityContract,
        address admin,
        address[] memory tokens,
        uint256 warpSeconds
    ) internal {
        uint256 warpedSeconds;

        uint256 warpPerCycle = 30 days;
        while (warpedSeconds < warpSeconds) {
            if (warpedSeconds + warpPerCycle > warpSeconds) {
                // last warp -> only warp difference
                vm.warp(block.timestamp + warpSeconds - warpedSeconds);
            } else {
                vm.warp(block.timestamp + warpPerCycle);
            }

            vm.prank(admin);
            FluidLiquidityAdminModule(liquidityContract).updateExchangePrices(tokens);

            warpedSeconds += warpPerCycle;
        }
    }

    /// @dev checks that supply ratio in Liquidity storage exchangePricesAndConfig for `token` is `ratio`
    /// with `mode` being 0 if withInterest > interestFree, otherwise 1
    function _assertSupplyRatio(FluidLiquidityResolver resolver, address token, uint8 mode, uint256 ratio) internal {
        uint256 exchangePricesAndConfig = resolver.getExchangePricesAndConfig(token);

        uint256 ratioInStorage = (exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_RATIO) &
            X15;
        uint256 modeInStorage = ratioInStorage & 1; // first bit
        ratioInStorage = ratioInStorage >> 1; // other 14 bits;

        assertEq(modeInStorage, mode, "supply ratio mode bit is not as expected");
        assertEq(ratioInStorage, ratio, "supply ratio is not as expected");
    }

    /// @dev checks that borrow ratio in Liquidity storage exchangePricesAndConfig for `token` is `ratio`
    /// with `mode` being 0 if withInterest > interestFree, otherwise 1
    function _assertBorrowRatio(FluidLiquidityResolver resolver, address token, uint8 mode, uint256 ratio) internal {
        uint256 exchangePricesAndConfig = resolver.getExchangePricesAndConfig(token);

        uint256 ratioInStorage = (exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_RATIO) &
            X15;
        uint256 modeInStorage = ratioInStorage & 1; // first bit
        ratioInStorage = ratioInStorage >> 1; // other 14 bits;

        assertEq(modeInStorage, mode, "borrow ratio mode bit is not as expected");
        assertEq(ratioInStorage, ratio, "borrow ratio is not as expected");
    }

    /// @dev sets utilization of the protocol to a certain percentage by supplying safe and borrowing
    /// @param utilization in percentage as 1e4 (1e6 = 100%)
    function _setUtilization(
        int256 utilization,
        address liquidityContract,
        address token,
        address user1,
        address user2
    ) internal {
        // 1. supply safe as user1
        // prank msg.sender to be user1
        // vm.prank(user1);
        // // execute
        // FluidLiquidityUserModule(liquidityContract).operate(token, DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));
        // if (utilization > 0) {
        //     int256 borrowAmount_ = (DEFAULT_SUPPLY_AMOUNT * utilization) / 1e6;
        //     // 2. borrow as user2
        //     // prank msg.sender to be user2
        //     vm.prank(user2);
        //     // execute borrow
        //     FluidLiquidityUserModule(liquidityContract).operate(token, 0, borrowAmount_, address(0), user2, new bytes(0));
        // }
        // assertEq(ReadModule(liquidityContract).utilization(token), utilization);
    }

    function _updateRevenueCollector(address liquidityContract, address admin, address revenueCollector) internal {
        vm.prank(admin);
        FluidLiquidityAdminModule(liquidityContract).updateRevenueCollector(revenueCollector);
    }
}
