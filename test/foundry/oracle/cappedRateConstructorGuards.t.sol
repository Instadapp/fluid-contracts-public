//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { FluidCappedRate as FluidCappedRateV2, FluidCappedRateBase as FluidCappedRateBaseV2 } from "../../../contracts/oracleV2/cappedRates/fluidCappedRate.sol";
import { ErrorTypes as ErrorTypesV2 } from "../../../contracts/oracleV2/cappedRates/errorTypes.sol";
import { Error as ErrorV2 } from "../../../contracts/oracleV2/cappedRates/error.sol";

contract MockCappedRateSource {
    uint256 internal immutable RATE;

    constructor(uint256 rate_) {
        RATE = rate_;
    }

    function rate() external view returns (uint256) {
        return RATE;
    }
}

contract TestCappedRateV2 is FluidCappedRateV2 {
    constructor(FluidCappedRateBaseV2.CappedRateConstructorParams memory params_) FluidCappedRateV2(params_) {}

    function _getNewRateRaw() internal view override returns (uint256 exchangeRate_) {
        return MockCappedRateSource(_RATE_SOURCE).rate();
    }
}

contract CappedRateConstructorGuardsTest is Test {
    address internal constant DUMMY_LIQUIDITY = address(0x1234);

    function _paramsV2(
        address rateSource_
    ) internal pure returns (FluidCappedRateBaseV2.CappedRateConstructorParams memory) {
        return
            FluidCappedRateBaseV2.CappedRateConstructorParams({
                infoName: "TEST / TEST",
                liquidity: DUMMY_LIQUIDITY,
                rateSource: rateSource_,
                rateMultiplier: 1,
                invertCenterPrice: false,
                minUpdateDiffPercent: 100,
                minHeartbeat: 7 days,
                avoidForcedLiquidationsCol: false,
                avoidForcedLiquidationsDebt: false,
                maxAPRPercent: 10e4,
                maxDownFromMaxReachedPercentCol: 20e4,
                maxDownFromMaxReachedPercentDebt: 2e4,
                maxDebtUpCapPercent: 5e4
            });
    }

    function test_fluidCappedRateV2_constructor_RevertsOnZeroInitialRate() public {
        address source_ = address(new MockCappedRateSource(0));

        vm.expectRevert(
            abi.encodeWithSelector(ErrorV2.FluidOracleError.selector, ErrorTypesV2.CappedRate__NewRateZero)
        );
        new TestCappedRateV2(_paramsV2(source_));
    }

    function test_fluidCappedRateV2_constructor_RevertsOnInitialRateStorageOverflow() public {
        address source_ = address(new MockCappedRateSource(uint256(type(uint168).max) + 1));

        vm.expectRevert(
            abi.encodeWithSelector(ErrorV2.FluidOracleError.selector, ErrorTypesV2.CappedRate__StorageOverflow)
        );
        new TestCappedRateV2(_paramsV2(source_));
    }

    function test_fluidCappedRateV2_constructor_AcceptsInitialRateAtUint168Boundary() public {
        address source_ = address(new MockCappedRateSource(type(uint168).max));

        TestCappedRateV2 cappedRate_ = new TestCappedRateV2(_paramsV2(source_));
        assertEq(cappedRate_.getExchangeRate(), type(uint168).max);
    }
}
