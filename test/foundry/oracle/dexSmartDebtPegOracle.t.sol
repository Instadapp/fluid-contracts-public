//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColPegOracle } from "../../../contracts/oracle/oracles/dexSmartColPegOracle.sol";
import { DexSmartDebtPegOracle } from "../../../contracts/oracle/oracles/dexSmartDebtPegOracle.sol";
import { ErrorTypes } from "../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../contracts/oracle/error.sol";
import { IStakedUSDe } from "../../../contracts/config/ethenaRateHandler/interfaces/iStakedUSDe.sol";
import { IFluidOracle } from "../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console2.sol";

contract DexSmartDebtPegOracleTest is Test {
    address internal constant DEX_USDC_USDT = 0x085B07A30381F3Cc5A4250e10E4379d465b770ac;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;
    address internal constant FallbackCLRSOracle_WBTC_USDC = 0x131BA983Ab640Ce291B98694b3Def4288596cD09;

    address internal constant DEX_WSTETH_ETH = 0x25F0A3B25cBC0Ca0417770f686209628323fF901;
    address internal constant RESERVES_CONVERSION_ORACLE = 0xf1442714E502723D5bB253B806Fd7555BEE0336C; // Wsteth contract rate

    DexSmartDebtPegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21005237);

        oracle = new DexSmartDebtPegOracle(
            // string memory infoName_,
            // address dexPool_,
            // address reservesConversionOracle_,
            // bool quoteInToken0_,
            // bool reservesConversionInvert_,
            // uint256 reservesPegBufferPercent_,
            // IFluidOracle colDebtOracle_,
            // bool colDebtInvert_
            "USDC/USDT debt shares per 1 ETH",
            DEX_USDC_USDT,
            address(0),
            false,
            false,
            1000, // 10000 = 1%; 100 = 0.01%
            IFluidOracle(UniV3CheckCLRSOracle_ETH_USDC),
            false,
            6 // Decimals of Quote asset -> USDC -> 6
        );
    }

    function test_getExchangeRate_ETH() public {
        // ((1e54 / _getDexSmartDebtOperate()) * _getExternalPrice(_COL_DEBT_ORACLE.getExchangeRateOperate())) / 1e27;

        // 200$ total reserves
        // on
        // 100 shares

        // 200e12 * 1e33 / 100e18  = 2e27
        // adjusted for buffer percent so slightly more (debt increases)

        // 1e54 / 2e27 = 5e26

        // external UniV3CheckCLRSOracle_ETH_USDC operate returns:
        // 2642.045442814273598

        // 5e26* 2642e15 = 1321e42 / e27 = 1321e15

        // EXPECT TO GET:
        // 1 share = ~2$
        // so shares per 1 ETH should be ETH USD price / 2 = ~1321 shares = 1321e18
        // scaled to 1e27 so ~1321e27

        assertEq(oracle.getExchangeRateOperate(), 1323_253514788856674907629156477);
    }

    function test_getExchangeRate_WBTC() public {
        oracle = new DexSmartDebtPegOracle(
            // string memory infoName_,
            // address dexPool_,
            // address reservesConversionOracle_,
            // bool quoteInToken0_,
            // bool reservesConversionInvert_,
            // uint256 reservesPegBufferPercent_,
            // IFluidOracle colDebtOracle_,
            // bool colDebtInvert_
            "USDC/USDT debt shares per 1 WBTC",
            DEX_USDC_USDT,
            address(0),
            false,
            false,
            1000, // 10000 = 1%; 100 = 0.01%
            IFluidOracle(FallbackCLRSOracle_WBTC_USDC),
            false,
            6 // Decimals of Quote asset -> USDC -> 6
        );

        // EXPECT TO GET:
        // 1 share = ~2$
        // so shares per 1 WBTC should be WBTC USD price / 2 = ~34000 shares = 34000e18
        // scaled to 1e27 so ~34000e27
        // adjusted decimals diff 34000e37

        assertEq(oracle.getExchangeRateOperate(), 34045_0360112089807505277836407638705250835);
    }

    function test_getExchangeRate_CombinedSmartCol() public {
        // approx wstETH ETH amounts:
        // total supply shares: 21821166340000000
        // total borrow shares: 15821166340000000
        // "collateralReserves": {
        //   "token0RealReserves": "18459468557",
        //   "token1RealReserves": "21823558396",
        //   "token0ImaginaryReserves": "147666909173592",
        //   "token1ImaginaryReserves": "174561377025168"
        // },
        // "debtReserves": {
        //   "token0Debt": "13384093522",
        //   "token1Debt": "15823460003",
        //   "token0RealReserves": "13383884843",
        //   "token1RealReserves": "15819750617",
        //   "token0ImaginaryReserves": "107053774484847",
        //   "token1ImaginaryReserves": "126551398135386"
        // },

        // reserves conversion oracle: 1182306642976930878000000000

        DexSmartColPegOracle smartColPegOracle = new DexSmartColPegOracle(
            // string memory infoName_,
            // address dexPool_,
            // address reservesConversionOracle_,
            // bool quoteInToken0_,
            // bool reservesConversionInvert_,
            // uint256 reservesPegBufferPercent_,
            // IFluidOracle colDebtOracle_,
            // bool colDebtInvert_
            "ETH per 1 WSTETH/ETH col share",
            DEX_WSTETH_ETH,
            RESERVES_CONVERSION_ORACLE,
            false, // quote in ETH (token1)
            false,
            1000, // 10000 = 1%; 100 = 0.01%
            IFluidOracle(address(0)),
            false,
            18 // shares decimals
        );

        // expect ~2 ETH per 1 share, -0,1%

        // total col reserves = 18459468557 * 1182306642976930878000000000 / 1e27 +  21823558396 = 43648310696
        // 43648310696 ETH / 21821166340000000 shares = 2000273954925 ETH / SHARE
        // reduced by 0.1% = 1998273680970.075 should be 1.998273680970075e27

        assertEq(smartColPegOracle.getExchangeRateOperate(), 1998273680956688953959919266);

        oracle = new DexSmartDebtPegOracle(
            // string memory infoName_,
            // address dexPool_,
            // address reservesConversionOracle_,
            // bool quoteInToken0_,
            // bool reservesConversionInvert_,
            // uint256 reservesPegBufferPercent_,
            // IFluidOracle colDebtOracle_,
            // bool colDebtInvert_
            "WSTETH/ETH shares debt per 1 col",
            DEX_WSTETH_ETH,
            RESERVES_CONVERSION_ORACLE,
            false, // quote in ETH (token1)
            false,
            1000, // 10000 = 1%; 100 = 0.01%
            IFluidOracle(address(smartColPegOracle)),
            false,
            18 // shares decimals
        );

        // expect ~0.998 debt share per 1 col share (+0,2% as debt is increased and col reduced by 0,1%)

        // total debt reserves = 13384093522 * 1182306642976930878000000000 / 1e27 +  15823460003 = 31647562684
        // 31647562684 ETH / 15821166340000000 shares = 2000330570065 ETH / SHARE
        // increased by 0.1% = 2002330900635.065 should be 2.002330900635065e27

        // so 1e54 / 2.002330900635065e27 * 1.998273680970075e27 / 1e27 = 997973751659277095210637358

        assertEq(oracle.getExchangeRateOperate(), 997973751673678837462029209);
    }
}
