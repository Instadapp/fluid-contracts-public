//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidVaultT4 } from "../../../../contracts/protocols/vault/vaultT4/coreModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";

import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";

import "forge-std/console2.sol";

contract VaultT4LiquidateNativeWithAsborb is Test {
    FluidDexT1 internal constant DEX_WSTETH_ETH = FluidDexT1(payable(0x0B1a513ee24972DAEf112bC777a5610d4325C9e7));
    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    FluidVaultT4 internal constant VAULTT4_WSTETH_ETH =
        FluidVaultT4(payable(0x528CF7DBBff878e02e48E83De5097F8071af768D));

    address internal constant WSTETH_HOLDER = 0x3c22ec75ea5D745c78fc84762F7F1E6D82a2c5BF;

    IERC20 internal constant WSTETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    FluidVaultResolver VAULT_RESOLVER = FluidVaultResolver(0x814c8C7ceb1411B364c2940c4b9380e739e06686);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21542701);
        vm.deal(WSTETH_HOLDER, 1e40);
    }

    function test_liquidateWithAbsorbNative() public {
        // get current oracle & oracle price
        // replace with mock oracle and reduce price by 4%
        // try liquidate with absorb having to be run

        FluidVaultResolver.VaultEntireData memory vaultData_ = VAULT_RESOLVER.getVaultEntireData(
            address(VAULTT4_WSTETH_ETH)
        );
        uint256 price = vaultData_.configs.oraclePriceLiquidate;
        console2.log("Current Oracle Price:", price);
        price = (price * 96) / 100;
        vm.mockCall(
            vaultData_.configs.oracle,
            abi.encodeWithSelector(MockOracle.getExchangeRateLiquidate.selector),
            abi.encode(price)
        );

        console2.log("new Oracle Price should be:", price);
        vaultData_ = VAULT_RESOLVER.getVaultEntireData(address(VAULTT4_WSTETH_ETH));
        console2.log("new Oracle Price is:", vaultData_.configs.oraclePriceLiquidate);

        // check liquidation available
        FluidVaultResolver.LiquidationStruct memory liquidationData = VAULT_RESOLVER.getVaultLiquidation(
            address(VAULTT4_WSTETH_ETH),
            1e40
        );
        assertTrue(liquidationData.absorbAvailable);

        vm.prank(WSTETH_HOLDER);
        WSTETH.approve(address(VAULTT4_WSTETH_ETH), 1e40);

        vm.prank(WSTETH_HOLDER);
        vm.expectRevert(); // first smart vaults have a bug for payable, in this vault it would revert. (solved through other ways)
        VAULTT4_WSTETH_ETH.liquidate{ value: 682e18 }(1e18, 682e18, 1, 1, 1, 1, WSTETH_HOLDER, true);
    }
}
