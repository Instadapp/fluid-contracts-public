// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";

import { DeviationHelpers } from "../../../../contracts/libraries/utils/deviationHelpers.sol";

contract DeviationHelpersTest is Test {
    uint256 internal constant PRECISION_E4 = 1e4;
    uint256 internal constant PRECISION_E6 = 1e6;

    function test_ExactMatch() public pure {
        assertFalse(DeviationHelpers.isOutsideDeviation(1e18, 1e18, 0, PRECISION_E4));
        assertFalse(DeviationHelpers.isOutsideDeviation(1e18, 1e18, 100, PRECISION_E4));
    }

    function test_OnePercentBand_E4() public pure {
        // 1% = 100 at 1e4; exact ±1% in-band, +2% outside
        assertFalse(DeviationHelpers.isOutsideDeviation(1e18, 101e16, 100, PRECISION_E4));
        assertFalse(DeviationHelpers.isOutsideDeviation(1e18, 99e16, 100, PRECISION_E4));
        assertTrue(DeviationHelpers.isOutsideDeviation(1e18, 102e16, 100, PRECISION_E4));
    }

    function test_OnePercentBand_E6() public pure {
        assertFalse(DeviationHelpers.isOutsideDeviation(2e18, 199e16, 1e4, PRECISION_E6));
        assertTrue(DeviationHelpers.isOutsideDeviation(2e18, 15e17, 1e4, PRECISION_E6));
    }

    function test_ZeroBase() public pure {
        assertFalse(DeviationHelpers.isOutsideDeviation(0, 0, 100, PRECISION_E4));
        assertTrue(DeviationHelpers.isOutsideDeviation(0, 1, 100, PRECISION_E4));
    }

    function test_ZeroPrecision() public pure {
        assertTrue(DeviationHelpers.isOutsideDeviation(1e18, 1e18, 100, 0));
    }
}
