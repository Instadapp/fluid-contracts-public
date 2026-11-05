//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidSmartLending, Events } from "../../../../contracts/protocols/dex/smartLending/main.sol";
import { FluidSmartLendingFactory } from "../../../../contracts/protocols/dex/smartLending/factory/main.sol";
import { Error as FluidDexError } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexErrorTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { IFluidDexFactory } from "../../../../contracts/protocols/dex/interfaces/iDexFactory.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

/// @dev Exchange price accrual and the `setFeeOrReward` bounds of Smart Lending, without a fork.
contract FluidSmartLendingExchangePriceTest is Test, Events {
    address internal constant LIQUIDITY_PLACEHOLDER = address(0xBEEF);
    address internal constant DEX_FACTORY_PLACEHOLDER = address(0xDEF0);
    address internal constant SMART_LENDING_FACTORY_PLACEHOLDER = address(0xD0D0);
    address internal constant DEX_PLACEHOLDER = address(0x1111);

    address internal constant TOKEN0 = address(0xAAA0);
    address internal constant TOKEN1 = address(0xBBB1);

    uint256 internal constant DEX_ID = 7;

    uint256 internal constant YEAR = 365 days;
    uint256 internal constant FLOOR = 1e18;
    int256 internal constant MAX_REWARD = 1e6;
    int256 internal constant MAX_FEE = -2e5;

    FluidSmartLending internal smartLending;

    address internal auth = makeAddr("auth");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.mockCall(
            DEX_FACTORY_PLACEHOLDER,
            abi.encodeWithSelector(IFluidDexFactory.getDexAddress.selector, DEX_ID),
            abi.encode(DEX_PLACEHOLDER)
        );

        IFluidDexT1.ConstantViews memory cv_;
        cv_.dexId = DEX_ID;
        cv_.liquidity = LIQUIDITY_PLACEHOLDER;
        cv_.token0 = TOKEN0;
        cv_.token1 = TOKEN1;
        vm.mockCall(DEX_PLACEHOLDER, abi.encodeWithSelector(IFluidDexT1.constantsView.selector), abi.encode(cv_));

        smartLending = new FluidSmartLending(
            DEX_ID,
            LIQUIDITY_PLACEHOLDER,
            DEX_FACTORY_PLACEHOLDER,
            SMART_LENDING_FACTORY_PLACEHOLDER
        );

        _mockAuth(auth, true);
        _mockAuth(stranger, false);
    }

    function test_setFeeOrReward_AcceptsMaxReward() public {
        vm.expectEmit(true, true, true, true, address(smartLending));
        emit LogFeeOrRewardSet(MAX_REWARD);

        _setFeeOrReward(MAX_REWARD);

        assertEq(smartLending.feeOrReward(), MAX_REWARD);
    }

    function test_setFeeOrReward_RevertIfAboveMaxReward() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__OutOfRange
            )
        );
        _setFeeOrReward(MAX_REWARD + 1);
    }

    function test_setFeeOrReward_AcceptsMaxFee() public {
        vm.expectEmit(true, true, true, true, address(smartLending));
        emit LogFeeOrRewardSet(MAX_FEE);

        _setFeeOrReward(MAX_FEE);

        assertEq(smartLending.feeOrReward(), MAX_FEE);
    }

    function test_setFeeOrReward_RevertIfBelowMaxFee() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__OutOfRange
            )
        );
        _setFeeOrReward(MAX_FEE - 1);
    }

    function test_setFeeOrReward_RevertIfNotAuth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexError.FluidSmartLendingError.selector,
                FluidDexErrorTypes.SmartLending__Unauthorized
            )
        );
        vm.prank(stranger);
        smartLending.setFeeOrReward(1e4);
    }

    function testFuzz_setFeeOrReward_AcceptsExactlyTheBoundedRange(int256 feeOrReward_) public {
        feeOrReward_ = bound(feeOrReward_, 3 * MAX_FEE, 2 * MAX_REWARD);

        if (feeOrReward_ < MAX_FEE || feeOrReward_ > MAX_REWARD) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    FluidDexError.FluidSmartLendingError.selector,
                    FluidDexErrorTypes.SmartLending__OutOfRange
                )
            );
            _setFeeOrReward(feeOrReward_);
        } else {
            _setFeeOrReward(feeOrReward_);
            assertEq(smartLending.feeOrReward(), feeOrReward_);
        }
    }

    function test_updateExchangePrice_RewardRaisesPrice() public {
        _setFeeOrReward(MAX_REWARD);
        vm.warp(block.timestamp + YEAR / 2);

        assertEq(_accrue(), 1.5e18);
    }

    function test_setFeeOrReward_AccruesPreviousRateBeforeSwitching() public {
        _setFeeOrReward(1e5);
        vm.warp(block.timestamp + YEAR);

        _setFeeOrReward(MAX_FEE);

        assertEq(_price(), 1.1e18);
        assertEq(uint256(smartLending.lastTimestamp()), block.timestamp);
    }

    function test_updateExchangePrice_FreshInstanceAtMaxFeeStaysAtFloor() public {
        _setFeeOrReward(MAX_FEE);
        // six years at -20% accrue 120% of the price, more than the price itself
        vm.warp(block.timestamp + 6 * YEAR);

        assertEq(_accrue(), FLOOR);
    }

    function testFuzz_updateExchangePrice_FreshInstanceFeeStaysAtFloor(uint256 fee_, uint256 elapsed_) public {
        fee_ = bound(fee_, 1, uint256(-MAX_FEE));
        elapsed_ = bound(elapsed_, 0, 100 * YEAR);

        _setFeeOrReward(-int256(fee_));
        vm.warp(block.timestamp + elapsed_);

        assertEq(_accrue(), FLOOR);
    }

    function test_updateExchangePrice_FeeClawsBackRewardExactly() public {
        _setFeeOrReward(1e5);
        vm.warp(block.timestamp + YEAR);
        _setFeeOrReward(MAX_FEE);
        uint256 lifted_ = _price();
        assertEq(lifted_, 1.1e18);

        uint256 elapsed_ = YEAR / 4;
        vm.warp(block.timestamp + elapsed_);

        uint256 expected_ = _feePrice(lifted_, uint256(-MAX_FEE), elapsed_);
        assertEq(expected_, 1.045e18);
        assertEq(_accrue(), expected_);
    }

    function test_updateExchangePrice_FeeIsChargedOncePerWindow() public {
        _setFeeOrReward(1e5);
        vm.warp(block.timestamp + YEAR);
        _setFeeOrReward(MAX_FEE);

        vm.warp(block.timestamp + YEAR / 10);
        assertEq(_accrue(), 1.078e18);

        vm.warp(block.timestamp + YEAR / 10);
        assertEq(_accrue(), 1.05644e18);
    }

    function test_updateExchangePrice_FeeBeyondRewardClampsToFloor() public {
        _setFeeOrReward(1e5);
        vm.warp(block.timestamp + YEAR);
        _setFeeOrReward(MAX_FEE);

        vm.warp(block.timestamp + YEAR);
        assertEq(_accrue(), FLOOR);

        vm.warp(block.timestamp + YEAR);
        assertEq(_accrue(), FLOOR);
    }

    function test_updateExchangePrice_FeeOneWeiAboveExcessClampsToFloor() public {
        uint256 price_ = 1.25e18 - 2;

        (uint256 feeAmount_, uint256 newPrice_) = _accrueMaxFeeForOneYearFrom(price_);

        assertEq(feeAmount_, price_ - FLOOR + 1);
        assertEq(newPrice_, FLOOR);
    }

    function test_updateExchangePrice_FeeEqualToExcessLandsOnFloor() public {
        uint256 price_ = 1.25e18;

        (uint256 feeAmount_, uint256 newPrice_) = _accrueMaxFeeForOneYearFrom(price_);

        assertEq(feeAmount_, price_ - FLOOR);
        assertEq(newPrice_, FLOOR);
    }

    function test_updateExchangePrice_FeeOneWeiBelowExcessStaysAboveFloor() public {
        uint256 price_ = 1.25e18 + 1;

        (uint256 feeAmount_, uint256 newPrice_) = _accrueMaxFeeForOneYearFrom(price_);

        assertEq(feeAmount_, price_ - FLOOR - 1);
        assertEq(newPrice_, FLOOR + 1);
    }

    function test_setFeeOrReward_SucceedsAfterFeeOvershotFloor() public {
        _setFeeOrReward(MAX_FEE);
        vm.warp(block.timestamp + 6 * YEAR);

        _setFeeOrReward(MAX_REWARD);

        assertEq(_price(), FLOOR);
        assertEq(smartLending.feeOrReward(), MAX_REWARD);

        vm.warp(block.timestamp + YEAR);
        assertEq(_accrue(), 2e18);
    }

    function testFuzz_updateExchangePrice_RewardThenFeeMatchesFormulaAndStaysAboveFloor(
        uint256 reward_,
        uint256 rewardPeriod_,
        uint256 fee_,
        uint256 feePeriod_
    ) public {
        reward_ = bound(reward_, 0, uint256(MAX_REWARD));
        rewardPeriod_ = bound(rewardPeriod_, 0, 10 * YEAR);
        fee_ = bound(fee_, 0, uint256(-MAX_FEE));
        feePeriod_ = bound(feePeriod_, 0, 30 * YEAR);

        _setFeeOrReward(int256(reward_));
        vm.warp(block.timestamp + rewardPeriod_);
        _setFeeOrReward(-int256(fee_));

        uint256 lifted_ = FLOOR + _accruedAmount(FLOOR, reward_, rewardPeriod_);
        assertEq(_price(), lifted_);

        vm.warp(block.timestamp + feePeriod_);

        uint256 price_ = _accrue();
        assertEq(price_, _feePrice(lifted_, fee_, feePeriod_));
        assertGe(price_, FLOOR);
    }

    function _mockAuth(address caller_, bool isAuth_) internal {
        vm.mockCall(
            SMART_LENDING_FACTORY_PLACEHOLDER,
            abi.encodeWithSelector(
                FluidSmartLendingFactory.isSmartLendingAuth.selector,
                address(smartLending),
                caller_
            ),
            abi.encode(isAuth_)
        );
    }

    function _setFeeOrReward(int256 feeOrReward_) internal {
        vm.prank(auth);
        smartLending.setFeeOrReward(feeOrReward_);
    }

    function _price() internal view returns (uint256) {
        return smartLending.exchangePrice();
    }

    /// @dev Persists the accrual and returns the stored price after checking the view quoted the same value.
    function _accrue() internal returns (uint256 price_) {
        (uint184 quoted_, ) = smartLending.getUpdateExchangePrice();
        smartLending.updateExchangePrice();
        price_ = _price();
        assertEq(price_, uint256(quoted_), "view must quote the price that gets persisted");
    }

    /// @dev Linear accrual of `rate_` (1e6 = 100% per year) over `elapsed_` seconds, as in `getUpdateExchangePrice`.
    function _accruedAmount(uint256 price_, uint256 rate_, uint256 elapsed_) internal pure returns (uint256) {
        return (price_ * rate_ * elapsed_) / (1e6 * YEAR);
    }

    /// @dev max(1e18, price_ - fee) with the fee accrued over `elapsed_` seconds.
    function _feePrice(uint256 price_, uint256 fee_, uint256 elapsed_) internal pure returns (uint256) {
        uint256 feeAmount_ = _accruedAmount(price_, fee_, elapsed_);
        uint256 reduced_ = price_ > feeAmount_ ? price_ - feeAmount_ : 0;
        return reduced_ > FLOOR ? reduced_ : FLOOR;
    }

    /// @dev Writes `exchangePrice` into slot 5, packed above `lastTimestamp` and `feeOrReward` (layout pinned by
    ///      smartLendingStorageLayout.t.sol). Accrual from 1e18 cannot reach prices that sit one wei off a boundary.
    function _seedExchangePrice(uint256 price_) internal {
        bytes32 slot_ = bytes32(uint256(5));
        uint256 packed_ = uint256(vm.load(address(smartLending), slot_));
        packed_ = (packed_ & ((1 << 72) - 1)) | (price_ << 72);
        vm.store(address(smartLending), slot_, bytes32(packed_));
        assertEq(_price(), price_);
    }

    /// @dev One year at -20% accrues `price_ / 5` rounded down, and 1.25e18 is where that equals `price_ - 1e18`,
    ///      so the seeded price picks which side of the floor the fee lands on.
    function _accrueMaxFeeForOneYearFrom(uint256 price_) internal returns (uint256 feeAmount_, uint256 newPrice_) {
        _seedExchangePrice(price_);
        _setFeeOrReward(MAX_FEE);
        vm.warp(block.timestamp + YEAR);

        feeAmount_ = _accruedAmount(price_, uint256(-MAX_FEE), YEAR);
        newPrice_ = _accrue();
    }
}
