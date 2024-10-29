//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColPegOracle } from "../../../contracts/oracle/oracles/dexSmartColPegOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";
import { IStakedUSDe } from "../../../contracts/config/ethenaRateHandler/interfaces/iStakedUSDe.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console2.sol";

contract DexSmartColPegOracleTest is Test {
    address internal constant DEX_WBTC_CBBTC = 0x1d3e52a11B98Ed2AAB7eB0Bfe1cbB6525233204d;
    address internal constant FallbackCLRSOracle_CBBTC_USDC = 0x390421d1Fe8e238FFd9Ef86563CBF76F348CdD92; // USES BTC-USD

    DexSmartColPegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21005237);

        oracle = new DexSmartColPegOracle(
            // string memory infoName_,
            // address dexPool_,
            // address reservesConversionOracle_,
            // bool quoteInToken0_,
            // bool reservesConversionInvert_,
            // uint256 reservesPegBufferPercent_,
            // IFluidOracle colDebtOracle_,
            // bool colDebtInvert_
            "USDC debt per 1 WBTC/CBBTC share",
            DEX_WBTC_CBBTC,
            address(0),
            false,
            false,
            1000, // 10000 = 1%; 100 = 0.01%
            IFluidOracle(FallbackCLRSOracle_CBBTC_USDC),
            false,
            8 // decimals of Base asset -> CBBTC -> 8
        );
    }

    function test_getExchangeRate() public {
        // total BTC reserves 0.002000060000 + 0.001996020000 = ~0.004 BTC
        // per total col shares 0.002000000000000000 = 0.002
        // so (COL_TOKEN/SHARE) = 2:1
        // adjusted for buffer percent so slightly less (col decreases)

        // so one share is worth ~double the normal BTC amount
        // normal USDC / CBBTC = 68365.9772339829511783324858768
        // considering shares have 10 decimals more than CBBTC
        // = 68365.977233982951178 e15
        // so it should be ~68365977233982951178 * 2 = ~136_000e15

        assertEq(oracle.getExchangeRateOperate(), 136239_031856025465932);
    }
}
