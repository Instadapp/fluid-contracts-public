//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexAdminStructs } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { DexSlotsLink } from "../../../../contracts/libraries/dexSlotsLink.sol";

import { PoolT1BaseTest } from "./pool.t.sol";

/// @dev Guards of `initialize()` and `updateFeeAndRevenueCut()` on DEXes that are deployed but not initialized yet.
/// Fee is in 1e6 = 100% (capped at 10% on its own), revenue cut is passed in 4 decimals and stored as a whole percent,
/// so `fee * cutPercent` is what the product bound limits.
contract PoolT1InitializeGuardsTest is PoolT1BaseTest {
    uint256 internal constant MAX_FEE_REVENUE_PRODUCT = 990_000;

    // 1e4 per percent
    uint256 internal constant CUT_UNIT = 1e4;

    function _deployFreshDex() internal returns (FluidDexT1 dex_) {
        bytes memory creationCode_ = abi.encodeCall(
            poolT1DeploymentLogic.dexT1,
            (DAI_USDC.token0, DAI_USDC.token1, 1e4)
        );
        vm.prank(alice);
        dex_ = FluidDexT1(payable(dexFactory.deployDex(address(poolT1DeploymentLogic), creationCode_)));

        _setApproval(IERC20(DAI_USDC.token0), address(dex_), alice);
        _setApproval(IERC20(DAI_USDC.token1), address(dex_), alice);
        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), admin, DAI_USDC.token0, address(dex_), true);
        _setUserAllowancesDefaultWithModeWithHighLimit(address(liquidity), admin, DAI_USDC.token1, address(dex_), true);
    }

    function _params(
        bool smartCol_,
        bool smartDebt_
    ) internal view returns (DexAdminStructs.InitializeVariables memory i_) {
        i_ = DexAdminStructs.InitializeVariables({
            smartCol: smartCol_,
            token0ColAmt: smartCol_ ? 1e4 * DAI_USDC.token0Wei : 0,
            smartDebt: smartDebt_,
            token0DebtAmt: smartDebt_ ? 1e4 * DAI_USDC.token0Wei : 0,
            centerPrice: 1e27,
            fee: 0,
            revenueCut: 0,
            upperPercent: 10 * 1e4,
            lowerPercent: 10 * 1e4,
            upperShiftThreshold: 5 * 1e4,
            lowerShiftThreshold: 5 * 1e4,
            thresholdShiftTime: 1 days,
            centerPriceAddress: 0,
            hookAddress: 0,
            maxCenterPrice: 1.2e27,
            minCenterPrice: 0.8e27
        });
    }

    function _initialize(FluidDexT1 dex_, DexAdminStructs.InitializeVariables memory i_) internal {
        vm.prank(alice);
        FluidDexT1Admin(address(dex_)).initialize(i_);
    }

    function _initializeFresh(uint256 fee_, uint256 cutPercent_) internal returns (FluidDexT1 dex_) {
        dex_ = _deployFreshDex();
        DexAdminStructs.InitializeVariables memory i_ = _params(true, false);
        i_.fee = fee_;
        i_.revenueCut = cutPercent_ * CUT_UNIT;
        _initialize(dex_, i_);
    }

    function _updateFeeAndRevenueCut(FluidDexT1 dex_, uint256 fee_, uint256 cutPercent_) internal {
        vm.prank(alice);
        FluidDexT1Admin(address(dex_)).updateFeeAndRevenueCut(fee_, cutPercent_ * CUT_UNIT);
    }

    function _expectDexError(uint256 errorId_) internal {
        vm.expectRevert(abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, errorId_));
    }

    function _assertInitializeRevertsConfigOverflow(uint256 fee_, uint256 cutPercent_) internal {
        FluidDexT1 dex_ = _deployFreshDex();
        DexAdminStructs.InitializeVariables memory i_ = _params(true, false);
        i_.fee = fee_;
        i_.revenueCut = cutPercent_ * CUT_UNIT;

        _expectDexError(FluidDexTypes.DexT1Admin__ConfigOverflow);
        _initialize(dex_, i_);
    }

    function _assertUpdateRevertsConfigOverflow(FluidDexT1 dex_, uint256 fee_, uint256 cutPercent_) internal {
        _expectDexError(FluidDexTypes.DexT1Admin__ConfigOverflow);
        _updateFeeAndRevenueCut(dex_, fee_, cutPercent_);
    }

    function _storeSupplyShares(FluidDexT1 dex_, uint256 slotValue_) internal {
        vm.store(address(dex_), bytes32(DexSlotsLink.DEX_TOTAL_SUPPLY_SHARES_SLOT), bytes32(slotValue_));
    }

    function _storeBorrowShares(FluidDexT1 dex_, uint256 slotValue_) internal {
        vm.store(address(dex_), bytes32(DexSlotsLink.DEX_TOTAL_BORROW_SHARES_SLOT), bytes32(slotValue_));
    }

    function _assertStoredFeeAndCut(FluidDexT1 dex_, uint256 fee_, uint256 cutPercent_) internal {
        assertEq(_getDexVariables2Data(dex_).fee, fee_, "fee is not as expected");
        assertEq(_getDexVariables2Data(dex_).revenueCut, cutPercent_, "revenue cut is not as expected");
    }

    function test_initialize_AcceptsFeeRevenueProductAtBound() public {
        // 9.9% fee with 10% cut, then 0.99% fee with the maximum 100% cut
        FluidDexT1 highFee_ = _initializeFresh(99_000, 10);
        FluidDexT1 fullCut_ = _initializeFresh(9_900, 100);

        assertEq(99_000 * 10, MAX_FEE_REVENUE_PRODUCT, "test setup sanity: product must sit on the bound");
        assertEq(9_900 * 100, MAX_FEE_REVENUE_PRODUCT, "test setup sanity: product must sit on the bound");
        _assertStoredFeeAndCut(highFee_, 99_000, 10);
        _assertStoredFeeAndCut(fullCut_, 9_900, 100);
    }

    function test_initialize_RevertIfFeeRevenueProductAboveBound() public {
        _assertInitializeRevertsConfigOverflow(99_001, 10);
        _assertInitializeRevertsConfigOverflow(9_901, 100);
        // no fee lands exactly on the bound with a 13% cut, this is the closest product above it
        _assertInitializeRevertsConfigOverflow(76_154, 13);
    }

    function testFuzz_initialize_FeeRevenueProductBoundIsInclusive(uint256 cutPercent_) public {
        // below 10% cut the largest fee under the bound is above the 10% fee cap, so another guard would answer
        cutPercent_ = bound(cutPercent_, 10, 100);
        uint256 maxFee_ = MAX_FEE_REVENUE_PRODUCT / cutPercent_;

        FluidDexT1 dex_ = _initializeFresh(maxFee_, cutPercent_);
        _assertStoredFeeAndCut(dex_, maxFee_, cutPercent_);

        _assertInitializeRevertsConfigOverflow(maxFee_ + 1, cutPercent_);
    }

    function test_updateFeeAndRevenueCut_AcceptsFeeRevenueProductAtBound() public {
        FluidDexT1 dex_ = DAI_USDC.dexCol;

        _updateFeeAndRevenueCut(dex_, 99_000, 10);
        _assertStoredFeeAndCut(dex_, 99_000, 10);

        _updateFeeAndRevenueCut(dex_, 9_900, 100);
        _assertStoredFeeAndCut(dex_, 9_900, 100);
    }

    function test_updateFeeAndRevenueCut_RevertIfFeeRevenueProductAboveBound() public {
        FluidDexT1 dex_ = DAI_USDC.dexCol;

        _assertUpdateRevertsConfigOverflow(dex_, 99_001, 10);
        _assertUpdateRevertsConfigOverflow(dex_, 9_901, 100);
        // no fee lands exactly on the bound with a 13% cut, this is the closest product above it
        _assertUpdateRevertsConfigOverflow(dex_, 76_154, 13);
    }

    function testFuzz_updateFeeAndRevenueCut_FeeRevenueProductBoundIsInclusive(uint256 cutPercent_) public {
        // below 10% cut the largest fee under the bound is above the 10% fee cap, so another guard would answer
        cutPercent_ = bound(cutPercent_, 10, 100);
        uint256 maxFee_ = MAX_FEE_REVENUE_PRODUCT / cutPercent_;
        FluidDexT1 dex_ = DAI_USDC.dexCol;

        _updateFeeAndRevenueCut(dex_, maxFee_, cutPercent_);
        _assertStoredFeeAndCut(dex_, maxFee_, cutPercent_);

        _assertUpdateRevertsConfigOverflow(dex_, maxFee_ + 1, cutPercent_);
    }

    function test_initialize_InitializesWhenAllGuardsClear() public {
        FluidDexT1 dex_ = _deployFreshDex();
        assertEq(getDexType(dex_), 0, "test setup sanity: smart col and debt bits must be clear");
        assertEq(getTotalSupplyShares(dex_), 0, "test setup sanity: supply shares must be clear");
        assertEq(getTotalBorrowShares(dex_), 0, "test setup sanity: borrow shares must be clear");

        _initialize(dex_, _params(true, true));

        assertEq(getDexType(dex_), 3, "smart col and debt bits are not set");
        assertGt(getTotalSupplyShares(dex_), 0, "supply shares are not set");
        assertGt(getTotalBorrowShares(dex_), 0, "borrow shares are not set");
    }

    function test_initialize_RevertIfSmartColBitSet() public {
        FluidDexT1 dex_ = _deployFreshDex();
        _initialize(dex_, _params(true, false));
        // leaves the bit as the only thing that marks the DEX as initialized
        _storeSupplyShares(dex_, 0);
        _storeBorrowShares(dex_, 0);
        assertEq(getDexType(dex_), 1, "test setup sanity: only the smart col bit must be set");
        assertEq(getTotalSupplyShares(dex_), 0, "test setup sanity: supply shares must be clear");
        assertEq(getTotalBorrowShares(dex_), 0, "test setup sanity: borrow shares must be clear");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }

    function test_initialize_RevertIfSmartDebtBitSet() public {
        FluidDexT1 dex_ = _deployFreshDex();
        _initialize(dex_, _params(false, true));
        _storeSupplyShares(dex_, 0);
        _storeBorrowShares(dex_, 0);
        assertEq(getDexType(dex_), 2, "test setup sanity: only the smart debt bit must be set");
        assertEq(getTotalSupplyShares(dex_), 0, "test setup sanity: supply shares must be clear");
        assertEq(getTotalBorrowShares(dex_), 0, "test setup sanity: borrow shares must be clear");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }

    function test_initialize_RevertIfOnlySupplySharesSet() public {
        FluidDexT1 dex_ = _deployFreshDex();
        _storeSupplyShares(dex_, 1);
        assertEq(getDexType(dex_), 0, "test setup sanity: smart col and debt bits must be clear");
        assertEq(getTotalSupplyShares(dex_), 1, "test setup sanity: supply shares must be set");
        assertEq(getTotalBorrowShares(dex_), 0, "test setup sanity: borrow shares must be clear");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }

    function test_initialize_RevertIfOnlyBorrowSharesSet() public {
        FluidDexT1 dex_ = _deployFreshDex();
        _storeBorrowShares(dex_, 1);
        assertEq(getDexType(dex_), 0, "test setup sanity: smart col and debt bits must be clear");
        assertEq(getTotalSupplyShares(dex_), 0, "test setup sanity: supply shares must be clear");
        assertEq(getTotalBorrowShares(dex_), 1, "test setup sanity: borrow shares must be set");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }

    function testFuzz_initialize_RevertIfSupplySharesNonZero(uint256 shares_, uint256 maxShares_) public {
        shares_ = bound(shares_, 1, X128);
        maxShares_ = bound(maxShares_, 0, X128);
        FluidDexT1 dex_ = _deployFreshDex();
        _storeSupplyShares(dex_, (maxShares_ << 128) | shares_);
        assertEq(getTotalSupplyShares(dex_), shares_, "test setup sanity: supply shares must be set");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }

    function testFuzz_initialize_RevertIfBorrowSharesNonZero(uint256 shares_, uint256 maxShares_) public {
        shares_ = bound(shares_, 1, X128);
        maxShares_ = bound(maxShares_, 0, X128);
        FluidDexT1 dex_ = _deployFreshDex();
        _storeBorrowShares(dex_, (maxShares_ << 128) | shares_);
        assertEq(getTotalBorrowShares(dex_), shares_, "test setup sanity: borrow shares must be set");

        _expectDexError(FluidDexTypes.DexT1Admin__AlreadyInitialized);
        _initialize(dex_, _params(true, false));
    }
}
