//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import "./usdOracleForkTestBase.sol";
import { IUSDOracle } from "../../../contracts/oracleV2/interfaces/iUSDOracle.sol";

/// @dev Read-only consumer: its `view` functions only compile if the oracle view entries are `view`-callable,
///      and calling them puts the oracle's internal staticcall inside an outer static frame.
contract ViewOnlyConsumer {
    function price(address oracle_, address token_) external view returns (uint256) {
        return IUSDOracle(oracle_).getPriceView(token_, 0, true, true);
    }

    function priceDetailed(address oracle_, address token_) external view returns (uint256, uint8, uint8) {
        return IUSDOracle(oracle_).getPriceDetailedView(token_, 0, true, true);
    }

    function priceDetailedRaw(address oracle_, address token_) external view returns (uint256, uint8, uint8) {
        return IUSDOracle(oracle_).getPriceDetailedViewRaw(token_, 0, true, true);
    }
}

/// @dev Fluid source with Write support; Write rates differ from view rates to show which getter was used.
contract MockFluidOracleWithWrite is MockFluidOracleWithDebt {
    uint256 public writeOperateValue = 7e27;
    uint256 public writeLiquidateValue = 8e27;
    uint256 public writeOperateDebtValue = 9e27;
    uint256 public writeLiquidateDebtValue = 11e27;
    bool public revertWriteWithReason;
    uint256 public writeCalls;

    function setRevertWriteWithReason(bool revertWriteWithReason_) external {
        revertWriteWithReason = revertWriteWithReason_;
    }

    function getExchangeRateOperateWrite() external returns (uint256) {
        if (revertWriteWithReason) revert("CLX_WRITE_FAIL");
        writeCalls++;
        return writeOperateValue;
    }

    function getExchangeRateLiquidateWrite() external returns (uint256) {
        if (revertWriteWithReason) revert("CLX_WRITE_FAIL");
        writeCalls++;
        return writeLiquidateValue;
    }

    function getExchangeRateOperateDebtWrite() external returns (uint256) {
        if (revertWriteWithReason) revert("CLX_WRITE_FAIL");
        writeCalls++;
        return writeOperateDebtValue;
    }

    function getExchangeRateLiquidateDebtWrite() external returns (uint256) {
        if (revertWriteWithReason) revert("CLX_WRITE_FAIL");
        writeCalls++;
        return writeLiquidateDebtValue;
    }
}

/// @dev Write mode: `getPrice` uses Write getters on Fluid/capped legs, view entries never do,
///      and Write failures fall back to view instead of bubbling.
contract FluidUSDOracleWriteModeTest is UsdOracleForkTestBase {
    function _fluidSrc(address oracle_) internal pure returns (SourceConfig memory) {
        return SourceConfig({ sourceType: SOURCE_FLUID_ORACLE, source: oracle_, capOperand: 0 });
    }

    function _registerKey(uint8 isOperate_, uint8 isCollateral_) internal {
        bytes[] memory calls_ = new bytes[](2);
        calls_[0] = abi.encodeWithSelector(
            usdOracle.registerTransientOracleKey.selector,
            _key(USDC, 0, isOperate_, isCollateral_)
        );
        calls_[1] = abi.encodeWithSelector(usdOracle.setPriceMode.selector, PRICE_MODE_MARKET);
        _adminSession(admin, calls_);
    }

    function test_getPrice_usesWriteGetterOnCollateral() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, writeOracle.writeOperateValue(), "getPrice should use the operate Write rate");
        assertEq(writeOracle.writeCalls(), 1, "Write getter should be called exactly once");

        // Write mode is reset before getPrice returns: a later view read uses the view getter.
        uint256 viewPrice = usdOracle.getPriceView(USDC, 0, true, true);
        assertEq(viewPrice, writeOracle.operateValue(), "getPriceView after getPrice should use the view rate");
        assertEq(writeOracle.writeCalls(), 1, "view read must not call the Write getter");
    }

    function test_getPrice_usesLiquidateWriteGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());
        _registerKey(0, 1);

        uint256 price = usdOracle.getPrice(USDC, 0, false, true);
        assertEq(price, writeOracle.writeLiquidateValue(), "getPrice should use the liquidate Write rate");
        assertEq(writeOracle.writeCalls(), 1, "Write getter should be called exactly once");
    }

    function test_getPrice_debtLegUsesDebtWriteGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 0, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPrice(USDC, 0, true, false);
        assertEq(price, writeOracle.writeOperateDebtValue(), "debt leg should use the operate DebtWrite rate");
        assertEq(writeOracle.writeCalls(), 1, "DebtWrite getter should be called exactly once");
    }

    function test_getPrice_debtLegUsesLiquidateDebtWriteGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 0, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());
        _registerKey(0, 0);

        uint256 price = usdOracle.getPrice(USDC, 0, false, false);
        assertEq(price, writeOracle.writeLiquidateDebtValue(), "debt leg should use the liquidate DebtWrite rate");
        assertEq(writeOracle.writeCalls(), 1, "DebtWrite getter should be called exactly once");
    }

    function test_getPrice_debtWriteRevertFallsBackToViewGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 0, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        writeOracle.setRevertWriteWithReason(true);
        uint256 price = usdOracle.getPrice(USDC, 0, true, false);
        assertEq(price, writeOracle.operateDebtValue(), "DebtWrite failure should fall back to the view Debt rate");
    }

    function test_getPriceView_neverUsesWriteGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        uint256 price = usdOracle.getPriceView(USDC, 0, true, true);
        assertEq(price, writeOracle.operateValue(), "getPriceView should use the view rate");
        assertEq(writeOracle.writeCalls(), 0, "getPriceView must not call the Write getter");
    }

    function test_getPrice_writeRevertFallsBackToViewGetter() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        writeOracle.setRevertWriteWithReason(true);
        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, writeOracle.operateValue(), "Write failure should fall back to the view rate, not bubble");
    }

    function test_getPrice_writeAndViewRevertZeroLegWithDedicatedError() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        // Source broken on both getters: leg zeroes and surfaces the oracle's own error, not the source's.
        writeOracle.setRevertWriteWithReason(true);
        writeOracle.setReverts(true, false);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__RateZero)
        );
        usdOracle.getPrice(USDC, 0, true, true);
    }

    // ==================== View entries under static frames ====================
    // `getPriceView` is `view` but staticcalls the non-view `_getPriceImplNoWrite`. Legal per EIP-214: a static
    // frame faults only on state-modifying opcodes, not on the callee's declared mutability. These pin that.

    function test_viewEntries_workFromViewContextAndNestedStaticFrames() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());
        uint256 expected = writeOracle.operateValue();

        ViewOnlyConsumer consumer = new ViewOnlyConsumer();
        assertEq(consumer.price(address(usdOracle), USDC), expected, "getPriceView from a view function");

        (uint256 detailed, , ) = consumer.priceDetailed(address(usdOracle), USDC);
        assertEq(detailed, expected, "getPriceDetailedView from a view function");
        (uint256 detailedRaw, , ) = consumer.priceDetailedRaw(address(usdOracle), USDC);
        assertEq(detailedRaw, expected, "getPriceDetailedViewRaw from a view function");

        // Outer STATICCALL of the view wrapper -> oracle view entry -> inner STATICCALL of the non-view impl.
        (bool ok, bytes memory data) = address(consumer).staticcall(
            abi.encodeCall(ViewOnlyConsumer.price, (address(usdOracle), USDC))
        );
        assertTrue(ok, "nested static frames must not fault");
        assertEq(abi.decode(data, (uint256)), expected, "nested static frames must return the price");
        assertEq(writeOracle.writeCalls(), 0, "no Write getter may run on a view path");
    }

    function test_viewEntries_staticcalledDirectly() public {
        MockFluidOracleWithWrite writeOracle = new MockFluidOracleWithWrite();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(writeOracle)), _emptyCfg(), _emptyCfg());

        (bool ok, bytes memory data) = address(usdOracle).staticcall(
            abi.encodeCall(IUSDOracle.getPriceView, (USDC, 0, true, true))
        );
        assertTrue(ok, "raw staticcall of getPriceView must succeed");
        assertEq(abi.decode(data, (uint256)), writeOracle.operateValue());

        // The impl target is self-call gated: only the oracle's own bridge may call it.
        (ok, ) = address(usdOracle).staticcall(
            abi.encodeWithSignature("_getPriceImplNoWrite(address,uint256,bool,bool)", USDC, 0, true, true)
        );
        assertFalse(ok, "_getPriceImplNoWrite must reject non-self callers");

        // Even the Write entry survives a static frame: the oracle itself writes nothing, and the source's
        // Write getter faults on its SSTORE inside `try`, so the leg falls back to the view getter. This is
        // what makes `eth_call` simulation of `getPrice` return the view price instead of reverting.
        (ok, data) = address(usdOracle).staticcall(abi.encodeCall(IUSDOracle.getPrice, (USDC, 0, true, true)));
        assertTrue(ok, "getPrice under staticcall degrades to the view path rather than reverting");
        assertEq(abi.decode(data, (uint256)), writeOracle.operateValue(), "static getPrice yields the view rate");
    }

    function test_getPrice_sourceWithoutWriteSupportFallsBackToView() public {
        MockFluidOracleWithDebt plainOracle = new MockFluidOracleWithDebt();
        _registerAndSetConfig(admin, USDC, 0, 1, 1, _fluidSrc(address(plainOracle)), _emptyCfg(), _emptyCfg());
        _registerKey(1, 0);

        uint256 price = usdOracle.getPrice(USDC, 0, true, true);
        assertEq(price, plainOracle.operateValue(), "missing Write support should fall back to the view rate");

        price = usdOracle.getPrice(USDC, 0, true, false);
        assertEq(
            price,
            plainOracle.operateDebtValue(),
            "missing DebtWrite support should fall back to the view Debt rate"
        );
    }
}
