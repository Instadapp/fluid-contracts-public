// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { TokenAmtResolver } from "../../../contracts/oracleV2/common/tokenAmtResolver.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";

contract MockPriceRawOracle {
    struct PriceData {
        uint256 price;
        uint8 decimals;
        uint8 tokenType;
    }

    mapping(bytes32 => PriceData) internal _prices;

    function setPriceRaw(address token_, uint8 priceMode_, uint256 price_, uint8 decimals_, uint8 tokenType_) external {
        _prices[keccak256(abi.encode(token_, priceMode_))] = PriceData(price_, decimals_, tokenType_);
    }

    function getPriceRawForMode(
        address token_,
        uint8 priceMode_
    ) external view returns (uint256 priceRaw_, uint8 decimals_, uint8 tokenType_) {
        PriceData memory d = _prices[keccak256(abi.encode(token_, priceMode_))];
        return (d.price, d.decimals, d.tokenType);
    }
}

contract TokenAmtResolverHarness is TokenAmtResolver {
    function getUsdValueForTokenAmount(
        address usdOracle_,
        address token_,
        uint256 amount_,
        uint8 priceMode_
    ) external view returns (uint256) {
        return _getUsdValueForTokenAmount(usdOracle_, token_, amount_, priceMode_);
    }

    function getTokenAmountForUsdValue(
        address usdOracle_,
        address token_,
        uint256 usdValue_,
        uint8 priceMode_
    ) external view returns (uint256) {
        return _getTokenAmountForUsdValue(usdOracle_, token_, usdValue_, priceMode_);
    }
}

contract TokenAmtResolverTest is Test {
    TokenAmtResolverHarness public harness;
    MockPriceRawOracle public oracle;

    address constant TOKEN_18DEC = address(0x1111);
    address constant TOKEN_6DEC = address(0x2222);
    address constant TOKEN_8DEC = address(0x3333);

    uint8 constant PRICE_MODE_MARKET = 1;

    function setUp() public {
        harness = new TokenAmtResolverHarness();
        oracle = new MockPriceRawOracle();

        // ETH-like token: 18 decimals, $2000
        oracle.setPriceRaw(TOKEN_18DEC, PRICE_MODE_MARKET, 2_000e27, 18, 3);
        // USDC-like token: 6 decimals, $1
        oracle.setPriceRaw(TOKEN_6DEC, PRICE_MODE_MARKET, 1e27, 6, 2);
        // WBTC-like token: 8 decimals, $60000
        oracle.setPriceRaw(TOKEN_8DEC, PRICE_MODE_MARKET, 60_000e27, 8, 3);
    }

    function test_getUsdValueForTokenAmount_18DecToken() public view {
        // 1 ETH ($2000) = 1e18 amount → 2000 * 1e27 USD value
        uint256 usdValue = harness.getUsdValueForTokenAmount(address(oracle), TOKEN_18DEC, 1e18, PRICE_MODE_MARKET);
        assertEq(usdValue, 2_000e27);
    }

    function test_getUsdValueForTokenAmount_6DecToken() public view {
        // 100 USDC ($1) = 100e6 amount → 100 * 1e27 USD value
        uint256 usdValue = harness.getUsdValueForTokenAmount(address(oracle), TOKEN_6DEC, 100e6, PRICE_MODE_MARKET);
        assertEq(usdValue, 100e27);
    }

    function test_getUsdValueForTokenAmount_8DecToken() public view {
        // 0.5 WBTC ($60000) = 5e7 amount → 30000 * 1e27 USD value
        uint256 usdValue = harness.getUsdValueForTokenAmount(address(oracle), TOKEN_8DEC, 5e7, PRICE_MODE_MARKET);
        assertEq(usdValue, 30_000e27);
    }

    function test_getTokenAmountForUsdValue_18DecToken() public view {
        // $2000 in USD → 1 ETH = 1e18
        uint256 amount = harness.getTokenAmountForUsdValue(address(oracle), TOKEN_18DEC, 2_000e27, PRICE_MODE_MARKET);
        assertEq(amount, 1e18);
    }

    function test_getTokenAmountForUsdValue_6DecToken() public view {
        // $100 in USD → 100 USDC = 100e6
        uint256 amount = harness.getTokenAmountForUsdValue(address(oracle), TOKEN_6DEC, 100e27, PRICE_MODE_MARKET);
        assertEq(amount, 100e6);
    }

    function test_getTokenAmountForUsdValue_8DecToken() public view {
        // $60000 in USD → 1 WBTC = 1e8
        uint256 amount = harness.getTokenAmountForUsdValue(address(oracle), TOKEN_8DEC, 60_000e27, PRICE_MODE_MARKET);
        assertEq(amount, 1e8);
    }

    function test_getUsdValueForTokenAmount_revertsOnZeroPrice() public {
        oracle.setPriceRaw(TOKEN_18DEC, PRICE_MODE_MARKET, 0, 18, 3);

        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.OracleV2Common__PriceZero)
        );
        harness.getUsdValueForTokenAmount(address(oracle), TOKEN_18DEC, 1e18, PRICE_MODE_MARKET);
    }

    function test_getTokenAmountForUsdValue_revertsOnZeroPrice() public {
        oracle.setPriceRaw(TOKEN_18DEC, PRICE_MODE_MARKET, 0, 18, 3);

        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.OracleV2Common__PriceZero)
        );
        harness.getTokenAmountForUsdValue(address(oracle), TOKEN_18DEC, 1e27, PRICE_MODE_MARKET);
    }

    function test_roundTrip_usdToTokenAndBack() public view {
        uint256 originalUsd = 5_000e27;

        uint256 tokenAmt = harness.getTokenAmountForUsdValue(
            address(oracle),
            TOKEN_18DEC,
            originalUsd,
            PRICE_MODE_MARKET
        );
        uint256 recoveredUsd = harness.getUsdValueForTokenAmount(
            address(oracle),
            TOKEN_18DEC,
            tokenAmt,
            PRICE_MODE_MARKET
        );

        assertEq(recoveredUsd, originalUsd, "Round-trip should be lossless for 18-decimal token");
    }

    function test_roundTrip_6DecRoundingLoss() public view {
        // 6-decimal tokens may lose precision on very small USD values
        uint256 smallUsd = 1e20; // $0.0000001 in 1e27 precision

        uint256 tokenAmt = harness.getTokenAmountForUsdValue(address(oracle), TOKEN_6DEC, smallUsd, PRICE_MODE_MARKET);
        uint256 recoveredUsd = harness.getUsdValueForTokenAmount(
            address(oracle),
            TOKEN_6DEC,
            tokenAmt,
            PRICE_MODE_MARKET
        );

        // May lose precision due to integer division
        assertLe(recoveredUsd, smallUsd, "Recovered USD should be <= original due to rounding");
    }
}
