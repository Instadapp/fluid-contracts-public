//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { VaultT1BaseTest } from "./vault.t.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

/// @notice `rebalance()` on a native-token vault must never keep `msg.value` the legs did not consume:
/// not when a leg reverts into its catch, and not when no native leg runs at all.
contract VaultT1RebalanceNativeRefundTest is VaultT1BaseTest {
    uint256 internal constant RATE_PRECISION = 1e4;

    int256 internal constant NATIVE_COL = 5 * 1e18;
    int256 internal constant THREE_DEBT = 5000 * 1e6;
    int256 internal constant FOUR_COL = 10_000 * 1e18;
    int256 internal constant NATIVE_DEBT = 2 * 1e18;

    function setUp() public virtual override {
        super.setUp();

        _setOracleThreePrice(2000 * 1e39);
        _setOracleFourPrice(1e54 / (2000 * 1e27));

        // vaultThree: native supply / DAI borrow. vaultFour: USDC supply / native borrow.
        vm.prank(alice);
        vaultThree.operate{ value: uint256(NATIVE_COL) }(0, NATIVE_COL, THREE_DEBT, alice);

        vm.prank(alice);
        vaultFour.operate(0, FOUR_COL, NATIVE_DEBT, alice);

        // the non-native supply leg pulls its token from the rebalancer through the vault's liquidityCallback
        vm.prank(alice);
        supplyToken.approve(address(vaultFour), type(uint256).max);

        // USDC needs utilization at Liquidity, otherwise its supply rate is 0 and no supply-side gap can open
        _borrow(mockProtocol, address(supplyToken), alice, 500_000 * 1e6);

        vm.deal(alice, 1000 ether);
    }

    /// @dev supply magnifier > 100% grows the vault's supply faster than Liquidity's, opening a gap the
    ///      rebalance has to close by depositing.
    function _openSupplyGap(address vault_, uint256 magnifier_) internal {
        vm.prank(alice);
        FluidVaultT1Admin(vault_).updateSupplyRateMagnifier(magnifier_);
        vm.warp(block.timestamp + 365 days);
    }

    /// @dev borrow magnifier > 100% grows the vault's borrow faster than Liquidity's, so the rebalance
    ///      borrows the difference out (no native value involved on either vault's borrow token here).
    function _openBorrowGap(address vault_, uint256 magnifier_) internal {
        vm.prank(alice);
        FluidVaultT1Admin(vault_).updateBorrowRateMagnifier(magnifier_);
        vm.warp(block.timestamp + 365 days);
    }

    function _revertNativeOperate() internal {
        vm.mockCallRevert(
            address(liquidity),
            abi.encodeWithSelector(IFluidLiquidityLogic.operate.selector, nativeToken),
            abi.encode("native operate forced to revert")
        );
    }

    /// @notice the supply-deposit leg forwards `msg.value` to Liquidity; when that call reverts the ETH comes
    /// back to the vault and must be returned to the caller rather than stranded.
    function test_rebalance_RefundsEthWhenNativeSupplyLegReverts() public {
        _openSupplyGap(address(vaultThree), 2 * RATE_PRECISION);
        _openBorrowGap(address(vaultThree), 2 * RATE_PRECISION);

        uint256 aliceBefore_ = alice.balance;

        _revertNativeOperate();

        vm.prank(alice);
        vaultThree.rebalance{ value: 10 ether }();

        assertEq(alice.balance, aliceBefore_, "caller ETH not fully refunded after failed supply leg");
        assertEq(address(vaultThree).balance, 0, "ETH stranded in vault after failed supply leg");
    }

    /// @notice on a native-borrow vault the payback leg is the only one that moves here, so when it reverts the
    /// whole call reverts and the caller's ETH is returned by the revert itself rather than left in the vault.
    function test_rebalance_NativePaybackLegRevertLeavesNoEthBehind() public {
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultFour)).updateBorrowRateMagnifier(RATE_PRECISION / 2);
        vm.warp(block.timestamp + 365 days);

        uint256 aliceBefore_ = alice.balance;

        _revertNativeOperate();

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NothingToRebalance));
        vm.prank(alice);
        vaultFour.rebalance{ value: 10 ether }();

        assertEq(alice.balance, aliceBefore_, "caller ETH not returned after failed payback leg");
        assertEq(address(vaultFour).balance, 0, "ETH stranded in vault after failed payback leg");
    }

    /// @notice the case a per-catch refund would miss entirely: the supply side is balanced so no native leg
    /// runs at all, but `msg.value` is still accepted because the supply token is native.
    function test_rebalance_RefundsEthWhenNoNativeLegRuns() public {
        // only a borrow gap -> the DAI borrow leg runs, the native supply leg does not
        _openBorrowGap(address(vaultThree), 2 * RATE_PRECISION);

        uint256 aliceBefore_ = alice.balance;

        vm.prank(alice);
        vaultThree.rebalance{ value: 3 ether }();

        assertEq(alice.balance, aliceBefore_, "caller ETH not refunded when no native leg ran");
        assertEq(address(vaultThree).balance, 0, "ETH stranded in vault when no native leg ran");
    }

    /// @notice a successful native rebalance keeps only what it actually deposited.
    function test_rebalance_ConsumesOnlyWhatTheSupplyLegDeposits() public {
        _openSupplyGap(address(vaultThree), 2 * RATE_PRECISION);

        uint256 aliceBefore_ = alice.balance;

        vm.prank(alice);
        (int256 supplyAmt_, ) = vaultThree.rebalance{ value: 50 ether }();

        assertGt(supplyAmt_, 0, "test setup: supply leg must have deposited");
        assertEq(aliceBefore_ - alice.balance, uint256(supplyAmt_), "consumed more than the leg deposited");
        assertEq(address(vaultThree).balance, 0, "ETH left over after a successful rebalance");
    }

    /// @notice over-funding is refunded and the rebalance still happens.
    function test_rebalance_RefundsExcessWhenOverfunded() public {
        _openSupplyGap(address(vaultThree), 2 * RATE_PRECISION);

        uint256 aliceBefore_ = alice.balance;

        vm.prank(alice);
        (int256 supplyAmt_, ) = vaultThree.rebalance{ value: 500 ether }();

        assertGt(supplyAmt_, 0, "test setup: supply leg must have deposited");
        assertLt(uint256(supplyAmt_), 500 ether, "test setup: call must be over-funded");
        assertEq(aliceBefore_ - alice.balance, uint256(supplyAmt_), "excess not refunded");
        assertEq(address(vaultThree).balance, 0, "ETH left over after an over-funded rebalance");
    }

    /// @notice nothing to do on either side still reverts rather than silently keeping the ETH.
    function test_rebalance_RevertIfNothingToRebalance() public {
        _openSupplyGap(address(vaultThree), 2 * RATE_PRECISION);

        vm.prank(alice);
        vaultThree.rebalance{ value: 50 ether }();

        // the gap is closed now, so a second call in the same block has nothing to do
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NothingToRebalance));
        vm.prank(alice);
        vaultThree.rebalance{ value: 1 ether }();
    }
}
