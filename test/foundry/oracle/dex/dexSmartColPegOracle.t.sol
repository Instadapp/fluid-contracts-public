//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColPegOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartColPegOracle.sol";
import { DexConversionPriceFluidOracle } from "../../../../contracts/oracle/implementations/dex/conversionPriceGetters/conversionPriceFluidOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console2.sol";

contract DexSmartColPegOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_WBTC_CBBTC = 0x1d3e52a11B98Ed2AAB7eB0Bfe1cbB6525233204d;
    address internal constant FallbackCLRSOracle_CBBTC_USDC = 0x390421d1Fe8e238FFd9Ef86563CBF76F348CdD92; // USES BTC-USD

    DexSmartColPegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21005237);
    }

    function test_getExchangeRate_WBTC() public {
        oracle = new DexSmartColPegOracle(
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "WBTC per 1 WBTC/CBBTC share",
                SAMPLE_TARGET_DECIMALS,
                DEX_WBTC_CBBTC,
                true, // quote in token0, WBTC
                IFluidOracle(address(0)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1,
                1e10
            )
        );

        (uint256 operateRate, uint256 liquidateRate) = oracle.dexSmartColSharesRates();
        console2.log("Operate shares Rate:", operateRate);
        console2.log("Liquidate shares Rate:", liquidateRate);

        // total BTC reserves 0.002000060000 + 0.001996020000 = ~0.004 BTC
        // per total col shares 0.002000000000000000 = 0.002
        // so (COL_TOKEN/SHARE) = 2:1
        // adjusted for buffer percent so slightly less (col decreases)

        // so one share is worth ~double the normal BTC amount

        // should be ~2e17. Because ~2 WBTC per 1 share, so 2e8 but scaled to e27 -> * 1e9

        assertEq(oracle.getExchangeRateOperate(), 199604000000000000);
    }

    function test_getExchangeRate_USDC() public {
        oracle = new DexSmartColPegOracle(
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "USDC debt per 1 WBTC/CBBTC share",
                SAMPLE_TARGET_DECIMALS,
                DEX_WBTC_CBBTC,
                false, // quote in token1, CBBTC
                IFluidOracle(FallbackCLRSOracle_CBBTC_USDC),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1,
                1e10
            )
        );

        // normal USDC / CBBTC = 68365.9772339829511783324858768
        // considering shares have 10 decimals more than CBBTC
        // = 68365.977233982951178 e15
        // so it should be ~68365977233982951178 * 2 = ~136_000e15

        assertEq(oracle.getExchangeRateOperate(), 136238_898077022925419);
    }
}

contract DexSmartColPegOracleTestWEETH is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_WEETH_ETH = 0x86f874212335Af27C41cDb855C2255543d1499cE;

    DexSmartColPegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21236579);

        oracle = new DexSmartColPegOracle(
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "WSTETH per 1 WEETH/ETH colShare",
                SAMPLE_TARGET_DECIMALS,
                DEX_WEETH_ETH,
                false, // quote in ETH token1
                IFluidOracle(0x2F95631D59F564D5e2dD0c028d4DAF3B876D84Fd), // Wsteth contract rate
                true,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(
                    address(0x5f51AF8512d108F29c1f8De692fa96f0D3776a54), // Weeth contract rate
                    false,
                    1e18,
                    1e18
                ),
                1,
                1
            )
        );
    }

    function test_getExchangeRate() public view {
        assertEq(oracle.getExchangeRateOperate(), 1_685350318810579514680838347);
    }
}
