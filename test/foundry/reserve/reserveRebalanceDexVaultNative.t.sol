// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidReserveContract } from "../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../contracts/reserve/proxy.sol";

/// @dev Mock dex vault: retains native ETH sent on `rebalance` and signals a deposit leg so allowance debit runs.
contract MockDexVaultRebalance {
    function rebalance(
        int256,
        int256,
        int256,
        int256
    ) external payable returns (int256 colAmount_, int256 debtAmount_) {
        colAmount_ = 1;
        debtAmount_ = 0;
    }
}

/// @dev Rebalancer-attached msg.value is excluded from native allowance debit.
contract ReserveContractTestRebalanceDexVaultNative is Test {
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    FluidReserveContract internal reserve;
    MockDexVaultRebalance internal vault0;

    address internal owner = address(0x1001);
    address internal auth = address(0x1002);
    address internal rebalancer = address(0x1003);

    uint256 internal constant RESERVE_ETH = 10 ether;
    uint256 internal constant ALLOWANCE = 2 ether;
    uint256 internal constant REBALANCE_VALUE = 1 ether;

    function setUp() public {
        FluidReserveContract impl = new FluidReserveContract(address(0), address(0));
        reserve = FluidReserveContract(payable(new FluidReserveContractProxy(address(impl), new bytes(0))));

        address[] memory auths_ = new address[](1);
        auths_[0] = auth;
        address[] memory rebalancers_ = new address[](1);
        rebalancers_[0] = rebalancer;
        reserve.initialize(auths_, rebalancers_, owner);

        vault0 = new MockDexVaultRebalance();

        vm.deal(address(reserve), RESERVE_ETH);
        vm.deal(rebalancer, RESERVE_ETH);

        address[] memory protocols_ = new address[](1);
        protocols_[0] = address(vault0);
        address[] memory tokens_ = new address[](1);
        tokens_[0] = NATIVE_TOKEN;
        uint256[] memory amounts_ = new uint256[](1);
        amounts_[0] = ALLOWANCE;

        vm.prank(auth);
        reserve.approve(protocols_, tokens_, amounts_);
    }

    function test_rebalanceDexVault_MsgValueExcludedFromAllowanceDebit() public {
        uint256 allowanceBefore_ = reserve.nativeTokenAllowances(address(vault0));

        vm.prank(rebalancer);
        reserve.rebalanceDexVault{ value: REBALANCE_VALUE }(address(vault0), REBALANCE_VALUE, 0, 0, 0, 0);

        assertEq(
            reserve.nativeTokenAllowances(address(vault0)),
            allowanceBefore_,
            "rebalancer msg.value is not debited from allowance"
        );
        assertEq(address(vault0).balance, REBALANCE_VALUE, "vault received value_");
    }

    function test_rebalanceDexVault_ReserveBalanceDebitedFromAllowance() public {
        uint256 allowanceBefore_ = reserve.nativeTokenAllowances(address(vault0));
        uint256 reserveBalanceBefore_ = address(reserve).balance;

        vm.prank(rebalancer);
        reserve.rebalanceDexVault(address(vault0), REBALANCE_VALUE, 0, 0, 0, 0);

        assertEq(
            reserve.nativeTokenAllowances(address(vault0)),
            allowanceBefore_ - REBALANCE_VALUE,
            "reserve-owned spend debited from allowance"
        );
        assertEq(address(reserve).balance, reserveBalanceBefore_ - REBALANCE_VALUE, "reserve balance reduced");
    }
}
