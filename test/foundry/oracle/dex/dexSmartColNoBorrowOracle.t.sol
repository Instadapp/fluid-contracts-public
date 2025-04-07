//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColNoBorrowOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartColNoBorrowOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console.sol";

contract DexSmartColNoBorrowOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_ETH = 0x2886a01a0645390872a9eb99dAe1283664b0c524;

    DexSmartColNoBorrowOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21279959);
    }

    function test_getExchangeRateInToken0() public {
        oracle = new DexSmartColNoBorrowOracle(
            DexSmartColNoBorrowOracle.DexSmartColNoBorrowOracleParams(
                "USDC per 1 USDC/ETH share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                true, // quote in token0, USDC
                IFluidOracle(address(0)),
                false,
                1,
                1e12
            )
        );

        assertEq(oracle.getExchangeRateOperate(), 2140827015641922); // 2.140827015641922 USDC per 1 col share
    }

    function test_getExchangeRateInToken1() public {
        oracle = new DexSmartColNoBorrowOracle(
            DexSmartColNoBorrowOracle.DexSmartColNoBorrowOracleParams(
                "ETH per 1 USDC/ETH share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                false, // quote in token1, ETH
                IFluidOracle(address(0)),
                false,
                1,
                1
            )
        );

        assertEq(oracle.getExchangeRateOperate(), 621430458881550723305306); // 0.000621430458881550723305306 ETH per 1 col share
    }

    function test_getExchangeRateInToken1ConvertToWstETH() public {
        address wstETHContractRate = 0x2F95631D59F564D5e2dD0c028d4DAF3B876D84Fd;

        oracle = new DexSmartColNoBorrowOracle(
            DexSmartColNoBorrowOracle.DexSmartColNoBorrowOracleParams(
                "WSTETH per 1 USDC/ETH share",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_ETH,
                false, // quote in token1, ETH
                IFluidOracle(wstETHContractRate), // assume WSTETH as debt, so USDC-ETH / WSTETH
                true,
                1,
                1
            )
        );

        // should be less than ETH per col share. wsteth exchange rate is ~1.18% (1186101883005106763000000000) so result 0.000523926711343797060442828
        assertEq(oracle.getExchangeRateOperate(), 523926711343797060442828); // 0.000523926711343797060442828
    }
}
