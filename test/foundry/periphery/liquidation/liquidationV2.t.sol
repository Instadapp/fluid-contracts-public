//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { VaultFactoryTest } from "../../vaultT1/factory/vaultFactory.t.sol";
import { VaultT1BaseTest } from "../../vaultT1/vault/vault.t.sol";
import { VaultsBaseTest } from "../../dex/poolT1/vaults.t.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { VaultT1Liquidator } from "../../../../contracts/periphery/liquidation/main.sol";
import { VaultLiquidator } from "../../../../contracts/periphery/liquidation/proxy.sol";
import { VaultLiquidatorImplementationV1 } from "../../../../contracts/periphery/liquidation/implementations/implementationsV1.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

import { Structs as VaultStructs } from "../../../../contracts/periphery/resolvers/vault/structs.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { MockFLA } from "../../../../contracts/mocks/mockFLA.sol";
import { MockSwap } from "../../../../contracts/mocks/mockSwap.sol";
import { MockWETH } from "../../../../contracts/mocks/mockWETH.sol";

import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";


import { FluidVaultT1_Not_For_Prod } from "../../../../contracts/protocols/vault/vaultT1_not_for_prod/coreModule/main.sol";


contract VaultT1LiquidatorBase is VaultsBaseTest, VaultT1BaseTest {
    using stdStorage for StdStorage;

    VaultLiquidator vaultLiquidator;
    VaultLiquidatorImplementationV1 vaultLiquidatorImplementationV1;

    MockWETH wETH_;
    MockFLA fla_;
    MockSwap swapAggr_;

    function setUp() public virtual override(VaultT1BaseTest, VaultsBaseTest) {
        super.setUp();

        wETH_ = new MockWETH();
        fla_ = new MockFLA();
        swapAggr_ = new MockSwap();
        address[] memory rebalancers_ = new address[](1);
        rebalancers_[0] = address(alice);

        vaultLiquidatorImplementationV1 = new VaultLiquidatorImplementationV1(address(fla_), address(wETH_));
        address[] memory implementations_ = new address[](1);
        implementations_[0] = address(vaultLiquidatorImplementationV1);

        vaultLiquidator = new VaultLiquidator(address(bob), rebalancers_, implementations_);

        TestERC20(address(DAI)).mint(address(fla_), 1e50 ether);
        TestERC20(address(DAI)).mint(address(swapAggr_), 1e50 ether);
        TestERC20(address(USDC)).mint(address(fla_), 1e50 ether);
        TestERC20(address(USDC)).mint(address(swapAggr_), 1e50 ether);
        TestERC20(address(DAI)).mint(address(vaultLiquidator), 1e50 ether);
        TestERC20(address(USDC)).mint(address(vaultLiquidator), 1e50 ether);
        vm.deal(alice, 500 ether);
        vm.startPrank(alice);
        wETH_.deposit{ value: 200 ether }();
        wETH_.transfer(address(fla_), 100 ether);
        wETH_.transfer(address(swapAggr_), 100 ether);
        vm.stopPrank();
        vm.deal(address(swapAggr_), 1e50 ether);
        vm.deal(address(vaultLiquidator), 1e20 ether);
    }

    struct LiquidatorParams {
        DexVaultParams vaultParams;
        VaultType vaultType;

        bool paybackInToken0;
        bool withdrawInToken0;
    }

    struct LiquidatorVariables {
        string assertMessage;
        address vault;
        FluidDexT1 dex;

        uint256 supplyAmountToken0;
        uint256 supplyAmountToken1;

        uint256 borrowAmountToken0;
        uint256 borrowAmountToken1;
    }

    struct LiquidatorData {
        address flashloanToken;
        uint256 flashloanAmount;

        uint256 collateralAmountToken0;
        uint256 collateralAmountToken1;

        uint256 debtAmountToken0;
        uint256 debtAmountToken1;

        address sellToken;
        uint256 sellAmount;
        address buyToken;
        uint256 buyAmount;

        int256 totalToken0OutOfLiquidity;
        int256 totalToken1OutOfLiquidity;
    }

    function _getLiquidationParams(
        LiquidatorParams memory params_,
        LiquidatorVariables memory var_,
        VaultStructs.LiquidationStruct memory liquidationData_
    ) internal returns (LiquidatorData memory liquidatorData_) {
        if (params_.vaultType == VaultType.VaultT2 || params_.vaultType == VaultType.VaultT4) {
            (liquidatorData_.collateralAmountToken0, liquidatorData_.collateralAmountToken1) = _getDexWithdrawPerfectInOneTokenAmount(var_.dex, liquidationData_.outAmt,  params_.withdrawInToken0);
            
            liquidatorData_.sellToken = params_.withdrawInToken0 ? liquidationData_.token0Out : liquidationData_.token1Out;
            liquidatorData_.sellAmount = params_.withdrawInToken0 ? liquidatorData_.collateralAmountToken0 : liquidatorData_.collateralAmountToken1;

            liquidatorData_.totalToken0OutOfLiquidity += int256(liquidatorData_.collateralAmountToken0);
            liquidatorData_.totalToken1OutOfLiquidity += int256(liquidatorData_.collateralAmountToken1);
        } else {
            (liquidatorData_.collateralAmountToken0, liquidatorData_.collateralAmountToken1) = (liquidationData_.outAmt, 0);
            liquidatorData_.sellToken = liquidationData_.token0Out;
            liquidatorData_.sellAmount = liquidationData_.outAmt;

            liquidatorData_.totalToken0OutOfLiquidity += int256(liquidatorData_.collateralAmountToken0);
            liquidatorData_.totalToken1OutOfLiquidity += int256(liquidatorData_.collateralAmountToken1);
        }

        if (params_.vaultType == VaultType.VaultT3 || params_.vaultType == VaultType.VaultT4) {
            (liquidatorData_.debtAmountToken0, liquidatorData_.debtAmountToken1) = _getDexPaybackPerfectInOneTokenAmount(var_.dex, liquidationData_.inAmt,  params_.paybackInToken0);

            address debtToken_ = params_.paybackInToken0 ? liquidationData_.token0In : liquidationData_.token1In;
            uint256 debtAmount_ = params_.paybackInToken0 ? liquidatorData_.debtAmountToken0 : liquidatorData_.debtAmountToken1;
            liquidatorData_.flashloanToken = debtToken_;
            liquidatorData_.flashloanAmount = (debtAmount_ * 100) / 100;
            liquidatorData_.buyToken = debtToken_;
            liquidatorData_.buyAmount = debtAmount_;

            liquidatorData_.totalToken0OutOfLiquidity -= int256(liquidatorData_.debtAmountToken0);
            liquidatorData_.totalToken1OutOfLiquidity -= int256(liquidatorData_.debtAmountToken1);
        } else {
            (liquidatorData_.debtAmountToken0, liquidatorData_.debtAmountToken1) = (liquidationData_.inAmt, 0);
            liquidatorData_.flashloanToken = liquidationData_.token0In;
            liquidatorData_.flashloanAmount = (liquidationData_.inAmt * 100) / 100;

            liquidatorData_.buyToken = liquidationData_.token0In;
            liquidatorData_.buyAmount = liquidationData_.inAmt;

            // Note: had to swap token0 and token1
            liquidatorData_.totalToken1OutOfLiquidity -= int256(liquidatorData_.debtAmountToken0);

        }
    }

    function _testLiquidator(LiquidatorParams memory params_, string memory customMessage_) internal {
        LiquidatorVariables memory var_;

        var_.assertMessage = string(abi.encodePacked(
            customMessage_,
            "::_testLiquidator::",
            _getDexVaultPoolName(params_.vaultParams, params_.vaultType)
        ));

        var_.vault = _getVaultTypeAddress(params_.vaultParams, params_.vaultType);
        var_.dex = FluidDexT1(payable(_getDexTypeAddressForVault(params_.vaultParams, params_.vaultType)));

        VaultStructs.LiquidationStruct memory liquidationData_ = vaultResolver.getVaultLiquidation(address(var_.vault), 0);
        assertNotEq(liquidationData_.outAmt, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.outAmt: Before first liquidation")));
        assertNotEq(liquidationData_.inAmt, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.inAmt: Before first liquidation")));
        assertNotEq(
            liquidationData_.outAmtWithAbsorb,
            0,
            string(abi.encodePacked(var_.assertMessage, "liquidationData_.outAmtWithAbsorb: Before first liquidation"))
        );   
        assertNotEq(liquidationData_.inAmtWithAbsorb, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.inAmtWithAbsorb: Before first liquidation")));

        // console.log("liquidationData_.outAmt: Before first liquidation", liquidationData_.outAmt);
        // console.log("liquidationData_.inAmt: Before first liquidation", liquidationData_.inAmt);
        // console.log("liquidationData_.outAmtWithAbsorb: Before first liquidation", liquidationData_.outAmtWithAbsorb);
        // console.log("liquidationData_.inAmtWithAbsorb: Before first liquidation", liquidationData_.inAmtWithAbsorb);

        VaultLiquidatorImplementationV1.LiquidationParams memory liquidatorParams;

        // params_.paybackInToken0 = !params_.paybackInToken0;
        LiquidatorData memory liquidatorData_ = _getLiquidationParams(params_, var_, liquidationData_);

        liquidatorParams = VaultLiquidatorImplementationV1.LiquidationParams({
            vault: address(var_.vault),
            vaultType: uint256(params_.vaultType) + 1,
            expiration: 0,
            topTick: type(int256).min,

            route: 5,
            flashloanToken: liquidatorData_.flashloanToken,
            flashloanAmount: liquidatorData_.flashloanAmount,

            token0DebtAmt: liquidatorData_.debtAmountToken0,
            token1DebtAmt: liquidatorData_.debtAmountToken1,
            debtSharesMin: 0,
            colPerUnitDebt: 0,
            token0ColAmtPerUnitShares: params_.withdrawInToken0 ? 1 : 0,
            token1ColAmtPerUnitShares: params_.withdrawInToken0 ? 0 : 1,
            absorb: liquidationData_.absorbAvailable,

            swapToken: liquidatorData_.sellToken,
            swapAmount: liquidatorData_.sellAmount,
            swapRouter: address(swapAggr_),
            swapApproval: address(swapAggr_),
            swapData: abi.encodeWithSelector(
                MockSwap.swap.selector,
                liquidatorData_.buyToken, // buy
                liquidatorData_.sellToken, // sell,
                liquidatorData_.buyAmount,
                liquidatorData_.sellAmount
            )
        });

        VaultDexStateData memory preState_;
        
        if (params_.vaultType != VaultType.VaultT1) {
            preState_ = _getDexVaultState(params_.vaultParams, params_.vaultType, address(vaultLiquidator), 1);
        }
        vm.prank(alice);
        vaultLiquidator.execute(address(vaultLiquidatorImplementationV1), abi.encodeWithSelector(VaultLiquidatorImplementationV1.liquidation.selector, liquidatorParams));
        if (params_.vaultType != VaultType.VaultT1) {
            VaultDexStateData memory postState_ = _getDexVaultState(params_.vaultParams, params_.vaultType, address(vaultLiquidator), 1);
            assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), -liquidatorData_.totalToken0OutOfLiquidity, 750294766000000, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
            assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -liquidatorData_.totalToken1OutOfLiquidity, 750294766000000, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));
        
            assertApproxEqAbs(int256(preState_.userToken0Balance) - int256(postState_.userToken0Balance), 0, 750294766000000, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
            assertApproxEqAbs(int256(preState_.userToken1Balance) - int256(postState_.userToken1Balance), 0, 750294766000000, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));
        }

        liquidationData_ = vaultResolver.getVaultLiquidation(address(var_.vault), 0);
        assertEq(liquidationData_.outAmt, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.outAmt: After first liquidation")));
        assertEq(liquidationData_.inAmt, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.inAmt: After first liquidation")));
        assertEq(liquidationData_.outAmtWithAbsorb, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.outAmtWithAbsorb: After first liquidation")));
        assertEq(liquidationData_.inAmtWithAbsorb, 0, string(abi.encodePacked(var_.assertMessage, "liquidationData_.inAmtWithAbsorb: After first liquidation")));
    }

    struct VaultT1Params {
        FluidVaultT1 vault;
        MockOracle oracle;
    }

    function testLiquidatorT1() public {
        int nativeCol_ = 5 * 1e18;
        int debt_ = 7900 * 1e18;

        uint oracleThreePrice_ = 1e27 * (2000); // 1 ETH = 2000 DAI

        // 1e27 * 2000 * 1e18 / 1 * 1e18
        _setOracleThreePrice(oracleThreePrice_);

        vm.prank(alice);
        vaultThree.operate{ value: uint(nativeCol_) }(
            0, // new position
            nativeCol_,
            debt_,
            alice
        );
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(address(vaultThree));
        assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
        assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
        assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);

        oracleThreePrice_ = (oracleThreePrice_ * 95) / 100;
        _setOracleThreePrice(oracleThreePrice_);

        DexVaultParams memory vaultParams;
        vaultParams.vaultT1 = FluidVaultT1_Not_For_Prod(payable(address(vaultThree)));
        vaultParams.oracleT1 = oracleThree;

        LiquidatorParams memory liquidatorParams = LiquidatorParams({
            vaultParams: vaultParams,
            vaultType: VaultType.VaultT1,

            withdrawInToken0: true,
            paybackInToken0: true
        });
        _testLiquidator(liquidatorParams, "testLiquidatorT1");
    }

    function testLiquidatorA() public {
        DexVaultParams[1] memory vaults_ = [DAI_USDC_VAULT];
        VaultType[4] memory vaultTypes_ = [VaultType.VaultT1, VaultType.VaultT2, VaultType.VaultT3, VaultType.VaultT4];


        OperateParams[4] memory params_ = [
            OperateParams({
                supplyToken0: 100,
                supplyToken1: 0,
                supplyShareMinMax: 0,
                borrowToken0: 0,
                borrowToken1: 75,
                borrowShareMinMax: 0
            }),
            OperateParams({
                supplyToken0: 50,
                supplyToken1: 150,
                supplyShareMinMax: 1,
                borrowToken0: 0,
                borrowToken1: 75,
                borrowShareMinMax: 0
            }),
            OperateParams({
                supplyToken0: 100,
                supplyToken1: 0,
                supplyShareMinMax: 1,
                borrowToken0: 40,
                borrowToken1: 110,
                borrowShareMinMax: 150
            }),
            OperateParams({
                supplyToken0: 50,
                supplyToken1: 150,
                supplyShareMinMax: 1,
                borrowToken0: 50,
                borrowToken1: 100,
                borrowShareMinMax: 150
            })
        ];

        for(uint256 i = 0; i < vaults_.length; i++) {
            for(uint256 j = 0; j < vaultTypes_.length; j++) {
                if (vaultTypes_[j] == VaultType.VaultT1) continue;

                OperateParams memory param_ = params_[j];

                OperateData memory d_ = _testOperate(vaults_[i], vaultTypes_[j], _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], param_), alice, 0, "testLiquidator(supply)");


                uint256 oraclePrice_ = _getOraclePrice(vaults_[i], vaultTypes_[j]) * 900 / 1000;
                _setOraclePrice(vaults_[i], vaultTypes_[j], oraclePrice_);

                LiquidatorParams memory liquidatorParams = LiquidatorParams({
                    vaultParams: vaults_[i],
                    vaultType: vaultTypes_[j],

                    withdrawInToken0: true,
                    paybackInToken0: true
                });

                _testLiquidator(liquidatorParams, "testLiquidator(liquidate)");
            }
        }
    }

    // function testVaultT1LiquidatorContractNativeCollateral() public {
    //     int nativeCol_ = 5 * 1e18;
    //     int debt_ = 7900 * 1e18;

    //     uint oracleThreePrice_ = 1e27 * (2000); // 1 ETH = 2000 DAI

    //     // 1e27 * 2000 * 1e18 / 1 * 1e18
    //     _setOracleThreePrice(oracleThreePrice_);

    //     vm.prank(alice);
    //     vaultThree.operate{ value: uint(nativeCol_) }(
    //         0, // new position
    //         nativeCol_,
    //         debt_,
    //         alice
    //     );
    //     FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(address(vaultThree));
    //     assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
    //     assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);

    //     oracleThreePrice_ = (oracleThreePrice_ * 95) / 100;
    //     _setOracleThreePrice(oracleThreePrice_);

    //     _liquidate(address(vaultThree));
    // }

    // function testVaultT1LiquidatorContractNativeDebt() public {
    //     int collateral = 10_000 * 1e18;
    //     int debt = 3.995 * 1e18;
    //     uint oraclePrice = (1e27 * (1 * 1e18)) / (2000 * 1e18); // 1 ETH = 2000 DAI => 1 DAI => 1/2000 ETH

    //     address vault = address(vaultFour);

    //     // 1e27 * 1 * 1e18 / 2000 * 1e18
    //     _setOracleFourPrice(oraclePrice);

    //     vm.prank(alice);
    //     vaultFour.operate(
    //         0, // new position
    //         collateral,
    //         debt,
    //         alice
    //     );

    //     FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(address(vault));
    //     assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
    //     assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);
    //     console.log("Oracle data oraclePriceOperate", vaultData_.configs.oraclePriceOperate);
    //     console.log("Oracle data oraclePriceLiquidate", vaultData_.configs.oraclePriceLiquidate);
    //     console.log("Oracle data", vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
    //     console.log("Oracle data", vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);

    //     oraclePrice = (oraclePrice * 975) / 1000;
    //     _setOracleFourPrice(oraclePrice);
    //     vaultData_ = vaultResolver.getVaultEntireData(address(vault));
    //     assertNotEq(vaultData_.configs.oraclePriceOperate, 0);
    //     assertNotEq(vaultData_.configs.oraclePriceLiquidate, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalSupplyVault, 0);
    //     assertNotEq(vaultData_.totalSupplyAndBorrow.totalBorrowVault, 0);
    //     console.log("Oracle data after oraclePriceOperate", vaultData_.configs.oraclePriceOperate);
    //     console.log("Oracle data after oraclePriceLiquidate", vaultData_.configs.oraclePriceLiquidate);

    //     _liquidate(vault);
    // }

    // function _liquidate(address vault) internal {
    //     VaultStructs.LiquidationStruct memory liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
    //     assertNotEq(liquidationData_.outAmt, 0, "liquidationData_.outAmt: Before first liquidation");
    //     assertNotEq(liquidationData_.inAmt, 0, "liquidationData_.inAmt: Before first liquidation");
    //     assertNotEq(
    //         liquidationData_.outAmtWithAbsorb,
    //         0,
    //         "liquidationData_.outAmtWithAbsorb: Before first liquidation"
    //     );
    //     assertNotEq(liquidationData_.inAmtWithAbsorb, 0, "liquidationData_.inAmtWithAbsorb: Before first liquidation");

    //     console.log("liquidationData_.outAmt: Before first liquidation", liquidationData_.outAmt);
    //     console.log("liquidationData_.inAmt: Before first liquidation", liquidationData_.inAmt);
    //     console.log("liquidationData_.outAmtWithAbsorb: Before first liquidation", liquidationData_.outAmtWithAbsorb);
    //     console.log("liquidationData_.inAmtWithAbsorb: Before first liquidation", liquidationData_.inAmtWithAbsorb);

    //     VaultT1Liquidator.LiquidatorParams memory LiquidatorParams = VaultT1Liquidator.LiquidatorParams({
    //         vault: address(vault),
    //         supply: liquidationData_.token0Out,
    //         borrow: liquidationData_.token0In,
    //         supplyAmount: (liquidationData_.outAmt * 110) / 100,
    //         borrowAmount: (liquidationData_.inAmt * 110) / 100,
    //         colPerUnitDebt: 0,
    //         absorb: true,
    //         swapRouter: address(swapAggr),
    //         swapApproval: address(swapAggr),
    //         swapData: abi.encodeWithSelector(
    //             MockSwap.swap.selector,
    //             liquidationData_.token0In, // buy
    //             liquidationData_.token0Out, // sell,
    //             liquidationData_.inAmt,
    //             liquidationData_.outAmt
    //         ),
    //         route: 5
    //     });

    //     vm.prank(alice);
    //     vaultT1Liquidation.liquidation(LiquidatorParams);

    //     liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
    //     assertEq(liquidationData_.outAmt, 0, "liquidationData_.outAmt: After first liquidation");
    //     assertEq(liquidationData_.inAmt, 0, "liquidationData_.inAmt: After first liquidation");
    //     assertEq(liquidationData_.outAmtWithAbsorb, 0, "liquidationData_.outAmtWithAbsorb: After first liquidation");
    //     assertEq(liquidationData_.inAmtWithAbsorb, 0, "liquidationData_.inAmtWithAbsorb: After first liquidation");

    //     liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
    //     assertEq(liquidationData_.outAmt, 0, "liquidationData_.outAmt: Before second liquidation");
    //     assertEq(liquidationData_.inAmt, 0, "liquidationData_.inAmt: Before second liquidation");
    //     assertEq(liquidationData_.outAmtWithAbsorb, 0, "liquidationData_.outAmtWithAbsorb: Before second liquidation");
    //     assertEq(liquidationData_.inAmtWithAbsorb, 0, "liquidationData_.inAmtWithAbsorb: Before second liquidation");

    //     LiquidatorParams = VaultT1Liquidator.LiquidatorParams({
    //         vault: address(vault),
    //         supply: liquidationData_.token0Out,
    //         borrow: liquidationData_.token0In,
    //         supplyAmount: (liquidationData_.outAmt * 110) / 100,
    //         borrowAmount: (liquidationData_.inAmt * 110) / 100,
    //         colPerUnitDebt: 0,
    //         absorb: true,
    //         swapRouter: address(swapAggr),
    //         swapApproval: address(swapAggr),
    //         swapData: abi.encodeWithSelector(
    //             MockSwap.swap.selector,
    //             liquidationData_.token0In, // buy
    //             liquidationData_.token0Out, // sell,
    //             liquidationData_.inAmt,
    //             liquidationData_.outAmt
    //         ),
    //         route: 5
    //     });

    //     vm.prank(alice);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidLiquidationAmt)
    //     );
    //     vaultT1Liquidation.liquidation(LiquidatorParams);

    //     liquidationData_ = vaultResolver.getVaultLiquidation(address(vault), 0);
    //     assertEq(liquidationData_.outAmt, 0, "liquidationData_.outAmt: After second liquidation");
    //     assertEq(liquidationData_.inAmt, 0, "liquidationData_.inAmt: After second liquidation");
    //     assertEq(liquidationData_.outAmtWithAbsorb, 0, "liquidationData_.outAmtWithAbsorb: After second liquidation");
    //     assertEq(liquidationData_.inAmtWithAbsorb, 0, "liquidationData_.inAmtWithAbsorb: After second liquidation");
    // }
}
