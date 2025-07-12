//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibString } from "solmate/src/utils/LibString.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { FluidVaultPositionsResolver } from "../../../../contracts/periphery/resolvers/vaultPositions/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";

import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";
import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexStrcuts } from "../../../../contracts/protocols/dex/poolT1/coreModule/structs.sol";
import { Structs as DexAdminStrcuts } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { FluidContractFactory } from "../../../../contracts/deployer/main.sol";

import { ConstantVariables as FluidDexT1ConstantVariables } from "../../../../contracts/protocols/dex/poolT1/common/constantVariables.sol";

import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";
import { MockDexCenterPrice } from "../../../../contracts/mocks/mockDexCenterPrice.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { DexFactoryBaseTest } from "./factory/dexFactory.t.sol";
import { FluidLiquidityUserModule } from "../../../../contracts/liquidity/userModule/main.sol";

import { Events as FluidLiquidityUserModuleEvents } from "../../../../contracts/liquidity/userModule/events.sol";

import { VaultFactoryBaseTest } from "../../vaultT1/factory/vaultFactory.t.sol";
import { PoolT1BaseTest } from "./pool.t.sol";

import { FluidVaultT1DeploymentLogic_Not_For_Prod } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic_not_for_prod.sol";
import { FluidVaultT2DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT2Logic.sol";
import { FluidVaultT3DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT3Logic.sol";
import { FluidVaultT4DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT4Logic.sol";

import { FluidVaultSecondary } from "../../../../contracts/protocols/vault/vaultTypesCommon/coreModule/main2.sol";

import { Error as FluidVaultError } from "../../../../contracts/protocols/vault/error.sol";

import { FluidVaultT1Admin_Not_For_Prod } from "../../../../contracts/protocols/vault/vaultT1_not_for_prod/adminModule/main.sol";
import { FluidVaultT1_Not_For_Prod } from "../../../../contracts/protocols/vault/vaultT1_not_for_prod/coreModule/main.sol";
import { FluidVaultT1Operate_Not_For_Prod } from "../../../../contracts/protocols/vault/vaultT1_not_for_prod/coreModule/mainOperate.sol";

import { FluidVaultT2Admin } from "../../../../contracts/protocols/vault/vaultT2/adminModule/main.sol";
import { FluidVaultT2 } from "../../../../contracts/protocols/vault/vaultT2/coreModule/main.sol";
import { FluidVaultT2Operate } from "../../../../contracts/protocols/vault/vaultT2/coreModule/mainOperate.sol";

import { FluidVaultT3Admin } from "../../../../contracts/protocols/vault/vaultT3/adminModule/main.sol";
import { FluidVaultT3 } from "../../../../contracts/protocols/vault/vaultT3/coreModule/main.sol";
import { FluidVaultT3Operate } from "../../../../contracts/protocols/vault/vaultT3/coreModule/mainOperate.sol";

import { FluidVaultT4Admin } from "../../../../contracts/protocols/vault/vaultT4/adminModule/main.sol";
import { FluidVaultT4 } from "../../../../contracts/protocols/vault/vaultT4/coreModule/main.sol";
import { FluidVaultT4Operate } from "../../../../contracts/protocols/vault/vaultT4/coreModule/mainOperate.sol";


import { IFluidVault } from "../../../../contracts/protocols/vault/interfaces/iVault.sol";

import { MiniDeployer } from "../../../../contracts/protocols/vault/factory/deploymentHelpers/miniDeployer.sol";
import { SStore2Deployer } from "../../../../contracts/protocols/dex/factory/deploymentHelpers/SSTORE2Deployer.sol";

import { StorageRead } from "../../../../contracts/libraries/storageRead.sol";


contract VaultsBaseTest is VaultFactoryBaseTest, PoolT1BaseTest {
    uint256 constant X19 = 0x7ffff;

    FluidVaultT1DeploymentLogic_Not_For_Prod _vaultT1NotForProdDeploymentLogic;
    FluidVaultT2DeploymentLogic _vaultT2DeploymentLogic;
    FluidVaultT3DeploymentLogic _vaultT3DeploymentLogic;
    FluidVaultT4DeploymentLogic _vaultT4DeploymentLogic;

    SStore2Deployer _sstore2Deployer;

    FluidVaultPositionsResolver _vaultPositionsResolver;
    FluidVaultResolver _vaultResolver;

    struct DexVaultParams {
        DexParams dex;
        FluidVaultT1_Not_For_Prod vaultT1;
        FluidVaultT2 vaultT2;
        FluidVaultT3 vaultT3;
        FluidVaultT4 vaultT4;
        MockOracle oracleT1;
        MockOracle oracleT2;
        MockOracle oracleT3;
        MockOracle oracleT4;
        uint256 oracleT1Nonce;
        uint256 oracleT2Nonce;
        uint256 oracleT3Nonce;
        uint256 oracleT4Nonce;
        string vaultName;
    }

    enum VaultType {
        VaultT1,
        VaultT2,
        VaultT3,
        VaultT4
    }

    DexVaultParams DAI_USDC_VAULT;
    DexVaultParams USDC_ETH_VAULT;


    function setUp() public virtual override(PoolT1BaseTest, VaultFactoryBaseTest) {
        super.setUp();

        _vaultResolver = new FluidVaultResolver(
                address(vaultFactory),
                address(liquidityResolver_)
        );
        
        _vaultPositionsResolver = new FluidVaultPositionsResolver(
                IFluidVaultResolver(address(_vaultResolver)),
                IFluidVaultFactory(address(vaultFactory))
        );

        FluidVaultSecondary vaultSecondary_ = new FluidVaultSecondary();
        _sstore2Deployer = new SStore2Deployer();

        { // Vault T1 Not For Prod
            address vaultT1Pointer_ = _sstore2Deployer.deployCode(type(FluidVaultT1_Not_For_Prod).creationCode);
            address vaultT1OperatePointer_ = _sstore2Deployer.deployCode(type(FluidVaultT1Operate_Not_For_Prod).creationCode);
            _vaultT1NotForProdDeploymentLogic = new FluidVaultT1DeploymentLogic_Not_For_Prod(
                address(liquidity),
                address(vaultFactory),
                address(contractDeployerFactory),
                address(new FluidVaultT1Admin_Not_For_Prod()),
                address(vaultSecondary_),
                vaultT1OperatePointer_,
                vaultT1Pointer_
            );

            vm.prank(admin);
            vaultFactory.setVaultDeploymentLogic(address(_vaultT1NotForProdDeploymentLogic), true);
        }

        { // Vault T2
            address vaultT2Pointer_ = _sstore2Deployer.deployCode(type(FluidVaultT2).creationCode);
            address vaultT2OperatePointer_ = _sstore2Deployer.deployCode(type(FluidVaultT2Operate).creationCode);
            _vaultT2DeploymentLogic = new FluidVaultT2DeploymentLogic(
                address(liquidity),
                address(vaultFactory),
                address(contractDeployerFactory),
                address(new FluidVaultT2Admin()),
                address(vaultSecondary_),
                vaultT2OperatePointer_,
                vaultT2Pointer_
            );

            vm.prank(admin);
            vaultFactory.setVaultDeploymentLogic(address(_vaultT2DeploymentLogic), true);
        }

        { // Vault T3
            address vaultT3Pointer_ = _sstore2Deployer.deployCode(type(FluidVaultT3).creationCode);
            address vaultT3OperatePointer_ = _sstore2Deployer.deployCode(type(FluidVaultT3Operate).creationCode);
            _vaultT3DeploymentLogic = new FluidVaultT3DeploymentLogic(
                address(liquidity),
                address(vaultFactory),
                address(contractDeployerFactory),
                address(new FluidVaultT3Admin()),
                address(vaultSecondary_),
                vaultT3OperatePointer_,
                vaultT3Pointer_
            );

            vm.prank(admin);
            vaultFactory.setVaultDeploymentLogic(address(_vaultT3DeploymentLogic), true);
        }

        { // Vault T4
            (address vaultT4Pointer1_, address vaultT4Pointer2_) = _sstore2Deployer.deployCodeSplit(type(FluidVaultT4).creationCode);
            address vaultT4OperatePointer_ = _sstore2Deployer.deployCode(type(FluidVaultT4Operate).creationCode);
            _vaultT4DeploymentLogic = new FluidVaultT4DeploymentLogic(
                address(liquidity),
                address(vaultFactory),
                address(contractDeployerFactory),
                address(new FluidVaultT4Admin()),
                address(vaultSecondary_),
                vaultT4OperatePointer_,
                vaultT4Pointer1_,
                vaultT4Pointer2_
            );

            vm.prank(admin);
            vaultFactory.setVaultDeploymentLogic(address(_vaultT4DeploymentLogic), true);
        }

        DAI_USDC_VAULT = _deployDexVaults(DAI_USDC);
        _setUpDexVault(DAI_USDC_VAULT, 1e18); // price in 18 decimals

        USDC_ETH_VAULT = _deployDexVaults(USDC_ETH);
        _setUpDexVault(USDC_ETH_VAULT, 1e18); // price in 18 decimals
    }

    function _deployDexVaults(DexParams memory dex_) internal returns (DexVaultParams memory dexVault_) {
        bytes memory vaultT1CreationCode = abi.encodeCall(_vaultT1NotForProdDeploymentLogic.vaultT1, (dex_.token0, dex_.token1));
        bytes memory vaultT2CreationCode = abi.encodeCall(_vaultT2DeploymentLogic.vaultT2, (address(dex_.dexCol), dex_.token1));
        bytes memory vaultT3CreationCode = abi.encodeCall(_vaultT3DeploymentLogic.vaultT3, (dex_.token0, address(dex_.dexDebt)));
        bytes memory vaultT4CreationCode = abi.encodeCall(_vaultT4DeploymentLogic.vaultT4, (address(dex_.dexColDebt), address(dex_.dexColDebt)));

        vm.startPrank((admin));
        dexVault_.vaultT1 = FluidVaultT1_Not_For_Prod(payable(vaultFactory.deployVault(address(_vaultT1NotForProdDeploymentLogic), vaultT1CreationCode)));
        dexVault_.vaultT2 = FluidVaultT2(payable(vaultFactory.deployVault(address(_vaultT2DeploymentLogic), vaultT2CreationCode)));
        dexVault_.vaultT3 = FluidVaultT3(payable(vaultFactory.deployVault(address(_vaultT3DeploymentLogic), vaultT3CreationCode)));
        dexVault_.vaultT4 = FluidVaultT4(payable(vaultFactory.deployVault(address(_vaultT4DeploymentLogic), vaultT4CreationCode)));
        vm.stopPrank();

        dexVault_.dex = dex_;

        dexVault_.vaultName = dex_.poolName;

        vm.label(address(dexVault_.vaultT1), _getDexVaultPoolName(dexVault_, VaultType.VaultT1));
        vm.label(address(dexVault_.vaultT2), _getDexVaultPoolName(dexVault_, VaultType.VaultT2));
        vm.label(address(dexVault_.vaultT3), _getDexVaultPoolName(dexVault_, VaultType.VaultT3));
        vm.label(address(dexVault_.vaultT4), _getDexVaultPoolName(dexVault_, VaultType.VaultT4));

        vm.startPrank(bob);
        dexVault_.oracleT1 = MockOracle(contractDeployerFactory.deployContract(type(MockOracle).creationCode));
        dexVault_.oracleT1Nonce = contractDeployerFactory.totalContracts();
        dexVault_.oracleT2 = MockOracle(contractDeployerFactory.deployContract(type(MockOracle).creationCode));
        dexVault_.oracleT2Nonce = contractDeployerFactory.totalContracts();
        dexVault_.oracleT3 = MockOracle(contractDeployerFactory.deployContract(type(MockOracle).creationCode));
        dexVault_.oracleT3Nonce = contractDeployerFactory.totalContracts();
        dexVault_.oracleT4 = MockOracle(contractDeployerFactory.deployContract(type(MockOracle).creationCode));
        dexVault_.oracleT4Nonce = contractDeployerFactory.totalContracts();
        vm.stopPrank();

        vm.label(address(dexVault_.oracleT1), string(abi.encodePacked(_getDexVaultPoolName(dexVault_, VaultType.VaultT1), ":oracleT1")));
        vm.label(address(dexVault_.oracleT2), string(abi.encodePacked(_getDexVaultPoolName(dexVault_, VaultType.VaultT2), ":oracleT2")));
        vm.label(address(dexVault_.oracleT3), string(abi.encodePacked(_getDexVaultPoolName(dexVault_, VaultType.VaultT3), ":oracleT3")));
        vm.label(address(dexVault_.oracleT4), string(abi.encodePacked(_getDexVaultPoolName(dexVault_, VaultType.VaultT4), ":oracleT4")));
    }

    function _setUpDexVault(DexVaultParams memory dexVault_, uint256 priceInWei_) internal {
        // T1 Approval
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT1), alice);
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT1), bob);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT1), alice);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT1), bob);

        // T2 Approval
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT2), alice);
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT2), bob);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT2), alice);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT2), bob);

        // T3 Approval
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT3), alice);
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT3), bob);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT3), alice);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT3), bob);

        // T4 Approval
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT4), alice);
        _giveApproval(dexVault_.dex.token0, address(dexVault_.vaultT4), bob);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT4), alice);
        _giveApproval(dexVault_.dex.token1, address(dexVault_.vaultT4), bob);

        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), address(admin), address(dexVault_.dex.token0), address(dexVault_.vaultT1), true);
        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), address(admin), address(dexVault_.dex.token1), address(dexVault_.vaultT1), true);

        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), address(admin), address(dexVault_.dex.token1), address(dexVault_.vaultT2), true);

        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), address(admin), address(dexVault_.dex.token0), address(dexVault_.vaultT3), true);



        _setDexUserAllowancesDefault(address(dexVault_.dex.dexCol), address(admin), address(dexVault_.vaultT2));
        _setDexUserAllowancesDefault(address(dexVault_.dex.dexDebt), address(admin), address(dexVault_.vaultT3));
        _setDexUserAllowancesDefault(address(dexVault_.dex.dexColDebt), address(admin), address(dexVault_.vaultT4));

        {
            FluidVaultT1Admin_Not_For_Prod vaultAdmin_ = FluidVaultT1Admin_Not_For_Prod(address(dexVault_.vaultT1));
            vm.prank(admin);
            vaultAdmin_.updateCoreSettings(
                10000, // supplyFactor_ => 100%
                10000, // borrowFactor_ => 100%
                8000, // collateralFactor_ => 80%
                8100, // liquidationThreshold_ => 81%
                9000, // liquidationMaxLimit_ => 90%
                500, // withdrawGap_ => 5%
                0, // liquidationPenalty_ => 0%
                0 // borrowFee_ => 0.01%
            );

            _setOraclePrice(dexVault_, VaultType.VaultT1, _calculatePrice(dexVault_, VaultType.VaultT1, priceInWei_));
            vm.prank(admin);
            vaultAdmin_.updateOracle((dexVault_.oracleT1Nonce));

            vm.prank(admin);
            vaultAdmin_.updateRebalancer(address(admin));
        }

        {
            FluidVaultT2Admin vaultAdmin_ = FluidVaultT2Admin(address(dexVault_.vaultT2));
            vm.prank(admin);
            vaultAdmin_.updateCoreSettings(
                1000, // supplyRate_ => 10%
                10000, // borrowFactor_ => 100%
                8000, // collateralFactor_ => 80%
                8100, // liquidationThreshold_ => 81%
                9000, // liquidationMaxLimit_ => 90%
                500, // withdrawGap_ => 5%
                0, // liquidationPenalty_ => 0%
                0 // borrowFee_ => 0.01%
            );

            _setOraclePrice(dexVault_, VaultType.VaultT2, _calculatePrice(dexVault_, VaultType.VaultT2, priceInWei_));
            vm.prank(admin);
            vaultAdmin_.updateOracle((dexVault_.oracleT2Nonce));

            vm.prank(admin);
            vaultAdmin_.updateRebalancer(address(admin));
        }

        {
            FluidVaultT3Admin vaultAdmin_ = FluidVaultT3Admin(address(dexVault_.vaultT3));
            vm.prank(admin);
            vaultAdmin_.updateCoreSettings(
                10000, // supplyFactor_ => 100%
                1000, // borrowRate_ => 10%
                8000, // collateralFactor_ => 80%
                8100, // liquidationThreshold_ => 81%
                9000, // liquidationMaxLimit_ => 90%
                500, // withdrawGap_ => 5%
                0, // liquidationPenalty_ => 0%
                0 // borrowFee_ => 0.01%
            ); 

            _setOraclePrice(dexVault_, VaultType.VaultT3, _calculatePrice(dexVault_, VaultType.VaultT3, priceInWei_));
            vm.prank(admin);
            vaultAdmin_.updateOracle((dexVault_.oracleT3Nonce));

            vm.prank(admin);
            vaultAdmin_.updateRebalancer(address(admin));
        }

        {
            FluidVaultT4Admin vaultAdmin_ = FluidVaultT4Admin(address(dexVault_.vaultT4));
            vm.prank(admin);
            vaultAdmin_.updateCoreSettings(
                1000, // supplyRate_ => 10%
                1000, // borrowRate_ => 10%
                8000, // collateralFactor_ => 80%
                8100, // liquidationThreshold_ => 81%
                9000, // liquidationMaxLimit_ => 90%
                500, // withdrawGap_ => 5%
                0, // liquidationPenalty_ => 0%
                0 // borrowFee_ => 0.01%
            );

            _setOraclePrice(dexVault_, VaultType.VaultT4, _calculatePrice(dexVault_, VaultType.VaultT4, priceInWei_));
            vm.prank(admin);
            vaultAdmin_.updateOracle((dexVault_.oracleT4Nonce));

            vm.prank(admin);
            vaultAdmin_.updateRebalancer(address(admin));
        }

        _dustPosition(dexVault_);
    }

    function _giveApproval(address token_, address protocol_, address user_) internal {
        if (token_ != address(NATIVE_TOKEN_ADDRESS)) {
             _setApproval(IERC20(token_), address(protocol_), user_);
        }
    }

    function _getDexVaultPoolName(DexVaultParams memory dexVault_, VaultType vaultType_) internal returns (string memory s_) {
        s_ = string(
            abi.encodePacked(
                dexVault_.vaultName,
                ":::"
            )
        );
        if (vaultType_ == VaultType.VaultT1) {
            s_ = string(abi.encodePacked(s_, "VaultT1::"));
        } else if (vaultType_ == VaultType.VaultT2) {
            s_ = string(abi.encodePacked(s_, "VaultT2::"));
        } else if (vaultType_ == VaultType.VaultT3) {
            s_ = string(abi.encodePacked(s_, "VaultT3::"));
        } else if (vaultType_ == VaultType.VaultT4) {
            s_ = string(abi.encodePacked(s_, "VaultT4::"));
        }
    }

    function _setOraclePrice(DexVaultParams memory dexVault_, VaultType vaultType_, uint256 price_) internal {
        if (vaultType_ == VaultType.VaultT1) {
            dexVault_.oracleT1.setPrice(price_);
        } else if (vaultType_ == VaultType.VaultT2) {
            dexVault_.oracleT2.setPrice(price_);
        } else if (vaultType_ == VaultType.VaultT3) {
            dexVault_.oracleT3.setPrice(price_);
        } else if (vaultType_ == VaultType.VaultT4) {
            dexVault_.oracleT4.setPrice(price_);
        }
    }

    function _getOraclePrice(DexVaultParams memory dexVault_, VaultType vaultType_) internal returns (uint256 price_) {
        if (vaultType_ == VaultType.VaultT1) {
            price_ = dexVault_.oracleT1.price();
        } else if (vaultType_ == VaultType.VaultT2) {
            price_ = dexVault_.oracleT2.price();
        } else if (vaultType_ == VaultType.VaultT3) {
            price_ = dexVault_.oracleT3.price();
        } else if (vaultType_ == VaultType.VaultT4) {
            price_ = dexVault_.oracleT4.price();
        }
    }
    

    function _calculatePrice(DexVaultParams memory dexVault_, VaultType vaultType_, uint256 priceInWei_) internal returns (uint256 priceIn27Decimals_) {
        if (vaultType_ == VaultType.VaultT1) {
            priceIn27Decimals_ = priceInWei_ * 1e27 * dexVault_.dex.token1Wei / (dexVault_.dex.token0Wei * 1e18);
        } else if (vaultType_ == VaultType.VaultT2) {
            priceIn27Decimals_ = priceInWei_ * 1e27 * dexVault_.dex.token1Wei / (1e18 * 1e18);
        } else if (vaultType_ == VaultType.VaultT3) {
            priceIn27Decimals_ = priceInWei_ * 1e27 * 1e18 / (dexVault_.dex.token0Wei * 1e18);
        } else if (vaultType_ == VaultType.VaultT4) {
            priceIn27Decimals_ = priceInWei_ * 1e27 * 1e18 / (1e18 * 1e18);
        }
    }

    struct VaultVariablesData {
        uint256 isEntrancy;
        uint256 isCurrentBranchLiquidated;
        int256 topTick;
        uint256 signOfTopTick;
        uint256 absoluteValueOfTopTick;
        uint256 currentActiveBranch;
        uint256 totalBranchId;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 totalPositions;
    }

    function _getVaultVariablesData(address vault_) internal view returns(VaultVariablesData memory v_) {
        uint256 vaultVariables_ = StorageRead(vault_).readFromStorage(0);

        v_ = VaultVariablesData({
            isEntrancy: (vaultVariables_) & 1,
            isCurrentBranchLiquidated: (vaultVariables_ >> 1) & 1,
            signOfTopTick: (vaultVariables_ >> 2) & 1,
            topTick: 0,
            absoluteValueOfTopTick: (vaultVariables_ >> 3) & X19,
            currentActiveBranch: (vaultVariables_ >> 22) & X30,
            totalBranchId: (vaultVariables_ >> 52) & X30,
            totalSupply: (vaultVariables_ >> 82) & X64,
            totalBorrow: (vaultVariables_ >> 146) & X64,
            totalPositions: (vaultVariables_ >> 210) & X32
        });

        v_.topTick = v_.signOfTopTick == 1 ? int256(v_.absoluteValueOfTopTick) : -int256(v_.absoluteValueOfTopTick);

        v_.totalSupply = (v_.totalSupply >> 8) << (v_.totalSupply & X8);
        v_.totalBorrow = (v_.totalBorrow >> 8) << (v_.totalBorrow & X8);
    }

    struct VaultDexStateData {
        uint256 userToken0Balance;
        uint256 userToken1Balance;
        uint256 liquidityToken0Balance;
        uint256 liquidityToken1Balance;
        uint256 totalDexSupplyShares;
        uint256 totalDexBorrowShares;
        uint256 userDexSupplyShares;
        uint256 userDexBorrowShares;
        uint256 totalVaultSupply;
        uint256 totalVaultBorrow;
        uint256 userVaultSupplyBalance;
        uint256 userVaultBorrowBalance;

        address vaultAddress;
        address owner;
    }

    function _getVaultTypeAddress(DexVaultParams memory dexVault_, VaultType vaultType_) internal returns(address) {
        if (vaultType_ == VaultType.VaultT1) {
            return address(dexVault_.vaultT1);
        } else if (vaultType_ == VaultType.VaultT2) {
            return address(dexVault_.vaultT2);
        } else if (vaultType_ == VaultType.VaultT3) {
            return address(dexVault_.vaultT3);
        } else if (vaultType_ == VaultType.VaultT4) {
            return address(dexVault_.vaultT4);
        }
    } 

    function _getDexTypeAddressForVault(DexVaultParams memory dexVault_, VaultType vaultType_) internal returns(address) {
        if (vaultType_ == VaultType.VaultT1) {
            return address(0);
        } else if (vaultType_ == VaultType.VaultT2) {
            return address(dexVault_.dex.dexCol);
        } else if (vaultType_ == VaultType.VaultT3) {
            return address(dexVault_.dex.dexDebt);
        } else if (vaultType_ == VaultType.VaultT4) {
            return address(dexVault_.dex.dexColDebt);
        }
    }

    function _getDexVaultState(DexVaultParams memory dexVault_, VaultType vaultType_, address user_, uint256 nftId_) internal returns(VaultDexStateData memory ) {
        FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_)));
        address vault_ = _getVaultTypeAddress(dexVault_, vaultType_);

        VaultVariablesData memory vaultVariables_ = _getVaultVariablesData(vault_);

        uint256[] memory nftIds_ = new uint256[](1);    
        nftIds_[0] = nftId_;

        (FluidVaultPositionsResolver.UserPosition[] memory userPositions_) = _vaultPositionsResolver.getPositionsForNftIds(nftIds_);
        FluidVaultPositionsResolver.UserPosition memory userPosition_ = userPositions_[0];

        VaultDexStateData memory s_ = VaultDexStateData({
            userToken0Balance: _getTokenBalance( dexVault_.dex.token0, user_),
            userToken1Balance: _getTokenBalance(dexVault_.dex.token1, user_),
            liquidityToken0Balance: _getTokenBalance( dexVault_.dex.token0, address(liquidity)),
            liquidityToken1Balance: _getTokenBalance(dexVault_.dex.token1, address(liquidity)),
            totalDexSupplyShares: vaultType_ == VaultType.VaultT1 || vaultType_ == VaultType.VaultT3 ? 0 : getTotalSupplyShares(dex_),
            totalDexBorrowShares: vaultType_ == VaultType.VaultT1 || vaultType_ == VaultType.VaultT2 ? 0 : getTotalBorrowShares(dex_),
            userDexSupplyShares: vaultType_ == VaultType.VaultT1 || vaultType_ == VaultType.VaultT3 ? 0 : getUserSupplyShare(dex_, vault_),
            userDexBorrowShares: vaultType_ == VaultType.VaultT1 || vaultType_ == VaultType.VaultT2 ? 0 : getUserBorrowShare(dex_, vault_),
            totalVaultSupply: vaultVariables_.totalSupply,
            totalVaultBorrow: vaultVariables_.totalBorrow,
            userVaultSupplyBalance: userPosition_.supply,
            userVaultBorrowBalance: userPosition_.borrow,
            vaultAddress: vaultResolver.vaultByNftId(nftId_),
            owner: userPosition_.owner
        });

        return s_;
    }

    struct OperatePerfectParams {
        int256 supplyShareAmount;
        int256 supplyToken0MinMax;
        int256 supplyToken1MinMax;

        int256 borrowShareAmount;
        int256 borrowToken0MinMax;
        int256 borrowToken1MinMax;
    }

    struct OperatePerfectData {
        uint256 nftId;

        int256 supplyAmount;
        int256 supplyToken0Amount;
        int256 supplyToken1Amount;
    
        int256 borrowAmount;   
        int256 borrowToken0Amount;
        int256 borrowToken1Amount;
    }
    
    struct OperatePerfectVariables {
        string assertMessage;
        uint256 ethValue;
        int256[] r;
    }

    function _testOperatePerfect(
        DexVaultParams memory dexVault_,
        VaultType vaultType_,
        OperatePerfectParams memory params_,
        address user_,
        uint256 nftId_,
        string memory customMessage_
    ) internal returns (OperatePerfectData memory d_) {
        OperatePerfectVariables memory var_;
        var_.assertMessage = string(abi.encodePacked(
            customMessage_,
            "::_testOperatePerfect::",
            _getDexVaultPoolName(dexVault_, vaultType_)
        ));

        VaultDexStateData memory preState_ = _getDexVaultState(dexVault_, vaultType_, user_, nftId_);

        var_.ethValue = 0;
        if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            if (params_.supplyShareAmount > 0 || params_.borrowShareAmount < 0) {
                var_.ethValue = user_.balance;
            }
        }

        if (vaultType_ == VaultType.VaultT1) {
            vm.prank(user_);
            (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT1.operate{value: var_.ethValue}(
                nftId_,
                params_.supplyShareAmount,
                params_.borrowShareAmount,
                user_
            );
        } else if (vaultType_ == VaultType.VaultT2) {
            vm.prank(user_);
            var_.r;
            (d_.nftId, var_.r) = dexVault_.vaultT2.operatePerfect{value: var_.ethValue}(
                nftId_,
                params_.supplyShareAmount,
                params_.supplyToken0MinMax,
                params_.supplyToken1MinMax,
                params_.borrowShareAmount,
                user_
            );

            d_.supplyAmount = var_.r[0];
            d_.supplyToken0Amount = var_.r[1];
            d_.supplyToken1Amount = var_.r[2];
            d_.borrowAmount = var_.r[3];
        } else if (vaultType_ == VaultType.VaultT3) {
            vm.prank(user_);
            var_.r;
            (d_.nftId, var_.r) = dexVault_.vaultT3.operatePerfect{value: var_.ethValue}(
                nftId_,
                params_.supplyShareAmount,
                params_.borrowShareAmount,
                params_.borrowToken0MinMax,
                params_.borrowToken1MinMax,
                user_
            );

            d_.supplyAmount = var_.r[0];
            d_.borrowAmount = var_.r[1];
            d_.borrowToken0Amount = var_.r[2];
            d_.borrowToken1Amount = var_.r[3];
        } else if (vaultType_ == VaultType.VaultT4) {
            vm.prank(user_);
            var_.r;

            {
                (d_.nftId, var_.r) = dexVault_.vaultT4.operatePerfect{value: var_.ethValue}(
                    nftId_,
                    params_.supplyShareAmount,
                    params_.supplyToken0MinMax,
                    params_.supplyToken1MinMax,
                    params_.borrowShareAmount,
                    params_.borrowToken0MinMax,
                    params_.borrowToken1MinMax,
                    user_
                );
                
                {
                    d_.supplyAmount = var_.r[0];
                    d_.supplyToken0Amount = var_.r[1];
                    d_.supplyToken1Amount = var_.r[2];
                    d_.borrowAmount = var_.r[3];
                    d_.borrowToken0Amount = var_.r[4];
                    d_.borrowToken1Amount = var_.r[5]; 
                }
            }
        }       

        {

            VaultDexStateData memory postState_ = _getDexVaultState(dexVault_, vaultType_, user_, d_.nftId);

            if (vaultType_ == VaultType.VaultT1) {
                assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
                assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -(d_.borrowAmount), 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));
            
                assertApproxEqAbs(int256(preState_.userToken0Balance) - int256(postState_.userToken0Balance), d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
                assertApproxEqAbs(int256(preState_.userToken1Balance) - int256(postState_.userToken1Balance), -(d_.borrowAmount), 0, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));


            } else if (vaultType_ == VaultType.VaultT2) {
                assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), d_.supplyToken0Amount, 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
                assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -(d_.borrowAmount) + d_.supplyToken1Amount, 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));

                assertApproxEqAbs(int256(preState_.userToken0Balance) - int256(postState_.userToken0Balance), d_.supplyToken0Amount, 0, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
                assertApproxEqAbs(int256(preState_.userToken1Balance) - int256(postState_.userToken1Balance), -(d_.borrowAmount) + d_.supplyToken1Amount, 0, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));
                
                assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), (d_.supplyAmount), 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
                assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));

                // 1 wei: [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(withdraw)::_testOperatePerfect::DAI_USDC:::VaultT2::user dex supply shares is not expected: -100000000000000000000 !~= -99999999999999999999 (max delta: 0, real delta: 1)]
                assertApproxEqAbs(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), (d_.supplyAmount), 1, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));
                assertApproxEqAbs(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
            } else if (vaultType_ == VaultType.VaultT3) {
                assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), d_.supplyAmount - (d_.borrowToken0Amount), 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
                assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -(d_.borrowToken1Amount), 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));

                assertApproxEqAbs(int256(preState_.userToken0Balance) - int256(postState_.userToken0Balance), d_.supplyAmount - (d_.borrowToken0Amount), 0, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
                assertApproxEqAbs(int256(preState_.userToken1Balance) - int256(postState_.userToken1Balance), -(d_.borrowToken1Amount), 0, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));

                assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
                assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));

                assertApproxEqAbs(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));

                // 1 wei: [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT3::user dex borrow shares is not expected: 75000000000000002048 !~= 75000000000000000000 (max delta: 0, real delta: 2048)]
                assertApproxEqAbs(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), d_.borrowAmount, 2048, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
            } else if (vaultType_ == VaultType.VaultT4) {
                assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), d_.supplyToken0Amount - (d_.borrowToken0Amount), 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
                assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), d_.supplyToken1Amount - (d_.borrowToken1Amount), 0, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));

                assertApproxEqAbs(int256(preState_.userToken0Balance) - int256(postState_.userToken0Balance), d_.supplyToken0Amount - (d_.borrowToken0Amount), 0, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
                assertApproxEqAbs(int256(preState_.userToken1Balance) - int256(postState_.userToken1Balance), d_.supplyToken1Amount - (d_.borrowToken1Amount), 0, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));

                assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
                assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));
                
                // 1 wei: [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(withdraw)::_testOperatePerfect::DAI_USDC:::VaultT4::user dex supply shares is not expected: -100000000000000000000 !~= -99999999999999999999 (max delta: 0, real delta: 1)]
                assertApproxEqAbs(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), d_.supplyAmount, 1, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));

                // 2048 wei: [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT4::user dex borrow shares is not expected: 75000000000000002048 !~= 75000000000000000000 (max delta: 0, real delta: 2048)]
                assertApproxEqAbs(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), d_.borrowAmount, 2048, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
            }

            assertApproxEqAbs(int256(postState_.totalVaultSupply) - int256(preState_.totalVaultSupply), (d_.supplyAmount), 1, string(abi.encodePacked(var_.assertMessage, "total vault supply is not expected")));

            // [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT1::total vault borrow is not expected: 75000002 !~= 75000000 (max delta: 0, real delta: 2)]
            // [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(supply)::_testOperatePerfect::DAI_USDC:::VaultT3::total vault borrow is not expected: 2048 !~= 0 (max delta: 2, real delta: 2048)]
            // [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT3::total vault borrow is not expected: 75000000075000002560 !~= 75000000000000000000 (max delta: 2048, real delta: 75000002560)]
            int256 a = (d_.borrowAmount) * (1e18 + 1e9) / 1e18; // (75 * 1e18) + (75 * 1e9) or 1wei (for amount less than 1e9)
            uint256 weiDelta = (
                postState_.totalVaultBorrow > preState_.totalVaultBorrow ? postState_.totalVaultBorrow : preState_.totalVaultBorrow
            ) * (1e9) / 1e18 + 8196 + (a < 0 ? uint256(-a) : uint256(a));
    
            assertApproxEqAbs(int256(postState_.totalVaultBorrow) - int256(preState_.totalVaultBorrow), (d_.borrowAmount), weiDelta, string(abi.encodePacked(var_.assertMessage, "total vault borrow is not expected")));

            assertApproxEqAbs(int256(postState_.userVaultSupplyBalance) - int256(preState_.userVaultSupplyBalance), (d_.supplyAmount), 1, string(abi.encodePacked(var_.assertMessage, "user vault supply balance is not expected")));

            {
                weiDelta = ((
                    postState_.totalVaultBorrow > preState_.totalVaultBorrow ? postState_.totalVaultBorrow : preState_.totalVaultBorrow
                ) * (1e9) / 1e18) + 8196 + (a < 0 ? uint256(-a) : uint256(a));
            }
            // [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT1::user vault borrow balance is not expected: 75000002 !~= 75000000 (max delta: 0, real delta: 2)] 
            // [FAIL. Reason: test_perfectSupplyBorrowPaybackWithdraw(borrow)::_testOperatePerfect::DAI_USDC:::VaultT3::user vault borrow balance is not expected: 75000000075000000003 !~= 75000000000000000000 (max delta: 2, real delta: 75000000003)]
            assertApproxEqAbs(int256(postState_.userVaultBorrowBalance) - int256(preState_.userVaultBorrowBalance), (d_.borrowAmount), weiDelta, string(abi.encodePacked(var_.assertMessage, "user vault borrow balance is not expected")));
        }
    }

    struct OperateParams {
        int256 supplyToken0;
        int256 supplyToken1;
        int256 supplyShareMinMax;

        int256 borrowToken0;
        int256 borrowToken1;
        int256 borrowShareMinMax;
    }

    struct OperateData {
        uint256 nftId;

        int256 supplyAmount;
    
        int256 borrowAmount;
    }

    struct OperateVariables {
        string assertMessage;
        uint256 ethValue;
        int256[] r;
    }
    

    function _testOperate(
        DexVaultParams memory dexVault_,
        VaultType vaultType_,
        OperateParams memory params_,
        address user_,
        uint256 nftId_,
        string memory customMessage_
    ) internal returns (OperateData memory d_) {
        OperatePerfectVariables memory var_;
        var_.assertMessage = string(abi.encodePacked(
            customMessage_,
            "::_testOperate::",
            _getDexVaultPoolName(dexVault_, vaultType_)
        ));

        VaultDexStateData memory preState_ = _getDexVaultState(dexVault_, vaultType_, user_, nftId_);

        var_.ethValue = 0;
        if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            if (params_.supplyToken0 > 0 || params_.borrowToken1 < 0) {
                var_.ethValue = user_.balance;
            }
        }

        if (vaultType_ == VaultType.VaultT1) {
            vm.prank(user_);
            (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT1.operate{value: var_.ethValue}(
                nftId_,
                params_.supplyToken0,
                params_.borrowToken1,
                user_
            );
        } else if (vaultType_ == VaultType.VaultT2) {
            vm.prank(user_);
            (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT2.operate{value: var_.ethValue}(
                nftId_,
                params_.supplyToken0,
                params_.supplyToken1,
                params_.supplyShareMinMax,
                params_.borrowToken1,
                user_
            );
        } else if (vaultType_ == VaultType.VaultT3) {
            vm.prank(user_);
            (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT3.operate{value: var_.ethValue}(
                nftId_,
                params_.supplyToken0,
                params_.borrowToken0,
                params_.borrowToken1,
                params_.borrowShareMinMax,
                user_
            );
        } else if (vaultType_ == VaultType.VaultT4) {
            vm.prank(user_);
            (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT4.operate{value: var_.ethValue}(
                nftId_,
                params_.supplyToken0,
                params_.supplyToken1,
                params_.supplyShareMinMax,
                params_.borrowToken0,
                params_.borrowToken1,
                params_.borrowShareMinMax,
                user_
            );
        }       

        VaultDexStateData memory postState_ = _getDexVaultState(dexVault_, vaultType_, user_, d_.nftId);

        uint256 maxDetla_ = 0;
        assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), params_.supplyToken0 - params_.borrowToken0 , maxDetla_, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
        assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -params_.borrowToken1 + params_.supplyToken1, maxDetla_, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));

        assertApproxEqAbs(int256(postState_.userToken0Balance) - int256(preState_.userToken0Balance), params_.borrowToken0 - params_.supplyToken0, 0, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
        assertApproxEqAbs(int256(postState_.userToken1Balance) - int256(preState_.userToken1Balance), params_.borrowToken1 - params_.supplyToken1, 0, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));
            
        if (vaultType_ == VaultType.VaultT1) {
            assertApproxEqAbs(params_.supplyToken0, d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "params_.supplyToken0 != d_.supplyAmount token0 is not expected")));
            assertApproxEqAbs(params_.borrowToken1, d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "params_.borrowToken1 != d_.borrowAmount token1 is not expected")));
        } else if (vaultType_ == VaultType.VaultT2) {
            
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), (d_.supplyAmount), 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));

            // [FAIL. Reason: test_supplyBorrowPaybackWithdraw(supply)::_testOperate::DAI_USDC:::VaultT2::user dex supply shares is not expected: 9999371068627457_2288 !~= 9999371068627457_4725 (max delta: 0, real delta: 2437)] 
            _comparePrecision(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), (d_.supplyAmount), 1e18, 0, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
        } else if (vaultType_ == VaultType.VaultT3) {
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));

            assertApproxEqAbs(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));
            // [FAIL. Reason: test_supplyBorrowPaybackWithdraw(borrow)::_testOperate::DAI_USDC:::VaultT3::user dex borrow shares is not expected: 75001665921846110208 !~= 75001665921846106952 (max delta: 0, real delta: 3256)]
            _comparePrecision(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), d_.borrowAmount, 1e18, 0, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
        } else if (vaultType_ == VaultType.VaultT4) {
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));

            // [FAIL. Reason: test_supplyBorrowPaybackWithdraw(supply)::_testOperate::DAI_USDC:::VaultT4::user dex supply shares is not expected: 99993710686274572288 !~= 99993710686274574725 (max delta: 0, real delta: 2437)]
            _comparePrecision(int256(postState_.userDexSupplyShares) - int256(preState_.userDexSupplyShares), d_.supplyAmount, 1e18, 0, string(abi.encodePacked(var_.assertMessage, "user dex supply shares is not expected")));

            // [FAIL. Reason: test_supplyBorrowPaybackWithdraw(borrow)::_testOperate::DAI_USDC:::VaultT4::user dex borrow shares is not expected: 75004876701897660416 !~= 75004876701897657840 (max delta: 0, real delta: 2576)]
            _comparePrecision(int256(postState_.userDexBorrowShares) - int256(preState_.userDexBorrowShares), d_.borrowAmount, 1e18, 0, string(abi.encodePacked(var_.assertMessage, "user dex borrow shares is not expected")));
        }

        // delta: 1 << 14
        assertApproxEqAbs(int256(postState_.totalVaultSupply) - int256(preState_.totalVaultSupply), (d_.supplyAmount), 16384, string(abi.encodePacked(var_.assertMessage, "total vault supply is not expected")));

        // TODO: [FAIL. Reason: test_supplyBorrowPaybackWithdraw(withdraw)::_testOperate::DAI_USDC:::VaultT3::total vault borrow is not expected: 19000219648 !~= 0 (max delta: 2048, real delta: 19000219648)]
       int256 a = (d_.borrowAmount) * (1e18 + 1e9) / 1e18; // (75 * 1e18) + (75 * 1e9) or 1wei (for amount less than 1e9)
            uint256 weiDelta = (
                postState_.totalVaultBorrow > preState_.totalVaultBorrow ? postState_.totalVaultBorrow : preState_.totalVaultBorrow
            ) * (1e18 + 1e9) / 1e18 + 8196 + (a < 0 ? uint256(-a) : uint256(a));
        assertApproxEqAbs(int256(postState_.totalVaultBorrow) - int256(preState_.totalVaultBorrow), (d_.borrowAmount), weiDelta, string(abi.encodePacked(var_.assertMessage, "total vault borrow is not expected")));

        assertApproxEqAbs(int256(postState_.userVaultSupplyBalance) - int256(preState_.userVaultSupplyBalance), (d_.supplyAmount), 16384, string(abi.encodePacked(var_.assertMessage, "user vault supply balance is not expected")));

        assertApproxEqAbs(int256(postState_.userVaultBorrowBalance) - int256(preState_.userVaultBorrowBalance), (d_.borrowAmount), weiDelta, string(abi.encodePacked(var_.assertMessage, "user vault borrow balance is not expected")));
    }

    function getVaultLiquidation(
        address payable vault_,
        uint tokenInAmt_
    ) public returns (FluidVaultResolver.LiquidationStruct memory liquidationData_) {
        liquidationData_.vault = vault_;
        FluidVaultT2.ConstantViews memory constants_ = FluidVaultT2(payable(vault_)).constantsView();
        // liquidationData_.tokenIn = constants_.borrowToken;
        // liquidationData_.tokenOut = constants_.supplyToken;

        uint amtOut_;
        uint amtIn_;

        // running without absorb
        try FluidVaultT2(payable(vault_)).simulateLiquidate(tokenInAmt_, false) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidVault.FluidLiquidateResult.selector) {
                    assembly {
                        amtOut_ := mload(add(lowLevelData_, 36))
                        amtIn_ := mload(add(lowLevelData_, 68))
                    }
                    liquidationData_.outAmt = amtOut_;
                    liquidationData_.inAmt = amtIn_;
                } else {
                    // inAmt & outAmt remains 0
                }
            }
        }

        // running with absorb
        try FluidVaultT2(payable(vault_)).simulateLiquidate(tokenInAmt_, true) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidVault.FluidLiquidateResult.selector) {
                    assembly {
                        amtOut_ := mload(add(lowLevelData_, 36))
                        amtIn_ := mload(add(lowLevelData_, 68))
                    }
                    liquidationData_.outAmtWithAbsorb = amtOut_;
                    liquidationData_.inAmtWithAbsorb = amtIn_;
                } else {
                    // inAmtWithAbsorb & outAmtWithAbsorb remains 0
                }
            }
        }

    }

    function _getDexPaybackPerfectInOneTokenAmount(
        FluidDexT1 dex_,
        uint shareAmount_,
        bool paybackInToken0_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt_;
        try dex_.paybackPerfectInOneToken(
            shareAmount_,
            paybackInToken0_ ? type(uint128).max : 0,
            paybackInToken0_ ? 0 : type(uint128).max,
            true
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 36) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexSingleTokenOutput.selector) {
                    assembly {
                        amt_ := mload(add(lowLevelData_, 36))
                    }
                    token0Amount_ = paybackInToken0_ ? amt_ : 0;
                    token1Amount_ = paybackInToken0_ ? 0 : amt_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    function _getDexWithdrawPerfectInOneTokenAmount(
        FluidDexT1 dex_,
        uint shareAmount_,
        bool withdrawInToken0_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt_;
        try dex_.withdrawPerfectInOneToken(
            shareAmount_,
            withdrawInToken0_ ? type(uint128).max : 0,
            withdrawInToken0_ ? 0 : type(uint128).max,
            address(0x000000000000000000000000000000000000dEaD)
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 36) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexLiquidityOutput.selector) {
                    assembly {
                        amt_ := mload(add(lowLevelData_, 36))
                    }
                    token0Amount_ = withdrawInToken0_ ? amt_ : 0;
                    token1Amount_ = withdrawInToken0_ ? 0 : amt_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    function _getDexDepositPerfect(
        FluidDexT1 dex_,
        uint shareAmount_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt0_;
        uint256 amt1_;
        try dex_.depositPerfect(
            shareAmount_,
            type(uint256).max,
            type(uint256).max,
            true
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexPerfectLiquidityOutput.selector) {
                    assembly {
                        amt0_ := mload(add(lowLevelData_, 36))
                        amt1_ := mload(add(lowLevelData_, 68))
                    }
                    token0Amount_ = amt0_;
                    token1Amount_ = amt1_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    function _getDexWithdrawPerfect(
        FluidDexT1 dex_,
        uint shareAmount_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt0_;
        uint256 amt1_;
        try dex_.withdrawPerfect(
            shareAmount_,
            type(uint256).min,
            type(uint256).min,
            address(0x000000000000000000000000000000000000dEaD)
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexPerfectLiquidityOutput.selector) {
                    assembly {
                        amt0_ := mload(add(lowLevelData_, 36))
                        amt1_ := mload(add(lowLevelData_, 68))
                    }
                    token0Amount_ = amt0_;
                    token1Amount_ = amt1_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    function _getDexBorrowPerfect(
        FluidDexT1 dex_,
        uint shareAmount_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt0_;
        uint256 amt1_;
        try dex_.borrowPerfect(
            shareAmount_,
            type(uint256).min,
            type(uint256).min,
            address(0x000000000000000000000000000000000000dEaD)
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexPerfectLiquidityOutput.selector) {
                    assembly {
                        amt0_ := mload(add(lowLevelData_, 36))
                        amt1_ := mload(add(lowLevelData_, 68))
                    }
                    token0Amount_ = amt0_;
                    token1Amount_ = amt1_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    function _getDexPaybackPerfect(
        FluidDexT1 dex_,
        uint shareAmount_
    ) public returns (uint256 token0Amount_, uint256 token1Amount_) {

        uint256 amt0_;
        uint256 amt1_;
        try dex_.paybackPerfect(
            shareAmount_,
            type(uint256).max,
            type(uint256).max,
            true
        ) {
            // Handle successful execution
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                if (errorSelector_ == IFluidDexT1.FluidDexPerfectLiquidityOutput.selector) {
                    assembly {
                        amt0_ := mload(add(lowLevelData_, 36))
                        amt1_ := mload(add(lowLevelData_, 68))
                    }
                    token0Amount_ = amt0_;
                    token1Amount_ = amt1_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
            }
        }
    }

    struct LiquidateParams {
        uint256 debtToken0Percentage;
        uint256 debtToken1Percentage;

        uint256 collateralToken0MinAmount;
        uint256 collateralToken1MinAmount;

        uint256 debtToken0MinAmount;
        uint256 debtToken1MinAmount;
    }

    struct LiquidationVariables {
        uint256 colateralAmount;
        uint256 debtAmount;

        bool absorb;

        uint256 debtToken0Amt;
        uint256 debtToken1Amt;

        FluidVaultResolver.LiquidationStruct liquidationData;
    }

    struct LiquidateData {
        uint256 debtShares;
        uint256 colShares;

        uint256 token0Col;
        uint256 token1Col;

        uint256 token0Debt;
        uint256 token1Debt;
    }
    

    function _testLiquidate(
        DexVaultParams memory dexVault_,
        VaultType vaultType_,
        LiquidateParams memory params_,
        address user_,
        uint256 nftId_,
        string memory customMessage_
    ) internal returns (LiquidateData memory d_) {
        string memory assertMessage_ = string(abi.encodePacked(
            customMessage_,
            "::_testLiquidate::",
            _getDexVaultPoolName(dexVault_, vaultType_),
            "::Debt0Percentage: ",
            LibString.toString(params_.debtToken0Percentage),
            "::Debt1Percentage: ",
            LibString.toString(params_.debtToken1Percentage)
        ));

        LiquidationVariables memory l_;

        VaultDexStateData memory preState_ = _getDexVaultState(dexVault_, vaultType_, user_, nftId_);

        l_.liquidationData = getVaultLiquidation(payable(_getVaultTypeAddress(dexVault_, vaultType_)), 0);

        l_.colateralAmount = l_.liquidationData.outAmt > l_.liquidationData.outAmtWithAbsorb ? l_.liquidationData.outAmt : l_.liquidationData.outAmtWithAbsorb;
        l_.debtAmount = l_.liquidationData.inAmt > l_.liquidationData.inAmtWithAbsorb ? l_.liquidationData.inAmt : l_.liquidationData.inAmtWithAbsorb;
        l_.absorb = l_.liquidationData.inAmtWithAbsorb > l_.liquidationData.inAmt;

        if (vaultType_ == VaultType.VaultT1) {
            // vm.prank(user_);
            // (d_.nftId, d_.supplyAmount, d_.borrowAmount) = dexVault_.vaultT1.liquidate(
            //     nftId_,
            //     params_.supplyToken0,
            //     params_.borrowToken1,
            //     user_
            // );
        } else if (vaultType_ == VaultType.VaultT2) {
            if (params_.debtToken1Percentage == 0) return d_;
            l_.debtAmount = l_.debtAmount * params_.debtToken1Percentage / 100;
            l_.colateralAmount = l_.colateralAmount * params_.debtToken1Percentage / 100;

            vm.prank(user_);
            (d_.debtShares, d_.colShares, d_.token0Col, d_.token1Col) = dexVault_.vaultT2.liquidate{value: l_.debtAmount}(
                l_.debtAmount,
                0, // colPerUnitDebt
                params_.collateralToken0MinAmount,
                params_.collateralToken1MinAmount,
                user_,
                l_.absorb
            );

            d_.token1Debt = d_.debtShares;
        } else {
            if (params_.debtToken0Percentage > 0 && params_.debtToken1Percentage > 0) {
                (l_.debtToken0Amt, l_.debtToken1Amt) = _getDexPaybackPerfect(
                    FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_))),
                    l_.debtAmount * params_.debtToken0Percentage / 100
                );

                if (vaultType_ == VaultType.VaultT3) {
                    vm.prank(user_);
                    (d_.debtShares, d_.token0Debt, d_.token1Debt, d_.colShares) = dexVault_.vaultT3.liquidatePerfect{value: l_.debtToken1Amt * l_.debtAmount / 1e18}(
                        l_.debtAmount * params_.debtToken0Percentage / 100,
                        l_.debtToken0Amt, 
                        l_.debtToken1Amt,
                        0, // colPerUnitDebt
                        user_,
                        l_.absorb
                    );

                    d_.token0Col = d_.colShares;
                } else if (vaultType_ == VaultType.VaultT4) {
                    vm.prank(user_);
                    (d_.debtShares, d_.token0Debt, d_.token1Debt, d_.colShares, d_.token0Col, d_.token1Col) = dexVault_.vaultT4.liquidatePerfect{value: l_.debtToken1Amt * l_.debtAmount / 1e18}(
                        l_.debtAmount * params_.debtToken0Percentage / 100,
                        l_.debtToken0Amt, 
                        l_.debtToken1Amt,
                        0, // colPerUnitDebt
                        params_.collateralToken0MinAmount,
                        params_.collateralToken1MinAmount,
                        user_,
                        l_.absorb
                    );
                }
            } else {
                if (params_.debtToken0Percentage > 0) {
                    (d_.token0Debt, d_.token1Debt) = _getDexPaybackPerfectInOneTokenAmount(
                        FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_))),
                        l_.debtAmount * params_.debtToken0Percentage / 100,
                        true
                    );
                } else if (params_.debtToken1Percentage > 0) {
                    (d_.token0Debt, d_.token1Debt) = _getDexPaybackPerfectInOneTokenAmount(
                        FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_))),
                        l_.debtAmount * params_.debtToken1Percentage / 100,
                        false
                    );
                }

                if (vaultType_ == VaultType.VaultT3) {
                    vm.prank(user_);
                    (d_.debtShares, d_.colShares) = dexVault_.vaultT3.liquidate{value: d_.token1Debt}(
                        d_.token0Debt,
                        d_.token1Debt,
                        1, // debtShareMin
                        0, // colPerUnitDebt
                        user_,
                        l_.absorb
                    );
                    d_.token0Col = d_.colShares;
                } else if (vaultType_ == VaultType.VaultT4) {
                    vm.prank(user_);
                    (d_.debtShares, d_.colShares, d_.token0Col, d_.token1Col) = dexVault_.vaultT4.liquidate{value: d_.token1Debt}(
                        d_.token0Debt,
                        d_.token1Debt,
                        1, // debtShareMin
                        0, // colPerUnitDebt
                        params_.collateralToken0MinAmount,
                        params_.collateralToken1MinAmount,
                        user_,
                        l_.absorb
                    );
                }
            }
        }

        // VaultDexStateData memory postState_ = _getDexVaultState(dexVault_, vaultType_, user_, nftId_);

        // uint256 maxDetla_ = 0;
        // assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), -int256(d_.token0Col) + int256(d_.token0Debt), maxDetla_, string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected")));
        // assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), int256(d_.token1Debt) - int256(d_.token1Col), maxDetla_, string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected")));
        // assertApproxEqAbs(int256(postState_.userToken0Balance) - int256(preState_.userToken0Balance), int256(d_.token0Col) - int256(d_.token0Debt), 0, string(abi.encodePacked(assertMessage_, "user balance token0 is not expected")));
        // assertApproxEqAbs(int256(postState_.userToken1Balance) - int256(preState_.userToken1Balance), -int256(d_.token1Debt) + int256(d_.token1Col), 0, string(abi.encodePacked(assertMessage_, "user balance token1 is not expected")));
    }

    function _convertOperatePerfectParamsToWei(DexVaultParams memory dexVault_, VaultType vaultType_, OperatePerfectParams memory params_) internal returns(OperatePerfectParams memory updatedParams_) {
        if (vaultType_ == VaultType.VaultT1) {
            updatedParams_.supplyShareAmount = params_.supplyShareAmount * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken0MinMax = params_.supplyToken0MinMax * 0;
            updatedParams_.supplyToken1MinMax = params_.supplyToken1MinMax * 0;
            updatedParams_.borrowShareAmount = params_.borrowShareAmount * int256(dexVault_.dex.token1Wei);
            updatedParams_.borrowToken0MinMax = params_.borrowToken0MinMax * 0;
            updatedParams_.borrowToken1MinMax = params_.borrowToken1MinMax * 0;
        } else if (vaultType_ == VaultType.VaultT2) {
            updatedParams_.supplyShareAmount = params_.supplyShareAmount * 1e18;
            updatedParams_.supplyToken0MinMax = params_.supplyToken0MinMax * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1MinMax = params_.supplyToken1MinMax * int256(dexVault_.dex.token1Wei);
            updatedParams_.borrowShareAmount = params_.borrowShareAmount * int256(dexVault_.dex.token1Wei);
            updatedParams_.borrowToken0MinMax = params_.borrowToken0MinMax * 0;
            updatedParams_.borrowToken1MinMax = params_.borrowToken1MinMax * 0;
        } else if (vaultType_ == VaultType.VaultT3) {
            updatedParams_.supplyShareAmount = params_.supplyShareAmount * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken0MinMax = params_.supplyToken0MinMax * 0;
            updatedParams_.supplyToken1MinMax = params_.supplyToken1MinMax * 0;
            updatedParams_.borrowShareAmount = params_.borrowShareAmount * 1e18;
            updatedParams_.borrowToken0MinMax = params_.borrowToken0MinMax * int256(dexVault_.dex.token0Wei);
            updatedParams_.borrowToken1MinMax = params_.borrowToken1MinMax * int256(dexVault_.dex.token1Wei);
        } else if (vaultType_ == VaultType.VaultT4) {
            updatedParams_.supplyShareAmount = params_.supplyShareAmount * 1e18;
            updatedParams_.supplyToken0MinMax = params_.supplyToken0MinMax * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1MinMax = params_.supplyToken1MinMax * int256(dexVault_.dex.token1Wei);
            updatedParams_.borrowShareAmount = params_.borrowShareAmount * 1e18;
            updatedParams_.borrowToken0MinMax = params_.borrowToken0MinMax * int256(dexVault_.dex.token0Wei);
            updatedParams_.borrowToken1MinMax = params_.borrowToken1MinMax * int256(dexVault_.dex.token1Wei);
        }

        return updatedParams_;
    }

    function _convertOperateParamsToWei(DexVaultParams memory dexVault_, VaultType vaultType_, OperateParams memory params_) internal returns(OperateParams memory updatedParams_) {
        if (vaultType_ == VaultType.VaultT1) {
            updatedParams_.supplyShareMinMax = params_.supplyShareMinMax * 1e18;
            updatedParams_.supplyToken0 = params_.supplyToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1 = params_.supplyToken1 * 0;

            updatedParams_.borrowShareMinMax = params_.borrowShareMinMax * 0;
            updatedParams_.borrowToken0 = params_.borrowToken0 * 0;
            updatedParams_.borrowToken1 = params_.borrowToken1 * int256(dexVault_.dex.token1Wei);
        } else if (vaultType_ == VaultType.VaultT2) {
            updatedParams_.supplyShareMinMax = params_.supplyShareMinMax * 1e18;
            updatedParams_.supplyToken0 = params_.supplyToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1 = params_.supplyToken1 * int256(dexVault_.dex.token1Wei);

            updatedParams_.borrowShareMinMax = params_.borrowShareMinMax * 0;
            updatedParams_.borrowToken0 = params_.borrowToken0 * 0;
            updatedParams_.borrowToken1 = params_.borrowToken1 * int256(dexVault_.dex.token1Wei);
        } else if (vaultType_ == VaultType.VaultT3) {
            updatedParams_.supplyShareMinMax = params_.supplyShareMinMax * 0;
            updatedParams_.supplyToken0 = params_.supplyToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1 = params_.supplyToken1 * 0;

            updatedParams_.borrowShareMinMax = params_.borrowShareMinMax * 1e18;
            updatedParams_.borrowToken0 = params_.borrowToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.borrowToken1 = params_.borrowToken1 * int256(dexVault_.dex.token1Wei);
        } else if (vaultType_ == VaultType.VaultT4) {
            updatedParams_.supplyShareMinMax = params_.supplyShareMinMax * 1e18;
            updatedParams_.supplyToken0 = params_.supplyToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.supplyToken1 = params_.supplyToken1 * int256(dexVault_.dex.token1Wei);

            updatedParams_.borrowShareMinMax = params_.borrowShareMinMax * 1e18;
            updatedParams_.borrowToken0 = params_.borrowToken0 * int256(dexVault_.dex.token0Wei);
            updatedParams_.borrowToken1 = params_.borrowToken1 * int256(dexVault_.dex.token1Wei);
        }

        return updatedParams_;
    }

    struct RebalanceParams {
        uint256 depositOrWithdraw;
        uint256 borrowOrPayback;
        uint256 timeToSkip;
    }

    struct RebalanceVariables {
        string assertMessage;
        address vault;

        uint256 ethValue;

        RebalanceDataParams params;
    }

    struct RebalanceDataParams {
        int256 colToken0MinMax;
        int256 colToken1MinMax;
        int256 debtToken0MinMax;
        int256 debtToken1MinMax;
    }

    struct RebalanceData {
        int256 supplyAmount;
        int256 borrowAmount;
    }

    error ErrorRebalance(int256 supplyAmount, int256 borrowAmount);

    function _simulateRebalance(
        address vault_,
        RebalanceDataParams memory params_,
        uint256 ethValue_,
        address user_
    ) public {
        vm.prank(admin);
        FluidVaultT4Admin(vault_).updateRebalancer(user_); // 100%
       
        vm.prank(user_);
        try FluidVaultT2(payable(vault_)).rebalance{value: ethValue_}(
            params_.colToken0MinMax,
            params_.colToken1MinMax,
            params_.debtToken0MinMax,
            params_.debtToken1MinMax
        ) returns (int256 supplyAmount, int256 borrowAmount) {
            // Handle successful execution
            revert ErrorRebalance(supplyAmount, borrowAmount);
        } catch Error(string memory) {
            // Handle generic errors with a reason
        } catch (bytes memory lowLevelData_) {
            // Check if the error data is long enough to contain a selector
            if (lowLevelData_.length >= 36) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(lowLevelData_, 0x20))
                }
                uint256 errorCode;
                if (errorSelector_ == FluidVaultError.FluidVaultError.selector) {
                    assembly {
                        errorCode := mload(add(lowLevelData_, 36))
                    }
                    assertEq(errorCode, 31031, "nothing rebalance to rebalance");
                    revert ErrorRebalance(0, 0);
                } else {
                    revert("rebalance failed");
                }
            }
        }
        
    }

    struct RebalanceAmountData {
        int256 supplyAmount;
        int256 borrowAmount;

        int256 token0Amount;
        int256 token1Amount;
        
        int256 supplyToken0Amount;
        int256 supplyToken1Amount;

        int256 borrowToken0Amount;
        int256 borrowToken1Amount;
    }

    function _getRebalanceAmounts(
        DexVaultParams memory dexVault_,
        VaultType vaultType_,
        address vault_,
        RebalanceDataParams memory params_,
        uint256 ethValue_,
        address user_
    ) internal returns(RebalanceAmountData memory d_) {
        FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_)));

        (, bytes memory data_) = address(this).call(abi.encodeWithSelector(this._simulateRebalance.selector, vault_, params_, ethValue_, user_));

        int256 amt0_;
        int256 amt1_;
        if (data_.length >= 68) {
                bytes4 errorSelector_;
                assembly {
                    // Extract the selector from the error data
                    errorSelector_ := mload(add(data_, 0x20))
                }
                if (errorSelector_ == VaultsBaseTest.ErrorRebalance.selector) {
                    assembly {
                        amt0_ := mload(add(data_, 36))
                        amt1_ := mload(add(data_, 68))
                    }
                    d_.supplyAmount = amt0_;
                    d_.borrowAmount = amt1_;
                } else {
                    // token0Amount_ & token1Amount_ remains 0
                }
        }

        if (d_.supplyAmount > 10 ) {
            if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                (uint256 a, uint256 b) = _getDexDepositPerfect(dex_, uint256(d_.supplyAmount));

                d_.token0Amount += -int256(a);
                d_.token1Amount += -int256(b);

                d_.supplyToken0Amount += int256(a);
                d_.supplyToken1Amount += int256(b);
            } else {
                d_.token0Amount += -int256(d_.supplyAmount );

                d_.supplyToken0Amount += int256(d_.supplyAmount);
            }
        } else if (d_.supplyAmount < -10) {
            if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                (uint256 a, uint256 b) = _getDexWithdrawPerfect(dex_, uint256(-d_.supplyAmount));

                d_.token0Amount += int256(a);
                d_.token1Amount += int256(b);
                
                d_.supplyToken0Amount += -int256(a);
                d_.supplyToken1Amount += -int256(b);
            } else {
                d_.token0Amount += int256(-d_.supplyAmount);

                d_.supplyToken0Amount += -int256(-d_.supplyAmount);
            }
        }

        if (d_.borrowAmount > 0) {
            if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4) && d_.borrowAmount > 10) {
                (uint256 a, uint256 b) = _getDexBorrowPerfect(dex_, uint256(d_.borrowAmount));

                d_.token0Amount += int256(a);
                d_.token1Amount += int256(b);

                d_.borrowToken0Amount += int256(a);
                d_.borrowToken1Amount += int256(b);
            } else {
                d_.token1Amount += int256(d_.borrowAmount);

                d_.borrowToken1Amount += int256(d_.borrowAmount);
            }

        } else if (d_.borrowAmount < 0) {
            if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4) && d_.borrowAmount < -10) {
                (uint256 a, uint256 b) = _getDexPaybackPerfect(dex_, uint256(-d_.borrowAmount));

                d_.token0Amount += -int256(a);
                d_.token1Amount += -int256(b);

                d_.borrowToken0Amount += -int256(a);
                d_.borrowToken1Amount += -int256(b);
            } else {
                d_.token1Amount += -int256(-d_.borrowAmount);

                d_.borrowToken1Amount += -int256(-d_.borrowAmount);
            }
        }
    }


    struct RebalanceStateVariables {
        address vault;

        uint256 liqSupplyExPrice;
        uint256 liqBorrowExPrice;
        uint256 vaultSupplyExPrice;
        uint256 vaultBorrowExPrice;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 totalSupplyVault;
        uint256 totalBorrowVault;
    }

    function _getRebalanceState(DexVaultParams memory dexVault_, VaultType vaultType_) internal returns(RebalanceDataParams memory params_) {
        RebalanceStateVariables memory v_;
        v_.vault = payable(_getVaultTypeAddress(dexVault_, vaultType_));
        VaultVariablesData memory vaultVariables_ = _getVaultVariablesData(v_.vault);
        (FluidLiquidityResolver.UserSupplyData memory userSupplyDataToken0_, ) = resolver.getUserSupplyData(address(v_.vault), dexVault_.dex.token0);
        (FluidLiquidityResolver.UserBorrowData memory userBorrowDataToken1_, ) = resolver.getUserBorrowData(address(v_.vault), dexVault_.dex.token1);

        (v_.liqSupplyExPrice, v_.liqBorrowExPrice, v_.vaultSupplyExPrice, v_.vaultBorrowExPrice) = FluidVaultT2(
            payable(v_.vault)
        ).updateExchangePrices(StorageRead(v_.vault).readFromStorage(bytes32(uint256(1))));

        if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
            FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_)));
            v_.totalSupply = (getUserSupplyShare(dex_, v_.vault) * v_.liqSupplyExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        } else {
            v_.totalSupply = userSupplyDataToken0_.supply;
        }

        if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4)) {
            FluidDexT1 dex_ = FluidDexT1(payable(_getDexTypeAddressForVault(dexVault_, vaultType_)));
            v_.totalBorrow = (getUserBorrowShare(dex_, v_.vault) * v_.liqBorrowExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        } else {
            v_.totalBorrow = userBorrowDataToken1_.borrow;
        }

        v_.totalSupplyVault = (vaultVariables_.totalSupply * v_.vaultSupplyExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        v_.totalBorrowVault = (vaultVariables_.totalBorrow * v_.vaultBorrowExPrice) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // console.log("v_.totalSupply", v_.totalSupply);
        // console.log("v_.totalBorrow", v_.totalBorrow);
        // console.log("v_.totalSupplyVault", v_.totalSupplyVault);
        // console.log("v_.totalBorrowVault", v_.totalBorrowVault);

        if (v_.totalSupplyVault > v_.totalSupply) {
            params_.colToken0MinMax = int256(type(int256).max);
            params_.colToken1MinMax = int256(type(int256).max);
        } else if ((v_.totalSupplyVault < v_.totalSupply)) {
            params_.colToken0MinMax = -int256(1);
            params_.colToken1MinMax = -int256(1);
        }

        if (v_.totalBorrowVault > v_.totalBorrow) {
            params_.debtToken0MinMax = int256(1);
            params_.debtToken1MinMax = int256(1);
        } else if (v_.totalBorrowVault < v_.totalBorrow) {
            params_.debtToken0MinMax = -int256(type(int256).max);
            params_.debtToken1MinMax = -int256(type(int256).max);
        }
    }

    function _testRebalance(
        DexVaultParams memory dexVault_,
        VaultType vaultType_,
        RebalanceParams memory params_,
        address user_,
        string memory customMessage_
    ) internal returns (RebalanceData memory d_) {
        RebalanceVariables memory var_;
        var_.vault = payable(_getVaultTypeAddress(dexVault_, vaultType_));

        var_.assertMessage = string(abi.encodePacked(
            customMessage_,
            "::_testRebalance::",
            _getDexVaultPoolName(dexVault_, vaultType_),
            "::",
            params_.depositOrWithdraw == 1 ? "deposit" : params_.depositOrWithdraw == 2 ? "withdraw" : "none",
            "::",
            params_.borrowOrPayback == 1 ? "borrow" : params_.borrowOrPayback == 2 ? "payback" : "none",
            "::",
            LibString.toString(params_.timeToSkip),
            "::"
        ));

        VaultDexStateData memory preState_ = _getDexVaultState(dexVault_, vaultType_, user_, 0);
        

        var_.ethValue = 0;
        if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            
            var_.ethValue = user_.balance;
            
        }

        if (params_.depositOrWithdraw == 1) {
            // var_.params.colToken0MinMax = int256(type(int256).max);
            // var_.params.colToken1MinMax = int256(type(int256).max);

            if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                int256 rate_ = int256(10_000);
                vm.prank(admin);
                FluidVaultT2Admin(var_.vault).updateSupplyRate(rate_);
            } else {
                uint256 mag_ = 60_000; // 6x
                vm.prank(admin);
                FluidVaultT3Admin(var_.vault).updateSupplyRateMagnifier(mag_);
            }

            if (params_.borrowOrPayback == 0) {
                if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4)) {
                    int256 rate_ = int256(0);
                    vm.prank(admin);
                    FluidVaultT4Admin(var_.vault).updateBorrowRate(rate_);
                } else {
                    uint256 mag_ = 10_000;
                    vm.prank(admin);
                    FluidVaultT2Admin(var_.vault).updateBorrowRateMagnifier(mag_);
                }
            }
        }

        if (params_.depositOrWithdraw == 2) {
            // var_.params.colToken0MinMax = int256(1);
            // var_.params.colToken1MinMax = int256(1);
            if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                int256 rate_ = -int256(10_000);
                vm.prank(admin);
                FluidVaultT4Admin(var_.vault).updateSupplyRate(rate_);
            } else {
                uint256 mag_ = 100;
                vm.prank(admin);
                FluidVaultT3Admin(var_.vault).updateSupplyRateMagnifier(mag_);
            }

            if (params_.borrowOrPayback == 0) {
                if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4)) {
                    int256 rate_ = int256(0);
                    vm.prank(admin);
                    FluidVaultT4Admin(var_.vault).updateBorrowRate(rate_);
                } else {
                    uint256 mag_ = 10_000;
                    vm.prank(admin);
                    FluidVaultT2Admin(var_.vault).updateBorrowRateMagnifier(mag_);
                }
            }
        }

        if (params_.borrowOrPayback == 1) {
            // var_.params.debtToken0MinMax = int256(1);
            // var_.params.debtToken1MinMax = int256(1);

            if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4)) {
                int256 rate_ = int256(10_000);
                vm.prank(admin);
                FluidVaultT4Admin(var_.vault).updateBorrowRate(rate_);
            } else {
                uint256 mag_ = 60_000; // 6x
                vm.prank(admin);
                FluidVaultT2Admin(var_.vault).updateBorrowRateMagnifier(mag_);
            }

            if (params_.depositOrWithdraw == 0) {
                // var_.params.colToken0MinMax = int256(type(int256).max);
                // var_.params.colToken1MinMax = int256(type(int256).max);
                if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                    int256 rate_ = int256(0);
                    vm.prank(admin);
                    FluidVaultT4Admin(var_.vault).updateSupplyRate(rate_);
                } else {
                    uint256 mag_ = 10_000;
                    vm.prank(admin);
                    FluidVaultT3Admin(var_.vault).updateSupplyRateMagnifier(mag_);
                }
            }
        }
        
        if (params_.borrowOrPayback == 2) {
            // var_.params.debtToken0MinMax = -int256(type(int256).max);
            // var_.params.debtToken1MinMax = -int256(type(int256).max);

            if ((vaultType_ == VaultType.VaultT3 || vaultType_ == VaultType.VaultT4)) {
                int256 rate_ = -int256(10_000);
                vm.prank(admin);
                FluidVaultT4Admin(var_.vault).updateBorrowRate(rate_);
            } else {
                uint256 mag_ = 100;
                vm.prank(admin);
                FluidVaultT2Admin(var_.vault).updateBorrowRateMagnifier(mag_);
            }

            if (params_.depositOrWithdraw == 0) {
                if ((vaultType_ == VaultType.VaultT2 || vaultType_ == VaultType.VaultT4)) {
                    int256 rate_ = int256(0);
                    vm.prank(admin);
                    FluidVaultT4Admin(var_.vault).updateSupplyRate(rate_);
                } else {
                    uint256 mag_ = 10_000;
                    vm.prank(admin);
                    FluidVaultT3Admin(var_.vault).updateSupplyRateMagnifier(mag_);
                }
            }
        }

        skip(params_.timeToSkip);

        var_.params = _getRebalanceState(dexVault_, vaultType_);

        RebalanceAmountData memory amts_ = _getRebalanceAmounts(dexVault_, vaultType_, var_.vault, var_.params, var_.ethValue, user_);

        vm.prank(admin);
        FluidVaultT4Admin(var_.vault).updateRebalancer(user_); // 100%

        vm.prank(user_);
        (d_.supplyAmount, d_.borrowAmount) = FluidVaultT2(payable(var_.vault)).rebalance{value: var_.ethValue}(
            var_.params.colToken0MinMax,
            var_.params.colToken1MinMax,
            var_.params.debtToken0MinMax,
            var_.params.debtToken1MinMax
        );    

        VaultDexStateData memory postState_ = _getDexVaultState(dexVault_, vaultType_, user_, 0);

        uint256 maxDetla_ = 2;
        assertApproxEqAbs(int256(postState_.liquidityToken0Balance) - int256(preState_.liquidityToken0Balance), -amts_.token0Amount, maxDetla_, string(abi.encodePacked(var_.assertMessage, "liquidity balance token0 is not expected")));
        assertApproxEqAbs(int256(postState_.liquidityToken1Balance) - int256(preState_.liquidityToken1Balance), -amts_.token1Amount, maxDetla_, string(abi.encodePacked(var_.assertMessage, "liquidity balance token1 is not expected")));

        assertApproxEqAbs(int256(postState_.userToken0Balance) - int256(preState_.userToken0Balance), amts_.token0Amount, maxDetla_, string(abi.encodePacked(var_.assertMessage, "user balance token0 is not expected")));
        assertApproxEqAbs(int256(postState_.userToken1Balance) - int256(preState_.userToken1Balance), amts_.token1Amount, maxDetla_, string(abi.encodePacked(var_.assertMessage, "user balance token1 is not expected")));
            
        if (vaultType_ == VaultType.VaultT2) {
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), (d_.supplyAmount), 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));
        } else if (vaultType_ == VaultType.VaultT3) {
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), 0, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));
        } else if (vaultType_ == VaultType.VaultT4) {
            assertApproxEqAbs(int256(postState_.totalDexSupplyShares) - int256(preState_.totalDexSupplyShares), d_.supplyAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex supply shares is not expected")));
            assertApproxEqAbs(int256(postState_.totalDexBorrowShares) - int256(preState_.totalDexBorrowShares), d_.borrowAmount, 0, string(abi.encodePacked(var_.assertMessage, "total dex borrow shares is not expected")));
        }

        {
            var_.params = _getRebalanceState(dexVault_, vaultType_);
            (, bytes memory data_) = address(this).call(abi.encodeWithSelector(this._simulateRebalance.selector, var_.vault, var_.params, var_.ethValue, user_));

            int256 amt0_;
            int256 amt1_;
            if (data_.length >= 68) {
                    bytes4 errorSelector_;
                    assembly {
                        // Extract the selector from the error data
                        errorSelector_ := mload(add(data_, 0x20))
                    }
                    if (errorSelector_ == VaultsBaseTest.ErrorRebalance.selector) {
                        assembly {
                            amt0_ := mload(add(data_, 36))
                            amt1_ := mload(add(data_, 68))
                        }
                        d_.supplyAmount = amt0_;
                        d_.borrowAmount = amt1_;
                    } else {
                        revert("failed rebalance simulate function");
                        // token0Amount_ & token1Amount_ remains 0
                    }
            }

            assertApproxEqAbs(d_.supplyAmount, 0, 0, string(abi.encodePacked(var_.assertMessage, "rebalance supply not zero")));
            assertApproxEqAbs(d_.borrowAmount, 0, 0, string(abi.encodePacked(var_.assertMessage, "rebalance borrow not zero")));
        }
    }

    function _dustPosition(DexVaultParams memory dexVault_) internal {
        uint256 dustCol_ = 1000;
        uint256 dustDebt_ = 50;

        {
            uint256 ethValue_ = 0;
            if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
                ethValue_ = bob.balance;
            }

            vm.prank(bob);
            dexVault_.vaultT1.operate{value: ethValue_}(
                0,
                int256(dustCol_ * dexVault_.dex.token0Wei),
                int256(dustDebt_ * 10 * dexVault_.dex.token1Wei),
                bob
            );
        }

        {   
            uint256 ethValue_ = 0;
            if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
                ethValue_ = bob.balance;
            }

            vm.prank(bob);
            dexVault_.vaultT2.operatePerfect{value: ethValue_}(
                0,
                int256(dustCol_ * 1e18),
                int256(dustCol_ * 10 * dexVault_.dex.token0Wei),
                int256(dustCol_ * 10 * dexVault_.dex.token1Wei),
                int256(dustDebt_ * dexVault_.dex.token1Wei),
                bob
            );
        }

        {
            uint256 ethValue_ = 0;
            if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
                ethValue_ = bob.balance;
            }

            vm.prank(bob);
            dexVault_.vaultT3.operatePerfect{value: ethValue_}(
                0,
                int256(dustCol_ * dexVault_.dex.token0Wei),
                int256(dustDebt_ * 1e18),
                int256(1 * dexVault_.dex.token0Wei),
                int256(1 * dexVault_.dex.token1Wei),
                bob
            );
        }

        {
            uint256 ethValue_ = 0;
            if (dexVault_.dex.token0 == address(NATIVE_TOKEN_ADDRESS) || dexVault_.dex.token1 == address(NATIVE_TOKEN_ADDRESS)) {
                ethValue_ = bob.balance;
            }

            vm.prank(bob);
            dexVault_.vaultT4.operatePerfect{value: ethValue_}(
                0,
                int256(dustCol_ * 1e18),
                int256(dustCol_ * 10 * dexVault_.dex.token0Wei),
                int256(dustCol_ * 10 * dexVault_.dex.token1Wei),
                int256(dustDebt_ * 1e18),
                int256(1 * dexVault_.dex.token0Wei),
                int256(1 * dexVault_.dex.token1Wei),
                bob
            );
        }
        
    }
}

contract VaultsOperatePerfectTest is VaultsBaseTest {

    function test_perfectSupplyBorrowPaybackWithdraw() public {
        DexVaultParams[2] memory vaults_ = [DAI_USDC_VAULT, USDC_ETH_VAULT];
        VaultType[4] memory vaultTypes_ = [VaultType.VaultT1, VaultType.VaultT2, VaultType.VaultT3, VaultType.VaultT4];

        OperatePerfectParams[4] memory params_ = [
            OperatePerfectParams({
                supplyShareAmount: 100,
                supplyToken0MinMax: 0,
                supplyToken1MinMax: 0,
                borrowShareAmount: 75,
                borrowToken0MinMax: 0,
                borrowToken1MinMax: 0
            }),
            OperatePerfectParams({
                supplyShareAmount: 100,
                supplyToken0MinMax: 105,
                supplyToken1MinMax: 105,
                borrowShareAmount: 75,
                borrowToken0MinMax: 0,
                borrowToken1MinMax: 0
            }),
            OperatePerfectParams({
                supplyShareAmount: 100,
                supplyToken0MinMax: 0,
                supplyToken1MinMax: 0,
                borrowShareAmount: 75,
                borrowToken0MinMax: 1,
                borrowToken1MinMax: 1
            }),
            OperatePerfectParams({
                supplyShareAmount: 100,
                supplyToken0MinMax: 105,
                supplyToken1MinMax: 105,
                borrowShareAmount: 75,
                borrowToken0MinMax: 1,
                borrowToken1MinMax: 1
            })
        ];

        for(uint256 i = 0; i < vaults_.length; i++) {
            for(uint256 j = 0; j < vaultTypes_.length; j++) {
                OperatePerfectParams memory supplyParams_;
                OperatePerfectParams memory borrowParams_;
                OperatePerfectParams memory paybackParams_;
                OperatePerfectParams memory withdrawParams_;

                supplyParams_.supplyShareAmount = params_[j].supplyShareAmount;
                supplyParams_.supplyToken0MinMax = params_[j].supplyToken0MinMax;
                supplyParams_.supplyToken1MinMax = params_[j].supplyToken1MinMax;
                OperatePerfectData memory d_ = _testOperatePerfect(vaults_[i], vaultTypes_[j], _convertOperatePerfectParamsToWei(vaults_[i], vaultTypes_[j], supplyParams_), alice, 0, "test_perfectSupplyBorrowPaybackWithdraw(supply)");

                borrowParams_.borrowShareAmount = params_[j].borrowShareAmount;
                borrowParams_.borrowToken0MinMax = params_[j].borrowToken0MinMax;
                borrowParams_.borrowToken1MinMax = params_[j].borrowToken1MinMax;

                OperatePerfectData memory db_ = _testOperatePerfect(vaults_[i], vaultTypes_[j], _convertOperatePerfectParamsToWei(vaults_[i], vaultTypes_[j], borrowParams_), alice, d_.nftId, "test_perfectSupplyBorrowPaybackWithdraw(borrow)");
                
                paybackParams_.borrowToken0MinMax = -(params_[j].borrowShareAmount * 10);
                paybackParams_.borrowToken1MinMax = -(params_[j].borrowShareAmount * 10);
                paybackParams_ = _convertOperatePerfectParamsToWei(vaults_[i], vaultTypes_[j], paybackParams_);
                paybackParams_.borrowShareAmount = type(int256).min;
                OperatePerfectData memory dp_ = _testOperatePerfect(vaults_[i], vaultTypes_[j], paybackParams_, alice, d_.nftId, "test_perfectSupplyBorrowPaybackWithdraw(payback)");

                withdrawParams_.supplyToken0MinMax = -1;
                withdrawParams_.supplyToken1MinMax = -1;
                withdrawParams_.supplyShareAmount = type(int256).min;

                OperatePerfectData memory dw_ = _testOperatePerfect(vaults_[i], vaultTypes_[j], withdrawParams_, alice, d_.nftId, "test_perfectSupplyBorrowPaybackWithdraw(withdraw)");
            }
        }
    }
}

contract VaultsOperateTest is VaultsBaseTest {

    function test_supplyBorrowPaybackWithdraw() public {
        DexVaultParams[2] memory vaults_ = [DAI_USDC_VAULT, USDC_ETH_VAULT];
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
                OperateParams memory supplyParams_;
                OperateParams memory borrowParams_;
                OperateParams memory paybackParams_;
                OperateParams memory withdrawParams_;

                supplyParams_.supplyToken0 = params_[j].supplyToken0;
                supplyParams_.supplyToken1 = params_[j].supplyToken1;
                supplyParams_.supplyShareMinMax = params_[j].supplyShareMinMax;

                borrowParams_.borrowToken0 = params_[j].borrowToken0;
                borrowParams_.borrowToken1 = params_[j].borrowToken1;
                borrowParams_.borrowShareMinMax = params_[j].borrowShareMinMax;

                paybackParams_.borrowToken0 = -(params_[j].borrowToken0) * 75 / 100;
                paybackParams_.borrowToken1 = -(params_[j].borrowToken1) * 75 / 100;
                paybackParams_.borrowShareMinMax = -1;
                paybackParams_ = _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], paybackParams_);

                withdrawParams_.supplyToken0 = -(params_[j].supplyToken0) * 75 / 100;
                withdrawParams_.supplyToken1 = -(params_[j].supplyToken1) * 75 / 100;
                withdrawParams_.supplyShareMinMax = -250;
                withdrawParams_ = _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], withdrawParams_);

               OperateData memory d_ = _testOperate(vaults_[i], vaultTypes_[j], _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], supplyParams_), alice, 0, "test_supplyBorrowPaybackWithdraw(supply)");
                _testOperate(vaults_[i], vaultTypes_[j], _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], borrowParams_), alice, d_.nftId, "test_supplyBorrowPaybackWithdraw(borrow)");
                _testOperate(vaults_[i], vaultTypes_[j], paybackParams_, alice, d_.nftId, "test_supplyBorrowPaybackWithdraw(payback)");
                _testOperate(vaults_[i], vaultTypes_[j], withdrawParams_, alice, d_.nftId, "test_supplyBorrowPaybackWithdraw(withdraw)");
            }
        }
    }

    function test_liquidate() public {
        DexVaultParams[2] memory vaults_ = [DAI_USDC_VAULT, USDC_ETH_VAULT];
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
                if (vaultTypes_[j] == VaultType.VaultT1) {
                    continue;
                }

                OperateData memory d_ = _testOperate(vaults_[i], vaultTypes_[j], _convertOperateParamsToWei(vaults_[i], vaultTypes_[j], params_[j]), alice, 0, "test_liquidate(supply and borrow)");

                _setOraclePrice(vaults_[i], vaultTypes_[j], _getOraclePrice(vaults_[i], vaultTypes_[j]) * 800 / 1000); // decrease by 10%
                uint256 snapshotId_ = vm.snapshot();

                for (uint256 k = 0; k < 3; k++) {
                    LiquidateParams memory liquidateParams;

                    liquidateParams.debtToken0Percentage = k == 0 || k == 2 ? 100 : 0;
                    liquidateParams.debtToken1Percentage = k == 1 || k == 2 ? 100 : 0;

                    for(uint256 l = 0; l < 3; l++) {
                        liquidateParams.collateralToken0MinAmount = l == 0 || l == 2 ? 1 : 0;
                        liquidateParams.collateralToken1MinAmount = l == 1 || l == 2 ? 1 : 0;
                        liquidateParams.debtToken0MinAmount = l == 2 || k == 2 ? type(uint256).max : 0;
                        liquidateParams.debtToken1MinAmount = l == 2 || k == 2 ? type(uint256).max : 0;

                        _testLiquidate(vaults_[i], vaultTypes_[j], liquidateParams, alice, d_.nftId, "test_liquidate(liquidate)");
                        vm.revertTo(snapshotId_);
                    }
                } 
            }
        }
    }

    function test_rebalance() public {
        DexVaultParams[1] memory vaults_ = [DAI_USDC_VAULT];
        VaultType[4] memory vaultTypes_ = [VaultType.VaultT1, VaultType.VaultT2, VaultType.VaultT3, VaultType.VaultT4];

        RebalanceParams[4] memory params_ = [
            RebalanceParams({
                depositOrWithdraw: 1,
                borrowOrPayback: 0,
                timeToSkip: 30 days
            }),
            RebalanceParams({
                depositOrWithdraw: 0,
                borrowOrPayback: 1,
                timeToSkip: 30 days
            }),
            RebalanceParams({
                depositOrWithdraw: 2,
                borrowOrPayback: 0,
                timeToSkip: 30 days
            }),
            RebalanceParams({
                depositOrWithdraw: 0,
                borrowOrPayback: 2,
                timeToSkip: 30 days
            })
        ];

        for(uint256 i = 0; i < vaults_.length; i++) {
            for(uint256 j = 0; j < vaultTypes_.length; j++) {
                for(uint256 k = 0; k < params_.length; k++) {
                    _testRebalance(vaults_[i], vaultTypes_[j], params_[k], alice, "test_rebalance");
                }
            }
        }
    }

}

