//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LibraryLiquidityCalcsBaseTest } from "./liquidityCalcsBaseTest.t.sol";
import { AuthInternals } from "../../../../contracts/liquidity/adminModule/main.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { LibsErrorTypes as ErrorTypes } from "../../../../contracts/libraries/errorTypes.sol";

contract LibraryLiquidityBorrowRateFromUtilizationTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_KINK = 10 * _DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%
    uint256 constant _DEFAULT_KINK2 = 90 * _DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant _DEFAULT_RATE_AT_KINK2 = 80 * _DEFAULT_PERCENT_PRECISION; // 10% + half way to 150% = 80% for data compatibility with v1

    function test_calcBorrowRateFromUtilization_rateVersion1() public {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_MAX
        );

        uint256 rateData = _computeRateDataPackedV1(rataDataV1Params);
        uint256 utilization = 90 * _DEFAULT_PERCENT_PRECISION; // 90%

        uint256 rate = testHelper.calcBorrowRateFromUtilization(rateData, utilization);

        // rate should be rate at kink + half of 10% to 150% at 100%  -> 140% / 2 = 70% + 10% = 80%
        assertEq(rate, 80 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcBorrowRateFromUtilization_rateVersion2() public {
        AdminModuleStructs.RateDataV2Params memory rataDataV2Params = AdminModuleStructs.RateDataV2Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_KINK2,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_KINK2,
            _DEFAULT_RATE_AT_MAX
        );

        uint256 rateData = _computeRateDataPackedV2(rataDataV2Params);
        uint256 utilization = 95 * _DEFAULT_PERCENT_PRECISION; // 95%

        uint256 rate = testHelper.calcBorrowRateFromUtilization(rateData, utilization);

        // rate should be rate at kink2 + half of 80% to 150% at 100%  -> 70% / 2 = 35% + 80% = 115%
        assertEq(rate, 115 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcBorrowRateFromUtilization_rateVersion0() public {
        uint256 rateData = type(uint256).max << 4; // making last 4 bits 0

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityCalcs.FluidLiquidityCalcsError.selector,
                ErrorTypes.LiquidityCalcs__UnsupportedRateVersion
            )
        );
        testHelper.calcBorrowRateFromUtilization(rateData, 10 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcBorrowRateFromUtilization_rateVersion3() public {
        uint256 rateData = (type(uint256).max << 4) | 3; // making last 4 bits value 3

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityCalcs.FluidLiquidityCalcsError.selector,
                ErrorTypes.LiquidityCalcs__UnsupportedRateVersion
            )
        );
        testHelper.calcBorrowRateFromUtilization(rateData, 10 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcBorrowRateFromUtilization_rateAtMaxCap() public {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            65535 // 16 bits max value
        );

        uint256 rateData = 1 | // version
            (rataDataV1Params.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV1Params.kink << LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) |
            (rataDataV1Params.rateAtUtilizationKink << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) |
            (rataDataV1Params.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX);

        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcBorrowRateFromUtilization(rateData, utilization);
        assertEq(rate, 65535);
    }

    function test_calcBorrowRateFromUtilization_rateJustAboveMaxCap() public {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            65535 // 16 bits max value
        );

        uint256 rateData = 1 | // version
            (rataDataV1Params.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV1Params.kink << LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) |
            (rataDataV1Params.rateAtUtilizationKink << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) |
            (rataDataV1Params.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX);

        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION + 1;

        uint256 rate = testHelper.calcBorrowRateFromUtilization(rateData, utilization);
        assertEq(rate, 65535); // rate should be limited to max value
    }

    function test_calcBorrowRateFromUtilization_rateAboveMaxCap() public {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            65535 // 16 bits max value
        );

        uint256 rateData = 1 | // version
            (rataDataV1Params.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV1Params.kink << LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) |
            (rataDataV1Params.rateAtUtilizationKink << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) |
            (rataDataV1Params.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX);

        uint256 utilization = 150 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcBorrowRateFromUtilization(rateData, utilization);
        assertEq(rate, 65535); // rate should be limited to max value
    }

    function test_calcBorrowRateFromUtilization_EmitBorrowRateMaxCap() public {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            65535 // 16 bits max value
        );

        uint256 rateData = 1 | // version
            (rataDataV1Params.rateAtUtilizationZero << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_ZERO) |
            (rataDataV1Params.kink << LiquiditySlotsLink.BITS_RATE_DATA_V1_UTILIZATION_AT_KINK) |
            (rataDataV1Params.rateAtUtilizationKink << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_KINK) |
            (rataDataV1Params.rateAtUtilizationMax << LiquiditySlotsLink.BITS_RATE_DATA_V1_RATE_AT_UTILIZATION_MAX);

        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION + 1;

        vm.expectEmit(true, true, true, true);
        emit LiquidityCalcs.BorrowRateMaxCap();
        testHelper.calcBorrowRateFromUtilization(rateData, utilization);
    }
}

contract LibraryLiquidityCalcsRateV1Tests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_KINK = 10 * _DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%

    uint256 immutable DEFAULT_RATE_DATA_V1;

    constructor() {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V1 = _computeRateDataPackedV1(rataDataV1Params);
    }

    function test_calcRateV1_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV1_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 + half of 4% to 10% at 80%  -> 7%
        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, 7 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV1_AtUtilizationAboveKink1BelowMax() public {
        uint256 utilization = 90 * _DEFAULT_PERCENT_PRECISION; // 90%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);

        // rate should be rate at kink + half of 10% to 150% at 100%  -> 140% / 2 = 70% + 10% = 80%
        assertEq(rate, 80 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV1_AtUtilizationAboveMax() public {
        // when above 100% utilization

        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        // rate should be rate at kink + double the increase from 80% -> 100% (10% to 150% from kink1 to max)
        // so 140% * 2 + 10% = 290%
        assertEq(rate, 290 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV1DecliningTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 16 * _DEFAULT_PERCENT_PRECISION; // 16%
    uint256 constant _DEFAULT_RATE_AT_KINK = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%

    uint256 immutable DEFAULT_RATE_DATA_V1;

    constructor() {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V1 = _computeRateDataPackedV1(rataDataV1Params);
    }

    function test_calcRateV1_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV1_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 + half decline of 16% to 4% at 80%  -> 16% - 6% = 10%
        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, 10 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV1_AtUtilizationAboveKink1BelowMax() public {
        uint256 utilization = 90 * _DEFAULT_PERCENT_PRECISION; // 90%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);

        // rate should be rate at kink + half of 4% to 150% at 100%  -> 146% / 2 = 73% + 4% = 77%
        assertEq(rate, 77 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV1_AtUtilizationAboveMax() public {
        // when above 100% utilization

        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        // rate should be rate at kink + double the increase from 80% -> 100% (4% to 150% from kink1 to max)
        // so 146% * 2 + 4% = 296%
        assertEq(rate, 296 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV1FlatTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_KINK = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%

    uint256 immutable DEFAULT_RATE_DATA_V1;

    constructor() {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V1 = _computeRateDataPackedV1(rataDataV1Params);
    }

    function test_calcRateV1_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV1_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 flat
        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, 4 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV1_AtUtilizationAboveKink1BelowMax() public {
        uint256 utilization = 90 * _DEFAULT_PERCENT_PRECISION; // 90%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);

        // rate should be rate at kink + half of 4% to 150% at 100%  -> 146% / 2 = 73% + 4% = 77%
        assertEq(rate, 77 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV1_AtUtilizationAboveMax() public {
        // when above 100% utilization

        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        // rate should be rate at kink + double the increase from 80% -> 100% (4% to 150% from kink1 to max)
        // so 146% * 2 + 4% = 296%
        assertEq(rate, 296 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV1FlatZeroTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_KINK = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%

    uint256 immutable DEFAULT_RATE_DATA_V1;

    constructor() {
        AdminModuleStructs.RateDataV1Params memory rataDataV1Params = AdminModuleStructs.RateDataV1Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V1 = _computeRateDataPackedV1(rataDataV1Params);
    }

    function test_calcRateV1_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV1_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 flat
        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, 0);
    }

    function test_calcRateV1_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV1_AtUtilizationAboveKink1BelowMax() public {
        uint256 utilization = 90 * _DEFAULT_PERCENT_PRECISION; // 90%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);

        // rate should be rate at kink + half of 0% to 150% at 100%  -> 75%
        assertEq(rate, 75 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV1_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV1_AtUtilizationAboveMax() public {
        // when above 100% utilization

        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV1(DEFAULT_RATE_DATA_V1, utilization);
        // rate should be rate at kink + double the increase from 80% -> 100% (0% to 150% from kink1 to max)
        // so 150% * 2 + 0 = 300%
        assertEq(rate, 300 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV2Tests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 80 * _DEFAULT_PERCENT_PRECISION; // 80%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 4 * _DEFAULT_PERCENT_PRECISION; // 4%
    uint256 constant _DEFAULT_RATE_AT_KINK = 10 * _DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant _DEFAULT_RATE_AT_MAX = 150 * _DEFAULT_PERCENT_PRECISION; // 150%
    uint256 constant _DEFAULT_KINK2 = 90 * _DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant _DEFAULT_RATE_AT_KINK2 = 80 * _DEFAULT_PERCENT_PRECISION; // 10% + half way to 150% = 80% for data compatibility with v1

    uint256 immutable DEFAULT_RATE_DATA_V2;

    constructor() {
        AdminModuleStructs.RateDataV2Params memory rataDataV2Params = AdminModuleStructs.RateDataV2Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_KINK2,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_KINK2,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V2 = _computeRateDataPackedV2(rataDataV2Params);
    }

    function test_calcRateV2_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV2_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 + half of 4% to 10% at 80%  -> 7%
        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, 7 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV2_AtUtilizationAboveKink1BelowKink2() public {
        uint256 utilization = 85 * _DEFAULT_PERCENT_PRECISION; // 85%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink1 + half of 10% (at kink1) to 80% (at kink2) = 10% + 35% = 45%
        assertEq(rate, 45 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationKink2() public {
        uint256 utilization = _DEFAULT_KINK2;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK2);
    }

    function test_calcRateV2_AboveKink2BelowMax() public {
        uint256 utilization = 95 * _DEFAULT_PERCENT_PRECISION; // 95%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink2 + half of 80% to 150% at 100%  -> 70% / 2 = 35% + 80% = 115%
        assertEq(rate, 115 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV2_AtUtilizationAboveMax() public {
        // when above 100% utilization
        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        // rate should be rate at max + twice the increase from 90% -> 100% (80% to 150% from kink2 to max)
        // so 70% * 2 + 150% = 290%
        assertEq(rate, 290 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV2DecliningTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 50 * _DEFAULT_PERCENT_PRECISION; // 50%
    uint256 constant _DEFAULT_KINK2 = 90 * _DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_KINK = 17 * _DEFAULT_PERCENT_PRECISION; // 17%
    uint256 constant _DEFAULT_RATE_AT_KINK2 = 14 * _DEFAULT_PERCENT_PRECISION; // 14%
    uint256 constant _DEFAULT_RATE_AT_MAX = 100 * _DEFAULT_PERCENT_PRECISION; // 100%

    uint256 immutable DEFAULT_RATE_DATA_V2;

    constructor() {
        AdminModuleStructs.RateDataV2Params memory rataDataV2Params = AdminModuleStructs.RateDataV2Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_KINK2,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_KINK2,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V2 = _computeRateDataPackedV2(rataDataV2Params);
    }

    function test_calcRateV2_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV2_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 + 80% of rate at kink, so 80% of 17 -> 13.6%
        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, 1360);
    }

    function test_calcRateV2_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV2_AtUtilizationAboveKink1BelowKink2() public {
        uint256 utilization = 85 * _DEFAULT_PERCENT_PRECISION; // 85%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink1 17% MINUS 87.5% decline of 3% = 17% - 2.625% = 14.375%
        assertEq(rate, 1437);
    }

    function test_calcRateV2_AtUtilizationKink2() public {
        uint256 utilization = _DEFAULT_KINK2;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK2);
    }

    function test_calcRateV2_AboveKink2BelowMax() public {
        uint256 utilization = 95 * _DEFAULT_PERCENT_PRECISION; // 95%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink2 + half of 14% to 100% at 100% -> 14% + 43% = 57%
        assertEq(rate, 57 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV2_AtUtilizationAboveMax() public {
        // when above 100% utilization
        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        // rate should be rate at max + twice the increase from 90% -> 100% (14% to 100% from kink2 to max)
        // so 86% * 2 + 100% = 272%
        assertEq(rate, 272 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV2FlatTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 50 * _DEFAULT_PERCENT_PRECISION; // 50%
    uint256 constant _DEFAULT_KINK2 = 90 * _DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_KINK = 10 * _DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant _DEFAULT_RATE_AT_KINK2 = 10 * _DEFAULT_PERCENT_PRECISION; // 10%
    uint256 constant _DEFAULT_RATE_AT_MAX = 100 * _DEFAULT_PERCENT_PRECISION; // 100%

    uint256 immutable DEFAULT_RATE_DATA_V2;

    constructor() {
        AdminModuleStructs.RateDataV2Params memory rataDataV2Params = AdminModuleStructs.RateDataV2Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_KINK2,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_KINK2,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V2 = _computeRateDataPackedV2(rataDataV2Params);
    }

    function test_calcRateV2_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV2_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be rate at 0 + 80% of rate at kink, so 80% of 10 -> 8%
        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, 8 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV2_AtUtilizationAboveKink1BelowKink2() public {
        uint256 utilization = 85 * _DEFAULT_PERCENT_PRECISION; // 85%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be flat 10%
        assertEq(rate, 10 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationKink2() public {
        uint256 utilization = _DEFAULT_KINK2;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK2);
    }

    function test_calcRateV2_AboveKink2BelowMax() public {
        uint256 utilization = 95 * _DEFAULT_PERCENT_PRECISION; // 95%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink2 + half of 10% to 100% at 100% -> 10% + 45% = 55%
        assertEq(rate, 55 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV2_AtUtilizationAboveMax() public {
        // when above 100% utilization
        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        // rate should be rate at max + twice the increase from 90% -> 100% (10% to 100% from kink2 to max)
        // so 90% * 2 + 100% = 280%
        assertEq(rate, 280 * _DEFAULT_PERCENT_PRECISION);
    }
}

contract LibraryLiquidityCalcsRateV2FlatZeroTests is LibraryLiquidityCalcsBaseTest, AuthInternals {
    uint256 constant _DEFAULT_PERCENT_PRECISION = 1e2;
    uint256 constant _DEFAULT_KINK = 50 * _DEFAULT_PERCENT_PRECISION; // 50%
    uint256 constant _DEFAULT_KINK2 = 90 * _DEFAULT_PERCENT_PRECISION; // 90%
    uint256 constant _DEFAULT_RATE_AT_ZERO = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_KINK = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_KINK2 = 0 * _DEFAULT_PERCENT_PRECISION; // 0%
    uint256 constant _DEFAULT_RATE_AT_MAX = 100 * _DEFAULT_PERCENT_PRECISION; // 100%

    uint256 immutable DEFAULT_RATE_DATA_V2;

    constructor() {
        AdminModuleStructs.RateDataV2Params memory rataDataV2Params = AdminModuleStructs.RateDataV2Params(
            address(1),
            _DEFAULT_KINK,
            _DEFAULT_KINK2,
            _DEFAULT_RATE_AT_ZERO,
            _DEFAULT_RATE_AT_KINK,
            _DEFAULT_RATE_AT_KINK2,
            _DEFAULT_RATE_AT_MAX
        );
        DEFAULT_RATE_DATA_V2 = _computeRateDataPackedV2(rataDataV2Params);
    }

    function test_calcRateV2_AtUtilization0() public {
        uint256 utilization = 0 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_ZERO);
    }

    function test_calcRateV2_AtUtilizationAbove0BelowKink1() public {
        uint256 utilization = 40 * _DEFAULT_PERCENT_PRECISION;

        // rate should be 0
        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, 0);
    }

    function test_calcRateV2_AtUtilizationKink1() public {
        uint256 utilization = _DEFAULT_KINK;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK);
    }

    function test_calcRateV2_AtUtilizationAboveKink1BelowKink2() public {
        uint256 utilization = 85 * _DEFAULT_PERCENT_PRECISION; // 85%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be flat 0%
        assertEq(rate, 0);
    }

    function test_calcRateV2_AtUtilizationKink2() public {
        uint256 utilization = _DEFAULT_KINK2;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_KINK2);
    }

    function test_calcRateV2_AboveKink2BelowMax() public {
        uint256 utilization = 95 * _DEFAULT_PERCENT_PRECISION; // 95%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);

        // rate should be rate at kink2 + half of 0% to 100% at 100% -> 50%
        assertEq(rate, 50 * _DEFAULT_PERCENT_PRECISION);
    }

    function test_calcRateV2_AtUtilizationMax() public {
        uint256 utilization = 100 * _DEFAULT_PERCENT_PRECISION;

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        assertEq(rate, _DEFAULT_RATE_AT_MAX);
    }

    function test_calcRateV2_AtUtilizationAboveMax() public {
        // when above 100% utilization
        uint256 utilization = 120 * _DEFAULT_PERCENT_PRECISION; // utilization at 120%

        uint256 rate = testHelper.calcRateV2(DEFAULT_RATE_DATA_V2, utilization);
        // rate should be rate at max + twice the increase from 90% -> 100% (0% to 100% from kink2 to max)
        // so 100% * 2 + 100% = 300%
        assertEq(rate, 300 * _DEFAULT_PERCENT_PRECISION);
    }
}
