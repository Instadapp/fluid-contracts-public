//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";
import { FluidVaultPositionsResolver } from "../../../../contracts/periphery/resolvers/vaultPositions/main.sol";

import { VaultsBaseTest } from "../../dex/poolT1/vaults.t.sol";

abstract contract FluidVaultResolverRobustnessTestBase is Test {
    address internal constant ALLOWED_DEPLOYER = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e; // team multisig is an allowed deployer

    // address that is not listed as token, user or anything
    address internal constant UNUSED_ADDRESS = 0x9aA2B2aba70EEF169a8ad6949C0B2F68e3C6e63F;
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address newVault;
    address existingVault;

    FluidVaultResolver curVaultResolver;

    function _runResolverMethods() internal {
        // for existing, configured at Liquidity vault
        console.log("for existing vault");
        _runAllResolverMethods(existingVault, true);

        // for new, not configured at Liquidity vault
        console.log("for new vault");
        _runAllResolverMethods(newVault, false);

        uint256 vaultId_ = 2; // for sure existing vault id
        curVaultResolver.getVaultAddress(vaultId_);
        uint256 vaultType = curVaultResolver.getVaultType(existingVault);
        assertNotEq(vaultType, 0, "vautlType for existing is 0");
        vaultId_ = 777; // not existing vault id
        curVaultResolver.getVaultAddress(vaultId_);
        vaultType = curVaultResolver.getVaultType(address(1));
        assertEq(vaultType, 0, "vautlType for not existing is NOT 0");

        address[] memory vaults_ = new address[](2);
        vaults_[0] = existingVault;
        vaults_[1] = newVault;
        curVaultResolver.getVaultsAbsorb(vaults_);
        curVaultResolver.getVaultsEntireData(vaults_);

        uint256[] memory tokensInAmt_ = new uint256[](2);
        tokensInAmt_[0] = 1e20;
        tokensInAmt_[1] = 1e10;
        curVaultResolver.getMultipleVaultsLiquidation(vaults_, tokensInAmt_);

        uint256 nftId_ = 2; // for sure existing nft id
        curVaultResolver.getTokenConfig(nftId_);
        curVaultResolver.positionByNftId(nftId_);
        curVaultResolver.vaultByNftId(nftId_);
        curVaultResolver.getPositionDataRaw(existingVault, nftId_);
        // for new vault
        curVaultResolver.getPositionDataRaw(newVault, nftId_);

        nftId_ = 1e14; // not existing nft id
        curVaultResolver.getTokenConfig(nftId_);
        curVaultResolver.vaultByNftId(nftId_);
        curVaultResolver.getPositionDataRaw(existingVault, nftId_);
        curVaultResolver.getPositionDataRaw(newVault, nftId_);

        curVaultResolver.positionByNftId(nftId_);

        nftId_ = 0;
        curVaultResolver.getTokenConfig(nftId_);
        curVaultResolver.vaultByNftId(nftId_);
        curVaultResolver.getPositionDataRaw(existingVault, nftId_);
        curVaultResolver.getPositionDataRaw(newVault, nftId_);

        curVaultResolver.positionByNftId(nftId_);
    }

    function _runAllResolverMethods(address vault_, bool isConfigured_) internal {
        console.log("running resolver methods for vault Id", curVaultResolver.getVaultId(vault_));
        curVaultResolver.getAbsorbedLiquidityRaw(vault_);
        curVaultResolver.getRateRaw(vault_);
        curVaultResolver.getVaultAbsorb(vault_);

        curVaultResolver.getVaultState(vault_);
        curVaultResolver.getVaultVariables2Raw(vault_);
        curVaultResolver.getVaultVariablesRaw(vault_);

        uint256 branchId_ = 1;
        curVaultResolver.getBranchDataRaw(vault_, branchId_);

        uint256 tokenInAmt_ = 1e20;
        curVaultResolver.getVaultLiquidation(vault_, tokenInAmt_);

        int256 tick_ = 10000;
        uint256 tickId_ = 1;
        curVaultResolver.getTickDataRaw(vault_, tick_);
        curVaultResolver.getTickIdDataRaw(vault_, tick_, tickId_);

        int256 key_ = 2;
        curVaultResolver.getTickHasDebtRaw(vault_, key_);

        if (isConfigured_) {
            address rebalancer = curVaultResolver.getRebalancer(vault_);
            assertNotEq(rebalancer, address(0), "rebalancer for configured vault is address zero");
            FluidVaultResolver.VaultEntireData memory vaultEntireData = curVaultResolver.getVaultEntireData(vault_);
            assertNotEq(
                vaultEntireData.configs.rebalancer,
                address(0),
                "rebalancer for configured vault is address zero"
            );
        } else {
            curVaultResolver.getRebalancer(vault_);
            curVaultResolver.getVaultEntireData(vault_);
        }
    }
}

contract FluidVaultResolverRobustnessTest is FluidVaultResolverRobustnessTestBase {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    FluidVaultT1DeploymentLogic vaultT1Deployer =
        FluidVaultT1DeploymentLogic(0x15f6F562Ae136240AB9F4905cb50aCA54bCbEb5F);

    address internal constant USDC_FORK = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT_FORK = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant Vault_wstETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;

    FluidLiquidityResolver liquidityResolver;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        curVaultResolver = new FluidVaultResolver(address(VAULT_FACTORY), address(liquidityResolver));

        // create a new vault, without configuring it at Liquidity
        bytes memory vaultT1CreationCode = abi.encodeCall(
            vaultT1Deployer.vaultT1,
            (address(USDC_FORK), address(WSTETH))
        );
        vm.prank(ALLOWED_DEPLOYER);
        newVault = FluidVaultFactory(address(VAULT_FACTORY)).deployVault(address(vaultT1Deployer), vaultT1CreationCode);
        existingVault = Vault_wstETH_USDC;
    }

    function test_allMethodsWithoutReverts_T1() public {
        _runResolverMethods();

        // this test ensures there are no reverts for any method available on the resolver
        curVaultResolver.getTotalVaults();
        curVaultResolver.totalPositions();
        curVaultResolver.getAllVaultsAddresses();
        curVaultResolver.getVaultsEntireData();
        curVaultResolver.getAllVaultsLiquidation();

        address user_ = ALLOWED_DEPLOYER;
        curVaultResolver.positionsByUser(user_);
        curVaultResolver.positionsNftIdOfUser(user_);
    }
}

contract FluidVaultResolverNewTypesRobustnessTest is FluidVaultResolverRobustnessTestBase, VaultsBaseTest {
    address newVaultT2;
    address newVaultT3;
    address newVaultT4;

    function setUp() public virtual override {
        super.setUp();

        DexParams memory dex_ = DAI_USDC;

        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        curVaultResolver = new FluidVaultResolver(address(vaultFactory), address(liquidityResolver));

        // create new vaults, without configuring them at Liquidity

        bytes memory vaultT2CreationCode = abi.encodeCall(
            _vaultT2DeploymentLogic.vaultT2,
            (address(dex_.dexCol), dex_.token0)
        );
        bytes memory vaultT3CreationCode = abi.encodeCall(
            _vaultT3DeploymentLogic.vaultT3,
            (dex_.token1, address(dex_.dexDebt))
        );
        bytes memory vaultT4CreationCode = abi.encodeCall(
            _vaultT4DeploymentLogic.vaultT4,
            (address(dex_.dexCol), address(dex_.dexDebt))
        );

        vm.startPrank((admin));
        newVaultT2 = address(vaultFactory.deployVault(address(_vaultT2DeploymentLogic), vaultT2CreationCode));
        newVaultT3 = address(vaultFactory.deployVault(address(_vaultT3DeploymentLogic), vaultT3CreationCode));
        newVaultT4 = address(vaultFactory.deployVault(address(_vaultT4DeploymentLogic), vaultT4CreationCode));
        vm.stopPrank();

        // @dev we do not run this test for vaultT1_not_for_prod because that is a special case that resolver
        // must not support: it is vault type 1 with constants of NEW common struct.
    }

    function test_allMethodsWithoutReverts_T2() public {
        newVault = newVaultT2;
        existingVault = address(DAI_USDC_VAULT.vaultT2);

        _runResolverMethods();

        // this test ensures there are no reverts for any method available on the resolver
        curVaultResolver.getTotalVaults();
        curVaultResolver.totalPositions();
        curVaultResolver.getAllVaultsAddresses();
        // curVaultResolver.getVaultsEntireData(); not running because vaultT1 not prod fails as described above
        // curVaultResolver.getAllVaultsLiquidation(); not running because vaultT1 not prod fails as described above

        address user_ = ALLOWED_DEPLOYER;
        curVaultResolver.positionsByUser(user_);
        curVaultResolver.positionsNftIdOfUser(user_);
    }

    function test_allMethodsWithoutReverts_T3() public {
        newVault = newVaultT3;
        existingVault = address(DAI_USDC_VAULT.vaultT3);

        _runResolverMethods();

        // this test ensures there are no reverts for any method available on the resolver
        curVaultResolver.getTotalVaults();
        curVaultResolver.totalPositions();
        curVaultResolver.getAllVaultsAddresses();
        // curVaultResolver.getVaultsEntireData(); not running because vaultT1 not prod fails as described above
        // curVaultResolver.getAllVaultsLiquidation(); not running because vaultT1 not prod fails as described above

        address user_ = ALLOWED_DEPLOYER;
        curVaultResolver.positionsByUser(user_);
        curVaultResolver.positionsNftIdOfUser(user_);
    }

    function test_allMethodsWithoutReverts_T4() public {
        newVault = newVaultT4;
        existingVault = address(DAI_USDC_VAULT.vaultT4);

        _runResolverMethods();

        // this test ensures there are no reverts for any method available on the resolver
        curVaultResolver.getTotalVaults();
        curVaultResolver.totalPositions();
        curVaultResolver.getAllVaultsAddresses();
        // curVaultResolver.getVaultsEntireData(); not running because vaultT1 not prod fails as described above
        // curVaultResolver.getAllVaultsLiquidation(); not running because vaultT1 not prod fails as described above

        address user_ = ALLOWED_DEPLOYER;
        curVaultResolver.positionsByUser(user_);
        curVaultResolver.positionsNftIdOfUser(user_);
    }

    function test_vaultPositionsResolver() public {
        FluidVaultPositionsResolver resolver = new FluidVaultPositionsResolver(
            IFluidVaultResolver(address(curVaultResolver)),
            IFluidVaultFactory(address(vaultFactory))
        );
        resolver.getAllVaultNftIds(address(DAI_USDC_VAULT.vaultT1));
        resolver.getAllVaultNftIds(address(DAI_USDC_VAULT.vaultT2));
        resolver.getAllVaultNftIds(address(DAI_USDC_VAULT.vaultT3));
        resolver.getAllVaultNftIds(address(DAI_USDC_VAULT.vaultT4));

        resolver.getAllVaultPositions(address(DAI_USDC_VAULT.vaultT1));
        resolver.getAllVaultPositions(address(DAI_USDC_VAULT.vaultT2));
        resolver.getAllVaultPositions(address(DAI_USDC_VAULT.vaultT3));
        resolver.getAllVaultPositions(address(DAI_USDC_VAULT.vaultT4));
    }
}
