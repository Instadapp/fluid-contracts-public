// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { Structs as CLXStructs } from "../../../contracts/oracleV2/stocks/clxStockOracle/structs.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";

// ======================= Mocks =======================

contract MockChainlinkFeed {
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint80 public latestRoundId;
    mapping(uint80 => Round) internal _rounds;
    uint8 public decimals_ = 8;

    function pushRound(int256 answer_, uint256 updatedAt_) external {
        ++latestRoundId;
        _rounds[latestRoundId] = Round({ answer: answer_, updatedAt: updatedAt_ });
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        Round memory r_ = _rounds[latestRoundId];
        return (latestRoundId, r_.answer, 0, r_.updatedAt, latestRoundId);
    }

    function getRoundData(uint80 roundId_) external view returns (uint80, int256, uint256, uint256, uint80) {
        Round memory r_ = _rounds[roundId_];
        require(r_.updatedAt != 0 || r_.answer != 0, "no round");
        return (roundId_, r_.answer, 0, r_.updatedAt, roundId_);
    }
}

contract MockBackedAutoFeeToken {
    uint256 public newMultiplier = 1e18;
    uint256 public newMultiplierActivationTime;

    function setMultiplier(uint256 multiplier_) external {
        newMultiplier = multiplier_;
    }

    function getCurrentMultiplier() external view returns (uint256, uint256, uint256) {
        return (newMultiplier, 0, 0);
    }
}

contract MockBackedWrapper {
    MockBackedAutoFeeToken public immutable token;

    constructor(MockBackedAutoFeeToken token_) {
        token = token_;
    }

    function convertToAssets(uint256 shares_) external view returns (uint256) {
        (uint256 multiplier_, , ) = token.getCurrentMultiplier();
        return (shares_ * multiplier_) / 1e18;
    }

    function asset() external view returns (address) {
        return address(token);
    }
}

contract MockLiquidityGovernance {
    address admin;

    constructor(address admin_) {
        admin = admin_;
    }

    // Governance slot = keccak256("eip1967.proxy.admin") - 1
    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        bytes32 govSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        if (slot_ == govSlot) {
            return uint256(uint160(admin));
        }
        return 0;
    }
}

contract MockERC20 {
    uint8 decimals_;
    string symbol_;

    constructor(uint8 dec_, string memory sym_) {
        decimals_ = dec_;
        symbol_ = sym_;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function symbol() external view returns (string memory) {
        return symbol_;
    }
}

// ======================= Admin Interfaces =======================

interface IFluidOracleWrite {
    // Non-view oracle getters; may persist source state
    function getExchangeRateOperateWrite() external returns (uint256 exchangeRate_);

    function getExchangeRateLiquidateWrite() external returns (uint256 exchangeRate_);

    function getExchangeRateOperateDebtWrite() external returns (uint256 exchangeRate_);

    function getExchangeRateLiquidateDebtWrite() external returns (uint256 exchangeRate_);
}

interface IUSDOracle {
    // View getters
    function getPriceView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_);

    function getPriceDetailedView(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_);

    function getPriceDetailedViewRaw(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_);
}

interface IUSDOracleAdmin {
    struct SourceConfig {
        uint8 sourceType;
        address source;
        uint16 capOperand;
    }

    struct OracleKey {
        address token;
        uint256 eMode;
        uint8 isOperate;
        uint8 isCollateral;
    }

    function setTokenType(address token_, uint8 tokenType_) external;

    function setSourceConfig(
        address token_,
        SourceConfig memory src1_,
        SourceConfig memory src2_,
        SourceConfig memory src3_
    ) external;

    function registerTransientOracleKey(OracleKey memory key_) external;

    function setPriceMode(uint8 priceMode_) external;

    function multicall(bytes[] calldata data_) external returns (bytes[] memory results_);
}

// ======================= Test Contract =======================

contract UsdOracleClxWriteIntegrationTest is Test {
    // CLX oracle constants
    uint256 internal constant RATE_MULTIPLIER = 1e19;
    uint256 internal constant MAX_EXTENDED_CAP_PERCENT = 10e4;

    // USD oracle constants (from variables.sol and structs)
    uint8 internal constant TOKEN_TYPE_VOLATILE = 3;
    uint8 internal constant TOKEN_TYPE_STABLE = 2;
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;
    uint8 internal constant SOURCE_STABLE = 3;
    uint8 internal constant PRICE_MODE_MARKET = 1;

    // Market hours session types and constants
    uint8 constant sessionTypeRegular = 1;
    uint16 constant REGULAR_MINUTES = 390; // 6.5h
    uint16 constant POST_MINUTES = 240; // 4h
    uint16 constant PRE_MINUTES = 330; // 5.5h
    uint16 constant WEEKDAY_EXTENDED_MINUTES = 1050; // 17.5h

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    FluidUsEquityMarketHours marketHours;
    MockChainlinkFeed feed;
    MockBackedAutoFeeToken token;
    MockBackedWrapper wrapper;
    FluidCLXStockOracle clxOracle;
    MockLiquidityGovernance liquidityMock;

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

    function setUp() public {
        // Warp to Monday regular session start time
        uint32 monStart = uint32(1_700_000_000);
        vm.warp(uint256(monStart) + 1 hours);

        // Deploy mocks
        liquidityMock = new MockLiquidityGovernance(admin);
        feed = new MockChainlinkFeed();
        token = new MockBackedAutoFeeToken();
        wrapper = new MockBackedWrapper(token);

        // Create token mocks
        stockToken = address(new MockERC20(18, "wSPY"));
        debtToken = address(new MockERC20(6, "USDC"));

        // Deploy market hours
        FluidUsEquityMarketHours impl = new FluidUsEquityMarketHours(address(liquidityMock));
        FluidUsEquityMarketHoursProxy proxy = new FluidUsEquityMarketHoursProxy(
            address(impl),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        marketHours = FluidUsEquityMarketHours(address(proxy));

        // Set up auth and week sessions
        vm.prank(admin);
        marketHours.updateAuth(AUTH, 1);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(_weekWithWeekend(monStart));

        // Deploy CLX oracle
        feed.pushRound(int256(300e8), uint256(monStart + 1 hours));
        clxOracle = new FluidCLXStockOracle(
            CLXStructs.CLXStockOracleConstructorParams({
                infoName: "wSPYx / USD",
                targetDecimals: 27,
                liquidity: address(liquidityMock),
                chainlinkFeed: address(feed),
                backedWrapper: address(wrapper),
                marketHours: address(marketHours),
                rateMultiplier: RATE_MULTIPLIER,
                maxMultiplierChangePercent: 100,
                maxExtendedHoursCapPercent: MAX_EXTENDED_CAP_PERCENT,
                maxPriceGapDownPercent: 4200,
                maxPriceGapUpPercent: 6800
            })
        );

        // Initialize anchor
        clxOracle.updateRegularHoursAnchor(0);
    }

    /// @dev Harness rather than `FluidUsdOracle`: production carries no batch entry for
    ///      `_marketKeyCalls` to run through.
    function _deployUsdOracle() internal returns (address) {
        return
            deployCode(
                "test/foundry/oracleV2/usdOracleForkTestBase.sol:FluidUsdOracleHarness",
                abi.encode(address(liquidityMock))
            );
    }

    function _deployVaultT1Oracle(address usdOracle_) internal returns (address) {
        return
            deployCode(
                "contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol:VaultT1Oracle",
                abi.encode(usdOracle_, stockToken, debtToken, uint256(0), uint256(0))
            );
    }

    function _configureUsdOracle(address usdOracle_) internal {
        // Register stock token as VOLATILE with CLX oracle source
        IUSDOracleAdmin.SourceConfig memory clxSrc = IUSDOracleAdmin.SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(clxOracle),
            capOperand: 0
        });
        IUSDOracleAdmin.SourceConfig memory empty = IUSDOracleAdmin.SourceConfig({
            sourceType: 0,
            source: address(0),
            capOperand: 0
        });

        vm.startPrank(admin);
        // Configure stock token (VOLATILE, CLX source)
        IUSDOracleAdmin(usdOracle_).setTokenType(stockToken, TOKEN_TYPE_VOLATILE);
        IUSDOracleAdmin(usdOracle_).setSourceConfig(stockToken, clxSrc, empty, empty);
        // Register all 4 directions for stock token
        IUSDOracleAdmin(usdOracle_).multicall(_marketKeyCalls(stockToken));

        // Configure debt token (STABLE, $1 source)
        IUSDOracleAdmin(usdOracle_).setTokenType(debtToken, TOKEN_TYPE_STABLE);
        IUSDOracleAdmin.SourceConfig memory stableSrc = IUSDOracleAdmin.SourceConfig({
            sourceType: SOURCE_STABLE,
            source: address(0),
            capOperand: 0
        });
        IUSDOracleAdmin(usdOracle_).setSourceConfig(debtToken, stableSrc, empty, empty);
        // Register all 4 directions for debt token
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

    function test_writePath_persistsAnchorThroughFullStack() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vaultOracle = _deployVaultT1Oracle(usdOracle);

        // Verify anchor is pre-initialized to roundId 1 from setUp
        CLXStructs.CLXStockOracleConfig memory configBefore = clxOracle.getConfig();
        uint80 roundIdBefore = configBefore.lastRegularHoursRoundId;
        assertTrue(roundIdBefore > 0, "anchor should be pre-initialized");

        // Push a new feed round (roundId will be 2)
        uint32 monStart = uint32(1_700_000_000);
        vm.warp(uint256(monStart) + 2 hours); // reference roll delay
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Call write getter through vault oracle
        uint256 rateWritten = IFluidOracleWrite(vaultOracle).getExchangeRateOperateWrite();
        assertTrue(rateWritten > 0, "rate should be nonzero");

        // Verify CLX anchor persisted to new round
        CLXStructs.CLXStockOracleConfig memory configAfter = clxOracle.getConfig();
        assertEq(configAfter.lastRegularHoursRoundId, roundIdBefore + 1, "anchor should advance to new round");
        assertEq(configAfter.lastVerifiedRegularHoursEnd, block.timestamp, "end time should match block.timestamp");
    }

    function test_writePath_liquidateDirectionPersists() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vaultOracle = _deployVaultT1Oracle(usdOracle);

        CLXStructs.CLXStockOracleConfig memory configBefore = clxOracle.getConfig();
        uint80 roundIdBefore = configBefore.lastRegularHoursRoundId;
        assertTrue(roundIdBefore > 0, "anchor should be pre-initialized");

        uint32 monStart = uint32(1_700_000_000);
        vm.warp(uint256(monStart) + 2 hours); // reference roll delay
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Liquidate write path
        uint256 rateLiquidate = IFluidOracleWrite(vaultOracle).getExchangeRateLiquidateWrite();
        assertTrue(rateLiquidate > 0, "liquidate rate should be nonzero");

        CLXStructs.CLXStockOracleConfig memory configAfter = clxOracle.getConfig();
        assertEq(configAfter.lastRegularHoursRoundId, roundIdBefore + 1, "anchor should advance on liquidate");
        assertEq(configAfter.lastVerifiedRegularHoursEnd, block.timestamp, "end time should match");
    }

    function test_writePath_debtLegHitsDebtWriteGetter() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);

        // Vault with supply=debtToken (collateral, STABLE $1) and borrow=stockToken (debt, CLX).
        // Only stockToken (debt leg) touches CLX via getExchangeRateOperateDebtWrite.
        address vaultOracle2 = deployCode(
            "contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol:VaultT1Oracle",
            abi.encode(usdOracle, debtToken, stockToken, uint256(0), uint256(0))
        );

        CLXStructs.CLXStockOracleConfig memory configBefore = clxOracle.getConfig();
        uint80 roundIdBefore = configBefore.lastRegularHoursRoundId;
        assertTrue(roundIdBefore > 0, "anchor should be pre-initialized");

        uint32 monStart = uint32(1_700_000_000);
        vm.warp(uint256(monStart) + 2 hours); // reference roll delay
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Call operate write; collateral leg (stable $1) does not touch CLX, only debt leg does
        uint256 rate = IFluidOracleWrite(vaultOracle2).getExchangeRateOperateWrite();
        assertTrue(rate > 0, "rate should be nonzero");

        // Anchor advanced, proving getExchangeRateOperateDebtWrite on stockToken was called
        CLXStructs.CLXStockOracleConfig memory configAfter = clxOracle.getConfig();
        assertEq(configAfter.lastRegularHoursRoundId, roundIdBefore + 1, "debt leg write must persist anchor");
    }

    function test_viewPath_neverWritesToClx() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vaultOracle = _deployVaultT1Oracle(usdOracle);

        // Snapshot CLX state
        CLXStructs.CLXStockOracleConfig memory snap = clxOracle.getConfig();
        uint80 snapRoundId = snap.lastRegularHoursRoundId;
        uint32 snapEndTime = snap.lastVerifiedRegularHoursEnd;
        uint104 snapMultiplier = snap.acceptedMultiplier;
        uint32 snapMultiplierTime = snap.lastMultiplierUpdateTime;

        uint32 monStart = uint32(1_700_000_000);
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Call all 4 USD oracle price view directions
        IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true); // operate collateral
        IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, false); // operate debt
        IUSDOracle(usdOracle).getPriceView(stockToken, 0, false, true); // liquidate collateral
        IUSDOracle(usdOracle).getPriceView(stockToken, 0, false, false); // liquidate debt
        IUSDOracle(usdOracle).getPriceDetailedView(stockToken, 0, true, true);
        IUSDOracle(usdOracle).getPriceDetailedViewRaw(stockToken, 0, false, false);

        // Vault view getters with success checks
        (bool okOperate, ) = address(vaultOracle).staticcall(abi.encodeWithSignature("getExchangeRateOperate()"));
        assertTrue(okOperate, "vault operate view must succeed");
        (bool okLiquidate, ) = address(vaultOracle).staticcall(abi.encodeWithSignature("getExchangeRateLiquidate()"));
        assertTrue(okLiquidate, "vault liquidate view must succeed");
        (bool okExchangeRate, ) = address(vaultOracle).staticcall(abi.encodeWithSignature("getExchangeRate()"));
        assertTrue(okExchangeRate, "vault exchange rate view must succeed");

        // Verify CLX state unchanged
        CLXStructs.CLXStockOracleConfig memory snapAfter = clxOracle.getConfig();
        assertEq(snapAfter.lastRegularHoursRoundId, snapRoundId, "roundId should not change on view");
        assertEq(snapAfter.lastVerifiedRegularHoursEnd, snapEndTime, "endTime should not change on view");
        assertEq(snapAfter.acceptedMultiplier, snapMultiplier, "multiplier should not change on view");
        assertEq(snapAfter.lastMultiplierUpdateTime, snapMultiplierTime, "multiplierTime should not change on view");
    }

    function test_writeThenViewSameTx() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vaultOracle = _deployVaultT1Oracle(usdOracle);

        uint32 monStart = uint32(1_700_000_000);
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Write then view in same tx
        uint256 rateWrite = IFluidOracleWrite(vaultOracle).getExchangeRateOperateWrite();
        uint256 rateView = IUSDOracle(usdOracle).getPriceView(stockToken, 0, true, true);

        // Decimals: stock 18, debt 6. Price = CLX rate (which is ~300e8 * 1e19 / 1e27 scaled) divided by debt $1
        // Both should resolve to same rate
        assertTrue(rateWrite > 0, "write rate should be nonzero");
        assertTrue(rateView > 0, "view rate should be nonzero");
    }

    function test_multiplierSyncThroughStack() public {
        address usdOracle = _deployUsdOracle();
        _configureUsdOracle(usdOracle);
        address vaultOracle = _deployVaultT1Oracle(usdOracle);

        uint32 monStart = uint32(1_700_000_000);
        feed.pushRound(int256(301e8), uint256(monStart + 2 hours));

        // Snapshot initial multiplier
        CLXStructs.CLXStockOracleConfig memory snap1 = clxOracle.getConfig();
        uint104 mult1 = snap1.acceptedMultiplier;

        // Sync once to warm anchor
        IFluidOracleWrite(vaultOracle).getExchangeRateOperateWrite();

        // Warp 30 days forward to allow 1% multiplier change (max allowed per 30d)
        vm.warp(block.timestamp + 30 days);

        // Push a new feed round at current time
        feed.pushRound(int256(301e8), block.timestamp);

        // Move multiplier by 1% in-band
        uint256 newMult = (uint256(mult1) * 101) / 100;
        token.setMultiplier(newMult);

        // Call write again
        IFluidOracleWrite(vaultOracle).getExchangeRateOperateWrite();

        // Verify multiplier updated
        CLXStructs.CLXStockOracleConfig memory snap2 = clxOracle.getConfig();
        uint104 mult2 = snap2.acceptedMultiplier;
        assertTrue(mult2 > mult1, "multiplier should increase");
        assertLe(mult2, uint104(newMult), "multiplier should not exceed live");
    }
}
