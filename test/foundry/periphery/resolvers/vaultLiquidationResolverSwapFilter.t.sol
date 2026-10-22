//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidVaultLiquidationResolver } from "../../../../contracts/periphery/resolvers/vaultLiquidation/main.sol";
import { Structs } from "../../../../contracts/periphery/resolvers/vaultLiquidation/structs.sol";
import { Structs as VaultResolverStructs } from "../../../../contracts/periphery/resolvers/vault/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { TestERC20 } from "../../testERC20.sol";

/// @dev Non-fork regression tests for `_filterSwapsUntilTarget` edge cases: a zero target amount, and 3+ entries
/// for the same protocol in the input. Both panic pre-fix; neither needs real vault state, so the `Swap[]`
/// inputs are constructed directly against the public filter/sort entry points.
contract FluidVaultLiquidationResolverFilterEdgeCasesTest is Test {
    FluidVaultLiquidationResolver resolver;

    address internal constant PROTOCOL = address(0xBEEF);
    address internal constant TOKEN_IN = address(0x1111);
    address internal constant TOKEN_OUT = address(0x2222);

    function setUp() public {
        // VAULT_RESOLVER / LIQUIDITY are never called by the code paths under test here.
        resolver = new FluidVaultLiquidationResolver(IFluidVaultResolver(address(1)), IFluidLiquidity(address(2)));
    }

    function _swap(uint256 inAmt_, uint256 outAmt_, bool withAbsorb_) internal pure returns (Structs.Swap memory) {
        return
            Structs.Swap({
                path: Structs.SwapPath({ protocol: PROTOCOL, tokenIn: TOKEN_IN, tokenOut: TOKEN_OUT }),
                data: Structs.SwapData({
                    inAmt: inAmt_,
                    outAmt: outAmt_,
                    withAbsorb: withAbsorb_,
                    ratio: outAmt_ == 0 ? 0 : (outAmt_ * 1e27) / inAmt_
                })
            });
    }

    function test_filterToTargetInAmt_WhenTargetInAmtZero() public {
        Structs.Swap[] memory swaps = new Structs.Swap[](1);
        swaps[0] = _swap(100, 200, false);

        (Structs.Swap[] memory filtered, uint256 actualInAmt, uint256 actualOutAmt) = resolver.filterToTargetInAmt(
            swaps,
            0
        );

        assertEq(filtered.length, 0);
        assertEq(actualInAmt, 0);
        assertEq(actualOutAmt, 0);
    }

    function test_filterToApproxOutAmt_WhenTargetOutAmtZero() public {
        Structs.Swap[] memory swaps = new Structs.Swap[](1);
        swaps[0] = _swap(100, 200, false);

        (Structs.Swap[] memory filtered, uint256 actualInAmt, uint256 actualOutAmt) = resolver.filterToApproxOutAmt(
            swaps,
            0
        );

        assertEq(filtered.length, 0);
        assertEq(actualInAmt, 0);
        assertEq(actualOutAmt, 0);
    }

    /// @dev 3 entries for the same protocol in the filtered window: pre-fix this overcounts `duplicatesCount_`
    /// (one count per matching pair, `C(3,2)=3`, instead of per removed entry, `3-1=2`) and undersizes the
    /// rebuilt array, so the loop that copies surviving non-zero entries writes out of bounds.
    function test_filterToTargetInAmt_WhenThreeEntriesSameProtocol() public {
        Structs.Swap[] memory swaps = new Structs.Swap[](3);
        swaps[0] = _swap(100, 200, false); // ratio 2e27
        swaps[1] = _swap(50, 60, false); // ratio 1.2e27
        swaps[2] = _swap(10, 5, true); // ratio 0.5e27

        (Structs.Swap[] memory filtered, uint256 actualInAmt, uint256 actualOutAmt) = resolver.filterToTargetInAmt(
            swaps,
            type(uint256).max
        );

        // only one survivor per protocol group; the with-absorb entry wins since it is last in ratio order
        assertEq(filtered.length, 1);
        assertEq(filtered[0].data.inAmt, 10);
        assertEq(filtered[0].data.outAmt, 5);
        assertEq(filtered[0].data.withAbsorb, true);
        assertEq(actualInAmt, 10);
        assertEq(actualOutAmt, 5);
    }

    /// @dev same as above with a 4th entry, so two full dedup passes are needed (duplicatesCount_ would
    /// overcount by 3 pre-fix, i.e. by more than just 1).
    function test_filterToTargetInAmt_WhenFourEntriesSameProtocol() public {
        Structs.Swap[] memory swaps = new Structs.Swap[](4);
        swaps[0] = _swap(400, 800, false); // ratio 2e27
        swaps[1] = _swap(100, 150, false); // ratio 1.5e27
        swaps[2] = _swap(50, 60, false); // ratio 1.2e27
        swaps[3] = _swap(10, 5, true); // ratio 0.5e27

        (Structs.Swap[] memory filtered, uint256 actualInAmt, uint256 actualOutAmt) = resolver.filterToTargetInAmt(
            swaps,
            type(uint256).max
        );

        assertEq(filtered.length, 1);
        assertEq(filtered[0].data.inAmt, 10);
        assertEq(filtered[0].data.outAmt, 5);
        assertEq(filtered[0].data.withAbsorb, true);
        assertEq(actualInAmt, 10);
        assertEq(actualOutAmt, 5);
    }
}

/// @dev mocks `getVaultLiquidation` with a caller-chosen fixed result, bypassing real VaultT1 tick/CF math so the
/// withdrawable-clamp rounding scenario in `getVaultsSwap` can be driven with exact numbers.
contract MockVaultResolverForLiquidation {
    VaultResolverStructs.LiquidationStruct internal _data;

    constructor(VaultResolverStructs.LiquidationStruct memory data_) {
        _data = data_;
    }

    function getVaultLiquidation(
        address,
        uint256
    ) external view returns (VaultResolverStructs.LiquidationStruct memory) {
        return _data;
    }
}

/// @dev mocks the one Liquidity storage slot `_getVaultT1Withdrawable` reads for a non-interest, no-active-limit
/// user supply (bit 0 = 0, withdrawal-limit bits = 0), so withdrawable is capped only by the token balance below.
contract MockLiquidityForWithdrawable {
    uint256 internal immutable _userSupplyData;

    constructor(uint256 userSupplyData_) {
        _userSupplyData = userSupplyData_;
    }

    function readFromStorage(bytes32) external view returns (uint256) {
        return _userSupplyData;
    }
}

/// @dev mocks `constantsView()` so `_getVaultTokens` resolves to caller-chosen token addresses.
contract MockVaultT1ForTokens {
    address public immutable supplyToken;
    address public immutable borrowToken;

    constructor(address supplyToken_, address borrowToken_) {
        supplyToken = supplyToken_;
        borrowToken = borrowToken_;
    }

    function constantsView() external view returns (IFluidVaultT1.ConstantViews memory constantsView_) {
        constantsView_.supplyToken = supplyToken;
        constantsView_.borrowToken = borrowToken;
    }
}

/// @dev Each builder counts this vault from the pre-clamp inAmt, then the withdrawable clamp rounds it to 0.
/// Mocked rather than a real VaultT1, since landing an exact clamp ratio needs tick/CF math.
contract FluidVaultLiquidationResolverClampRoundingTest is Test {
    FluidVaultLiquidationResolver internal resolver;
    MockVaultT1ForTokens internal mockVault;
    TestERC20 internal supplyToken;
    TestERC20 internal borrowToken;

    function setUp() public {
        supplyToken = new TestERC20("Supply", "SUP");
        borrowToken = new TestERC20("Borrow", "BOR");

        VaultResolverStructs.LiquidationStruct memory liquidationData;
        // without-absorb left at 0 so the with-absorb side is the only swap
        liquidationData.inAmtWithAbsorb = 500;
        liquidationData.outAmtWithAbsorb = 1000;
        MockVaultResolverForLiquidation mockVaultResolver = new MockVaultResolverForLiquidation(liquidationData);

        // interest-free user, withdrawal limit never activated, supply amount far above anything used here
        uint256 userSupplyData = BigMathMinified.toBigNumber(1e30, 56, 8, false) <<
            LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT;
        MockLiquidityForWithdrawable mockLiquidity = new MockLiquidityForWithdrawable(userSupplyData);

        // Liquidity's collateral balance of 1 wei is the binding withdrawable constraint, far below outAmt (1000)
        supplyToken.mint(address(mockLiquidity), 1);

        mockVault = new MockVaultT1ForTokens(address(supplyToken), address(borrowToken));
        resolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(mockVaultResolver)),
            IFluidLiquidity(address(mockLiquidity))
        );
    }

    function _vaults() internal view returns (address[] memory vaults_) {
        vaults_ = new address[](1);
        vaults_[0] = address(mockVault);
    }

    function _paths() internal view returns (Structs.SwapPath[] memory paths_) {
        paths_ = new Structs.SwapPath[](1);
        paths_[0] = Structs.SwapPath({
            protocol: address(mockVault),
            tokenIn: address(borrowToken),
            tokenOut: address(supplyToken)
        });
    }

    function test_getVaultsSwap_WhenWithdrawableClampRoundsInAmtToZero() public {
        assertEq(resolver.getVaultsSwap(_vaults()).length, 0);
    }

    function test_getVaultsSwapRaw_WhenWithdrawableClampRoundsInAmtToZero() public {
        assertEq(resolver.getVaultsSwapRaw(_vaults()).length, 0);
    }

    function test_getSwapsForPaths_WhenWithdrawableClampRoundsInAmtToZero() public {
        assertEq(resolver.getSwapsForPaths(_paths()).length, 0);
    }

    function test_getSwapsForPathsRaw_WhenWithdrawableClampRoundsInAmtToZero() public {
        assertEq(resolver.getSwapsForPathsRaw(_paths()).length, 0);
    }
}
