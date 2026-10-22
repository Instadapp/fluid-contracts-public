// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidWithdrawLimitAuth } from "../../../contracts/config/withdrawLimitAuth/main.sol";
import { FluidWithdrawLimitAuthDex } from "../../../contracts/config/withdrawLimitAuthDex/main.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { DexSlotsLink } from "../../../contracts/libraries/dexSlotsLink.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";

contract MockReserveWithRebalancer {
    address internal immutable REBALANCER;

    constructor(address rebalancer_) {
        REBALANCER = rebalancer_;
    }

    function isRebalancer(address account_) external view returns (bool) {
        return account_ == REBALANCER;
    }
}

contract MockDexWithdrawLimit {
    mapping(bytes32 => uint256) internal slots;

    address public lastUser;
    uint256 public lastLimit;

    function setSlot(bytes32 slot_, uint256 value_) external {
        slots[slot_] = value_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return slots[slot_];
    }

    function updateUserWithdrawalLimit(address user_, uint256 newLimit_) external {
        lastUser = user_;
        lastLimit = newLimit_;
    }
}

contract WithdrawLimitAuthHistoryTest is LiquidityBaseTest {
    address internal rebalancer = makeAddr("rebalancer");
    address internal multisig = makeAddr("multisig");

    FluidWithdrawLimitAuth internal handler;

    uint256 internal constant SUPPLY = 1_000_000 ether;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(2 days);

        handler = new FluidWithdrawLimitAuth(
            IFluidReserveContract(address(new MockReserveWithRebalancer(rebalancer))),
            address(liquidity),
            multisig
        );
        _setAsAuth(address(liquidity), admin, address(handler));

        // the base setUp already configures this user for USDC with a base limit far below SUPPLY
        _supply(address(liquidity), mockProtocolWithInterest, address(USDC), alice, SUPPLY);
    }

    function test_rebalanceWithdrawalLimit_OversizedLimitRecordsUserSupply() public {
        (uint256 supply_, ) = _supplyAndLimit();

        _rebalance(uint256(1) << 128);

        (, , uint256 leastDailyUserSupply_) = _history();
        assertGt(leastDailyUserSupply_, 0);
        assertEq(leastDailyUserSupply_, supply_);
    }

    function test_rebalanceWithdrawalLimit_MaxLimitRecordsUserSupply() public {
        (uint256 supply_, ) = _supplyAndLimit();

        _rebalance(type(uint256).max);

        (, , uint256 leastDailyUserSupply_) = _history();
        assertGt(leastDailyUserSupply_, 0);
        assertEq(leastDailyUserSupply_, supply_);
    }

    function test_rebalanceWithdrawalLimit_RevertIfHourlyLimitReachedAfterOversizedLimit() public {
        _rebalance(uint256(1) << 128);
        (uint256 in1Hour_, uint256 in24Hours_, ) = _history();
        assertEq(in1Hour_, 1);
        assertEq(in24Hours_, 1);

        (, uint256 limit_) = _supplyAndLimit();
        _rebalance((limit_ * 95) / 100);
        (in1Hour_, in24Hours_, ) = _history();
        assertEq(in1Hour_, 2);
        assertEq(in24Hours_, 2);

        (, limit_) = _supplyAndLimit();
        uint256 nextLimit_ = (limit_ * 95) / 100;
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__HourlyLimitReached)
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocolWithInterest), address(USDC), nextLimit_);
    }

    function test_rebalanceWithdrawalLimit_InRangeLimitRecordedAsIs() public {
        (uint256 supply_, uint256 limit_) = _supplyAndLimit();
        uint256 newLimit_ = (limit_ + supply_) / 2;
        assertGe(newLimit_, (limit_ * 95) / 100);
        assertLt(newLimit_, supply_);

        _rebalance(newLimit_);

        (, , uint256 leastDailyUserSupply_) = _history();
        assertEq(leastDailyUserSupply_, newLimit_);
    }

    function _rebalance(uint256 newLimit_) internal {
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocolWithInterest), address(USDC), newLimit_);
    }

    function _supplyAndLimit() internal view returns (uint256 supply_, uint256 limit_) {
        address[] memory users_ = new address[](1);
        users_[0] = address(mockProtocolWithInterest);
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        (uint256[] memory supplies_, uint256[] memory limits_) = handler.getUsersData(users_, tokens_);
        return (supplies_[0], limits_[0]);
    }

    function _history() internal view returns (uint256 in1Hour_, uint256 in24Hours_, uint256 leastDailyUserSupply_) {
        (, , uint8 rebalancesIn1Hour_, uint8 rebalancesIn24Hours_, uint160 least_) = handler.userData(
            address(mockProtocolWithInterest),
            address(USDC)
        );
        return (rebalancesIn1Hour_, rebalancesIn24Hours_, least_);
    }
}

contract WithdrawLimitAuthDexHistoryTest is Test {
    address internal rebalancer = makeAddr("rebalancer");
    address internal multisig = makeAddr("multisig");
    address internal user = makeAddr("dexUser");

    MockDexWithdrawLimit internal dex;
    FluidWithdrawLimitAuthDex internal handler;

    uint256 internal constant SUPPLY = 1_000_000 ether;
    uint256 internal constant EXPAND_PERCENT = 2000; // 20% in 4 decimals
    uint256 internal constant EXPAND_DURATION = 2 days;

    uint256 internal supplyAfterBigMath;

    function setUp() public virtual {
        vm.warp(2 days);

        dex = new MockDexWithdrawLimit();
        handler = new FluidWithdrawLimitAuthDex(
            IFluidReserveContract(address(new MockReserveWithRebalancer(rebalancer))),
            multisig
        );

        uint256 supplyBigNumber_ = BigMathMinified.toBigNumber(SUPPLY, 56, 8, BigMathMinified.ROUND_DOWN);
        supplyAfterBigMath = BigMathMinified.fromBigNumber(supplyBigNumber_, 8, 0xFF);

        // previous withdrawal limit stays 0, so the current limit is 0 and the 5% guard never binds
        dex.setSlot(
            DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user),
            (supplyBigNumber_ << DexSlotsLink.BITS_USER_SUPPLY_AMOUNT) |
                (EXPAND_PERCENT << DexSlotsLink.BITS_USER_SUPPLY_EXPAND_PERCENT) |
                (EXPAND_DURATION << DexSlotsLink.BITS_USER_SUPPLY_EXPAND_DURATION)
        );
    }

    function test_rebalanceWithdrawalLimit_OversizedLimitRecordsUserSupply() public {
        uint256 oversized_ = uint256(1) << 128;

        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(dex), user, oversized_);

        (, , , , uint160 leastDailyUserSupply_) = handler.userData(user);
        assertGt(uint256(leastDailyUserSupply_), 0);
        assertEq(uint256(leastDailyUserSupply_), supplyAfterBigMath);
        assertEq(dex.lastUser(), user);
        assertEq(dex.lastLimit(), oversized_);
    }

    function test_rebalanceWithdrawalLimit_RevertIfHourlyLimitReachedAfterOversizedLimit() public {
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(dex), user, uint256(1) << 128);

        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(dex), user, (supplyAfterBigMath * 95) / 100);

        (, , uint8 rebalancesIn1Hour_, uint8 rebalancesIn24Hours_, ) = handler.userData(user);
        assertEq(uint256(rebalancesIn1Hour_), 2);
        assertEq(uint256(rebalancesIn24Hours_), 2);

        uint256 nextLimit_ = (supplyAfterBigMath * 90) / 100;
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__HourlyLimitReached)
        );
        handler.rebalanceWithdrawalLimit(address(dex), user, nextLimit_);
    }
}
