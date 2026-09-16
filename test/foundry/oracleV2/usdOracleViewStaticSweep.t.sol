//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import "./usdOracleForkTestBase.sol";
import { MockFluidOracleWithWrite, ViewOnlyConsumer } from "./usdOracleWriteMode.t.sol";
import { MockSequencerUptimeFeed, FluidUsdOracleL2Harness } from "./usdOracleL2.t.sol";
import { FluidUsdOracleL2 } from "../../../contracts/oracleV2/usdOracle/mainL2.sol";
import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { VaultT1Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol";
import { IUSDOracle } from "../../../contracts/oracleV2/interfaces/iUSDOracle.sol";

/// TEST CONTRACT 1 (L1): Prove all USD oracle view entries are staticcall-safe
contract UsdOracleViewStaticSweepL1Test is UsdOracleForkTestBase {
    MockFluidOracleWithWrite mockFluid;

    function setUp() public override {
        super.setUp();
        // Register USDC with a write-capable mock Fluid source
        mockFluid = new MockFluidOracleWithWrite();
        SourceConfig memory fluidSrc = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(mockFluid),
            capOperand: 0
        });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, fluidSrc, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        // Register all four key combos: (1,1), (1,0), (0,1), (0,0)
        _registerKey(0, 1, 1);
        _registerKey(0, 1, 0);
        _registerKey(0, 0, 1);
        _registerKey(0, 0, 0);
    }

    function _registerKey(uint256 eMode_, uint8 isOperate_, uint8 isCollateral_) internal {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, eMode_, isOperate_, isCollateral_));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
    }

    // Sweep all view entries via staticcall: proves no state-modifying opcode executes
    function test_staticSweep_allViewEntries() public {
        // getPriceView (4 combos)
        (bool ok1, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, true)));
        assertTrue(ok1);

        (bool ok2, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, false)));
        assertTrue(ok2);

        (bool ok3, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, true)));
        assertTrue(ok3);

        (bool ok4, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, false)));
        assertTrue(ok4);

        // getPriceDetailedView (4 combos)
        (bool ok5, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, true))
        );
        assertTrue(ok5);

        (bool ok6, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, false))
        );
        assertTrue(ok6);

        (bool ok7, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, true))
        );
        assertTrue(ok7);

        (bool ok8, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, false))
        );
        assertTrue(ok8);

        // getPriceDetailedViewRaw (4 combos)
        (bool ok9, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, true, true))
        );
        assertTrue(ok9);

        (bool ok10, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, true, false))
        );
        assertTrue(ok10);

        (bool ok11, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, false, true))
        );
        assertTrue(ok11);

        (bool ok12, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, false, false))
        );
        assertTrue(ok12);

        // getPriceRawForMode (modes 1 and 2)
        (bool okRaw1, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceRawForMode, (USDC, 1)));
        assertTrue(okRaw1);

        (bool okRaw2, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceRawForMode, (USDC, 2)));
        assertTrue(okRaw2);

        // getConfiguredTokenOracles
        (bool okCfg, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getConfiguredTokenOracles, (USDC)));
        assertTrue(okCfg);

        // getTokenConfig
        (bool okTokCfg, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getTokenConfig, (USDC)));
        assertTrue(okTokCfg);

        // isGuardian
        (bool okGuard, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.isGuardian, (admin)));
        assertTrue(okGuard);

        // isEmodeValid
        (bool okEmode, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.isEmodeValid, (0, USDC)));
        assertTrue(okEmode);

        // isTokenConfigGovernanceApproved
        (bool okAppr, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.isTokenConfigGovernanceApproved, (USDC))
        );
        assertTrue(okAppr);

        // Ensure no write path was triggered
        assertEq(mockFluid.writeCalls(), 0);
    }

    // Call getPrice (write path) normally, then repeat full staticcall sweep
    function test_staticSweep_afterWritePath() public {
        // Trigger write path: getPrice calls the write getter on the source
        uint256 priceBeforeWrite = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(priceBeforeWrite, 0);
        assertEq(mockFluid.writeCalls(), 1);

        // Record write count after write path
        uint256 writeCountAfter = mockFluid.writeCalls();

        // Now run full staticcall sweep: nothing should fault, and writeCalls must not increase
        (bool ok1, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, true)));
        assertTrue(ok1);

        (bool ok2, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, false)));
        assertTrue(ok2);

        (bool ok3, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, true)));
        assertTrue(ok3);

        (bool ok4, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, false)));
        assertTrue(ok4);

        (bool ok5, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, true))
        );
        assertTrue(ok5);

        (bool ok6, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, false))
        );
        assertTrue(ok6);

        (bool ok7, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, true))
        );
        assertTrue(ok7);

        (bool ok8, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, false))
        );
        assertTrue(ok8);

        // Assert write count unchanged
        assertEq(mockFluid.writeCalls(), writeCountAfter);
    }

    // Test VaultT1Oracle view entries via staticcall
    function test_staticSweep_vaultT1Oracle() public {
        // Register a second token (USDT) with a plain Fluid source for the borrow leg
        MockFluidOracleWithDebt plainFluid = new MockFluidOracleWithDebt();
        SourceConfig memory plainSrc = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(plainFluid),
            capOperand: 0
        });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDT, plainSrc, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        // Register USDT keys so pricing works
        _registerKeyFor(USDT, 0, 1, 1);
        _registerKeyFor(USDT, 0, 1, 0);
        _registerKeyFor(USDT, 0, 0, 1);
        _registerKeyFor(USDT, 0, 0, 0);

        // Deploy VaultT1Oracle with USDC as collateral, USDT as debt
        VaultT1Oracle vaultOracle = new VaultT1Oracle(
            address(usdOracle),
            USDC,
            USDT,
            0, // supplyEMode
            0 // borrowEMode
        );

        // Test view methods via staticcall
        (bool ok1, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRate, ()));
        assertTrue(ok1);

        (bool ok2, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRateOperate, ()));
        assertTrue(ok2);

        (bool ok3, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRateLiquidate, ()));
        assertTrue(ok3);

        (bool ok4, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRateOperateRaw, ()));
        assertTrue(ok4);

        (bool ok5, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRateLiquidateRaw, ()));
        assertTrue(ok5);

        (bool ok6, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getExchangeRateRaw, ()));
        assertTrue(ok6);

        (bool ok7, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.getOracleConfig, ()));
        assertTrue(ok7);

        (bool ok8, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.infoName, ()));
        assertTrue(ok8);

        (bool ok9, ) = address(vaultOracle).staticcall(abi.encodeCall(vaultOracle.targetDecimals, ()));
        assertTrue(ok9);

        // Ensure no write path was triggered on either source
        assertEq(mockFluid.writeCalls(), 0);
    }

    function _registerKeyFor(address token_, uint256 eMode_, uint8 isOperate_, uint8 isCollateral_) internal {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(token_, eMode_, isOperate_, isCollateral_));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
    }
}

/// TEST CONTRACT 2 (L2): Prove L2 oracle view entries with sequencer are staticcall-safe
contract UsdOracleViewStaticSweepL2Test is UsdOracleForkTestBase {
    FluidUsdOracleL2 usdOracleL2;
    MockSequencerUptimeFeed sequencerFeed;
    MockFluidOracleWithWrite mockFluid;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        admin = makeAddr("admin");
        liquidityMock = new MockReadFromStorage();
        liquidityMock.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(admin)));

        // Set up healthy sequencer
        sequencerFeed = new MockSequencerUptimeFeed();
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        usdOracleL2 = new FluidUsdOracleL2Harness(address(liquidityMock), address(sequencerFeed));

        // Assign to base usdOracle for helpers
        usdOracle = FluidUsdOracle(address(usdOracleL2));

        clOracle = new MockChainlinkFeed(IChainlinkAggregatorV3(address(CHAINLINK_FEED)));

        vm.mockCall(USDC, abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));
        vm.mockCall(USDT, abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        vm.startPrank(admin);
        usdOracle.setTokenType(USDC, 2); // STABLE
        usdOracle.setTokenType(USDT, 2); // STABLE
        vm.stopPrank();

        // Register USDC with write-capable mock Fluid source
        mockFluid = new MockFluidOracleWithWrite();
        SourceConfig memory fluidSrc = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(mockFluid),
            capOperand: 0
        });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, fluidSrc, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        // Register all four key combos
        _registerKey(0, 1, 1);
        _registerKey(0, 1, 0);
        _registerKey(0, 0, 1);
        _registerKey(0, 0, 0);
    }

    function _registerKey(uint256 eMode_, uint8 isOperate_, uint8 isCollateral_) internal {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, eMode_, isOperate_, isCollateral_));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
    }

    // L2 view entries with healthy sequencer are staticcall-safe
    function test_L2_staticSweep_allViewEntries() public {
        // getPriceView (4 combos)
        (bool ok1, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, true)));
        assertTrue(ok1);

        (bool ok2, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, false)));
        assertTrue(ok2);

        (bool ok3, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, true)));
        assertTrue(ok3);

        (bool ok4, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, false, false)));
        assertTrue(ok4);

        // getPriceDetailedView (4 combos)
        (bool ok5, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, true))
        );
        assertTrue(ok5);

        (bool ok6, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, true, false))
        );
        assertTrue(ok6);

        (bool ok7, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, true))
        );
        assertTrue(ok7);

        (bool ok8, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedView, (USDC, 0, false, false))
        );
        assertTrue(ok8);

        // getPriceDetailedViewRaw (4 combos)
        (bool ok9, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, true, true))
        );
        assertTrue(ok9);

        (bool ok10, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, true, false))
        );
        assertTrue(ok10);

        (bool ok11, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, false, true))
        );
        assertTrue(ok11);

        (bool ok12, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, false, false))
        );
        assertTrue(ok12);

        // sequencerL2Data view
        (bool okSeq, ) = address(usdOracleL2).staticcall(abi.encodeCall(usdOracleL2.sequencerL2Data, ()));
        assertTrue(okSeq);

        // Other views
        (bool okRaw1, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceRawForMode, (USDC, 1)));
        assertTrue(okRaw1);

        (bool okCfg, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getConfiguredTokenOracles, (USDC)));
        assertTrue(okCfg);

        (bool okTok, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getTokenConfig, (USDC)));
        assertTrue(okTok);

        // No write path triggered
        assertEq(mockFluid.writeCalls(), 0);
    }

    // Negative case: sequencer DOWN -> getPriceView reverts, getPriceDetailedViewRaw succeeds (bypasses guard)
    function test_L2_getPriceView_reverts_whenSequencerDown() public {
        // Set sequencer DOWN: answer = 1 (Chainlink convention)
        sequencerFeed.setRound(2, 1, block.timestamp);

        // getPriceView should revert (guarded by sequencer check)
        (bool okView, ) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, true)));
        assertFalse(okView);

        // getPriceDetailedViewRaw should still succeed (bypasses guard)
        (bool okRaw, ) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceDetailedViewRaw, (USDC, 0, true, true))
        );
        assertTrue(okRaw);
    }
}
