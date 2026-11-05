//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultT1BaseTest } from "./vault.t.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { Structs as VaultStructs } from "../../../../contracts/periphery/resolvers/vault/structs.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { Error as VaultError } from "../../../../contracts/protocols/vault/error.sol";
import { ErrorTypes as VaultErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";

/// @notice A liquidation can leave a position with a net debt below MIN_DEBT. It stays with its owner: a max payback
///         and max withdraw close it, a payback from anyone only clears its debt, and any call that would leave it
///         in the band reverts.
contract VaultT1DustPositionsTest is VaultT1BaseTest {
    using BigMathMinified for uint256;

    int256 internal constant MIN_OPERATE = 1e4;
    uint256 internal constant MIN_DEBT = 1e4;
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant POSITION_DATA_SLOT = 3;

    function _setupAccruedDustPositions() internal returns (uint256[] memory nftIds_) {
        (nftIds_, , ) = _setupDustPositionsAfterLiquidation();
        vm.warp(block.timestamp + 1 days);

        (, uint256 liquidityBorrowExPrice_, , ) = vaultOne.updateExchangePrices(
            uint256(vaultOne.readFromStorage(bytes32(uint256(1))))
        );
        assertGt(liquidityBorrowExPrice_, 1e12, "precondition: interest accrued at Liquidity");
    }

    /// @dev A regular position liquidated right after the dust ones, so its net debt stays far above MIN_DEBT.
    function _setupLiquidatedPosition() internal returns (uint256 nftId_) {
        _setupDustPositionsAfterLiquidation();
        uint256 oraclePrice_ = oracleOne.price();

        vm.prank(alice);
        (nftId_, , ) = vaultOne.operate(0, 1e8, 1e8, alice);

        _setOracleOnePrice(oraclePrice_ / 63e11);
        VaultStructs.LiquidationStruct memory liquidationData_ = vaultResolver.getVaultLiquidation(
            address(vaultOne),
            0
        );
        vm.prank(bob);
        vaultOne.liquidate(liquidationData_.inAmt - 10, 0, address(bob), false);
        _setOracleOnePrice(oraclePrice_);
    }

    function _absorbedLiquidity() internal view returns (uint256) {
        return vaultResolver.getAbsorbedLiquidityRaw(address(vaultOne));
    }

    function _vaultExchangePrices() internal view returns (uint256 supplyExPrice_, uint256 borrowExPrice_) {
        (, , supplyExPrice_, borrowExPrice_) = vaultOne.updateExchangePrices(
            vaultResolver.getVaultVariables2Raw(address(vaultOne))
        );
    }

    function _positionDataSlot(uint256 nftId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(nftId_, POSITION_DATA_SLOT));
    }

    function _storedCol(uint256 nftId_) internal view returns (uint256 colRaw_) {
        uint256 colBigNumber_ = (uint256(vm.load(address(vaultOne), _positionDataSlot(nftId_))) >> 45) & X64;
        colRaw_ = (colBigNumber_ >> 8) << (colBigNumber_ & X8);
    }

    /// @dev Overwrites the position's stored dust debt (bits 109-172). Returns the value that was stored, which
    ///      differs from `dustRaw_` once it no longer fits the 56 bit coefficient.
    function _setStoredDust(uint256 nftId_, uint256 dustRaw_) internal returns (uint256 stored_) {
        bytes32 slot_ = _positionDataSlot(nftId_);
        uint256 dustBigNumber_ = dustRaw_.toBigNumber(56, 8, BigMathMinified.ROUND_DOWN);
        stored_ = (dustBigNumber_ >> 8) << (dustBigNumber_ & X8);

        uint256 positionData_ = uint256(vm.load(address(vaultOne), slot_));
        vm.store(address(vaultOne), slot_, bytes32((positionData_ & ~(X64 << 109)) | (dustBigNumber_ << 109)));
    }

    /// @dev Gross debt, collateral and dust of a liquidated position as the sync at the top of `operate` sees them.
    function _syncedPosition(
        uint256 nftId_
    ) internal view returns (uint256 grossDebtRaw_, uint256 colRaw_, uint256 dustRaw_) {
        uint256 positionData_ = vaultResolver.getPositionDataRaw(address(vaultOne), nftId_);
        int256 tick_ = (positionData_ & 2) == 2
            ? int256((positionData_ >> 2) & X19)
            : -int256((positionData_ >> 2) & X19);

        // the vault derives the pre-liquidation debt from the rounded up collateral
        uint256 colBigNumber_ = (positionData_ >> 45) & X64;
        uint256 colRoundedUp_ = (colBigNumber_ & X8) == 0
            ? (colBigNumber_ >> 8) + 1
            : ((colBigNumber_ >> 8) << (colBigNumber_ & X8)) + (1 << (colBigNumber_ & X8));
        uint256 debtRaw_ = ((TickMath.getRatioAtTick(int24(tick_)) * colRoundedUp_) >> 96) + 1;

        (, grossDebtRaw_, colRaw_, , ) = vaultOne.fetchLatestPosition(
            tick_,
            (positionData_ >> 21) & X24,
            debtRaw_,
            vaultResolver.getTickDataRaw(address(vaultOne), tick_)
        );

        uint256 dustBigNumber_ = (positionData_ >> 109) & X64;
        dustRaw_ = (dustBigNumber_ >> 8) << (dustBigNumber_ & X8);
    }

    function _dustPosition(uint256 nftId_) internal view returns (uint256 netDebtRaw_, uint256 colRaw_) {
        uint256 grossDebtRaw_;
        uint256 dustRaw_;
        (grossDebtRaw_, colRaw_, dustRaw_) = _syncedPosition(nftId_);
        netDebtRaw_ = grossDebtRaw_ - dustRaw_;
        assertGt(netDebtRaw_, 0, "precondition: the liquidation left a net debt");
        assertLt(netDebtRaw_, MIN_DEBT, "precondition: the net debt is below MIN_DEBT");
        assertGt(colRaw_, 0, "precondition: the liquidation left collateral");
    }

    function test_operate_OwnerClosesDustPositionAfterInterestAccrual() public {
        uint256[] memory nftIds_ = _setupAccruedDustPositions();
        (uint256 netDebtRaw_, uint256 colRaw_) = _dustPosition(nftIds_[0]);
        (uint256 supplyExPrice_, uint256 borrowExPrice_) = _vaultExchangePrices();
        uint256 absorbedBefore_ = _absorbedLiquidity();
        uint256 usdcBefore_ = USDC.balanceOf(alice);

        vm.prank(alice);
        (, int256 colLeg_, int256 debtLeg_) = vaultOne.operate(nftIds_[0], type(int256).min, type(int256).min, alice);

        assertEq(
            uint256(-colLeg_),
            (colRaw_ * supplyExPrice_) / EXCHANGE_PRICES_PRECISION - 1,
            "the owner withdraws the remaining collateral"
        );
        assertEq(
            uint256(-debtLeg_),
            (netDebtRaw_ * borrowExPrice_) / EXCHANGE_PRICES_PRECISION + 1,
            "the owner pays back the net debt"
        );
        assertEq(USDC.balanceOf(alice) - usdcBefore_, uint256(-colLeg_), "the collateral reaches the owner");
        assertEq(_absorbedLiquidity(), absorbedBefore_, "nothing is absorbed");
        (FluidVaultResolver.UserPosition memory position_, ) = vaultResolver.positionByNftId(nftIds_[0]);
        assertEq(position_.supply, 0, "the position is closed");
        assertEq(position_.borrow, 0, "the position is closed");
    }

    function test_operate_PaybackFromAnyoneLeavesCollateralWithOwner() public {
        uint256[] memory nftIds_ = _setupAccruedDustPositions();
        (uint256 netDebtRaw_, uint256 colRaw_) = _dustPosition(nftIds_[0]);
        (, uint256 borrowExPrice_) = _vaultExchangePrices();
        uint256 absorbedBefore_ = _absorbedLiquidity();
        _setApproval(DAI, address(vaultOne), bob);

        vm.prank(bob);
        (, , int256 debtLeg_) = vaultOne.operate(nftIds_[0], 0, type(int256).min, address(0));

        assertEq(
            uint256(-debtLeg_),
            (netDebtRaw_ * borrowExPrice_) / EXCHANGE_PRICES_PRECISION + 1,
            "the caller pays the net debt"
        );
        assertEq(_absorbedLiquidity(), absorbedBefore_, "nothing is absorbed");
        assertEq(_storedCol(nftIds_[0]), colRaw_, "the collateral stays on the position");
        assertEq(vaultFactory.ownerOf(nftIds_[0]), alice, "the owner keeps the position");
        (FluidVaultResolver.UserPosition memory position_, ) = vaultResolver.positionByNftId(nftIds_[0]);
        assertTrue(position_.isSupplyPosition, "the position holds no debt");
    }

    function test_operate_RevertIfDepositLeavesDustPosition() public {
        uint256[] memory nftIds_ = _setupAccruedDustPositions();
        _dustPosition(nftIds_[0]);

        vm.expectRevert(
            abi.encodeWithSelector(VaultError.FluidVaultError.selector, VaultErrorTypes.Vault__UserDebtTooLow)
        );
        vm.prank(bob);
        vaultOne.operate(nftIds_[0], MIN_OPERATE, 0, address(0));
    }

    function test_operate_RevertIfExplicitPaybackOnDustPosition() public {
        uint256[] memory nftIds_ = _setupAccruedDustPositions();

        vm.expectRevert(
            abi.encodeWithSelector(VaultError.FluidVaultError.selector, VaultErrorTypes.Vault__ExcessDebtPayback)
        );
        vm.prank(bob);
        vaultOne.operate(nftIds_[0], 0, -MIN_OPERATE, address(0));
    }

    function test_operate_OwnerBorrowsDustPositionBackAboveMinDebt() public {
        uint256[] memory nftIds_ = _setupAccruedDustPositions();
        (, uint256 colRaw_) = _dustPosition(nftIds_[0]);
        (uint256 supplyExPrice_, ) = _vaultExchangePrices();

        vm.prank(alice);
        vaultOne.operate(nftIds_[0], 1e6, MIN_OPERATE, alice);

        (FluidVaultResolver.UserPosition memory position_, ) = vaultResolver.positionByNftId(nftIds_[0]);
        assertFalse(position_.isSupplyPosition, "the position keeps its debt");
        assertGe(position_.borrow, MIN_DEBT, "the net debt is back above MIN_DEBT");
        assertEq(
            _storedCol(nftIds_[0]),
            colRaw_ + (1e6 * 1e12) / supplyExPrice_,
            "the deposit lands on the remaining collateral"
        );
    }

    function test_operate_KeepsPositionWhenNetDebtEqualsMinDebt() public {
        uint256 nftId_ = _setupLiquidatedPosition();
        (uint256 grossDebtRaw_, uint256 colRaw_, ) = _syncedPosition(nftId_);
        assertEq(_setStoredDust(nftId_, grossDebtRaw_ - MIN_DEBT), grossDebtRaw_ - MIN_DEBT);
        uint256 absorbedLiquidityBefore_ = _absorbedLiquidity();

        vm.prank(bob);
        vaultOne.operate(nftId_, 1e6, 0, address(0));

        assertEq(_absorbedLiquidity(), absorbedLiquidityBefore_, "nothing should be absorbed");
        assertEq(_storedCol(nftId_), colRaw_ + 1e6, "position should keep its collateral");
        (FluidVaultResolver.UserPosition memory position_, ) = vaultResolver.positionByNftId(nftId_);
        assertFalse(position_.isSupplyPosition, "the position should keep its debt");
        // the write path rounds the net debt up by a wei or two
        assertApproxEqAbs(position_.borrow, MIN_DEBT, 2, "position should keep its net debt");
    }

    function test_operate_RevertIfNetDebtIsBelowMinDebtAfterSync() public {
        uint256 nftId_ = _setupLiquidatedPosition();
        (uint256 grossDebtRaw_, , ) = _syncedPosition(nftId_);
        // the write path adds one wei of rounding, so MIN_DEBT - 1 still clears the floor
        assertEq(_setStoredDust(nftId_, grossDebtRaw_ - (MIN_DEBT - 2)), grossDebtRaw_ - (MIN_DEBT - 2));

        vm.expectRevert(
            abi.encodeWithSelector(VaultError.FluidVaultError.selector, VaultErrorTypes.Vault__UserDebtTooLow)
        );
        vm.prank(bob);
        vaultOne.operate(nftId_, 1e6, 0, address(0));
    }
}
