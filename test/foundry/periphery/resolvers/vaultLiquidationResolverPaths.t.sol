//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidVaultLiquidationResolver } from "../../../../contracts/periphery/resolvers/vaultLiquidation/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultLiquidation/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";

/// @dev mocks `getAllVaultsAddresses()` with a caller-chosen list, so `getAnySwapPaths` can be driven with
/// several VaultT1s sharing one token pair without a real factory/fork.
contract MockVaultResolverForPaths {
    address[] internal _vaults;

    constructor(address[] memory vaults_) {
        _vaults = vaults_;
    }

    function getAllVaultsAddresses() external view returns (address[] memory) {
        return _vaults;
    }
}

/// @dev mocks `constantsView()` so `_getVaultTokens` resolves to a caller-chosen token pair.
contract MockVaultT1ForPaths {
    address public immutable borrowToken;
    address public immutable supplyToken;

    constructor(address borrowToken_, address supplyToken_) {
        borrowToken = borrowToken_;
        supplyToken = supplyToken_;
    }

    function constantsView() external view returns (IFluidVaultT1.ConstantViews memory constantsView_) {
        constantsView_.borrowToken = borrowToken;
        constantsView_.supplyToken = supplyToken;
    }
}

/// @dev several vaults can share one token pair, so path sizing must not assume one vault per pair
contract FluidVaultLiquidationResolverPathsTest is Test {
    address internal constant TOKEN_IN = address(0x1111);
    address internal constant TOKEN_OUT = address(0x2222);

    function _deployResolverWithVaults(
        uint256 vaultCount_
    ) internal returns (FluidVaultLiquidationResolver resolver_, address[] memory vaults_) {
        vaults_ = new address[](vaultCount_);
        for (uint256 i; i < vaultCount_; ++i) {
            vaults_[i] = address(new MockVaultT1ForPaths(TOKEN_IN, TOKEN_OUT));
        }
        MockVaultResolverForPaths mockVaultResolver = new MockVaultResolverForPaths(vaults_);
        resolver_ = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(mockVaultResolver)),
            IFluidLiquidity(address(1))
        );
    }

    function test_getAnySwapPaths_WhenTwoVaultsShareSamePair() public {
        (FluidVaultLiquidationResolver resolver, address[] memory vaults) = _deployResolverWithVaults(2);

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = TOKEN_IN;
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = TOKEN_OUT;

        Structs.SwapPath[] memory paths = resolver.getAnySwapPaths(tokensIn, tokensOut);

        assertEq(paths.length, 2);
        assertEq(paths[0].protocol, vaults[0]);
        assertEq(paths[0].tokenIn, TOKEN_IN);
        assertEq(paths[0].tokenOut, TOKEN_OUT);
        assertEq(paths[1].protocol, vaults[1]);
    }

    function test_getAnySwapPaths_WhenThreeVaultsShareSamePair() public {
        (FluidVaultLiquidationResolver resolver, address[] memory vaults) = _deployResolverWithVaults(3);

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = TOKEN_IN;
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = TOKEN_OUT;

        Structs.SwapPath[] memory paths = resolver.getAnySwapPaths(tokensIn, tokensOut);

        assertEq(paths.length, 3);
        assertEq(paths[0].protocol, vaults[0]);
        assertEq(paths[1].protocol, vaults[1]);
        assertEq(paths[2].protocol, vaults[2]);
    }
}
