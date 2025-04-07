//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { DexSmartColPegOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartColPegOracle.sol";
import { DexSmartDebtPegOracle } from "../../../../contracts/oracle/oracles/dex/dexSmartDebtPegOracle.sol";
import { DexConversionPriceFluidOracle } from "../../../../contracts/oracle/implementations/dex/conversionPriceGetters/conversionPriceFluidOracle.sol";
import { ErrorTypes } from "../../../../contracts/oracle/errorTypes.sol";
import { Error } from "../../../../contracts/oracle/error.sol";
import { IFluidOracle } from "../../../../contracts/oracle/fluidOracle.sol";

import "forge-std/console2.sol";

contract DexSmartDebtPegOracleTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_USDT = 0x085B07A30381F3Cc5A4250e10E4379d465b770ac;
    address internal constant UniV3CheckCLRSOracle_ETH_USDC = 0x5b2860C6D6F888319C752aaCDaf8165C21095E3a;
    address internal constant FallbackCLRSOracle_WBTC_USDC = 0x131BA983Ab640Ce291B98694b3Def4288596cD09;

    address internal constant DEX_WSTETH_ETH = 0x25F0A3B25cBC0Ca0417770f686209628323fF901;
    address internal constant RESERVES_CONVERSION_ORACLE = 0xf1442714E502723D5bB253B806Fd7555BEE0336C; // Wsteth contract rate

    address internal constant DEX_GHO_USDC = 0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45;

    DexSmartDebtPegOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21005237);
    }

    function test_getExchangeRate_USDC() public {
        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "USDC/USDT debt shares per 1 USDC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_USDT,
                true, // quote in token0, USDC
                IFluidOracle(address(0)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1e18, 1e18),
                1,
                1
            )
        );

        // 200$ total reserves
        // on
        // 100 shares

        // 200e12 * 1e33 / 100e18  = 2e27
        // adjusted for buffer percent so slightly more (debt increases)
        // 1e54 / 2e27 = ~5e26

        (uint256 operateRate, uint256 liquidateRate) = oracle.dexSmartDebtSharesRates();
        assertEq(operateRate, 499394072686757340150262183);
        assertEq(liquidateRate, 499394072686757340150262183);

        assertEq(oracle.getExchangeRateOperate(), 499394072686757340150262183);
    }

    function test_getExchangeRate_ETH() public {
        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "USDC/USDT debt shares per 1 ETH",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_USDT,
                true, // quote in token0, USDC
                IFluidOracle(UniV3CheckCLRSOracle_ETH_USDC),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1e18, 1e18),
                1e12, // diff of USDC to shares decimals
                1
            )
        );

        // external UniV3CheckCLRSOracle_ETH_USDC operate returns:
        // 2642.045442814273598

        // 5e26* 2642e15 = 1321e42 / e27 = 1321e15

        // EXPECT TO GET:
        // 1 share = ~2$
        // so shares per 1 ETH should be ETH USD price / 2 = ~1321 shares = 1321e18
        // scaled to 1e27 so ~1321e27

        assertEq(oracle.getExchangeRateOperate(), 1323_253518905796187840388560187);
    }

    function test_getExchangeRate_WBTC() public {
        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "USDC/USDT debt shares per 1 WBTC",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_USDT,
                true, // quote in token0, USDC
                IFluidOracle(FallbackCLRSOracle_WBTC_USDC),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1e18, 1e18),
                1e12, // diff of USDC to shares decimals
                1
            )
        );

        // EXPECT TO GET:
        // 1 share = ~2$
        // so shares per 1 WBTC should be WBTC USD price / 2 = ~34000 shares = 34000e18
        // scaled to 1e27 so ~34000e27
        // adjusted decimals diff 34000e37
        assertEq(oracle.getExchangeRateOperate(), 34045_0361171307503942907400327229870249690);
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
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "ETH per 1 WSTETH/ETH col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_WSTETH_ETH,
                false, // quote in ETH (token1)
                IFluidOracle(address(0)),
                false,
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

        // expect ~2 ETH per 1 share, -0,1%

        // total col reserves = 18459468557 * 1182306642976930878000000000 / 1e27 +  21823558396 = 43648310696
        // 43648310696 ETH / 21821166340000000 shares = 2000273954925 ETH / SHARE
        // reduced by 0.1% = 1998273680970.075 should be 1.998273680970075e27

        assertEq(smartColPegOracle.getExchangeRateOperate(), 1998273680910861889337488089);

        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "WSTETH/ETH shares debt per 1 col",
                SAMPLE_TARGET_DECIMALS,
                DEX_WSTETH_ETH,
                false, // quote in ETH (token1)
                IFluidOracle(address(smartColPegOracle)),
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

        // expect ~0.998 debt share per 1 col share (+0,2% as debt is increased and col reduced by 0,1%)

        // total debt reserves = 13384093522 * 1182306642976930878000000000 / 1e27 +  15823460003 = 31647562684
        // 31647562684 ETH / 15821166340000000 shares = 2000330570065 ETH / SHARE
        // increased by 0.1% = 2002330900635.065 should be 2.002330900635065e27

        // so 1e54 / 2.002330900635065e27 * 1.998273680970075e27 / 1e27 = 997973751659277095210637358

        assertEq(oracle.getExchangeRateOperate(), 997973751650791978647202523);
    }

    function test_getExchangeRate_CombinedSmartCol_GHO_USDC() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21108403);

        // amounts:
        //   "totalSupplyShares": "100000000000000000000",
        //   "totalBorrowShares": "100000000000000000000",
        //   "poolReserves_": {
        //     "pool": "0xde632c3a214d5f14c1d8ddf0b92f8bcd188fee45",
        //     "token0": "0x40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f",
        //     "token1": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        //     "fee": "500",
        //     "collateralReserves": {
        //       "token0RealReserves": "100000024990199",
        //       "token1RealReserves": "100006983000000",
        //       "token0ImaginaryReserves": "199956990279911296",
        //       "token1ImaginaryReserves": "199956997182988289"
        //     },
        //     "debtReserves": {
        //       "token0Debt": "100000493401791",
        //       "token1Debt": "100008596000000",
        //       "token0RealReserves": "99958581248391",
        //       "token1RealReserves": "99950478595221",
        //       "token0ImaginaryReserves": "199859074156997866",
        //       "token1ImaginaryReserves": "199859065999438573"
        //     }

        DexSmartColPegOracle smartColPegOracle = new DexSmartColPegOracle(
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "USDC per 1 GHO/USDC col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                false, // quote in USDC (token1)
                IFluidOracle(address(0)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1,
                1e12
            )
        );

        // expect ~2 USDC or GHO per 1 share, -0,1%

        // total col reserves = 100000024990199 + 100006983000000 = 200007007990199.
        // scaled to USDC token decimals = 200_007007
        // 200_007007 * 1e18 USDC / 100e18 shares = 2_000070 USDC / SHARE
        // scaled to 1e27 (*1e9) = 2_000070e9
        // reduced by 0.1% should be ~1.998070008921e15

        assertEq(smartColPegOracle.getExchangeRateOperate(), 1998070380000000);

        DexSmartColPegOracle smartColPegOracleInGHO = new DexSmartColPegOracle(
            DexSmartColPegOracle.DexSmartColPegOracleParams(
                "USDC per 1 GHO/USDC col share",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                true, // quote in GHO (token0)
                IFluidOracle(address(0)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1e12, 1),
                1,
                1
            )
        );
        // same as for USDC but should be * 1e12 to adjust for GHO decimals (18)
        assertEq(smartColPegOracleInGHO.getExchangeRateOperate(), 1998070381190340e12);

        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "GHO/USDC debt sh. per 1 col sh.",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                false, // quote in USDC (token1)
                IFluidOracle(address(smartColPegOracle)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1e12,
                1
            )
        );

        // expect ~0.998 debt share per 1 col share (+0,2% as debt is increased and col reduced by 0,1%)

        // total debt reserves = 100000493401791 + 100008596000000 = 200009089401791e15
        // 200009089401791e15 debtToken / 100000000000000000000 shares = 2000090894 debtToken / SHARE
        // increased by 0.1% = 2002090984.894 should be 2.002090984894e27

        // so 1e54 / 2.002090984894e27 * 1.998070008921e27 / 1e27 = 997991611768226962396232985
        assertEq(oracle.getExchangeRateOperate(), 997991565270407603009343053);

        // when using GHO quoted col oracle
        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "GHO/USDC debt sh. per 1 col sh.",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                true, // quote in GHO (token0)
                IFluidOracle(address(smartColPegOracleInGHO)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1,
                1
            )
        );
        assertEq(oracle.getExchangeRateOperate(), 997991562882852026922073446);

        oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "GHO/USDC debt sh. per 1 col sh.",
                SAMPLE_TARGET_DECIMALS,
                DEX_GHO_USDC,
                false, // quote in USDC (token1)
                IFluidOracle(address(smartColPegOracleInGHO)),
                false,
                1000, // 10000 = 1%; 100 = 0.01%
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1e12),
                1,
                1
            )
        );
        assertEq(oracle.getExchangeRateOperate(), 997991565864955869023865017);
    }
}

contract DexSmartDebtPegOracleT4DiffTest is Test {
    uint8 public constant SAMPLE_TARGET_DECIMALS = 20; // sample target decimals - doesn't matter in test

    address internal constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21768700);
    }

    function test_getExchangeRate_SUSDE_USDT_T4() public {
        DexSmartDebtPegOracle oracle = new DexSmartDebtPegOracle(
            DexSmartDebtPegOracle.DexSmartDebtPegOracleParams(
                "USDC-T dbtSh /1 SUSDE-USDT colSh",
                SAMPLE_TARGET_DECIMALS,
                DEX_USDC_USDT,
                false, // quote in USDT (token1)
                IFluidOracle(0x8D72C81EDfdD7F0601c00bDAc5d09418cfbbedDa),
                false,
                1000, // pegBufferPercent; (10000 = 1%; 100 = 0.01%)
                DexConversionPriceFluidOracle.DexConversionPriceFluidOracleParams(address(0), false, 1, 1),
                1e12,
                1
            )
        );

        // existing 0x8D72C81EDfdD7F0601c00bDAc5d09418cfbbedDa oracle returns USDT per 1 SUSDE/USDT colShare, e.g.:
        // 2008996334479270
        uint256 usdtPerColShare = IFluidOracle(0x8D72C81EDfdD7F0601c00bDAc5d09418cfbbedDa).getExchangeRateOperate();
        console2.log("oracle debtShares liquidate:", usdtPerColShare);
        assertEq(usdtPerColShare, 2008996334479270);

        // smart debt oracle returns USDC-USDT debtSh per 1 USDT (in 1e27 here), e.g.:
        // 483420459118261427178599160

        // we need USDC-T dbtSh / 1 SUSDE-USDT colSh so
        // debtSh / 1 USDT * USDT / 1 colSh=

        // 483420459118261427178599160 * 2008996334479270 / 1e27 = 971189949050191
        // must scale to 1e27 as it is share per share not USDT -> so result * 1e12 = 971189930380873003097022829

        (uint256 debtSharesOperate, uint256 debtSharesLiquidate) = oracle.dexSmartDebtSharesRates();
        console2.log("oracle debtShares operate:", debtSharesOperate);
        assertEq(debtSharesOperate, 483420459118261427178599160);

        // Fetch the exchange rate from the deployed oracle.
        uint256 exchangeRate = oracle.getExchangeRateOperate();
        console2.log("Exchange Rate (USDC-USDT debt sh. per 1 SUSDE-USDT col sh.):", exchangeRate);

        // Verify that the fetched exchange rate is nonzero.
        assertEq(exchangeRate, 971189930380873003097022829);
    }
}
