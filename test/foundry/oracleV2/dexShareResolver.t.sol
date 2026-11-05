// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { DexShareResolver } from "../../../contracts/oracleV2/common/dexShareResolver.sol";
import { Error as CommonError } from "../../../contracts/oracleV2/common/error.sol";
import { ErrorTypes as CommonErrorTypes } from "../../../contracts/oracleV2/common/errorTypes.sol";
import { VaultOracleBase } from "../../../contracts/oracleV2/vaultOracle/base.sol";
import { Error as VaultError } from "../../../contracts/oracleV2/vaultOracle/error.sol";
import { ErrorTypes as VaultErrorTypes } from "../../../contracts/oracleV2/vaultOracle/errorTypes.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";
import { DexSlotsLink } from "../../../contracts/libraries/dexSlotsLink.sol";

contract SlotReaderMock {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        assembly {
            result_ := sload(slot_)
        }
    }
}

contract MockUsdOracleDetailed {
    struct PriceData {
        uint256 price;
        uint8 decimals;
        uint8 tokenType;
    }

    mapping(bytes32 => PriceData) internal _prices;

    function setPrice(
        address token_,
        bool isOperate_,
        bool isCollateral_,
        uint256 price_,
        uint8 decimals_,
        uint8 tokenType_
    ) external {
        _prices[_key(token_, isOperate_, isCollateral_)] = PriceData(price_, decimals_, tokenType_);
    }

    function getPriceDetailedView(
        address token_,
        uint256,
        bool isOperate_,
        bool isCollateral_
    ) public view returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        PriceData memory data_ = _prices[_key(token_, isOperate_, isCollateral_)];
        return (data_.price, data_.decimals, data_.tokenType);
    }

    function getPriceDetailedViewRaw(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        return getPriceDetailedView(token_, emode_, isOperate_, isCollateral_);
    }

    function _key(address token_, bool isOperate_, bool isCollateral_) internal pure returns (bytes32) {
        return keccak256(abi.encode(token_, isOperate_, isCollateral_));
    }

    function isEmodeValid(uint256, address) external pure returns (bool) {
        return true;
    }
}

contract MockTokenMetadata {
    uint8 internal immutable _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function symbol() external pure returns (string memory) {
        return "TOK";
    }
}

contract DexShareResolverHarness is DexShareResolver {
    function resolveCol(
        address usdOracle_,
        uint256 eMode_,
        bool isOperate_,
        DexParams memory d_,
        uint256 pegBufferPpm_
    ) external view returns (uint256 priceUsd_, uint256 decimals_) {
        return _resolveColShare(usdOracle_, eMode_, isOperate_, d_, pegBufferPpm_, false);
    }

    function resolveDebt(
        address usdOracle_,
        uint256 eMode_,
        bool isOperate_,
        DexParams memory d_,
        uint256 pegBufferPpm_
    ) external view returns (uint256 priceUsd_, uint256 decimals_) {
        return _resolveDebtShare(usdOracle_, eMode_, isOperate_, d_, pegBufferPpm_, false);
    }

    function applyPegBuffer(
        uint256 token0Reserves_,
        uint256 token1Reserves_,
        uint256 pegBufferPpm_,
        bool isCollateralSide_
    ) external pure returns (uint256 out0_, uint256 out1_) {
        return _applyPegBufferToReserves(token0Reserves_, token1Reserves_, pegBufferPpm_, isCollateralSide_);
    }
}

contract VaultOracleBaseHarness is VaultOracleBase {
    string internal _colNameValue;
    string internal _debtNameValue;
    uint256 internal _colDecimalsValue;
    uint256 internal _debtDecimalsValue;

    constructor(
        string memory colName_,
        string memory debtName_,
        uint256 colDecimals_,
        uint256 debtDecimals_,
        uint256 supplyEMode_,
        uint256 borrowEMode_
    ) VaultOracleBase(supplyEMode_, borrowEMode_, 0, 0) {
        _colNameValue = colName_;
        _debtNameValue = debtName_;
        _colDecimalsValue = colDecimals_;
        _debtDecimalsValue = debtDecimals_;
    }

    function compute(
        uint256 colPriceUsd_,
        uint256 colDecimals_,
        uint256 debtPriceUsd_,
        uint256 debtDecimals_
    ) external pure returns (uint256 exchangeRate_) {
        return _computeExchangeRate(colPriceUsd_, colDecimals_, debtPriceUsd_, debtDecimals_);
    }

    function tokenDecimals(address token_) external view returns (uint256 decimals_) {
        return _tokenDecimals(token_);
    }

    function resolveNormalCol(
        address usdOracle_,
        address token_,
        bool isOperate_
    ) external view returns (uint256 priceUsd_, uint256 decimals_) {
        return _resolveNormal(usdOracle_, token_, isOperate_, true, false);
    }

    function resolveNormalDebt(
        address usdOracle_,
        address token_,
        bool isOperate_
    ) external view returns (uint256 priceUsd_, uint256 decimals_) {
        return _resolveNormal(usdOracle_, token_, isOperate_, false, false);
    }

    function _getExchangeRate(bool, bool) internal pure override returns (uint256 exchangeRate_) {
        return 0;
    }

    function _collateralName() internal view override returns (string memory) {
        return _colNameValue;
    }

    function _debtName() internal view override returns (string memory) {
        return _debtNameValue;
    }

    function _collateralDecimals() internal view override returns (uint256) {
        return _colDecimalsValue;
    }

    function _debtDecimals() internal view override returns (uint256) {
        return _debtDecimalsValue;
    }

    function _oracleConfigAddresses()
        internal
        view
        override
        returns (
            address usdOracle_,
            address supplyToken0_,
            address supplyToken1_,
            address borrowToken0_,
            address borrowToken1_,
            address supplyDexPool_,
            address borrowDexPool_
        )
    {
        usdOracle_ = address(0);
        supplyToken0_ = address(0);
        supplyToken1_ = address(0);
        borrowToken0_ = address(0);
        borrowToken1_ = address(0);
        supplyDexPool_ = address(0);
        borrowDexPool_ = address(0);
    }
}

contract DexShareResolverTest is Test {
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    DexShareResolverHarness internal resolver;
    VaultOracleBaseHarness internal baseHarness;
    MockUsdOracleDetailed internal usdOracle;
    SlotReaderMock internal slotReader;
    SlotReaderMock internal dexPool;
    MockTokenMetadata internal erc20Token;

    address internal token0 = makeAddr("token0");
    address internal token1 = makeAddr("token1");

    bytes32 internal constant SUPPLY_TOKEN_0_SLOT = bytes32(uint256(101));
    bytes32 internal constant SUPPLY_TOKEN_1_SLOT = bytes32(uint256(102));
    bytes32 internal constant BORROW_TOKEN_0_SLOT = bytes32(uint256(201));
    bytes32 internal constant BORROW_TOKEN_1_SLOT = bytes32(uint256(202));
    bytes32 internal constant EXCHANGE_PRICE_TOKEN_0_SLOT = bytes32(uint256(301));
    bytes32 internal constant EXCHANGE_PRICE_TOKEN_1_SLOT = bytes32(uint256(302));

    function setUp() public {
        resolver = new DexShareResolverHarness();
        baseHarness = new VaultOracleBaseHarness("COL", "DEBT", 18, 6, 0, 0);
        usdOracle = new MockUsdOracleDetailed();
        slotReader = new SlotReaderMock();
        dexPool = new SlotReaderMock();
        erc20Token = new MockTokenMetadata(8);

        vm.etch(LIQUIDITY, address(slotReader).code);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_0_SLOT);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_1_SLOT);
    }

    function test_computeExchangeRate_andTargetDecimals_useUint256Decimals() public view {
        uint256 exchangeRate_ = baseHarness.compute(2_000e27, 18, 1e27, 6);

        assertEq(exchangeRate_, 2_000e15);
        assertEq(baseHarness.targetDecimals(), 15);
        assertEq(baseHarness.infoName(), "DEBT / 1 COL");
    }

    function test_tokenDecimals_returnsNative18AndErc20Decimals() public view {
        assertEq(baseHarness.tokenDecimals(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), 18);
        assertEq(baseHarness.tokenDecimals(address(erc20Token)), 8);
    }

    function test_resolveNormalCollateral_revertsOnZeroPrice() public {
        usdOracle.setPrice(token0, true, true, 0, 18, 0);

        vm.expectRevert(
            abi.encodeWithSelector(VaultError.FluidVaultOracleError.selector, VaultErrorTypes.VaultOracle__PriceZero)
        );
        baseHarness.resolveNormalCol(address(usdOracle), token0, true);
    }

    function test_resolveColShare_pricesBufferedCollateralShares() public {
        usdOracle.setPrice(token0, true, true, 2e27, 18, 0);
        usdOracle.setPrice(token1, true, true, 3e27, 6, 0);

        _setLiquidityAmount(SUPPLY_TOKEN_0_SLOT, 2e12, false);
        _setLiquidityAmount(SUPPLY_TOKEN_1_SLOT, 4e12, false);
        vm.store(address(dexPool), bytes32(uint256(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)), bytes32(uint256(2e18)));

        (uint256 priceUsdOperate_, uint256 decimalsOperate_) = resolver.resolveCol(
            address(usdOracle),
            0,
            true,
            _dexParams(),
            5_000
        );
        (uint256 priceUsdLiquidate_, ) = resolver.resolveCol(address(usdOracle), 0, true, _dexParams(), 1_000);

        assertEq(priceUsdOperate_, 7_960_000_000_000_000_000_000_000_000);
        assertEq(priceUsdLiquidate_, 7_992_000_000_000_000_000_000_000_000);
        assertEq(decimalsOperate_, 18);
    }

    function test_resolveDebtShare_pricesBufferedDebtShares() public {
        usdOracle.setPrice(token0, true, false, 2e27, 18, 0);
        usdOracle.setPrice(token1, true, false, 3e27, 6, 0);

        _setLiquidityAmount(BORROW_TOKEN_0_SLOT, 3e12, false);
        _setLiquidityAmount(BORROW_TOKEN_1_SLOT, 1e12, false);
        vm.store(address(dexPool), bytes32(uint256(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT)), bytes32(uint256(2e18)));

        (uint256 priceUsdOperate_, uint256 decimalsOperate_) = resolver.resolveDebt(
            address(usdOracle),
            0,
            true,
            _dexParams(),
            5_000
        );
        (uint256 priceUsdLiquidate_, ) = resolver.resolveDebt(address(usdOracle), 0, true, _dexParams(), 1_000);

        assertEq(priceUsdOperate_, 4_522_500_000_000_000_000_000_000_000);
        assertEq(priceUsdLiquidate_, 4_504_500_000_000_000_000_000_000_000);
        assertEq(decimalsOperate_, 18);
    }

    function test_applyPegBuffer_revertsWhenBufferTooLarge() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.OracleV2Common__InvalidPegBuffer
            )
        );
        resolver.applyPegBuffer(1, 1, 1e6, true);
    }

    function test_applyPegBuffer_zeroBufferReturnsUnchangedReserves() public view {
        (uint256 out0_, uint256 out1_) = resolver.applyPegBuffer(123_456, 789_012, 0, true);
        assertEq(out0_, 123_456);
        assertEq(out1_, 789_012);
    }

    function test_resolveColShare_revertsWhenTotalSharesAreZero() public {
        usdOracle.setPrice(token0, true, true, 1e27, 18, 0);
        usdOracle.setPrice(token1, true, true, 1e27, 6, 0);
        _setLiquidityAmount(SUPPLY_TOKEN_0_SLOT, 1e12, false);
        _setLiquidityAmount(SUPPLY_TOKEN_1_SLOT, 1e12, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.OracleV2Common__SharesZero
            )
        );
        resolver.resolveCol(address(usdOracle), 0, true, _dexParams(), 0);
    }

    function _dexParams() internal view returns (DexShareResolver.DexParams memory d_) {
        d_ = DexShareResolver.DexParams({
            dexPool: address(dexPool),
            token0: token0,
            token1: token1,
            supplyToken0Slot: SUPPLY_TOKEN_0_SLOT,
            supplyToken1Slot: SUPPLY_TOKEN_1_SLOT,
            borrowToken0Slot: BORROW_TOKEN_0_SLOT,
            borrowToken1Slot: BORROW_TOKEN_1_SLOT,
            exchangePriceToken0Slot: EXCHANGE_PRICE_TOKEN_0_SLOT,
            exchangePriceToken1Slot: EXCHANGE_PRICE_TOKEN_1_SLOT,
            token0NumeratorPrecision: 1,
            token0DenominatorPrecision: 1,
            token1NumeratorPrecision: 1,
            token1DenominatorPrecision: 1
        });
    }

    function test_resolveDebtShare_revertsWhenTotalBorrowSharesAreZero() public {
        usdOracle.setPrice(token0, true, false, 1e27, 18, 0);
        usdOracle.setPrice(token1, true, false, 1e27, 6, 0);
        _setLiquidityAmount(BORROW_TOKEN_0_SLOT, 1e12, false);
        _setLiquidityAmount(BORROW_TOKEN_1_SLOT, 1e12, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                CommonError.OracleV2CommonError.selector,
                CommonErrorTypes.OracleV2Common__SharesZero
            )
        );
        resolver.resolveDebt(address(usdOracle), 0, true, _dexParams(), 0);
    }

    function test_resolveColShare_revertsWhenOneTokenPriceIsZero() public {
        usdOracle.setPrice(token0, true, true, 2e27, 18, 0);
        usdOracle.setPrice(token1, true, true, 0, 6, 0);
        _setLiquidityAmount(SUPPLY_TOKEN_0_SLOT, 2e12, false);
        _setLiquidityAmount(SUPPLY_TOKEN_1_SLOT, 4e12, false);
        vm.store(address(dexPool), bytes32(uint256(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)), bytes32(uint256(2e18)));

        vm.expectRevert(
            abi.encodeWithSelector(CommonError.OracleV2CommonError.selector, CommonErrorTypes.OracleV2Common__PriceZero)
        );
        resolver.resolveCol(address(usdOracle), 0, true, _dexParams(), 5_000);
    }

    function test_resolveColShare_withInterestAdjustedReserves() public {
        usdOracle.setPrice(token0, true, true, 2e27, 18, 0);
        usdOracle.setPrice(token1, true, true, 3e27, 6, 0);

        _setLiquidityAmount(SUPPLY_TOKEN_0_SLOT, 2e12, true);
        _setLiquidityAmount(SUPPLY_TOKEN_1_SLOT, 4e12, true);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_0_SLOT);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_1_SLOT);

        vm.store(address(dexPool), bytes32(uint256(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT)), bytes32(uint256(2e18)));

        (uint256 priceUsd_, uint256 decimals_) = resolver.resolveCol(address(usdOracle), 0, true, _dexParams(), 5_000);

        assertGt(priceUsd_, 0, "Interest-adjusted reserves should produce non-zero price");
        assertEq(decimals_, 18);
    }

    function test_resolveDebtShare_withInterestAdjustedReserves() public {
        usdOracle.setPrice(token0, true, false, 2e27, 18, 0);
        usdOracle.setPrice(token1, true, false, 3e27, 6, 0);

        _setLiquidityAmount(BORROW_TOKEN_0_SLOT, 3e12, true);
        _setLiquidityAmount(BORROW_TOKEN_1_SLOT, 1e12, true);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_0_SLOT);
        _setExchangePrice(EXCHANGE_PRICE_TOKEN_1_SLOT);

        vm.store(address(dexPool), bytes32(uint256(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT)), bytes32(uint256(2e18)));

        (uint256 priceUsd_, uint256 decimals_) = resolver.resolveDebt(address(usdOracle), 0, true, _dexParams(), 5_000);

        assertGt(priceUsd_, 0, "Interest-adjusted debt reserves should produce non-zero price");
        assertEq(decimals_, 18);
    }

    function _setLiquidityAmount(bytes32 slot_, uint256 amount_, bool withInterest_) internal {
        uint256 encodedAmount_ = amount_ << 8;
        uint256 rawData_ = (encodedAmount_ << 1) | (withInterest_ ? 1 : 0);
        vm.store(LIQUIDITY, slot_, bytes32(rawData_));
    }

    function _setExchangePrice(bytes32 slot_) internal {
        uint256 rawData_ = (uint256(1e12) << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) |
            (uint256(1e12) << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_BORROW_EXCHANGE_PRICE);
        vm.store(LIQUIDITY, slot_, bytes32(rawData_));
    }
}
