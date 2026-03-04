//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultT1Resolver } from "../../../../contracts/periphery/resolvers/vaultT1/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../../../contracts/protocols/vault/interfaces/iVaultFactory.sol";
import { FluidVaultFactory } from "../../../../contracts/protocols/vault/factory/main.sol";
import { FluidVaultT1DeploymentLogic } from "../../../../contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";

contract FluidVaultT1ResolverRobustnessTest is Test {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidVaultFactory internal constant VAULT_FACTORY = IFluidVaultFactory(0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d);

    FluidVaultT1DeploymentLogic vaultT1Deployer =
        FluidVaultT1DeploymentLogic(0x15f6F562Ae136240AB9F4905cb50aCA54bCbEb5F);

    address internal constant ALLOWED_DEPLOYER = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e; // team multisig is an allowed deployer

    // address that is not listed as token, user or anything
    address internal constant UNUSED_ADDRESS = 0x9aA2B2aba70EEF169a8ad6949C0B2F68e3C6e63F;
    address internal constant UNUSED_TOKEN = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant Vault_wstETH_USDC = 0x51197586F6A9e2571868b6ffaef308f3bdfEd3aE;

    FluidLiquidityResolver liquidityResolver;
    FluidVaultT1Resolver resolver;

    address newVault;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19927377);

        liquidityResolver = new FluidLiquidityResolver(LIQUIDITY);
        resolver = new FluidVaultT1Resolver(address(VAULT_FACTORY), address(LIQUIDITY), address(liquidityResolver));

        // create a new vault, without configuring it at Liquidity
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(WSTETH)));
        vm.prank(ALLOWED_DEPLOYER);
        newVault = FluidVaultFactory(address(VAULT_FACTORY)).deployVault(address(vaultT1Deployer), vaultT1CreationCode);
    }

    function test_allMethodsWithoutReverts() public {
        // this test ensures there are no reverts for any method available on the resolver
        resolver.getTotalVaults();
        resolver.totalPositions();
        resolver.getAllVaultsAddresses();
        resolver.getVaultsEntireData();
        resolver.getAllVaultsLiquidation();

        address user_ = ALLOWED_DEPLOYER;
        resolver.positionsByUser(user_);
        resolver.positionsNftIdOfUser(user_);

        // for existing, configured at Liquidity vault
        _runAllResolverMethods(Vault_wstETH_USDC);
        // for existing, not configured at Liquidity vault
        _runAllResolverMethods(newVault);

        uint256 vaultId_ = 2; // for sure existing vault id
        resolver.getVaultAddress(vaultId_);
        resolver.getVaultType(Vault_wstETH_USDC);
        vaultId_ = 777; // not existing vault id
        resolver.getVaultAddress(vaultId_);
        resolver.getVaultType(address(1));

        address[] memory vaults_ = new address[](2);
        vaults_[0] = Vault_wstETH_USDC;
        vaults_[1] = newVault;
        resolver.getVaultsAbsorb(vaults_);
        resolver.getVaultsEntireData(vaults_);

        uint256[] memory tokensInAmt_ = new uint256[](2);
        tokensInAmt_[0] = 1e20;
        tokensInAmt_[1] = 1e10;
        resolver.getMultipleVaultsLiquidation(vaults_, tokensInAmt_);

        uint256 nftId_ = 2; // for sure existing nft id
        resolver.getTokenConfig(nftId_);
        resolver.positionByNftId(nftId_);
        resolver.vaultByNftId(nftId_);
        resolver.getPositionDataRaw(Vault_wstETH_USDC, nftId_);
        // for new vault
        resolver.getPositionDataRaw(newVault, nftId_);

        nftId_ = 1e14; // not existing nft id
        resolver.getTokenConfig(nftId_);
        resolver.vaultByNftId(nftId_);
        resolver.getPositionDataRaw(Vault_wstETH_USDC, nftId_);
        resolver.getPositionDataRaw(newVault, nftId_);

        resolver.positionByNftId(nftId_);

        nftId_ = 0;
        resolver.getTokenConfig(nftId_);
        resolver.vaultByNftId(nftId_);
        resolver.getPositionDataRaw(Vault_wstETH_USDC, nftId_);
        resolver.getPositionDataRaw(newVault, nftId_);

        resolver.positionByNftId(nftId_);
    }

    function _runAllResolverMethods(address vault_) internal {
        resolver.getAbsorbedLiquidityRaw(vault_);
        resolver.getRateRaw(vault_);
        resolver.getRebalancer(vault_);
        resolver.getVaultAbsorb(vault_);
        resolver.getVaultEntireData(vault_);
        resolver.getVaultId(vault_);
        resolver.getVaultState(vault_);
        resolver.getVaultVariables2Raw(vault_);
        resolver.getVaultVariablesRaw(vault_);

        uint256 branchId_ = 1;
        resolver.getBranchDataRaw(vault_, branchId_);

        uint256 tokenInAmt_ = 1e20;
        resolver.getVaultLiquidation(vault_, tokenInAmt_);

        int256 tick_ = 10000;
        uint256 tickId_ = 1;
        resolver.getTickDataRaw(vault_, tick_);
        resolver.getTickIdDataRaw(vault_, tick_, tickId_);

        int256 key_ = 2;
        resolver.getTickHasDebtRaw(vault_, key_);
    }
}
