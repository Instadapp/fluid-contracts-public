// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { FluidCHRStockOracle } from "../../../contracts/oracleV2/stocks/chrStockOracle/main.sol";
import { FluidCHRStockOracleL2 } from "../../../contracts/oracleV2/stocks/chrStockOracle/mainL2.sol";
import { Structs as CHRStructs } from "../../../contracts/oracleV2/stocks/chrStockOracle/structs.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { Error as UsdError } from "../../../contracts/oracleV2/usdOracle/error.sol";
import { ErrorTypes as UsdErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";

import { VaultT1Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol";
import { FluidUsdOracleHarness } from "./usdOracleForkTestBase.sol";

import { MockChronicle, MockRealityToken, MockRealityTokenTrade, MockAuthGate, SequencerUptimeFeedMock } from "./chrStockOracleMocks.sol";
import { MockLiquidityGovernance, MockERC20, IFluidOracleWrite, IUSDOracle, IUSDOracleAdmin } from "./usdOracleClxWriteIntegration.t.sol";

interface IUSDOracleRawMode {
    function getPriceRawForMode(address token_, uint8 priceMode_) external view returns (uint256, uint8, uint8);
}

interface IVaultOracleRates {
    function getExchangeRateOperate() external view returns (uint256);

    function getExchangeRateLiquidate() external view returns (uint256);
}

/// @notice USD oracle + Chronicle × Reality stock oracle (SOURCE_FLUID_ORACLE) + vault T1 oracle.
contract UsdOracleChrIntegrationTest is Test {
    // USD oracle constants (from variables.sol and structs)
    uint8 internal constant TOKEN_TYPE_VOLATILE = 3;
    uint8 internal constant TOKEN_TYPE_STABLE = 2;
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;
    uint8 internal constant SOURCE_STABLE = 3;
    uint8 internal constant PRICE_MODE_MARKET = 1;

    // Market hours session types and constants
    uint8 constant sessionTypeRegular = 1;
    uint16 constant REGULAR_MINUTES = 390;
    uint16 constant POST_MINUTES = 240;
    uint16 constant PRE_MINUTES = 330;
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address constant MID = address(0x1D1D);
    address constant HIGH = address(0x1E1E);

    uint256 constant MON = 1_700_000_000;
    uint256 constant REG_END = MON + 390 minutes;

    event LogRecordHint(uint256 value, uint256 age, uint256 regularEnd);

    FluidUsEquityMarketHours marketHours;
    MockLiquidityGovernance liquidityMock;
    MockChronicle chronicle;
    MockRealityToken rtoken;
    MockRealityTokenTrade trade;
    MockAuthGate authGate;
    SequencerUptimeFeedMock feed;
    FluidCHRStockOracle oracle;

    address admin = address(0xA11CE);
    address stockToken;
    address debtToken;

    function _weekWithWeekend(uint32 monStart_) internal pure returns (Structs.Session[] memory s_) {
        s_ = new Structs.Session[](6);
        for (uint256 i_; i_ < 4; i_++) {
            s_[i_] = Structs.Session({
                sessionStart: uint32(uint256(monStart_) + i_ * 1 days),
                durationMinutes: REGULAR_MINUTES,
                extendedDurationMinutes: WEEKDAY_EXTENDED_MINUTES,
                sessionType: sessionTypeRegular
            });
        }
        uint32 fri_ = uint32(uint256(monStart_) + 4 days);
        s_[4] = Structs.Session({
            sessionStart: fri_,
            durationMinutes: REGULAR_MINUTES,
            extendedDurationMinutes: POST_MINUTES,
            sessionType: sessionTypeRegular
        });
        uint32 weekendStart_ = uint32(uint256(fri_) + uint256(REGULAR_MINUTES + POST_MINUTES) * 1 minutes);
        s_[5] = Structs.Session({
            sessionStart: weekendStart_,
            durationMinutes: 56 * 60,
            extendedDurationMinutes: PRE_MINUTES,
            sessionType: 3 // holiday
        });
    }

    function _params() internal view returns (CHRStructs.CHRStockOracleConstructorParams memory p_) {
        p_ = CHRStructs.CHRStockOracleConstructorParams({
            infoName: "rSPY",
            targetDecimals: 27,
            chronicle: address(chronicle),
            rtoken: address(rtoken),
            realityTokenTrade: address(trade),
            marketHours: address(marketHours),
            authGate: address(authGate),
            maxCapPercent: 1500,
            maxBreakPercent: 3000,
            maxOperateAge: 1 hours,
            maxLiquidateAge: 1 days
        });
    }

    function setUp() public {
        vm.warp(MON + 1 hours);

        liquidityMock = new MockLiquidityGovernance(admin);
        FluidUsEquityMarketHours impl = new FluidUsEquityMarketHours(address(liquidityMock));
        FluidUsEquityMarketHoursProxy proxy = new FluidUsEquityMarketHoursProxy(
            address(impl),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        marketHours = FluidUsEquityMarketHours(address(proxy));
        vm.prank(admin);
        marketHours.updateAuth(AUTH, 1);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(uint32(MON)));

        chronicle = new MockChronicle();
        rtoken = new MockRealityToken();
        trade = new MockRealityTokenTrade();
        authGate = new MockAuthGate();
        feed = new SequencerUptimeFeedMock();
        feed.setRound(1, 0, MON - 1 days);
        authGate.setLevel(MID, 1);
        authGate.setLevel(HIGH, 2);

        stockToken = address(new MockERC20(18, "wSPY"));
        debtToken = address(new MockERC20(6, "USDC"));

        oracle = new FluidCHRStockOracleL2(_params(), address(feed));
        chronicle.set(true, 700e18, block.timestamp);
        vm.prank(HIGH);
        oracle.setAnchor(1e18);
    }

    // ======================= helpers =======================

    /// @dev Harness rather than `FluidUsdOracle`: production carries no batch entry for
    ///      `_marketKeyCalls` to run through.
    function _deployUsdOracle() internal returns (address) {
        return address(new FluidUsdOracleHarness(address(liquidityMock)));
    }

    function _deployVaultT1Oracle(address usdOracle_, address supply_, address borrow_) internal returns (address) {
        return address(new VaultT1Oracle(usdOracle_, supply_, borrow_, 0, 0));
    }

    function _configureUsdOracle(address usdOracle_) internal {
        IUSDOracleAdmin.SourceConfig memory crSrc = IUSDOracleAdmin.SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(oracle),
            capOperand: 0
        });
        IUSDOracleAdmin.SourceConfig memory empty = IUSDOracleAdmin.SourceConfig({
            sourceType: 0,
            source: address(0),
            capOperand: 0
        });

        vm.startPrank(admin);
        // stock token: VOLATILE, CHR oracle source
        IUSDOracleAdmin(usdOracle_).setTokenType(stockToken, TOKEN_TYPE_VOLATILE);
        IUSDOracleAdmin(usdOracle_).setSourceConfig(stockToken, crSrc, empty, empty);
        IUSDOracleAdmin(usdOracle_).multicall(_marketKeyCalls(stockToken));

        // debt token: STABLE, $1 source
        IUSDOracleAdmin(usdOracle_).setTokenType(debtToken, TOKEN_TYPE_STABLE);
        IUSDOracleAdmin.SourceConfig memory stableSrc = IUSDOracleAdmin.SourceConfig({
            sourceType: SOURCE_STABLE,
            source: address(0),
            capOperand: 0
        });
        IUSDOracleAdmin(usdOracle_).setSourceConfig(debtToken, stableSrc, empty, empty);
        IUSDOracleAdmin(usdOracle_).multicall(_marketKeyCalls(debtToken));
        vm.stopPrank();
    }

    /// @dev Batched: the transient key does not survive the transaction boundary that separate
    ///      top-level calls would put between it and `setPriceMode`.
    function _marketKeyCalls(address token_) internal pure returns (bytes[] memory calls_) {
        uint8[4] memory isOperate_ = [1, 0, 1, 0];
        uint8[4] memory isCollateral_ = [1, 1, 0, 0];

        calls_ = new bytes[](8);
        for (uint256 i_; i_ < 4; ++i_) {
            calls_[i_ * 2] = abi.encodeWithSelector(
                IUSDOracleAdmin.registerTransientOracleKey.selector,
                IUSDOracleAdmin.OracleKey({
                    token: token_,
                    eMode: 0,
                    isOperate: isOperate_[i_],
                    isCollateral: isCollateral_[i_]
                })
            );
            calls_[i_ * 2 + 1] = abi.encodeWithSelector(IUSDOracleAdmin.setPriceMode.selector, PRICE_MODE_MARKET);
        }
    }

    function _setPrice(uint256 price18_) internal {
        chronicle.set(true, price18_, block.timestamp);
    }

    function _expectUsdErr(uint256 id_) internal {
        vm.expectRevert(abi.encodeWithSelector(UsdError.FluidUsdOracleError.selector, id_));
    }

    // ======================= registration =======================

    /// @dev Registration needs no anchor: the probe in `setSourceConfig` (`_isFluidOracleWithDebt`) reads the
    ///      unanchored oracle, which prices live with no break or cap, so a far-off value is accepted too.
    function test_registration_SucceedsBeforeFirstAnchor() public {
        oracle = new FluidCHRStockOracleL2(_params(), address(feed));
        _setPrice(1400e18);
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);

        assertEq(IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true), 1400e27);
    }

    function test_registration_SucceedsOnceAnchored() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);

        assertEq(IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true), 700e27);
    }

    // ======================= view path =======================

    /// @dev Vault rate = colPrice × 10^(27 + debtDec − colDec) / debtPrice. Stock 18 dec, USDC 6 dec, USDC at $1,
    ///      so a CHR value `v` (1e27 per whole token) becomes `v × 1e15 / 1e27`.
    function test_viewPath_VaultRatesEqualCrValueConverted() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, stockToken, debtToken);

        _setPrice(705e18);
        assertEq(oracle.getExchangeRateOperate(), 705e27);

        assertEq(IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true), 705e27);
        assertEq(IUSDOracle(usdOracle).getPriceView(stockToken, 0, false, true), 705e27);
        assertEq(IVaultOracleRates(vault).getExchangeRateOperate(), 705e27 / 1e12);
        assertEq(IVaultOracleRates(vault).getExchangeRateLiquidate(), 705e27 / 1e12);
    }

    /// @dev A guarded CHR revert becomes a zero leg in the USD oracle (`_readFluidSource` catches it, then the
    ///      zero-rate check reverts `UsdOracle__RateZero`), so every price and vault rate over the stock token reverts.
    function test_viewPath_PausedCrSurfacesAsRateZero() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, stockToken, debtToken);

        vm.prank(MID);
        oracle.pause();

        _expectUsdErr(UsdErrorTypes.UsdOracle__RateZero);
        IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true);

        _expectUsdErr(UsdErrorTypes.UsdOracle__RateZero);
        IVaultOracleRates(vault).getExchangeRateOperate();

        _expectUsdErr(UsdErrorTypes.UsdOracle__RateZero);
        IVaultOracleRates(vault).getExchangeRateLiquidate();
    }

    /// @dev Outside the cap the operate leg reverts (rate zero up the stack) while liquidations price the
    ///      collateral at the cap floor.
    function test_viewPath_OutsideCapBlocksOperateAndFloorsLiquidate() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, stockToken, debtToken);

        _setPrice(590e18);

        _expectUsdErr(UsdErrorTypes.UsdOracle__RateZero);
        IVaultOracleRates(vault).getExchangeRateOperate();

        assertEq(IVaultOracleRates(vault).getExchangeRateLiquidate(), 595e27 / 1e12);
    }

    /// @dev Stock as the debt token: liquidations price the debt at the cap ceiling.
    function test_viewPath_DebtLegCappedAtCeilingOnLiquidate() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, debtToken, stockToken);

        _setPrice(810e18);

        _expectUsdErr(UsdErrorTypes.UsdOracle__RateZero);
        IVaultOracleRates(vault).getExchangeRateOperate();

        assertEq(IVaultOracleRates(vault).getExchangeRateLiquidate(), uint256(1e27 * 1e39) / 805e27);
    }

    // ======================= write path =======================

    /// @dev A reverting write getter (here: market hours down) falls back to the view getter, so vaults keep pricing.
    function test_writePath_FallsBackToViewWhenWriteReverts() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, stockToken, debtToken);

        vm.warp(MON + 2 hours);
        _setPrice(705e18);
        vm.mockCallRevert(address(marketHours), abi.encodeCall(FluidUsEquityMarketHours.getCurrentSession, ()), "down");

        assertEq(IFluidOracleWrite(vault).getExchangeRateOperateWrite(), 705e15);
        assertEq(oracle.getConfig().hintAge, 0);
    }

    function test_writePath_RecordsHintThroughStack() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vault = _deployVaultT1Oracle(usdOracle, stockToken, debtToken);

        // Monday 10:30 AM, inside the REGULAR window
        vm.warp(MON + 2 hours);
        _setPrice(705e18);
        assertEq(oracle.getConfig().hintAge, 0);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit LogRecordHint(705e27, MON + 2 hours, REG_END);
        assertEq(IFluidOracleWrite(vault).getExchangeRateOperateWrite(), 705e15);

        assertEq(oracle.getConfig().hintAge, MON + 2 hours);
        assertEq(oracle.getConfig().hintValue, 705e27);
    }

    // ======================= raw mode =======================

    function test_rawMode_ReachesGetExchangeRateWhilePaused() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);

        _setPrice(705e18);
        vm.prank(MID);
        oracle.pause();

        (uint256 priceRaw_, uint8 decimals_, uint8 tokenType_) = IUSDOracleRawMode(usdOracle).getPriceRawForMode(
            stockToken,
            PRICE_MODE_MARKET
        );
        assertEq(priceRaw_, 705e27);
        assertEq(decimals_, 18);
        assertEq(tokenType_, TOKEN_TYPE_VOLATILE);
    }
}
