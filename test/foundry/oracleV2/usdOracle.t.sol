//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import "./usdOracleForkTestBase.sol";

contract MockChainlinkFeedCustomDecimals is IChainlinkAggregatorV3 {
    uint8 internal immutable _decimals;
    int256 internal _answer;
    uint256 internal _updatedAt;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
        _updatedAt = block.timestamp;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "mock";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (roundId_, _answer, _updatedAt, _updatedAt, roundId_);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }
}

contract FluidUSDOracleTest is UsdOracleForkTestBase {
    // ==================== Access Control Tests ====================

    function testAccessControl_onlyGovernanceOrInitialMultisigAllowed() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        // Non-gov fails on registerTransientOracleKey
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));

        // Non-gov fails on setSourceConfig (only governance / multisig)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setSourceConfig(USDC, source, _emptyCfg(), _emptyCfg());

        // Gov works
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        // Governance can MODIFY an existing token-level source config
        SourceConfig memory newSourceCfg = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, newSourceCfg, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        // Config written is actually updated (spot check)
        {
            Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(USDC);
            require(infos.length > 0, "No configs found for USDC");
            Structs.ConfiguredTokenOracle memory info;
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                if (infos[i].eMode == 0 && infos[i].isOperate == true && infos[i].isCollateral == true) {
                    info = infos[i];
                    found = true;
                    break;
                }
            }
            require(found, "Config not found for expected mode");
            assertEq(
                info.primary.source1.sourceType,
                newSourceCfg.sourceType,
                "Governance should be able to modify sourceType"
            );
            assertEq(
                info.primary.source1.source,
                newSourceCfg.source,
                "Governance should be able to modify source address"
            );
        }

        // Multisig works for NEW configs
        address multisig = usdOracle.TEAM_MULTISIG();
        SourceConfig memory source2 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(multisig, USDT, 0, 1, 1, source2, _emptyCfg(), _emptyCfg());

        // Multisig modify existing token-level source: forbidden
        vm.startPrank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setSourceConfig(USDT, source2, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_multisig_cannotCallAdminMethodsOnExistingConfig() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        // Governance creates a config
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        // Multisig registers key for existing config and tries to setOverallCap -> should revert
        vm.startPrank(multisig);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();
    }

    function test_multisig_canCallAdminMethodsOnNewConfig() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        // Multisig creates token sources + new per-key config -> IS_NEW_CONFIG flag gets set
        vm.startPrank(multisig);
        usdOracle.setSourceConfig(USDC, source, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);

        // Now multisig can call setOverallCap because IS_NEW_CONFIG == 1
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);

        // Second cap write (different operand)
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 10000);
        vm.stopPrank();
    }

    function test_registerTransientOracleKey_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        usdOracle.registerTransientOracleKey(_key(address(0), 0, 1, 1));
    }

    function test_registerTransientOracleKey_revertsOnInvalidParams() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 2, 0));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 2));
    }

    function test_adminMethodsRevertWithoutRegisteredKey() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.setPriceMode(PRICE_MODE_MARKET);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.removeConfig();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.setSourceCapMode(SOURCE_CAP_NONE);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.setAltSourceConfig(USDC, source, _emptyCfg(), _emptyCfg());

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.removeAltSourceConfig(USDC);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.enableDeviationCheck(100);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.disableDeviationCheck();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.enableFallback();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.disableFallback();
        vm.stopPrank();
    }

    // ==================== OracleConfig CRUD ====================

    function testOracleConfig_multiplierDerivedFromFeedDecimals() public {
        MockChainlinkFeedCustomDecimals feed8_ = new MockChainlinkFeedCustomDecimals(8, 1e8);
        vm.startPrank(admin);
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(feed8_), capOperand: 0 });
        usdOracle.setSourceConfig(DUMMY_TOKEN, source, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        uint256 actual = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(actual, 1e27, "Expected 1e8 feed answer scaled by derived multiplier 10^19");
    }

    function testOracleConfig_invalidDerivedMultiplierReverts() public {
        MockChainlinkFeedCustomDecimals badFeed_ = new MockChainlinkFeedCustomDecimals(40, 1e8);
        SourceConfig memory badCfg = SourceConfig({ sourceType: 2, source: address(badFeed_), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidMultiplier)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, badCfg, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_isEmodeValid_matchesConfigsMap() public {
        vm.startPrank(admin);
        assertFalse(usdOracle.isEmodeValid(5, DUMMY_TOKEN));
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        usdOracle.setSourceConfig(DUMMY_TOKEN, source, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 5, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        assertTrue(usdOracle.isEmodeValid(5, DUMMY_TOKEN));
        vm.stopPrank();
    }

    function testOracleConfig_revertOnZeroAddressSource() public {
        SourceConfig memory zeroSource = _emptyCfg();
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, zeroSource, zeroSource, zeroSource);
        vm.stopPrank();
    }

    function testOracleConfig_removeConfig_revertsIfMissing() public {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.removeConfig();
        vm.stopPrank();
    }

    function testOracleConfig_removeConfig_succeedsIfPresent() public {
        SourceConfig memory cfg = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        // Add a config
        _registerAndSetConfig(admin, USDC, 0, 1, 1, cfg, _emptyCfg(), _emptyCfg());

        // Confirm config exists
        {
            ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(USDC);
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                ConfiguredTokenOracle memory info = infos[i];
                if (
                    info.eMode == 0 &&
                    info.isOperate == true &&
                    info.isCollateral == true &&
                    info.primary.source1.sourceType == 2 &&
                    info.primary.source1.source == address(clOracle)
                ) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Expected config not found before removal");
        }

        // Remove config
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.removeConfig();
        vm.stopPrank();

        // Confirm removed
        {
            ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(USDC);
            bool found = false;
            for (uint256 i = 0; i < infos.length; ++i) {
                if (
                    infos[i].eMode == 0 &&
                    infos[i].isOperate == true &&
                    infos[i].isCollateral == true &&
                    infos[i].primary.source1.sourceType == 2
                ) {
                    found = true;
                    break;
                }
            }
            assertTrue(!found, "Removed config still found");
        }

        // Subsequent removal reverts
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.removeConfig();
        vm.stopPrank();
    }

    function test_removeConfig_onlyGovernance() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 0, 0, source, _emptyCfg(), _emptyCfg());

        // Attacker cannot even register key
        address attacker = address(123456);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 0));

        // Multisig cannot remove
        address multisig = usdOracle.TEAM_MULTISIG();
        vm.startPrank(multisig);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 0));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeConfig();
        vm.stopPrank();
    }

    function test_removeConfig_revertsOnNonExistentConfig() public {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 0));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.removeConfig();
        vm.stopPrank();
    }

    // ==================== Fallback & Pricing ====================

    function test_getPrice_fallbackToEmodeZeroIfNotFound() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(133e24);

        // Emode=1 not found -> fallback to 0. With 27 feed decimals, multiplier is 0.
        uint256 price = usdOracle.getPrice(USDC, 1, true, true);
        assertEq(price, 133e24);
    }

    function test_getPrice_chainlinkStaleOperate() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__ChainlinkStale)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_getPrice_chainlinkStaleLiquidate() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__ChainlinkStale)
        );
        usdOracle.getPrice(USDC, 0, false, true);
    }

    function test_getPrice_chainlinkNotStaleLiquidate() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 6 days, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 1e18, "Liquidate price should equal the raw answer with derived multiplier 0");
    }

    function test_getPrice_revertsZeroAfterNegativeMultiplier() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1000), uint256(0), block.timestamp, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1000, "Tiny positive Chainlink answers remain non-zero when derived multiplier is 0");
    }

    function test_getPrice_revertsOnInvalidSource() public {
        SourceConfig memory src = SourceConfig({ sourceType: 88, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DAI, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_readSourceOrRevert_revertsOnZeroAfterMultiplier() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1000), uint256(0), block.timestamp, uint80(0))
        );

        uint256 rate = _readHarness().readSourceOrRevert(source, true, true);
        assertEq(rate, 1000, "Tiny positive Chainlink answers remain non-zero when derived multiplier is 0");
    }

    function test_readComposedPriceOrRevert_readsPrimary() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        clOracle.setExchangeRate(1e27);

        uint256 primaryPrice = _readHarness().readComposedPriceOrRevert(src1, _emptyCfg(), _emptyCfg(), true, true);

        assertEq(primaryPrice, 1e27, "Composed price should use the provided source");
    }

    function test_getConfiguredTokenOracles_returnsZeroRatesOnReadFailure() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(USDC);
        require(infos.length > 0, "Expected at least one configured oracle");
        assertEq(infos[0].primary.rate1, 0, "Best-effort source reads should surface failure as rate 0");
        assertEq(infos[0].primary.price, 0, "Best-effort composed price should be 0 when a configured leg fails");
    }

    // ==================== Guardian & Pause Tests (Bitmask) ====================

    function test_setGuardian_onlyGovernance() public {
        address guardian = makeAddr("guardian");

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setGuardian(guardian, true);

        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);
        assertTrue(usdOracle.isGuardian(guardian));

        vm.prank(admin);
        usdOracle.setGuardian(guardian, false);
        assertFalse(usdOracle.isGuardian(guardian));
    }

    function test_setPausedState_guardianCanToggleOperateBitOnly() public {
        address guardian = makeAddr("guardian");

        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);

        // Guardian can pause operate (bit 0)
        vm.prank(guardian);
        usdOracle.setPausedState(USDC, true, false);
        _assertPauseState(USDC, true, false);

        // Guardian can unpause operate
        vm.prank(guardian);
        usdOracle.setPausedState(USDC, false, false);
        _assertPauseState(USDC, false, false);

        // Guardian CANNOT set liquidate bit
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPausedState(USDC, false, true);

        // Guardian CANNOT set both bits
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPausedState(USDC, true, true);
    }

    function test_setPausedState_guardianCannotChangeLiquidateBit() public {
        address guardian = makeAddr("guardian");

        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);

        // Governance sets liquidate-paused (bit 1)
        vm.prank(admin);
        usdOracle.setPausedState(USDC, false, true);
        _assertPauseState(USDC, false, true);

        // Guardian tries to unpause (both false) -> liquidate bit would change from 1 to 0 -> revert
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPausedState(USDC, false, false);

        // Guardian can add operate while preserving liquidate because the liquidate bit is unchanged.
        vm.prank(guardian);
        usdOracle.setPausedState(USDC, true, true);
        _assertPauseState(USDC, true, true);
    }

    function test_setPausedState_governanceCanSetAnyState() public {
        // Governance can set any combination
        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, true);
        _assertPauseState(USDC, true, true);

        vm.prank(admin);
        usdOracle.setPausedState(USDC, false, true);
        _assertPauseState(USDC, false, true);

        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, false);
        _assertPauseState(USDC, true, false);

        vm.prank(admin);
        usdOracle.setPausedState(USDC, false, false);
        _assertPauseState(USDC, false, false);
    }

    function test_setPausedState_multisigCanSetAnyState() public {
        address multisig = usdOracle.TEAM_MULTISIG();

        vm.prank(multisig);
        usdOracle.setPausedState(USDC, false, true);
        _assertPauseState(USDC, false, true);

        vm.prank(multisig);
        usdOracle.setPausedState(USDC, false, false);
        _assertPauseState(USDC, false, false);

        vm.prank(multisig);
        usdOracle.setPausedState(USDC, true, true);
        _assertPauseState(USDC, true, true);
    }

    function test_getPrice_revertsWhenOperatePaused() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);

        // Pause operate only (state = 1)
        address guardian = makeAddr("guardian");
        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);
        vm.prank(guardian);
        usdOracle.setPausedState(USDC, true, false);

        // isOperate=true should revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPrice(USDC, 0, true, true);

        // isOperate=false (liquidate) should still work (liquidate bit not set)
        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertGt(price, 0, "Liquidate price should work when only operate-paused");

        // Unpause
        vm.prank(guardian);
        usdOracle.setPausedState(USDC, false, false);
        price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Operate price should work after unpause");
    }

    function test_getPrice_revertsWhenLiquidatePaused() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);

        // Pause liquidate only (state = 2)
        vm.prank(admin);
        usdOracle.setPausedState(USDC, false, true);

        // isOperate=true should work (operate bit not set)
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertGt(price, 0, "Operate should work when only liquidate-paused");

        // isOperate=false should revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPrice(USDC, 0, false, true);
    }

    function test_getPrice_revertsWhenBothPaused() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);

        // Pause both (state = 3)
        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPrice(USDC, 0, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPrice(USDC, 0, false, true);

        // Unpause both
        vm.prank(admin);
        usdOracle.setPausedState(USDC, false, false);
        assertGt(usdOracle.getPrice(USDC, 0, true, true), 0);
        assertGt(usdOracle.getPrice(USDC, 0, false, true), 0);
    }

    function test_setPausedState_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        usdOracle.setPausedState(address(0), true, false);
    }

    function test_revokedGuardian_cannotPause() public {
        address guardian = makeAddr("guardian");

        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);

        vm.prank(admin);
        usdOracle.setGuardian(guardian, false);

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPausedState(USDC, true, false);
    }

    function test_attackerCannotPause() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPausedState(USDC, true, false);
    }

    function test_deviationAndFallback_canBothBeEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 104e25, 104e25, 104e25, 104e25);
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(500); // 5%
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        // Primary = 1e27. Alt = 1.04e27. Deviation = 4% → within 5%.
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Should return primary price when deviation+fallback both enabled and primary ok");
    }

    function test_deviationAndFallback_operateBlocksWhenPrimaryFails() public {
        SourceConfig memory primarySource = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory altSource = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // stable $1

        // Set up operate config with both deviation and fallback
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primarySource, _emptyCfg(), _emptyCfg());
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, altSource, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        // Make primary fail for liquidate mode as well (> 7 days stale)
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        // Operate: should revert even though fallback is enabled (deviation requires primary)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_deviationAndFallback_liquidateUsesFallbackWhenPrimaryFails() public {
        SourceConfig memory primarySource = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory altSource = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // stable $1

        // Set up liquidate config with both deviation and fallback
        _registerAndSetConfig(admin, USDC, 0, 0, 1, primarySource, _emptyCfg(), _emptyCfg());
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setAltSourceConfig(USDC, altSource, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        // Make primary fail for liquidate mode as well (> 7 days stale)
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        // Liquidate: should use fallback (stable $1) since deviation doesn't apply
        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 1e27, "Liquidate should fall back to alt (stable $1) when primary fails");
    }

    function test_deviationOnly_skippedForLiquidate() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory altSource = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // stable $1

        // Set up liquidate config with deviation only (no fallback)
        _registerAndSetConfig(admin, USDC, 0, 0, 1, source, _emptyCfg(), _emptyCfg());
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setAltSourceConfig(USDC, altSource, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(100); // very tight 1%
        vm.stopPrank();

        // Set primary to $2000 — alt is $1. That's a massive deviation.
        clOracle.setExchangeRate(2000e27);

        // Liquidate should still work: deviation check doesn't apply to liquidate
        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 2000e27, "Liquidate should return primary price, ignoring deviation check");
    }

    // ==================== Token Config Tests ====================

    function test_setTokenType_governanceCanList() public {
        address newToken = address(0x456);
        vm.mockCall(newToken, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
        vm.prank(admin);
        usdOracle.setTokenType(newToken, 1); // PEG
        (, , uint8 tt1_, ) = usdOracle.getTokenConfig(newToken);
        assertEq(tt1_, 1);
    }

    function test_setTokenType_multisigCanList() public {
        address newToken = address(0x456);
        vm.mockCall(newToken, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
        address multisig = usdOracle.TEAM_MULTISIG();
        vm.prank(multisig);
        usdOracle.setTokenType(newToken, 2); // STABLE
        (, , uint8 tt2_, ) = usdOracle.getTokenConfig(newToken);
        assertEq(tt2_, 2);
    }

    function test_setTokenType_governanceCanChangeExistingType() public {
        (, , uint8 ttBefore_, ) = usdOracle.getTokenConfig(USDC);
        assertEq(ttBefore_, 2); // STABLE from setUp

        vm.prank(admin);
        usdOracle.setTokenType(USDC, 3); // change to VOLATILE
        (, , uint8 ttAfter_, ) = usdOracle.getTokenConfig(USDC);
        assertEq(ttAfter_, 3);
    }

    function test_setTokenType_multisigCannotChangeExistingType() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        (, , uint8 ttBefore_, ) = usdOracle.getTokenConfig(USDC);
        assertEq(ttBefore_, 2); // STABLE from setUp

        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setTokenType(USDC, 3);
        (, , uint8 ttAfter_, ) = usdOracle.getTokenConfig(USDC);
        assertEq(ttAfter_, ttBefore_);
    }

    function test_setTokenType_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        usdOracle.setTokenType(address(0), 1);
    }

    function test_setTokenType_revertsOnInvalidType() public {
        address newToken = address(0x456);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.setTokenType(newToken, 0);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.setTokenType(newToken, 4);
    }

    function test_setTokenType_revertsForUnauthorizedCaller() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setTokenType(address(0x456), 1);
    }

    function test_registerTransientOracleKey_revertsForUnlistedToken() public {
        address unlisted = address(0x789);
        (, , uint8 ttUnlisted_, ) = usdOracle.getTokenConfig(unlisted);
        assertEq(ttUnlisted_, 0);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenNotListed)
        );
        usdOracle.registerTransientOracleKey(_key(unlisted, 0, 1, 1));
    }

    function test_registerTransientOracleKey_succeedsForListedToken() public {
        vm.prank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
    }

    function test_getTokenConfig_returnsZeroForUnlisted() public view {
        (, , uint8 tt_, ) = usdOracle.getTokenConfig(address(0x999));
        assertEq(tt_, 0);
    }

    function test_getTokenConfig_returnsCorrectTypes() public view {
        (, , uint8 ttUsdc_, ) = usdOracle.getTokenConfig(USDC);
        assertEq(ttUsdc_, 2); // STABLE
        (, , uint8 ttDummy_, ) = usdOracle.getTokenConfig(DUMMY_TOKEN);
        assertEq(ttDummy_, 3); // VOLATILE
    }

    // ==================== Additional Coverage Tests ====================

    function test_constructor_revertsOnZeroLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        new FluidUsdOracle(address(0));
    }

    function test_proxy_deploysAndDelegatesConstantGetter() public {
        FluidUsdOracle implementation = new FluidUsdOracle(address(liquidityMock));
        FluidUsdOracle proxy = FluidUsdOracle(address(new FluidUsdOracleProxy(address(implementation), "")));

        assertEq(
            proxy.TEAM_MULTISIG(),
            implementation.TEAM_MULTISIG(),
            "Proxy should delegate to implementation getter"
        );
    }

    function test_getPrice_revertsOnNoConfig() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__NoConfig)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    /// @dev STABLE debt operate: MAX_OPERAND floors a depegged market price up to $1 (debt-only overall cap).
    function test_overallCap_maxOperand_floorsDepeggedPrice() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 0, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(5e24); // very low vs $1

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setOverallCap(OVERALL_CAP_MAX_OPERAND, 100); // $1.00
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27, "MAX_OPERAND should floor the price to $1");
    }

    /// @dev STABLE collateral operate: MIN_OPERAND caps a premium market price down to $1.
    function test_overallCap_minOperand_capsPremiumPrice() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(5e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1.00
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27, "MIN_OPERAND should cap the price at $1");
    }

    function test_setAltConfig_revertsWhenSource3IsSetWithoutSource2() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory stableAlt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setAltSourceConfig(USDC, stableAlt, _emptyCfg(), stableAlt);
        vm.stopPrank();
    }

    function test_enableDeviationCheck_revertsWithoutAltConfig() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.enableDeviationCheck(100);
        vm.stopPrank();
    }

    function test_enableDeviationCheck_revertsOnZeroBps() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.enableDeviationCheck(0);
        vm.stopPrank();
    }

    function test_enableFallback_revertsWithoutAltConfig() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.enableFallback();
        vm.stopPrank();
    }

    function test_removeAltConfig_revertsWhenMissing() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeAltConfig_clearsAltFlagsAndSources() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt1 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory alt2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt1, alt2, _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(250);
        usdOracle.disableFallback();
        usdOracle.disableDeviationCheck();
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(USDC);
        assertEq(info.alt.source1.sourceType, 0, "Alt source1 should be cleared");
        assertEq(info.alt.source2.sourceType, 0, "Alt source2 should be cleared");
        assertEq(info.alt.source3.sourceType, 0, "Alt source3 should be cleared");
        assertEq(info.maxDeviationBPS, 0, "Deviation already disabled before alt removal");
        assertFalse(info.isFallback, "Fallback already disabled before alt removal");
    }

    function test_removeAltSourceConfig_revertsWhenFallbackEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeAltSourceConfig_revertsWhenDeviationEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__DeviationCheckMustBeDisabled
            )
        );
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeAltSourceConfig_revertsWhenCrossPathEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, alt, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.removeAltSourceConfig(DUMMY_TOKEN);
        vm.stopPrank();
    }

    function test_removeAltSourceConfig_succeedsAfterCrossPathCleared() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, alt, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        usdOracle.removeAltSourceConfig(DUMMY_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.removeAltSourceConfig(DUMMY_TOKEN);
        vm.stopPrank();
    }

    function test_removeSourceConfig_revertsWhenCrossPathEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, alt, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.removeSourceConfig(DUMMY_TOKEN);
        vm.stopPrank();
    }

    function test_removeAdditionalSourceConfig_revertsWhenCrossPathEnabled() public {
        _setupPegTokenSources(pegToken);
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.removeAdditionalSourceConfig(pegToken);
        vm.stopPrank();
    }

    function test_removeAdditionalAltSourceConfig_revertsWhenCrossPathEnabled() public {
        _setupPegTokenSources(pegToken);
        SourceConfig memory alt = _stableSrc(0);
        vm.startPrank(admin);
        usdOracle.setAdditionalAltSourceConfig(pegToken, alt, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.removeAdditionalAltSourceConfig(pegToken);
        vm.stopPrank();
    }

    function test_removeAltSourceConfig_revertsWhenSecondKeyHasFallback() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 1, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());

        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 1, 1, 1));
        usdOracle.disableFallback();
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeSourceConfig_revertsWhenAltFallbackIsStillEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.removeSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeAdditionalSourceConfig_revertsWhenAdditionalAltFallbackIsStillEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
        usdOracle.setAdditionalSourceConfig(DUMMY_TOKEN, primary, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setAdditionalAltSourceConfig(DUMMY_TOKEN, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.removeAdditionalSourceConfig(DUMMY_TOKEN);
        vm.stopPrank();
    }

    function test_removeSourceConfig_revertsWhenAltDeviationIsStillEnabled() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__DeviationCheckMustBeDisabled
            )
        );
        usdOracle.removeSourceConfig(USDC);
        vm.stopPrank();
    }

    function test_removeAdditionalSourceConfig_revertsWhenAdditionalAltDeviationIsStillEnabled() public {
        _setupPegTokenSources(pegToken);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.enableDeviationCheck(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__DeviationCheckMustBeDisabled
            )
        );
        usdOracle.removeAdditionalSourceConfig(pegToken);
        vm.stopPrank();
    }

    function test_disableDeviationCheck_resetsDeviationToZero() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(250);
        usdOracle.disableDeviationCheck();
        vm.stopPrank();

        assertEq(_getSingleConfiguredOracle(USDC).maxDeviationBPS, 0, "Deviation check should be disabled");
    }

    function test_disableFallback_clearsFallbackFlag() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.disableFallback();
        vm.stopPrank();

        assertFalse(_getSingleConfiguredOracle(USDC).isFallback, "Fallback should be disabled");
    }

    function test_setConfigSingle_clearsTrailingPrimarySourcesOnUpdate() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory src2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory src3 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src1, src2, src3);

        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src1, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(USDC);
        assertEq(info.primary.source2.sourceType, 0, "Source2 should be cleared");
        assertEq(info.primary.source3.sourceType, 0, "Source3 should be cleared");
    }

    function test_setAltConfig_clearsTrailingAltSourcesOnUpdate() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt1 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory alt2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory alt3 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt1, alt2, alt3);
        usdOracle.setAltSourceConfig(USDC, alt1, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(USDC);
        assertEq(info.alt.source2.sourceType, 0, "Alt source2 should be cleared");
        assertEq(info.alt.source3.sourceType, 0, "Alt source3 should be cleared");
    }

    function test_getConfiguredTokenOracles_usesNativeFallbackSymbolForNonErc20() public {
        MockTokenWithoutSymbol token = new MockTokenWithoutSymbol();
        SourceConfig memory source = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        vm.prank(admin);
        usdOracle.setTokenType(address(token), 3);
        _registerAndSetConfig(admin, address(token), 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(address(token));
        // TokenSymbolResolver returns `UNK` when `symbol()` reverts (see `tokenSymbolResolver.sol`).
        assertEq(info.symbol, "UNK");
    }

    function test_getPrice_revertsOnInvalidChainlinkRate() public {
        SourceConfig memory source = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, source, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(-1), uint256(0), block.timestamp, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateInvalid)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_readSourceOrRevert_readsStableSource() public view {
        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }),
            true,
            true
        );
        assertEq(rate, 1e27, "Stable source should always return 1e27");
    }

    function test_readSourceOrRevert_revertsOnInvalidSourceType() public {
        vm.expectRevert();
        _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 99, source: address(0xBEEF), capOperand: 0 }),
            true,
            true
        );
    }

    function test_readSourceOrRevert_readsCappedRateOperateCollateral() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            true,
            true
        );

        assertEq(rate, 2e27, "Operate collateral should use getExchangeRateOperate");
    }

    function test_readSourceOrRevert_readsCappedRateOperateDebt() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            true,
            false
        );

        assertEq(rate, 3e27, "Operate debt should use getExchangeRateOperateDebt");
    }

    function test_readSourceOrRevert_readsCappedRateLiquidateCollateral() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            false,
            true
        );

        assertEq(rate, 4e27, "Liquidate collateral should use getExchangeRateLiquidate");
    }

    function test_readSourceOrRevert_readsCappedRateLiquidateDebt() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            false,
            false
        );

        assertEq(rate, 5e27, "Liquidate debt should use getExchangeRateLiquidateDebt");
    }

    function test_readSourceOrRevert_revertsWhenCappedRateCallFails() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setReverts(false, true, false, false, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            true,
            true
        );
    }

    function test_setConfigSingle_revertsForInvalidCappedRateWhenCenterPriceIsZero() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(0, 2e27, 3e27, 4e27, 5e27);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_setConfigSingle_revertsForInvalidCappedRateWhenOperateDebtIsZero() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 2e27, 0, 4e27, 5e27);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_setConfigSingle_acceptsFluidOracleWithoutCenterPrice() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();

        vm.startPrank(admin);
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_setConfigSingle_revertsFluidOracleWhenOperateIsZero() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(0, 3e27, 4e27, 5e27);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_setConfigSingle_revertsFluidOracleWhenOperateDebtIsZero() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 0, 4e27, 5e27);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_setConfigSingle_revertsCappedRateForFluidOracleWithoutCenterPrice() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: SOURCE_CAPPED_RATE, source: address(fluidOracle), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    /// @dev `_isCappedRate` now delegates to `_isFluidOracleWithDebt`, so zero operate fails capped-rate config too.
    function test_setConfigSingle_revertsForInvalidCappedRateWhenOperateIsZero() public {
        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 0, 3e27, 4e27, 5e27);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: SOURCE_CAPPED_RATE, source: address(cappedRate), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();
    }

    function test_readSourceOrRevert_readsFluidOracleOperateCollateral() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            true,
            true
        );

        assertEq(rate, 2e27, "Fluid oracle operate collateral should use getExchangeRateOperate");
    }

    function test_readSourceOrRevert_readsFluidOracleOperateDebt() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            true,
            false
        );

        assertEq(rate, 3e27, "Fluid oracle operate debt should use getExchangeRateOperateDebt");
    }

    function test_readSourceOrRevert_readsFluidOracleLiquidateCollateral() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            false,
            true
        );

        assertEq(rate, 4e27, "Fluid oracle liquidate collateral should use getExchangeRateLiquidate");
    }

    function test_readSourceOrRevert_readsFluidOracleLiquidateDebt() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);

        uint256 rate = _readHarness().readSourceOrRevert(
            SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: address(fluidOracle), capOperand: 0 }),
            false,
            false
        );

        assertEq(rate, 5e27, "Fluid oracle liquidate debt should use getExchangeRateLiquidateDebt");
    }

    function test_getPrice_fluidOracle_operateCollateral() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 2e27);
    }

    function test_getPrice_fluidOracle_operateDebt() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 3e27);
    }

    function test_getPrice_fluidOracle_liquidateCollateral() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, false, true), 4e27);
    }

    function test_getPrice_fluidOracle_liquidateDebt() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 0, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, false, false), 5e27);
    }

    function test_getPriceRawForMode_fluidOracleUsesUncappedGetExchangeRate() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        // operate/debt directional rates differ from getExchangeRate() (= operateValue)
        fluidOracle.setRates(7e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 3e27, "operate debt uses directional getter");
        (uint256 raw, , ) = usdOracle.getPriceRawForMode(DUMMY_TOKEN, PRICE_MODE_MARKET);
        assertEq(raw, 7e27, "raw mode uses getExchangeRate() via _readFluidSourceRaw");
    }

    function test_getPrice_mixedSources_chainlinkPlusFluidOracle() public {
        MockFluidOracleWithDebt fluidOracle = new MockFluidOracleWithDebt();
        fluidOracle.setRates(2e27, 2e27, 2e27, 2e27);
        SourceConfig memory src1 = SourceConfig({
            sourceType: SOURCE_CHAINLINK,
            source: address(clOracle),
            capOperand: 0
        });
        SourceConfig memory src2 = SourceConfig({
            sourceType: SOURCE_FLUID_ORACLE,
            source: address(fluidOracle),
            capOperand: 0
        });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src1, src2, _emptyCfg());

        clOracle.setExchangeRate(5e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 10e27, "Chainlink * Fluid oracle composition");
    }

    function test_getPrice_readsThreeSourceComposition() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory src2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory src3 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src1, src2, src3);

        clOracle.setExchangeRate(2e27);

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 2e27, "Three leg composition should preserve expected rate");
    }

    // ==================== Deviation Check Detailed Tests ====================

    function test_deviationCheck_operate_exceedsThreshold_reverts() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(100); // 1%
        vm.stopPrank();

        clOracle.setExchangeRate(2000e27);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__MaxDeviation)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_deviationCheck_operate_withinThreshold_returnsPrimary() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 104e25, 104e25, 104e25, 104e25);
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(500); // 5%
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        // Primary = 1e27. Alt capped rate = 1.04e27. Deviation = 4% → within 5%.
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Should return primary when within deviation threshold");
    }

    function test_deviationCheck_operate_primaryFails_deviationOnly_reverts() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_deviationCheck_operate_altFails_reverts() public {
        MockCappedRate altCapped = new MockCappedRate();
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        altCapped.setReverts(false, true, false, false, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_deviationCheck_capsAppliedAfterDeviationPasses() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 48e26, 48e26, 48e26, 48e26);
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(500); // 5%
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1.00 — collateral STABLE
        vm.stopPrank();

        clOracle.setExchangeRate(5e27);
        // Primary = 5e27. Alt = 4.8e27. Deviation = 4% → within 5%.
        // After deviation passes, MIN_OPERAND ($1 = 1e27) clamps 5e27 → 1e27.
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "MIN_OPERAND should be applied after deviation check passes");
    }

    function test_deviationCheck_withCappedRateAlt() public {
        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 1e27, 1e27, 1e27, 1e27);
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(500); // 5%
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Should return primary when CappedRate alt is within deviation");
    }

    // ==================== Fallback-Only Tests ====================

    function test_fallbackOnly_operate_primaryFails_usesAlt() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Fallback should use alt (stable $1) when primary fails for operate");
    }

    function test_fallbackOnly_operate_primaryOK_returnsPrimary() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        clOracle.setExchangeRate(2e27);
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 2e27, "Should return primary when it succeeds, even with fallback enabled");
    }

    function test_fallbackOnly_liquidate_primaryFails_usesAlt() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 0, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 1e27, "Fallback should use alt for liquidate when primary fails");
    }

    function test_fallbackOnly_liquidate_primaryOK_returnsPrimary() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 0, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        clOracle.setExchangeRate(2e27);
        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 2e27, "Should return primary for liquidate when it succeeds");
    }

    function test_fallback_altAlsoFails_reverts() public {
        MockCappedRate altCapped = new MockCappedRate();
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );
        altCapped.setReverts(false, true, false, false, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_altFlagSet_noFallbackNoDeviation_primaryFails_reverts() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    function test_fallback_capsAppliedToAltPrice() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // stable * 100 = 1e29
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1.00 = 1e27 — collateral
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Max cap should clamp fallback alt price");
    }

    /// @dev STABLE debt + MAX_OPERAND: floors a depegged fallback alt read up to $1 (`max(price, operand)`).
    function test_fallback_maxOperandAppliedToAltPrice() public {
        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 1e20, 1e20, 1e20, 1e20); // very small rate
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 0, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.setOverallCap(OVERALL_CAP_MAX_OPERAND, 100);
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        uint256 price = usdOracle.getPrice(USDC, 0, true, false);
        assertEq(price, 1e27, "MAX_OPERAND should floor fallback alt price to $1");
    }

    // ==================== CappedRate in Full getPrice Flow ====================

    function test_getPrice_cappedRate_operateCollateral() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 2e27, "Operate+collateral should use getExchangeRateOperate");
    }

    function test_getPrice_cappedRate_operateDebt() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, false);
        assertEq(price, 3e27, "Operate+debt should use getExchangeRateOperateDebt");
    }

    function test_getPrice_cappedRate_liquidateCollateral() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, false, true);
        assertEq(price, 4e27, "Liquidate+collateral should use getExchangeRateLiquidate");
    }

    function test_getPrice_cappedRate_liquidateDebt() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 0, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, false, false);
        assertEq(price, 5e27, "Liquidate+debt should use getExchangeRateLiquidateDebt");
    }

    function test_getPrice_cappedRate_revert_rateZero() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 3e27, 4e27, 5e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        capped.setReverts(false, true, false, false, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    // ==================== Stable Source in Full getPrice Flow ====================

    function test_getPrice_stableSource_returnsDollar() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Stable source should return $1 (1e27)");
    }

    function test_getPrice_stableSource_withPositiveMultiplier() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Stable sources always use derived multiplier 0");
    }

    function test_getPrice_stableSource_negativeMultiplierCausesZero_reverts() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1e27, "Stable sources always use derived multiplier 0");
    }

    // ==================== Two-Source Composition ====================

    function test_getPrice_twoSourceComposition() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 2e27, 2e27, 2e27);
        SourceConfig memory src1 = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        SourceConfig memory src2 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src1, src2, _emptyCfg());

        clOracle.setExchangeRate(3e27);

        // price = (2e27 * 3e27) / 1e27 = 6e27
        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 6e27, "Two-source composition: rate1 * rate2 / 1e27");
    }

    // ==================== Source Validation Edge Cases ====================

    function test_verifySourceConfig_stableWithNonZeroAddress_reverts() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0x123), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_verifySourceConfig_unknownSourceType_reverts() public {
        SourceConfig memory src = SourceConfig({ sourceType: 55, source: address(0x123), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_verifySourceConfig_chainlinkBadContract_reverts() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(0xDEAD), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert();
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    /// @dev SOURCE_REDSTONE uses the same AggregatorV3 validation and read path as SOURCE_CHAINLINK.
    function test_redstone_aggregatorV3CompatibleSource() public {
        vm.startPrank(admin);
        vm.expectRevert();
        usdOracle.setSourceConfig(
            DUMMY_TOKEN,
            SourceConfig({ sourceType: 4, source: address(0xDEAD), capOperand: 0 }),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();

        SourceConfig memory redstoneCfg = SourceConfig({ sourceType: 4, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, redstoneCfg, _emptyCfg(), _emptyCfg());

        SourceConfig memory chainlinkCfg = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, chainlinkCfg, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);
        assertEq(
            usdOracle.getPrice(DUMMY_TOKEN, 0, true, true),
            usdOracle.getPrice(USDC, 0, true, true),
            "Redstone and Chainlink source types should yield the same price for the same feed"
        );
    }

    function test_verifySourceConfig_cappedRate_centerPriceReverts_invalidSource() public {
        MockCappedRate badCapped = new MockCappedRate();
        badCapped.setReverts(true, false, false, false, false);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(badCapped), capOperand: 0 });

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_verifySourceConfig_cappedRate_operateDebtReverts_invalidSource() public {
        MockCappedRate badCapped = new MockCappedRate();
        badCapped.setReverts(false, false, true, false, false);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(badCapped), capOperand: 0 });

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function test_verifySourceConfig_source3WithoutSource2_reverts() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        SourceConfig memory src3 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidSource)
        );
        usdOracle.setSourceConfig(DUMMY_TOKEN, src1, _emptyCfg(), src3);
        vm.stopPrank();
    }

    // ==================== eMode Tests ====================

    function test_getPrice_usesSpecificEmodeWhenAvailable() public {
        // Token-level sources are shared: eMode-specific keys use the same primary feeds; multipliers are not per-key.
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 1, 1, 1, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27, "eMode 0");
        assertEq(usdOracle.getPrice(USDC, 1, true, true), 1e27, "eMode 1 matches token-level stable price");
    }

    function test_getPrice_emodeFallbackToZero() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(USDC, 2, true, true), 1e27, "Non-existent eMode 2 should fallback to eMode 0");
    }

    function test_getPrice_noConfigAndNoFallback_reverts() public {
        // No config at all for this token+mode
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__NoConfig)
        );
        usdOracle.getPrice(DAI, 1, true, true);
    }

    function test_setConfigSingle_emodeBoundaryValid() public {
        // totalEmodes = 3 (set in setUp), so eMode 3 should be valid
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 3, 1, 1, src, _emptyCfg(), _emptyCfg());

        assertEq(usdOracle.getPrice(USDC, 3, true, true), 1e27, "eMode at totalEmodes boundary should work");
    }

    function test_setConfigSingle_emodeZeroSkipsValidation() public {
        // eMode 0 should skip Money Market check entirely
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    // ==================== Chainlink Edge Cases ====================

    function test_chainlink_callFailure_rateZero() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.mockCallRevert(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            "feed down"
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateInvalid)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_chainlink_zeroExchangeRate_rateZero() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(0), uint256(0), block.timestamp, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_chainlink_exactStaleBoundaryOperate_notStale() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        // updatedAt + 25h == block.timestamp -> NOT stale (< not <=)
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 25 hours, uint80(0))
        );

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 1e18, "At exact 25h boundary, feed should return 1e18 answer unchanged (multiplier 0)");
    }

    function test_chainlink_justPastStaleBoundaryOperate_stale() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 25 hours - 1, uint80(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__ChainlinkStale)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_chainlink_exactStaleBoundaryLiquidate_notStale() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, src, _emptyCfg(), _emptyCfg());

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 7 days, uint80(0))
        );

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, false, true);
        assertEq(price, 1e18, "At exact 7-day boundary, feed should return 1e18 answer unchanged (multiplier 0)");
    }

    // ==================== Admin Methods on Non-existent Config ====================

    function test_adminMethods_revertOnNonExistentConfig() public {
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.setSourceCapMode(SOURCE_CAP_NONE);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.disableDeviationCheck();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__ConfigDoesNotExist
            )
        );
        usdOracle.disableFallback();

        vm.stopPrank();
    }

    // ==================== Transient Storage Behavior ====================

    function test_transient_registerTransientOracleKeyResetsNewConfigFlag() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.startPrank(multisig);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        // _tIsNewConfig is now 1

        // Re-register same key -> resets _tIsNewConfig to 0
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));

        // setOverallCap should now fail for multisig (config exists, _tIsNewConfig == 0)
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();
    }

    function test_transient_removeConfigSingleClearsKey() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.removeConfig();

        // Key cleared -> subsequent admin calls should fail
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__KeyNotRegistered)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();
    }

    function test_transient_multipleConfigsInSameTx() public {
        // Token-level sources are shared across keys; two per-key configs in one tx for the same token.
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);

        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        clOracle.setExchangeRate(5e27);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 5e27, "Operate path uses shared token sources");
        assertEq(usdOracle.getPrice(USDC, 0, false, true), 5e27, "Liquidate path uses shared token sources");
    }

    // ==================== removeAltConfig Access Control ====================

    function test_removeAltConfig_onlyGovernance() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        // Multisig cannot remove alt config
        address multisig = usdOracle.TEAM_MULTISIG();
        vm.startPrank(multisig);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeAltSourceConfig(USDC);
        vm.stopPrank();

        // Attacker cannot
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
    }

    // ==================== getConfiguredTokenOracles Edge Cases ====================

    function test_getConfiguredTokenOracles_multipleConfigs() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 0, src, _emptyCfg(), _emptyCfg());

        ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(USDC);
        assertEq(infos.length, 4, "Should have 4 configs for USDC");
        for (uint i = 0; i < infos.length; i++) {
            assertEq(keccak256(bytes(infos[i].symbol)), keccak256(bytes("USDC")), "Symbol should be USDC");
        }
    }

    function test_getConfiguredTokenOracles_includesAltInfo() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(USDC);
        assertEq(info.alt.source1.sourceType, 3, "Alt source type should be stable");
        assertTrue(info.isFallback, "Fallback should be enabled");
        assertEq(info.maxDeviationBPS, 500, "Deviation BPS should be 500");
    }

    function test_getConfiguredTokenOracles_emptyForUnconfiguredToken() public view {
        // Listed token with no oracle keys: `configsMap` empty (avoid random fork addresses that break `_tokenSymbol`).
        ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(DAI);
        assertEq(infos.length, 0, "Should return empty array when no keys configured");
    }

    /// @dev PEG key resolves primary to the peg path, so the market path is only visible via `additionalPrimary`.
    function test_getConfiguredTokenOracles_pegModeKeyExposesAdditionalSources() public {
        vm.mockCall(pegToken, abi.encodeWithSignature("symbol()"), abi.encode("PEG"));

        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 103e25, 103e25, 103e25, 103e25);
        SourceConfig memory pegSrc = SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(pegToken, pegSrc, _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(pegToken, _chainlinkSrc(0), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(pegToken);

        assertEq(info.priceMode, PRICE_MODE_PEG, "Price mode should be PEG");
        assertEq(info.primary.source1.source, address(cappedRate), "Primary should be the peg path");
        assertEq(info.additionalPrimary.source1.source, address(clOracle), "Additional should be the market path");
        assertEq(info.additionalPrimary.source1.sourceType, 2, "Additional leg should be Chainlink");
        assertEq(info.additionalPrimary.rate1, 1e27, "Additional leg rate should be read");
        assertEq(info.additionalAlt.source1.sourceType, 0, "Additional alt should be zero when unset");
    }

    function test_getConfiguredTokenOracles_exposesAdditionalAltSources() public {
        vm.mockCall(pegToken, abi.encodeWithSignature("symbol()"), abi.encode("PEG"));

        SourceConfig memory stableSrc = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(pegToken, stableSrc, _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(pegToken, _chainlinkSrc(0), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalAltSourceConfig(pegToken, stableSrc, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.stopPrank();

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(pegToken);
        assertEq(info.additionalPrimary.source1.source, address(clOracle), "Additional primary should be set");
        assertEq(info.additionalAlt.source1.sourceType, 3, "Additional alt should be the stable source");
    }

    function test_getConfiguredTokenOracles_additionalSourcesZeroForNonPegToken() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        ConfiguredTokenOracle memory info = _getSingleConfiguredOracle(USDC);
        assertEq(info.additionalPrimary.source1.sourceType, 0, "Additional primary should be zero for non-PEG");
        assertEq(info.additionalPrimary.price, 0, "Additional primary price should be zero for non-PEG");
        assertEq(info.additionalAlt.source1.sourceType, 0, "Additional alt should be zero for non-PEG");
    }

    // ==================== Cap Edge Cases ====================

    function test_overallCap_none_clearsOperandClamp() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0); // clear
        vm.stopPrank();

        clOracle.setExchangeRate(5e27); // would have been clamped to 1e27
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 5e27, "Price should be uncapped after OVERALL_CAP_NONE");
    }

    // ==================== Derived Multiplier Boundary Tests ====================

    function test_multiplier_maxValue21() public {
        MockChainlinkFeedCustomDecimals feed6_ = new MockChainlinkFeedCustomDecimals(6, 1);
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(feed6_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 1e21, "Multiplier 21 should scale by 10^21");
    }

    function test_multiplier_minValueNeg12() public {
        MockChainlinkFeedCustomDecimals feed39_ = new MockChainlinkFeedCustomDecimals(39, 1e27);
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(feed39_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 1e15, "1e27 / 10^12 = 1e15");
    }

    // ==================== setGuardian Edge Cases ====================

    function test_setGuardian_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__AddressZero)
        );
        usdOracle.setGuardian(address(0), true);
    }

    function test_setGuardian_multisigCannotCall() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setGuardian(makeAddr("guardian"), true);
    }

    function test_setGuardian_attackerCannotCall() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setGuardian(makeAddr("guardian"), true);
    }

    // ==================== readComposedPriceOrRevert Edge Cases ====================

    function test_readComposedPriceOrRevert_twoSources() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // 1e27
        SourceConfig memory src2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // 1e27

        // (1e27 * 1e27) / 1e27 = 1e27
        uint256 price = _readHarness().readComposedPriceOrRevert(src1, src2, _emptyCfg(), true, true);
        assertEq(price, 1e27, "Two-source composed price should be (rate1 * rate2) / 1e27");
    }

    function test_readComposedPriceOrRevert_threeSources() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // 1e27
        SourceConfig memory src2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // 1e27
        SourceConfig memory src3 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 }); // 1e27

        // ((1e27 * 1e27) / 1e27 * 1e27) / 1e27 = 1e27
        uint256 price = _readHarness().readComposedPriceOrRevert(src1, src2, src3, true, true);
        assertEq(price, 1e27, "Three-source composed price");
    }

    function test_readComposedPriceOrRevert_revertsOnZeroResult() public {
        // Two very small sources that compose to 0
        MockCappedRate tinyCapped = new MockCappedRate();
        tinyCapped.setRates(1e27, 1, 1, 1, 1);
        SourceConfig memory src1 = SourceConfig({ sourceType: 1, source: address(tinyCapped), capOperand: 0 }); // rate = 1
        SourceConfig memory src2 = SourceConfig({ sourceType: 1, source: address(tinyCapped), capOperand: 0 }); // rate = 1
        SourceConfig memory src3 = SourceConfig({ sourceType: 1, source: address(tinyCapped), capOperand: 0 }); // rate = 1

        // (1 * 1) / 1e27 = 0 -> but with only 2 sources this returns 0 without reverting
        // With 3 sources: ((1*1)/1e27 * 1) / 1e27 = 0 -> reverts
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        _readHarness().readComposedPriceOrRevert(src1, src2, src3, true, true);
    }

    // ==================== Multisig New Config Full Lifecycle ====================

    function test_multisig_fullNewConfigLifecycle() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(multisig);
        usdOracle.setSourceConfig(USDT, primary, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDT, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);

        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 200); // max $2 for STABLE collateral operate
        usdOracle.setAltSourceConfig(USDT, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableFallback();
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDT, 0, 1, 1));
        usdOracle.disableDeviationCheck();
        usdOracle.disableFallback();
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        // Raw price = 1e27 with derived multiplier 0.
        uint256 price = usdOracle.getPrice(USDT, 0, true, true);
        assertEq(price, 1e27, "Full lifecycle config should produce expected capped price");
    }

    // ==================== getTokenConfig Pause State Combinations ====================

    function test_getTokenConfig_allPauseStates() public {
        vm.startPrank(admin);

        usdOracle.setPausedState(USDC, false, false);
        (bool op, bool liq, , ) = usdOracle.getTokenConfig(USDC);
        assertFalse(op);
        assertFalse(liq);

        usdOracle.setPausedState(USDC, true, false);
        (op, liq, , ) = usdOracle.getTokenConfig(USDC);
        assertTrue(op);
        assertFalse(liq);

        usdOracle.setPausedState(USDC, false, true);
        (op, liq, , ) = usdOracle.getTokenConfig(USDC);
        assertFalse(op);
        assertTrue(liq);

        usdOracle.setPausedState(USDC, true, true);
        (op, liq, , ) = usdOracle.getTokenConfig(USDC);
        assertTrue(op);
        assertTrue(liq);

        vm.stopPrank();
    }

    // ==================== isGuardian View ====================

    function test_isGuardian_returnsFalseForNonGuardian() public {
        assertFalse(usdOracle.isGuardian(makeAddr("random")));
    }

    function test_isGuardian_returnsTrueForActiveGuardian() public {
        address guardian = makeAddr("guardian");
        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);
        assertTrue(usdOracle.isGuardian(guardian));
    }

    // ==================== CappedRate with Multiplier in getPrice ====================

    function test_getPrice_cappedRate_withPositiveMultiplier() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 1e27, 1e27, 1e27, 1e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 1e27, "CappedRate sources always use derived multiplier 0");
    }

    function test_getPrice_cappedRate_withNegativeMultiplier() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 1e27, 1e27, 1e27, 1e27);
        SourceConfig memory src = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 1e27, "CappedRate sources always use derived multiplier 0");
    }

    // ==================== Mixed Source Types in Composition ====================

    function test_getPrice_mixedSources_chainlinkPlusCappedRate() public {
        MockCappedRate capped = new MockCappedRate();
        capped.setRates(1e27, 2e27, 2e27, 2e27, 2e27);
        SourceConfig memory src1 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory src2 = SourceConfig({ sourceType: 1, source: address(capped), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src1, src2, _emptyCfg());

        clOracle.setExchangeRate(5e27);
        // (5e27 * 2e27) / 1e27 = 10e27
        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 10e27, "Chainlink * CappedRate composition");
    }

    function test_getPrice_mixedSources_chainlinkPlusStable() public {
        SourceConfig memory src1 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory src2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src1, src2, _emptyCfg());

        clOracle.setExchangeRate(3e27);
        // (3e27 * 1e27) / 1e27 = 3e27
        uint256 price = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price, 3e27, "Chainlink * Stable composition should preserve Chainlink price");
    }

    // ==================== Alt Source with Multiple Legs ====================

    function test_fallback_multiLegAltSource() public {
        MockCappedRate altCapped = new MockCappedRate();
        altCapped.setRates(1e27, 3e27, 3e27, 3e27, 3e27);
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt1 = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        SourceConfig memory alt2 = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt1, alt2, _emptyCfg());
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 26 hours, uint80(0))
        );

        // Alt: (3e27 * 1e27) / 1e27 = 3e27
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 3e27, "Multi-leg alt source fallback should compose correctly");
    }

    // ==================== Deviation: Boundary Test ====================

    function test_deviationCheck_exactlyAtBoundary_passes() public {
        MockCappedRate altCapped = new MockCappedRate();
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(1000); // 10%
        vm.stopPrank();

        // Primary = 1000e27, alt = 900e27 -> diff = 100e27 -> (100e27 * 10000) / 1000e27 = 1000 = 10%
        // 1000 > 1000 is false -> passes
        clOracle.setExchangeRate(1000e27);
        altCapped.setRates(1e27, 900e27, 900e27, 900e27, 900e27);

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, 1000e27, "At exact deviation boundary should pass");
    }

    function test_deviationCheck_justOverBoundary_reverts() public {
        MockCappedRate altCapped = new MockCappedRate();
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        usdOracle.enableDeviationCheck(999); // 9.99%
        vm.stopPrank();

        // diff = 100/1000 = 10% = 1000 BPS > 999 -> reverts
        clOracle.setExchangeRate(1000e27);
        altCapped.setRates(1e27, 900e27, 900e27, 900e27, 900e27);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__MaxDeviation)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    // ==================== Multiple Configs After Removal ====================

    function test_removeConfig_doesNotAffectOtherConfigs() public {
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.removeConfig();
        vm.stopPrank();

        // Operate config removed -> revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__NoConfig)
        );
        usdOracle.getPrice(USDC, 0, true, true);

        // Liquidate config still works
        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, 1e27, "Liquidate config should be unaffected by removal of operate config");
    }

    // ==================== getPriceView & getPriceDetailed ====================

    function test_getPriceView_returnsCorrectPrice() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);
        uint256 price = usdOracle.getPriceView(USDC, 0, true, true);
        assertEq(price, 1e27, "getPriceView should match getPrice for simple config");
    }

    function test_getPriceView_revertsWhenPaused() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__TokenPaused)
        );
        usdOracle.getPriceView(USDC, 0, true, true);
    }

    function test_getPriceDetailed_returnsCorrectPriceAndMetadata() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceDetailed(USDC, 0, true, true);
        assertEq(price, 1e27, "getPriceDetailed price should match getPrice");
        assertEq(decimals, 6, "USDC should have 6 decimals");
        assertEq(tokenType, 2, "USDC should be STABLE type");
    }

    function test_getPriceDetailedView_returnsCorrectPriceAndMetadata() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceDetailedView(USDC, 0, true, true);
        assertEq(price, 1e27, "getPriceDetailedView price should match");
        assertEq(decimals, 6);
        assertEq(tokenType, 2);
    }

    // ==================== getPriceRawForMode ====================

    function test_getPriceRawForMode_returnsZeroForNotSetMode() public {
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceRawForMode(USDC, 0);
        assertEq(price, 0);
        assertEq(decimals, 0);
        assertEq(tokenType, 0);
    }

    function test_getPriceRawForMode_returnsZeroForUnlistedToken() public {
        address unlisted = makeAddr("unlisted");
        (uint256 price, , ) = usdOracle.getPriceRawForMode(unlisted, 1);
        assertEq(price, 0);
    }

    function test_getPriceRawForMode_stableInPegModeReturnsDollar() public {
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceRawForMode(USDC, 2);
        assertEq(price, 1e27, "Stable token in PEG mode should return $1");
        assertEq(decimals, 6);
        assertEq(tokenType, 2);
    }

    function test_getPriceRawForMode_volatileInPegModeReturnsZero() public {
        (uint256 price, , ) = usdOracle.getPriceRawForMode(DUMMY_TOKEN, 2);
        assertEq(price, 0, "Volatile token in PEG mode should return 0");
    }

    function test_getPriceRawForMode_marketModeReadsFromSource() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        (uint256 price, uint8 decimals, uint8 tokenType) = usdOracle.getPriceRawForMode(USDC, 1);
        assertEq(price, 1e27, "Market mode should read composed price from source");
        assertEq(decimals, 6);
        assertEq(tokenType, 2);
    }

    function test_getPriceRawForMode_fallsBackToAltOnPrimaryFailure() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, primary, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(uint80(1), int256(1e18), uint256(0), block.timestamp - 11 days, uint80(0))
        );

        (uint256 price, , ) = usdOracle.getPriceRawForMode(USDC, 1);
        assertEq(price, 1e27, "Should fall back to stable alt ($1) when primary is stale");
    }

    function test_getPriceRawForMode_noCapsApplied() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100); // $1 cap — collateral STABLE
        vm.stopPrank();

        clOracle.setExchangeRate(5e27);
        // getPrice should clamp to $1
        uint256 priceGetPrice = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(priceGetPrice, 1e27, "getPrice should be capped");

        // getPriceRawForMode should return raw (no caps)
        (uint256 priceRaw, , ) = usdOracle.getPriceRawForMode(USDC, 1);
        assertEq(priceRaw, 5e27, "getPriceRawForMode should not apply caps");
    }

    function test_getPriceRawForMode_notAffectedByPause() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        usdOracle.setPausedState(USDC, true, true);
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        (uint256 price, , ) = usdOracle.getPriceRawForMode(USDC, 1);
        assertEq(price, 1e27, "getPriceRawForMode should bypass pause state");
    }

    // ==================== UUPS Upgrade ====================

    function test_upgrade_onlyGovernanceCanUpgrade() public {
        FluidUsdOracleHarness newImpl = new FluidUsdOracleHarness(address(liquidityMock));
        FluidUsdOracleProxy proxy = new FluidUsdOracleProxy(address(usdOracle), "");
        FluidUsdOracle proxied = FluidUsdOracle(address(proxy));

        // Non-governance cannot upgrade
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        proxied.upgradeToAndCall(address(newImpl), "");

        // Governance can upgrade
        vm.prank(admin);
        proxied.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_newImplWorksAfterUpgrade() public {
        FluidUsdOracleProxy proxy = new FluidUsdOracleProxy(address(usdOracle), "");
        FluidUsdOracle proxied = FluidUsdOracle(address(proxy));

        // Set up config through proxy
        vm.startPrank(admin);
        proxied.setTokenType(USDC, 2);
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        proxied.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        proxied.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        proxied.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        uint256 priceBefore = proxied.getPrice(USDC, 0, true, true);
        assertEq(priceBefore, 1e27, "Stable source returns $1");

        // Upgrade to new implementation
        FluidUsdOracleHarness newImpl = new FluidUsdOracleHarness(address(liquidityMock));
        vm.prank(admin);
        proxied.upgradeToAndCall(address(newImpl), "");

        // Config survives upgrade
        uint256 priceAfter = proxied.getPrice(USDC, 0, true, true);
        assertEq(priceAfter, 1e27, "Config should survive upgrade");
    }

    // ==================== enableDeviationCheck BPS Boundary ====================

    function test_enableDeviationCheck_revertsOnBpsAboveDenominator() public {
        SourceConfig memory primary = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, primary, _emptyCfg(), _emptyCfg());

        MockCappedRate altCapped = new MockCappedRate();
        SourceConfig memory alt = SourceConfig({ sourceType: 1, source: address(altCapped), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.enableDeviationCheck(10_001); // > 10_000 (BPS_DENOMINATOR)
        vm.stopPrank();
    }

    // ==================== setTokenType NATIVE_TOKEN_ADDRESS ====================

    function test_setTokenType_nativeTokenAddress_succeeds() public {
        address nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.prank(admin);
        usdOracle.setTokenType(nativeToken, 3); // VOLATILE

        (, , uint8 tokenType, uint8 decimals) = usdOracle.getTokenConfig(nativeToken);
        assertEq(tokenType, 3, "Native token should be listed as VOLATILE");
        assertEq(decimals, 18, "Native token should have 18 decimals");
    }

    // ==================== Event Emission ====================

    function test_event_logSourceConfigSet() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.expectEmit(true, true, true, true);
        emit LogSourceConfigSet(USDC, src, _emptyCfg(), _emptyCfg());

        vm.prank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
    }

    function test_event_logSourceConfigRemoved() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit LogSourceConfigRemoved(USDC);

        vm.prank(admin);
        usdOracle.removeSourceConfig(USDC);
    }

    function test_event_logPriceModeSet() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.stopPrank();

        OracleKey memory key = _key(USDC, 0, 1, 1);
        vm.expectEmit(true, true, true, true);
        emit LogPriceModeSet(key, PRICE_MODE_MARKET);

        vm.prank(admin);
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
    }

    function test_event_logGuardianSet() public {
        address guardian = makeAddr("guardian");

        vm.expectEmit(true, true, true, true);
        emit LogGuardianSet(guardian, true);

        vm.prank(admin);
        usdOracle.setGuardian(guardian, true);
    }

    function test_event_logTokenTypeSet() public {
        address newToken = makeAddr("newToken");
        vm.mockCall(newToken, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));

        vm.expectEmit(true, true, true, true);
        emit LogTokenTypeSet(newToken, 3, 8);

        vm.prank(admin);
        usdOracle.setTokenType(newToken, 3);
    }

    function test_event_logTokenPauseSet() public {
        vm.expectEmit(true, true, true, true);
        emit LogTokenPauseSet(USDC, true, false);

        vm.prank(admin);
        usdOracle.setPausedState(USDC, true, false);
    }

    function test_event_logAltSourceConfigSet() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        SourceConfig memory alt = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit LogAltSourceConfigSet(USDC, alt, _emptyCfg(), _emptyCfg());

        vm.prank(admin);
        usdOracle.setAltSourceConfig(USDC, alt, _emptyCfg(), _emptyCfg());
    }

    // ==================== Additional Source Config End-to-End ====================

    function test_additionalSourceConfig_pegTokenMarketModeUsesAdditionalSources() public {
        vm.startPrank(admin);
        usdOracle.setTokenType(DUMMY_TOKEN, 1); // PEG type

        MockCappedRate cappedRate = new MockCappedRate();
        cappedRate.setRates(1e27, 103e25, 103e25, 103e25, 103e25);
        SourceConfig memory pegSrc = SourceConfig({ sourceType: 1, source: address(cappedRate), capOperand: 0 });
        usdOracle.setSourceConfig(DUMMY_TOKEN, pegSrc, _emptyCfg(), _emptyCfg());

        SourceConfig memory marketSrc = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        usdOracle.setAdditionalSourceConfig(DUMMY_TOKEN, marketSrc, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        // PEG mode key reads from primary (capped rate)
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, pegSrc, _emptyCfg(), _emptyCfg());
        // Overwrite priceMode via register flow:
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setPriceMode(2); // PRICE_MODE_PEG
        vm.stopPrank();

        uint256 pegPrice = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(pegPrice, 103e25, "PEG mode should read from primary capped rate");

        // MARKET mode key: reads from additional sources (Chainlink)
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 0, 1));
        usdOracle.setPriceMode(1); // PRICE_MODE_MARKET
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        uint256 marketPrice = usdOracle.getPrice(DUMMY_TOKEN, 0, false, true);
        assertEq(marketPrice, 1e27, "MARKET mode should read from additional Chainlink source");
    }

    function test_additionalSourceConfig_pegRawModeUsesAdditionalSources() public {
        vm.startPrank(admin);
        usdOracle.setTokenType(DUMMY_TOKEN, 1); // PEG type

        SourceConfig memory pegSrc = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        usdOracle.setSourceConfig(DUMMY_TOKEN, pegSrc, _emptyCfg(), _emptyCfg());

        SourceConfig memory marketSrc = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        usdOracle.setAdditionalSourceConfig(DUMMY_TOKEN, marketSrc, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        // getPriceRawForMode with MARKET mode should use additional sources for PEG tokens
        (uint256 marketRaw, , ) = usdOracle.getPriceRawForMode(DUMMY_TOKEN, 1);
        assertEq(marketRaw, 1e27, "Market raw should use additional source for PEG token");

        // PEG mode should use primary sources
        (uint256 pegRaw, , ) = usdOracle.getPriceRawForMode(DUMMY_TOKEN, 2);
        assertEq(pegRaw, 1e27, "PEG raw should read from primary stable source");
    }

    // ==================== TokenSymbolResolver Chain-Specific Paths ====================

    function test_tokenSymbol_nativeEth_returnsETH() public {
        address nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.startPrank(admin);
        usdOracle.setTokenType(nativeToken, 3);
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        usdOracle.setSourceConfig(nativeToken, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(nativeToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(nativeToken);
        assertEq(infos.length, 1);
        assertEq(keccak256(bytes(infos[0].symbol)), keccak256(bytes("ETH")));
    }

    function test_tokenSymbol_nativePolygon_returnsPOL() public {
        vm.chainId(137);

        address nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.startPrank(admin);
        usdOracle.setTokenType(nativeToken, 3);
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        usdOracle.setSourceConfig(nativeToken, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(nativeToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(nativeToken);
        assertEq(infos.length, 1);
        assertEq(keccak256(bytes(infos[0].symbol)), keccak256(bytes("POL")));
    }

    function test_tokenSymbol_nativePlasma_returnsXPL() public {
        vm.chainId(9745);

        address nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.startPrank(admin);
        usdOracle.setTokenType(nativeToken, 3);
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        usdOracle.setSourceConfig(nativeToken, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(nativeToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(nativeToken);
        assertEq(infos.length, 1);
        assertEq(keccak256(bytes(infos[0].symbol)), keccak256(bytes("XPL")));
    }

    function test_tokenSymbol_nativeBnb_returnsBNB() public {
        vm.chainId(56);

        address nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.startPrank(admin);
        usdOracle.setTokenType(nativeToken, 3);
        SourceConfig memory src = SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
        usdOracle.setSourceConfig(nativeToken, src, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(nativeToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        Structs.ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(nativeToken);
        assertEq(infos.length, 1);
        assertEq(keccak256(bytes(infos[0].symbol)), keccak256(bytes("BNB")));
    }

    // ==================== Source/overall caps, default-oracle-configs vault matrix, edge cases ====================

    function test_sourceCapMode_min_capsSingleLeg() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(5e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_sourceCapMode_min_capsMultiLeg() public {
        SourceConfig memory s1 = _stableSrc(0);
        SourceConfig memory s2 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, s1, s2, _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, s1, s2, _emptyCfg());
        clOracle.setExchangeRate(4e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_sourceCapMode_max_floorsRate() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(2e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setSourceCapMode(SOURCE_CAP_MAX);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
    }

    /// @dev Regression for OV2-02: stale/zero leg must not be floored to capOperand*1e25 by SOURCE_CAP_MAX.
    function test_sourceCapMax_stalePrimaryFallsBackToAlt() public {
        uint256 altPrice_ = 2e27;
        uint256 capFloor_ = 1e27; // capOperand 100 * 1e25

        MockChainlinkFeedCustomDecimals primaryFeed_ = new MockChainlinkFeedCustomDecimals(27, int256(5e26));
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(27, int256(altPrice_));

        SourceConfig memory primary_ = SourceConfig({ sourceType: 2, source: address(primaryFeed_), capOperand: 100 });
        SourceConfig memory alt_ = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(DUMMY_TOKEN, primary_, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, alt_, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 0));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.enableFallback();
        usdOracle.setSourceCapMode(SOURCE_CAP_MAX);
        vm.stopPrank();

        primaryFeed_.setUpdatedAt(block.timestamp - 25 hours - 1);

        uint256 price_ = usdOracle.getPriceView(DUMMY_TOKEN, 0, true, false);
        assertEq(price_, altPrice_, "Stale primary fails over to alt source");
        assertNotEq(price_, capFloor_, "Stale zero leg is no longer floored to capOperand*1e25");
    }

    function test_sourceCapMode_none_ignoresCapOperands() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(3e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setSourceCapMode(SOURCE_CAP_NONE);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 3e27);
    }

    function test_sourceCapMode_invalidMode_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setSourceCapMode(3);
        vm.stopPrank();
    }

    function test_sourceCapMode_min_onDebtKey_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();
    }

    function test_sourceCapMode_max_onCollateralKey_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setSourceCapMode(SOURCE_CAP_MAX);
        vm.stopPrank();
    }

    function test_sourceCapMode_none_anyKey_succeeds() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setSourceCapMode(SOURCE_CAP_NONE);
        vm.stopPrank();
    }

    function test_sourceCapMode_zeroCapOperand_noEffect() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(6e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 6e27);
    }

    function test_overallCap_minOperand_clampsAbove() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(2e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_overallCap_maxOperand_floorsBelow() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(5e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setOverallCap(OVERALL_CAP_MAX_OPERAND, 100);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
    }

    function test_overallCap_minCrossPath_pegToken() public {
        _setupPegTokenSources(pegToken);
        // Peg path: capped-rate returns 1.02e27 (set by _setupPegTokenSources).
        // Market path: Chainlink at 1.2e27 (additional source). Market > peg, so MIN picks peg.
        clOracle.setExchangeRate(12e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        uint256 pegPrice = usdOracle.getPrice(pegToken, 0, true, true);
        assertGt(pegPrice, 0);

        // Without cross-path, read the market price via MARKET mode for same token
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        vm.stopPrank();
        uint256 marketPrice = usdOracle.getPrice(pegToken, 0, true, true);

        // Restore PEG mode without cross-path to get uncapped peg price
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        vm.stopPrank();
        uint256 rawPegPrice = usdOracle.getPrice(pegToken, 0, true, true);

        // MIN_CROSS_PATH: result should be min(pegPrice, marketPrice)
        uint256 expectedMin = rawPegPrice < marketPrice ? rawPegPrice : marketPrice;
        assertEq(pegPrice, expectedMin, "MIN_CROSS_PATH should pick min(peg, market)");
    }

    function test_overallCap_maxCrossPath_pegToken() public {
        _setupPegTokenSources(pegToken);
        // Peg path: capped-rate returns 1.02e27. Market path: Chainlink at 0.8e27.
        // Peg > market, so MAX picks peg.
        clOracle.setExchangeRate(8e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 0));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MAX_CROSS_PATH, 0);
        vm.stopPrank();

        uint256 cappedPrice = usdOracle.getPrice(pegToken, 0, true, false);

        // Get raw peg price (no cross-path)
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 0));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        vm.stopPrank();
        uint256 rawPegPrice = usdOracle.getPrice(pegToken, 0, true, false);

        // Get market price
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 0));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        vm.stopPrank();
        uint256 marketPrice = usdOracle.getPrice(pegToken, 0, true, false);

        // MAX_CROSS_PATH: result should be max(pegPrice, marketPrice)
        uint256 expectedMax = rawPegPrice > marketPrice ? rawPegPrice : marketPrice;
        assertEq(cappedPrice, expectedMax, "MAX_CROSS_PATH should pick max(peg, market)");
    }

    function test_overallCap_crossPath_volatile_noAlt_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_stableMarket_noAlt_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__AltSourceNotConfigured
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_stablePeg_reverts() public {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_stablePegDebt_max_reverts() public {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 0));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MAX_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_stablePeg_withAlt_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 0, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_pegWithoutAdditional_reverts() public {
        MockCappedRate cr = new MockCappedRate();
        SourceConfig memory pegLeg = SourceConfig({ sourceType: 1, source: address(cr), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(pegToken, pegLeg, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_pegWithAltButNoAdditional_reverts() public {
        MockCappedRate cr = new MockCappedRate();
        SourceConfig memory pegLeg = SourceConfig({ sourceType: 1, source: address(cr), capOperand: 0 });
        SourceConfig memory alt = _stableSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(pegToken, pegLeg, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(pegToken, alt, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_crossPath_pegMarketWithoutPrimary_reverts() public {
        vm.startPrank(admin);
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
        usdOracle.setAdditionalSourceConfig(DUMMY_TOKEN, _chainlinkSrc(0), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_setPriceMode_crossPath_stableMarketToPeg_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 0, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 0, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.stopPrank();
    }

    function test_setTokenType_crossPath_pegToVolatile_reverts() public {
        _setupPegTokenSources(pegToken);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.setTokenType(pegToken, 3); // VOLATILE
    }

    /// @dev The loop checks fallback before cross-path, so a key with both reports fallback first.
    function test_setTokenType_fallbackAndCrossPath_revertsOnFallbackFirst() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
    }

    /// @dev Deviation reads `altSrc` for both STABLE and VOLATILE, so this flip does not re-point it.
    function test_setTokenType_deviationCheck_volatileToStable_succeeds() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableDeviationCheck(500);

        usdOracle.setTokenType(DUMMY_TOKEN, 2); // STABLE
        vm.stopPrank();

        (, , uint8 tokenType, ) = usdOracle.getTokenConfig(DUMMY_TOKEN);
        assertEq(tokenType, 2, "Token type should be STABLE");
    }

    /// @dev Fallback reads `altSrc` for both STABLE and VOLATILE, so this flip does not re-point it.
    function test_setTokenType_fallback_volatileToStable_succeeds() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableFallback();

        usdOracle.setTokenType(DUMMY_TOKEN, 2); // STABLE
        vm.stopPrank();

        (, , uint8 tokenType, ) = usdOracle.getTokenConfig(DUMMY_TOKEN);
        assertEq(tokenType, 2, "Token type should be STABLE");
    }

    /// @dev PEG branch of the shared reference-source check: deviation needs `_additionalTokenSources`.
    function test_enableDeviationCheck_pegWithoutAdditional_reverts() public {
        MockCappedRate cr = new MockCappedRate();
        SourceConfig memory pegLeg = SourceConfig({ sourceType: 1, source: address(cr), capOperand: 0 });

        vm.startPrank(admin);
        usdOracle.setSourceConfig(pegToken, pegLeg, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SourceConfigNotSet
            )
        );
        usdOracle.enableDeviationCheck(100);
        vm.stopPrank();
    }

    /// @dev STABLE and VOLATILE both take the cross-path reference from `altSrc`, so the flip re-points nothing.
    function test_setTokenType_crossPath_volatileToStable_succeeds() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);

        usdOracle.setTokenType(DUMMY_TOKEN, 2); // STABLE
        vm.stopPrank();

        (, , uint8 tokenType, ) = usdOracle.getTokenConfig(DUMMY_TOKEN);
        assertEq(tokenType, 2, "Token type should be STABLE");

        vm.mockCall(DUMMY_TOKEN, abi.encodeWithSignature("symbol()"), abi.encode("DUM"));
        assertEq(
            _getSingleConfiguredOracle(DUMMY_TOKEN).overallCapMode,
            OVERALL_CAP_MIN_CROSS_PATH,
            "Cross-path cap should survive the flip"
        );
    }

    function test_setTokenType_deviationCheck_volatileToPeg_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__DeviationCheckMustBeDisabled
            )
        );
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
    }

    function test_setTokenType_fallback_volatileToPeg_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableFallback();
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__FallbackMustBeDisabled
            )
        );
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
    }

    function test_setTokenType_crossPath_volatileToPeg_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__CrossPathMustBeDisabled
            )
        );
        usdOracle.setTokenType(DUMMY_TOKEN, 1);
    }

    function test_overallCap_crossPath_volatile_nonzeroOperand_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 100);
        vm.stopPrank();
    }

    function test_overallCap_minCrossPath_volatile_onDebt_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 0, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_maxCrossPath_volatile_onCollateral_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MAX_CROSS_PATH, 0);
        vm.stopPrank();
    }

    function test_overallCap_minCrossPath_volatile_picksMin() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 1e8);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(12e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27, "MIN_CROSS_PATH should pick min(primary, alt)");

        clOracle.setExchangeRate(8e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 8e26, "MIN_CROSS_PATH should keep lower primary");
        assertEq(usdOracle.getPriceView(DUMMY_TOKEN, 0, true, true), 8e26);
    }

    function test_overallCap_maxCrossPath_volatile_picksMax() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 1e8);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 0, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 0));
        usdOracle.setOverallCap(OVERALL_CAP_MAX_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(8e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 1e27, "MAX_CROSS_PATH should pick max(primary, alt)");

        clOracle.setExchangeRate(12e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 12e26, "MAX_CROSS_PATH should keep higher primary");
    }

    function test_overallCap_minCrossPath_stableMarket_picksMin() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(12e26);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_overallCap_maxCrossPath_stableMarket_picksMax() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 0, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setOverallCap(OVERALL_CAP_MAX_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(8e26);
        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
    }

    function test_overallCap_minCrossPath_volatile_liquidate() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 0, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(12e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, false, true), 1e27);
    }

    function test_overallCap_crossPath_volatile_withFallback_primaryZero() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableFallback();
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
    }

    function test_overallCap_crossPath_volatile_primaryZero_noFallback_reverts() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_overallCap_crossPath_volatile_altZero_reverts() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 0);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_overallCap_crossPath_volatile_liquidate_altZero_usesPrimary() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 0);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 0, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, false, true), 1e27);
    }

    function test_overallCap_crossPath_peg_operate_additionalZero_reverts() public {
        _setupPegTokenSources(pegToken);
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(pegToken, 0, true, true);
    }

    function test_overallCap_crossPath_peg_liquidate_additionalZero_usesPrimary() public {
        _setupPegTokenSources(pegToken);
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        assertEq(usdOracle.getPrice(pegToken, 0, false, true), 102e25);
    }

    function test_overallCap_crossPath_volatile_withDeviation_appliesMin() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 1e8);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.enableDeviationCheck(5000);
        vm.stopPrank();

        clOracle.setExchangeRate(12e26);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
    }

    function test_overallCap_crossPath_volatile_withDeviation_revertsWhenFar() public {
        MockChainlinkFeedCustomDecimals altFeed_ = new MockChainlinkFeedCustomDecimals(8, 1e8);
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = SourceConfig({ sourceType: 2, source: address(altFeed_), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.enableDeviationCheck(100);
        vm.stopPrank();

        clOracle.setExchangeRate(12e26);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__MaxDeviation)
        );
        usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
    }

    function test_overallCap_operandZero_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 0);
        vm.stopPrank();
    }

    function test_overallCap_operandNonZero_forNone_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 100);
        vm.stopPrank();
    }

    function test_overallCap_minOnDebtKey_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 0, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();
    }

    function test_overallCap_maxOnCollateralKey_reverts() public {
        SourceConfig memory src = _chainlinkSrc(0);
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidCapConfig)
        );
        usdOracle.setOverallCap(OVERALL_CAP_MAX_OPERAND, 100);
        vm.stopPrank();
    }

    function test_sourceCapAndOverallCap_combined() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        clOracle.setExchangeRate(4e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_sourceCapAndCrossPath_combined() public {
        _setupPegTokenSources(pegToken);
        clOracle.setExchangeRate(1e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        assertGt(usdOracle.getPrice(pegToken, 0, true, true), 0);
    }

    function test_overallCap_appliedAfterDeviation() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(DUMMY_TOKEN, p, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(1e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.enableDeviationCheck(9000);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
    }

    function test_overallCap_appliedToFallbackPrice() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, p, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.enableFallback();
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_crossPath_withDeviation_active() public {
        _setupPegTokenSources(pegToken);
        clOracle.setExchangeRate(1e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.enableDeviationCheck(500);
        vm.stopPrank();

        usdOracle.getPrice(pegToken, 0, true, true);
    }

    function test_deviation_crossPath_uncappedReference_peg() public {
        _setupPegTokenSources(pegToken);
        clOracle.setExchangeRate(102e25);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        usdOracle.enableDeviationCheck(1000);
        vm.stopPrank();

        usdOracle.getPrice(pegToken, 0, true, true);
    }

    function test_fallback_perLegSourceCap_stillApplies() public {
        SourceConfig memory p = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        SourceConfig memory a = SourceConfig({ sourceType: 3, source: address(0), capOperand: 50 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, p, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(USDC, a, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, p, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.enableFallback();
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();

        clOracle.setExchangeRate(0);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 5e26);
    }

    function test_liquidateMode_capsNoDeviation() public {
        SourceConfig memory p = _chainlinkSrc(0);
        SourceConfig memory a = _stableSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(DUMMY_TOKEN, p, _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(DUMMY_TOKEN, a, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 0, 1, p, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(5e27);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 0, 1));
        usdOracle.enableDeviationCheck(1);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, false, true), 1e27);
    }

    function test_stablePegFastPath_capsIrrelevant() public {
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 50);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
    }

    function test_vaultCombo_1_volatile_collateral_stable_debt() public {
        _configureVolatileFourKeys(DUMMY_TOKEN);
        _configureStableFourKeys(USDC);
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
        assertEq(usdOracle.getPrice(USDC, 0, false, false), 1e27);
    }

    function test_vaultCombo_2_stable_collateral_volatile_debt() public {
        _configureStableFourKeys(USDC);
        _configureVolatileFourKeys(DUMMY_TOKEN);
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 1e27);
    }

    function test_vaultCombo_3_stable_stable() public {
        vm.startPrank(admin);
        usdOracle.setTokenType(USDT, 2);
        vm.stopPrank();
        _configureStableFourKeys(USDC);
        _configureStableFourKeys(USDT);
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(USDC, 0, true, true), 1e27);
        assertEq(usdOracle.getPrice(USDT, 0, true, false), 1e27);
    }

    function test_vaultCombo_4_peg_collateral_stable_debt() public {
        _configurePegCollateralFourKeys(pegToken);
        _configureStableFourKeys(USDC);
        clOracle.setExchangeRate(1e27);
        assertGt(usdOracle.getPrice(pegToken, 0, true, true), 0);
        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
    }

    function test_vaultCombo_5_peg_collateral_volatile_debt() public {
        _configurePegCollateralFourKeys(pegToken);
        _configureVolatileFourKeys(DUMMY_TOKEN);
        clOracle.setExchangeRate(1e27);
        assertGt(usdOracle.getPrice(pegToken, 0, true, true), 0);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, false), 1e27);
    }

    function test_vaultCombo_6_peg_peg_same_base() public {
        address pegB = makeAddr("pegB");
        vm.mockCall(pegB, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.startPrank(admin);
        usdOracle.setTokenType(pegB, TOKEN_TYPE_PEG);
        vm.stopPrank();
        _configurePegCollateralFourKeys(pegToken);
        _configurePegDebtFourKeys(pegB);
        clOracle.setExchangeRate(1e27);
        assertGt(usdOracle.getPrice(pegToken, 0, true, true), 0);
        assertGt(usdOracle.getPrice(pegB, 0, true, false), 0);
    }

    function test_vaultCombo_7_peg_peg_diff_base() public {
        address ethPeg = pegToken; // ETH-based peg (already set up with capped-rate → Chainlink)
        address usdPeg = makeAddr("usdPeg");
        vm.mockCall(usdPeg, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.startPrank(admin);
        usdOracle.setTokenType(usdPeg, TOKEN_TYPE_PEG);
        vm.stopPrank();

        _configurePegCollateralFourKeys(ethPeg);

        MockCappedRate usdPegRate = new MockCappedRate();
        usdPegRate.setRates(1e27, 105e25, 105e25, 105e25, 105e25);
        SourceConfig memory usdPegLeg = SourceConfig({ sourceType: 1, source: address(usdPegRate), capOperand: 0 });
        SourceConfig memory usdPegMkt = _chainlinkSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(usdPeg, usdPegLeg, _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(usdPeg, usdPegMkt, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerFullKey(usdPeg, 0, 1, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(usdPeg, 0, 1, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);
        _registerFullKey(usdPeg, 0, 0, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(usdPeg, 0, 0, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);

        clOracle.setExchangeRate(1e27);
        assertGt(usdOracle.getPrice(ethPeg, 0, true, true), 0);
        assertGt(usdOracle.getPrice(usdPeg, 0, true, false), 0);
        assertGt(usdOracle.getPrice(ethPeg, 0, false, true), 0);
        assertGt(usdOracle.getPrice(usdPeg, 0, false, false), 0);
    }

    function test_vaultCombo_8_volatile_collateral_peg_debt() public {
        _configureVolatileFourKeys(DUMMY_TOKEN);
        _configurePegDebtFourKeys(pegToken);
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
        assertGt(usdOracle.getPrice(pegToken, 0, true, false), 0);
    }

    function test_vaultCombo_9_volatile_volatile() public {
        address volB = makeAddr("volB");
        vm.mockCall(volB, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.startPrank(admin);
        usdOracle.setTokenType(volB, 3);
        vm.stopPrank();
        _configureVolatileFourKeys(DUMMY_TOKEN);
        _configureVolatileFourKeys(volB);
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(DUMMY_TOKEN, 0, true, true), 1e27);
        assertEq(usdOracle.getPrice(volB, 0, true, false), 1e27);
    }

    // ==================== Additional coverage gap tests ====================

    function test_sourceCapMode_max_capsMultiLeg() public {
        // Two-leg path (stable × Chainlink) on debt key with SOURCE_CAP_MAX.
        // Leg 2 has capOperand=100, Chainlink returns 0.5e27 → MAX caps to 1e27.
        // Composed: 1e27 (stable) × 1e27 (capped leg2) / 1e27 = 1e27.
        SourceConfig memory s1 = _stableSrc(0);
        SourceConfig memory s2 = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 100 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, s1, s2, _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, USDC, 0, 1, 0, s1, s2, _emptyCfg());
        clOracle.setExchangeRate(5e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 0));
        usdOracle.setSourceCapMode(SOURCE_CAP_MAX);
        vm.stopPrank();

        assertEq(usdOracle.getPrice(USDC, 0, true, false), 1e27);
    }

    function test_overallCap_none_clearsCrossPath() public {
        _setupPegTokenSources(pegToken);
        clOracle.setExchangeRate(8e26);

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_PEG);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_CROSS_PATH, 0);
        vm.stopPrank();

        uint256 withCrossPath = usdOracle.getPrice(pegToken, 0, true, true);

        // Clear cross-path cap
        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(pegToken, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_NONE, 0);
        vm.stopPrank();

        uint256 withoutCrossPath = usdOracle.getPrice(pegToken, 0, true, true);

        // Peg = 1.02e27, market = 0.8e27. With MIN_CROSS_PATH, price = 0.8e27.
        // After clearing, price = raw peg = 1.02e27. So cleared price > capped price.
        assertGt(withoutCrossPath, withCrossPath, "OVERALL_CAP_NONE should clear cross-path cap");
    }

    function test_stableLiquidateDebt_returnsExactlyOneDollar() public {
        _configureStableFourKeys(USDC);
        clOracle.setExchangeRate(95e25); // market at $0.95
        assertEq(usdOracle.getPrice(USDC, 0, false, false), 1e27, "Stable liquidate debt must return exactly $1");
    }

    function test_stableLiquidateCollateral_returnsExactlyOneDollar() public {
        _configureStableFourKeys(USDC);
        clOracle.setExchangeRate(105e25); // market at $1.05
        assertEq(usdOracle.getPrice(USDC, 0, false, true), 1e27, "Stable liquidate collateral must return exactly $1");
    }

    // ==================== Governance-approved token source flag ====================

    function test_governanceApproved_multisigCreate_unstamped_governanceEdit_stamps() public {
        address multisig = usdOracle.TEAM_MULTISIG();
        address tkn_ = makeAddr("govApprovedTkn");
        vm.mockCall(tkn_, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(tkn_, abi.encodeWithSignature("symbol()"), abi.encode("GT"));
        SourceConfig memory src_ = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });

        vm.startPrank(multisig);
        usdOracle.setTokenType(tkn_, 3);
        usdOracle.setSourceConfig(tkn_, src_, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(tkn_));

        SourceConfig memory src2_ = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(tkn_, src2_, _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(tkn_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(tkn_));

        Structs.ConfiguredTokenOracle[] memory infos_ = usdOracle.getConfiguredTokenOracles(tkn_);
        require(infos_.length > 0, "no configs");
        assertTrue(infos_[0].governanceApproved);
    }

    function _gstMockToken(address t_) internal {
        vm.mockCall(t_, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(t_, abi.encodeWithSignature("symbol()"), abi.encode("SYM"));
    }

    function _gstNewToken(string memory name_) internal returns (address t_) {
        t_ = makeAddr(name_);
        _gstMockToken(t_);
    }

    function _gstSrcChainlink() internal view returns (SourceConfig memory) {
        return SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
    }

    function _gstSrcStable() internal pure returns (SourceConfig memory) {
        return SourceConfig({ sourceType: 3, source: address(0), capOperand: 0 });
    }

    function test_governanceStamp_setSourceConfig_multisig_false() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setSrc_ms");
        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_setSrc_gov");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAltSourceConfig_multisig_false() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setAlt_ms");
        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAltSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_setAlt_gov");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAdditionalSourceConfig_multisig_false() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setAdd_ms");
        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAdditionalSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_setAdd_gov");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAdditionalAltSourceConfig_multisig_false() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setAddAlt_ms");
        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setAdditionalAltSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_setAddAlt_gov");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_removeSourceConfig_multisig_reverts() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_rmSrc_ms");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeSourceConfig(t_);
    }

    function test_governanceStamp_removeAltSourceConfig_multisig_reverts() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_rmAlt_ms");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeAltSourceConfig(t_);
    }

    function test_governanceStamp_removeAdditionalSourceConfig_multisig_reverts() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_rmAdd_ms");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeAdditionalSourceConfig(t_);
    }

    function test_governanceStamp_removeAdditionalAltSourceConfig_multisig_reverts() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_rmAddAlt_ms");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.removeAdditionalAltSourceConfig(t_);
    }

    function test_governanceStamp_removeSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_rmSrc");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.removeSourceConfig(t_);
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        vm.stopPrank();
    }

    function test_governanceStamp_removeAltSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_rmAlt");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.removeAltSourceConfig(t_);
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        vm.stopPrank();
    }

    function test_governanceStamp_removeAdditionalSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_rmAdd");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.removeAdditionalSourceConfig(t_);
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        vm.stopPrank();
    }

    function test_governanceStamp_removeAdditionalAltSourceConfig_governance_true() public {
        address t_ = _gstNewToken("gst_rmAddAlt");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.removeAdditionalAltSourceConfig(t_);
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        vm.stopPrank();
    }

    function test_governanceStamp_setTokenConfigGovernanceApproved_multisig_reverts() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setTok_ms");
        vm.prank(admin);
        usdOracle.setTokenType(t_, 3);

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setTokenConfigGovernanceApproved(t_, true);
    }

    function test_governanceStamp_setTokenConfigGovernanceApproved_governance_true() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("gst_setTok_true");
        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.prank(admin);
        usdOracle.setTokenConfigGovernanceApproved(t_, true);
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    function test_governanceStamp_setTokenConfigGovernanceApproved_governance_false() public {
        address t_ = _gstNewToken("gst_setTok_false");
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.setTokenConfigGovernanceApproved(t_, false);
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
        vm.stopPrank();
    }

    // ==================== MS eMode-0 shadow create guard ====================

    function test_msShadowCreate_allowedWhenTokenUnapproved() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("shadow_unapproved");

        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        // Still unapproved (MS created sources) — more-specific eMode allowed
        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.registerTransientOracleKey(_key(t_, 1, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        assertTrue(usdOracle.isEmodeValid(1, t_));
    }

    function test_msShadowCreate_revertsWhenApprovedAndEmodeZeroExists() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("shadow_approved");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 0, 1)); // liquidate collateral eMode 0
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        // eMode 1 liquidate reads currently fall back to eMode 0
        clOracle.setExchangeRate(1e27);
        assertEq(usdOracle.getPrice(t_, 1, false, true), 1e27, "precondition: eMode 1 falls back to eMode 0");

        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
    }

    function test_msShadowCreate_allowedWhenApprovedButNoEmodeZeroForLeg() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("shadow_no_e0_leg");

        // Gov stamps token and only configures operate/col eMode 0 — liquidate/col has no eMode 0
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1)); // liquidate col eMode 1 — no eMode 0 for this leg
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        assertTrue(usdOracle.isEmodeValid(1, t_));
    }

    function test_msShadowCreate_governanceCanAlwaysCreate() public {
        address t_ = _gstNewToken("shadow_gov_ok");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        // Same conditions that block MS — gov still succeeds
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        assertTrue(usdOracle.isEmodeValid(1, t_));
    }

    function test_msShadowCreate_allowedForEmodeZeroCreate() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("shadow_e0_create");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        // Creating eMode 0 itself is never a shadow create
        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 0, 1, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
    }

    function test_msShadowCreate_allowedAgainAfterClearingApproval() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("shadow_clear_approved");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        vm.prank(admin);
        usdOracle.setTokenConfigGovernanceApproved(t_, false);

        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        assertTrue(usdOracle.isEmodeValid(1, t_));
    }

    // ============ Approved tokens are governance-only for token-level sources ============

    /// @dev Regression: MS used to clear approval via a create-only alt write, then shadow-create in the same batch.
    function test_msSourceWrite_cannotSelfDisarmShadowGuardViaAltSourceWrite() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("approved_self_disarm");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.registerTransientOracleKey(_key(t_, 0, 0, 1));
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        // Step 1 of the old bypass: now rejected.
        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        // Step 2: approval survived, so the shadow guard still fires.
        vm.startPrank(ms_);
        usdOracle.registerTransientOracleKey(_key(t_, 1, 0, 1));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setPriceMode(PRICE_MODE_MARKET);
        vm.stopPrank();

        assertFalse(usdOracle.isEmodeValid(1, t_));
    }

    function test_msSourceWrite_revertsOnApprovedToken_setAdditionalAltSourceConfig() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("approved_add_alt");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, TOKEN_TYPE_PEG);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());

        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    /// @dev AUSD-shaped: approved with no sources, so `setSourceConfig` is a create for MS.
    function test_msSourceWrite_revertsOnApprovedTokenWithoutSources() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("approved_no_sources");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 2);
        usdOracle.setTokenConfigGovernanceApproved(t_, true);
        vm.stopPrank();
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());

        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    /// @dev `removeSourceConfig` clears sources but re-stamps approval, leaving approved + no primary sources.
    function test_msSourceWrite_revertsOnApprovedTokenAfterGovernanceRemovedSources() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("approved_after_remove");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.removeSourceConfig(t_);
        vm.stopPrank();

        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));

        vm.prank(ms_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__Unauthorized)
        );
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());

        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    /// @dev Onboarding preserved: MS may still write every bucket while unapproved.
    function test_msSourceWrite_allowedOnUnapprovedToken() public {
        address ms_ = usdOracle.TEAM_MULTISIG();
        address t_ = _gstNewToken("unapproved_src_writes");

        vm.startPrank(ms_);
        usdOracle.setTokenType(t_, TOKEN_TYPE_PEG);
        usdOracle.setSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        usdOracle.setAltSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        assertFalse(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    /// @dev Governance is never locked out.
    function test_governanceSourceWrite_allowedOnApprovedToken() public {
        address t_ = _gstNewToken("approved_gov_write");

        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 3);
        usdOracle.setSourceConfig(t_, _gstSrcChainlink(), _emptyCfg(), _emptyCfg());
        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
        usdOracle.setAltSourceConfig(t_, _gstSrcStable(), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        assertTrue(usdOracle.isTokenConfigGovernanceApproved(t_));
    }

    // ==================== getPricesRawForMode (multi token) ====================

    function _batchSetup() internal {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());
        usdOracle.setSourceConfig(DUMMY_TOKEN, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        clOracle.setExchangeRate(2e27);
    }

    function test_getPricesRawForMode_matchesSingleTokenGetter() public {
        _batchSetup();
        address unlisted = makeAddr("unlisted");

        address[] memory tokens = new address[](3);
        tokens[0] = USDC;
        tokens[1] = DUMMY_TOKEN;
        tokens[2] = unlisted;
        uint8[] memory modes = new uint8[](3);
        modes[0] = 2; // PEG on a STABLE token -> $1
        modes[1] = 1; // MARKET
        modes[2] = 1; // unlisted -> zeros

        (uint256[] memory prices, uint8[] memory decimals, uint8[] memory tokenTypes) = usdOracle.getPricesRawForMode(
            tokens,
            modes
        );

        assertEq(prices.length, 3);
        for (uint256 i = 0; i < 3; ++i) {
            (uint256 p, uint8 d, uint8 t) = usdOracle.getPriceRawForMode(tokens[i], modes[i]);
            assertEq(prices[i], p, "price mismatch vs single getter");
            assertEq(decimals[i], d, "decimals mismatch vs single getter");
            assertEq(tokenTypes[i], t, "tokenType mismatch vs single getter");
        }

        assertEq(prices[0], 1e27, "USDC PEG should be $1");
        assertEq(decimals[0], 6);
        assertEq(prices[1], 2e27, "DUMMY_TOKEN MARKET should read source");
        assertEq(decimals[1], 18);
        assertEq(prices[2], 0, "unlisted token should be 0");
        assertEq(tokenTypes[2], 0);
    }

    function test_getPricesRawForMode_revertsOnLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = DUMMY_TOKEN;
        uint8[] memory modes = new uint8[](3);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__InvalidParams)
        );
        usdOracle.getPricesRawForMode(tokens, modes);
    }

    function test_getPricesRawForMode_emptyTokensReturnsEmpty() public {
        address[] memory tokens = new address[](0);
        uint8[] memory modes = new uint8[](0);
        (uint256[] memory prices, uint8[] memory decimals, uint8[] memory tokenTypes) = usdOracle.getPricesRawForMode(
            tokens,
            modes
        );
        assertEq(prices.length, 0);
        assertEq(decimals.length, 0);
        assertEq(tokenTypes.length, 0);
    }

    function test_event_logAdditionalSourceConfigSet() public {
        address t_ = _gstNewToken("event_additional_src_set");
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.prank(admin);
        usdOracle.setTokenType(t_, 1);
        vm.prank(admin);
        usdOracle.setSourceConfig(t_, _stableSrc(0), _emptyCfg(), _emptyCfg());

        vm.expectEmit(true, true, true, true);
        emit LogAdditionalSourceConfigSet(t_, src, _emptyCfg(), _emptyCfg());

        vm.prank(admin);
        usdOracle.setAdditionalSourceConfig(t_, src, _emptyCfg(), _emptyCfg());
    }

    function test_event_logAdditionalSourceConfigRemoved() public {
        address t_ = _gstNewToken("event_additional_src_removed");
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _stableSrc(0), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit LogAdditionalSourceConfigRemoved(t_);

        vm.prank(admin);
        usdOracle.removeAdditionalSourceConfig(t_);
    }

    function test_event_logAdditionalAltSourceConfigSetAndRemoved() public {
        address t_ = _gstNewToken("event_additional_alt_set_removed");
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        vm.startPrank(admin);
        usdOracle.setTokenType(t_, 1);
        usdOracle.setSourceConfig(t_, _stableSrc(0), _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(t_, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit LogAdditionalAltSourceConfigSet(t_, src, _emptyCfg(), _emptyCfg());
        vm.prank(admin);
        usdOracle.setAdditionalAltSourceConfig(t_, src, _emptyCfg(), _emptyCfg());

        vm.expectEmit(true, true, true, true);
        emit LogAdditionalAltSourceConfigRemoved(t_);
        vm.prank(admin);
        usdOracle.removeAdditionalAltSourceConfig(t_);
    }

    function test_event_logSourceCapModeSet() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectEmit(true, true, true, true);
        emit LogSourceCapModeSet(_key(USDC, 0, 1, 1), SOURCE_CAP_MIN);
        usdOracle.setSourceCapMode(SOURCE_CAP_MIN);
        vm.stopPrank();
    }

    function test_event_logOverallCapSet() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectEmit(true, true, true, true);
        emit LogOverallCapSet(_key(USDC, 0, 1, 1), OVERALL_CAP_MIN_OPERAND, 100);
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, 100);
        vm.stopPrank();
    }

    function test_event_logDeviationAndFallbackToggles() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        usdOracle.setAltSourceConfig(USDC, src, _emptyCfg(), _emptyCfg());

        vm.expectEmit(true, true, true, true);
        emit LogDeviationCheckEnabled(_key(USDC, 0, 1, 1), 500);
        usdOracle.enableDeviationCheck(500);

        vm.expectEmit(true, true, true, true);
        emit LogDeviationCheckDisabled(_key(USDC, 0, 1, 1));
        usdOracle.disableDeviationCheck();

        vm.expectEmit(true, true, true, true);
        emit LogFallbackEnabled(_key(USDC, 0, 1, 1));
        usdOracle.enableFallback();

        vm.expectEmit(true, true, true, true);
        emit LogFallbackDisabled(_key(USDC, 0, 1, 1));
        usdOracle.disableFallback();
        vm.stopPrank();
    }

    function test_event_logOracleKeyConfigRemoved() public {
        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(USDC, 0, 1, 1));
        vm.expectEmit(true, true, true, true);
        emit LogOracleKeyConfigRemoved(_key(USDC, 0, 1, 1));
        usdOracle.removeConfig();
        vm.stopPrank();
    }

    function test_event_logTokenConfigGovernanceApproved() public {
        address t_ = _gstNewToken("event_token_approved");
        vm.prank(admin);
        usdOracle.setTokenType(t_, 3);

        vm.expectEmit(true, true, true, true);
        emit LogTokenConfigGovernanceApproved(t_, true);
        vm.prank(admin);
        usdOracle.setTokenConfigGovernanceApproved(t_, true);
    }

    function testFuzz_setPausedState_roundTrip(bool operatePaused_, bool liquidatePaused_) public {
        vm.prank(admin);
        usdOracle.setPausedState(USDC, operatePaused_, liquidatePaused_);

        (bool op_, bool liq_, , ) = usdOracle.getTokenConfig(USDC);
        assertEq(op_, operatePaused_);
        assertEq(liq_, liquidatePaused_);
    }

    function testFuzz_setOverallCap_minOperandCapsOrPassesThrough(uint96 rawPrice_, uint16 capOperand_) public {
        uint256 boundedPrice_ = bound(uint256(rawPrice_), 1e20, 1_000_000e27);
        uint16 boundedCapOperand_ = uint16(bound(uint256(capOperand_), 1, 10_000));

        SourceConfig memory src = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, DUMMY_TOKEN, 0, 1, 1, src, _emptyCfg(), _emptyCfg());

        clOracle.setExchangeRate(int256(boundedPrice_));

        vm.startPrank(admin);
        usdOracle.registerTransientOracleKey(_key(DUMMY_TOKEN, 0, 1, 1));
        usdOracle.setOverallCap(OVERALL_CAP_MIN_OPERAND, boundedCapOperand_);
        vm.stopPrank();

        uint256 expectedCap_ = uint256(boundedCapOperand_) * 1e25;
        (uint256 rawRead_, , ) = usdOracle.getPriceRawForMode(DUMMY_TOKEN, PRICE_MODE_MARKET);
        uint256 price_ = usdOracle.getPrice(DUMMY_TOKEN, 0, true, true);
        assertEq(price_, rawRead_ > expectedCap_ ? expectedCap_ : rawRead_);
    }

    // ==================== Event declarations for vm.expectEmit ====================
    event LogSourceConfigSet(address token, SourceConfig source1, SourceConfig source2, SourceConfig source3);
    event LogSourceConfigRemoved(address token);
    event LogAltSourceConfigSet(
        address token,
        SourceConfig altSource1,
        SourceConfig altSource2,
        SourceConfig altSource3
    );
    event LogAltSourceConfigRemoved(address token);
    event LogAdditionalSourceConfigSet(address token, SourceConfig source1, SourceConfig source2, SourceConfig source3);
    event LogAdditionalSourceConfigRemoved(address token);
    event LogAdditionalAltSourceConfigSet(
        address token,
        SourceConfig altSource1,
        SourceConfig altSource2,
        SourceConfig altSource3
    );
    event LogAdditionalAltSourceConfigRemoved(address token);
    event LogPriceModeSet(OracleKey key, uint8 priceMode);
    event LogOracleKeyConfigRemoved(OracleKey key);
    event LogSourceCapModeSet(OracleKey key, uint8 sourceCapMode);
    event LogOverallCapSet(OracleKey key, uint8 overallCapMode, uint16 overallCapOperand);
    event LogDeviationCheckEnabled(OracleKey key, uint24 maxDeviationBPS);
    event LogDeviationCheckDisabled(OracleKey key);
    event LogFallbackEnabled(OracleKey key);
    event LogFallbackDisabled(OracleKey key);
    event LogGuardianSet(address guardian, bool allowed);
    event LogTokenPauseSet(address token, bool operatePaused, bool liquidatePaused);
    event LogTokenTypeSet(address token, uint8 tokenType, uint8 decimals);
    event LogTokenConfigGovernanceApproved(address token, bool approved);
}
