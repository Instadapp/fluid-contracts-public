//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartT4PegOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartT4PegOracle.sol";
import { DexConversionPriceFluidOracle } from "../../../../contracts/oracle/implementations/dex/conversionPriceGetters/conversionPriceFluidOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console2.sol";

contract DexSmartT4PegOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_USDT = 0x085B07A30381F3Cc5A4250e10E4379d465b770ac;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;
    address internal constant FallbackCLRSOracle_WBTC_USDC = 0x131BA983Ab640Ce291B98694b3Def4288596cD09;

    address internal constant DEX_WSTETH_ETH = 0x25F0A3B25cBC0Ca0417770f686209628323fF901;
    address internal constant RESERVES_CONVERSION_ORACLE = 0xf1442714E502723D5bB253B806Fd7555BEE0336C; // Wsteth contract rate

    address internal constant DEX_GHO_USDC = 0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45;

    DexSmartT4PegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21005237);
    }

    function test_getExchangeRate_WSTETH_ETH() public {
        oracle = new DexSmartT4PegOracle(
            DexSmartT4PegOracle.DexSmartT4PegOracleParams(
                "WSTETH/ETH shares debt per 1 col",
                SAMPLE_TARGET_DECIMALS,
                DEX_WSTETH_ETH,
                false, // quote in ETH (token1)
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(
                    RESERVES_CONVERSION_ORACLE,
                    false,
                    1e18,
                    1e18
                ),
                1,
                1
            )
        );

        // see same expectation as in DexSmartDebtPegOracle test

        assertEq(oracle.getExchangeRateOperate(), 997973751650791978647202523);
    }

    function test_getExchangeRate_CombinedSmartCol_GHO_USDC() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21108403);

        oracle = new DexSmartT4PegOracle(
            DexSmartT4PegOracle.DexSmartT4PegOracleParams(
                "GHO/USDC debt sh. per 1 col sh.",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                false, // quote in USDC (token1)
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1e12),
                1,
                1
            )
        );

        // see same expectation as in DexSmartDebtPegOracle test

        assertEq(oracle.getExchangeRateOperate(), 997991565270407603009343053);

        oracle = new DexSmartT4PegOracle(
            DexSmartT4PegOracle.DexSmartT4PegOracleParams(
                "GHO/USDC debt sh. per 1 col sh.",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                true, // quote in GHO (token0)
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1,
                1
            )
        );

        // see same expectation as in DexSmartDebtPegOracle test

        assertEq(oracle.getExchangeRateOperate(), 997991562882852026922073446);
    }
}
