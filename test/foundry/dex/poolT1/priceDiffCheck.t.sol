// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { CoreHelpers } from "../../../../contracts/protocols/dex/poolT1/coreModule/helpers/coreHelpers.sol";
import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";
import { IFluidDexT1 } from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";

import "../../testERC20.sol";

import { PoolT1BaseTest, FluidDexT1 } from "./pool.t.sol";

/// @dev Exposes CoreHelpers' oracle-update logic unmodified, so tests run the real check, not a copy.
contract PriceDiffCheckExposed is CoreHelpers {
    constructor(address token0_, address token1_) CoreHelpers(_constants(token0_, token1_)) {}

    function _constants(address token0_, address token1_) private pure returns (ConstantViews memory c_) {
        c_.token0 = token0_;
        c_.token1 = token1_;
    }

    function priceDiffCheck(uint256 oldPrice_, uint256 newPrice_) external pure {
        _priceDiffCheck(oldPrice_, newPrice_);
    }

    function updateOracle(
        uint256 newPrice_,
        uint256 centerPrice_,
        uint256 dexVariables_
    ) external view returns (uint256) {
        return _updateOracle(newPrice_, centerPrice_, dexVariables_);
    }

    function oracleConstants() external pure returns (uint256 precision_, uint256 limit_) {
        return (ORACLE_PRECISION, ORACLE_LIMIT);
    }
}

contract FluidDexT1PriceDiffCheckTest is Test {
    using BigMathMinified for uint256;

    PriceDiffCheckExposed internal dex;

    uint256 internal constant ORACLE_PRECISION = 1e18;
    uint256 internal constant ORACLE_LIMIT = 5e16;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xff;

    function setUp() public {
        TestERC20 a_ = new TestERC20("TokenA", "TKA");
        TestERC20 b_ = new TestERC20("TokenB", "TKB");
        (address token0_, address token1_) = address(a_) < address(b_)
            ? (address(a_), address(b_))
            : (address(b_), address(a_));

        dex = new PriceDiffCheckExposed(token0_, token1_);
    }

    function test_oracleConstants_MatchProduction() public view {
        (uint256 precision_, uint256 limit_) = dex.oracleConstants();
        assertEq(precision_, ORACLE_PRECISION);
        assertEq(limit_, ORACLE_LIMIT);
    }

    function _bounds(uint256 oldPrice_) internal pure returns (uint256 upper_, uint256 lower_) {
        upper_ = (oldPrice_ * (ORACLE_PRECISION + ORACLE_LIMIT)) / ORACLE_PRECISION;
        lower_ = (oldPrice_ * (ORACLE_PRECISION - ORACLE_LIMIT)) / ORACLE_PRECISION;
    }

    function _expectHugeSwapDiffRevert() internal {
        vm.expectRevert(
            abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__OracleUpdateHugeSwapDiff)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        _priceDiffCheck: fixed-scale boundaries
    //////////////////////////////////////////////////////////////*/

    function test_priceDiffCheck_ExactPlus5PercentPasses() public view {
        uint256 old_ = 1e18;
        (uint256 upper_, ) = _bounds(old_);
        dex.priceDiffCheck(old_, upper_);
    }

    function test_priceDiffCheck_ExactMinus5PercentPasses() public view {
        uint256 old_ = 1e18;
        (, uint256 lower_) = _bounds(old_);
        dex.priceDiffCheck(old_, lower_);
    }

    function test_priceDiffCheck_RevertIfJustAbovePlus5Percent() public {
        uint256 old_ = 1e18;
        (uint256 upper_, ) = _bounds(old_);
        _expectHugeSwapDiffRevert();
        dex.priceDiffCheck(old_, upper_ + 1);
    }

    function test_priceDiffCheck_RevertIfJustBelowMinus5Percent() public {
        uint256 old_ = 1e18;
        (, uint256 lower_) = _bounds(old_);
        _expectHugeSwapDiffRevert();
        dex.priceDiffCheck(old_, lower_ - 1);
    }

    function test_priceDiffCheck_RevertIfAbove5Point2Percent() public {
        // pre-fix division-based check let a +5.2% move through; confirms the fix actually tightened it.
        uint256 old_ = 1e18;
        _expectHugeSwapDiffRevert();
        dex.priceDiffCheck(old_, (old_ * 1052) / 1000);
    }

    function test_priceDiffCheck_Minus4Point9PercentPasses() public view {
        // pre-fix check rejected a -4.9% move as if past the 5% limit; confirms the fix widened it back.
        uint256 old_ = 1e18;
        dex.priceDiffCheck(old_, (old_ * 951) / 1000);
    }

    /*//////////////////////////////////////////////////////////////
                    _priceDiffCheck: fuzz across price scales
    //////////////////////////////////////////////////////////////*/

    function _assertMatchesBand(uint256 old_, uint256 newPriceRaw_) internal {
        uint256 new_ = bound(newPriceRaw_, (old_ * 50) / 100, (old_ * 200) / 100);
        (uint256 upper_, uint256 lower_) = _bounds(old_);

        if (new_ > upper_ || new_ < lower_) {
            _expectHugeSwapDiffRevert();
            dex.priceDiffCheck(old_, new_);
        } else {
            dex.priceDiffCheck(old_, new_);
        }
    }

    function testFuzz_priceDiffCheck_MatchesBand_Scale1e18(uint256 newPriceRaw_) public {
        _assertMatchesBand(1e18, newPriceRaw_);
    }

    function testFuzz_priceDiffCheck_MatchesBand_Scale1e27(uint256 newPriceRaw_) public {
        _assertMatchesBand(1e27, newPriceRaw_);
    }

    function testFuzz_priceDiffCheck_MatchesBand_Scale1e6(uint256 newPriceRaw_) public {
        _assertMatchesBand(1e6, newPriceRaw_);
    }

    /*//////////////////////////////////////////////////////////////
                _updateOracle: same-block and next-block branches
    //////////////////////////////////////////////////////////////*/

    function _encode(uint256 normal_) internal pure returns (uint256) {
        return normal_.toBigNumber(32, 8, BigMathMinified.ROUND_DOWN);
    }

    function _decode(uint256 bigNumber_) internal pure returns (uint256) {
        return (bigNumber_ >> DEFAULT_EXPONENT_SIZE) << (bigNumber_ & DEFAULT_EXPONENT_MASK);
    }

    // bits 1-40 (last-to-last price) + 81-120 (center price) + timestamp == block.timestamp -> same-block path.
    function _sameBlockDexVariables(
        uint256 ts_,
        uint256 oldPrice_,
        uint256 centerPrice_
    ) internal pure returns (uint256) {
        return (ts_ << 121) | (_encode(centerPrice_) << 81) | (_encode(oldPrice_) << 1);
    }

    // bits 41-80 (last stored price) + a timestamp before block.timestamp -> next-block path.
    function _nextBlockDexVariables(uint256 ts_, uint256 oldPrice_) internal pure returns (uint256) {
        return ((ts_ - 100) << 121) | (_encode(oldPrice_) << 41);
    }

    function test_updateOracle_SameBlock_WithinBandPasses() public {
        uint256 ts_ = block.timestamp;
        uint256 centerPrice_ = _decode(_encode(1e27));
        uint256 oldPriceDecoded_ = _decode(_encode(1e27));
        (uint256 upper_, ) = _bounds(oldPriceDecoded_);

        dex.updateOracle(upper_, centerPrice_, _sameBlockDexVariables(ts_, oldPriceDecoded_, centerPrice_));
    }

    function test_updateOracle_SameBlock_RevertIfOutsideBand() public {
        uint256 ts_ = block.timestamp;
        uint256 centerPrice_ = _decode(_encode(1e27));
        uint256 oldPriceDecoded_ = _decode(_encode(1e27));
        (uint256 upper_, ) = _bounds(oldPriceDecoded_);

        _expectHugeSwapDiffRevert();
        dex.updateOracle(upper_ + 1, centerPrice_, _sameBlockDexVariables(ts_, oldPriceDecoded_, centerPrice_));
    }

    function test_updateOracle_NextBlock_WithinBandPasses() public {
        uint256 ts_ = block.timestamp + 1000;
        vm.warp(ts_);
        uint256 oldPriceDecoded_ = _decode(_encode(1e27));
        (uint256 upper_, ) = _bounds(oldPriceDecoded_);

        dex.updateOracle(upper_, 1e27, _nextBlockDexVariables(ts_, oldPriceDecoded_));
    }

    function test_updateOracle_NextBlock_RevertIfOutsideBand() public {
        uint256 ts_ = block.timestamp + 1000;
        vm.warp(ts_);
        uint256 oldPriceDecoded_ = _decode(_encode(1e27));
        (uint256 upper_, ) = _bounds(oldPriceDecoded_);

        _expectHugeSwapDiffRevert();
        dex.updateOracle(upper_ + 1, 1e27, _nextBlockDexVariables(ts_, oldPriceDecoded_));
    }
}

/// @dev Drives the check through a real pool swap, so the pass/revert outcome is the contract's own.
contract FluidDexT1PriceDiffCheckSwapTest is PoolT1BaseTest {
    function _adjustedToNormal(uint256 adjusted_, uint256 decimals_) internal pure returns (uint256) {
        return decimals_ > 12 ? adjusted_ * (10 ** (decimals_ - 12)) : adjusted_ / (10 ** (12 - decimals_));
    }

    // (X / (X + amountIn))^2 in 1e18 fixed point: the no-fee constant-product ratio for a token0-in swap.
    function _dropRatio1e18(uint256 x_, uint256 amountIn_) internal pure returns (uint256) {
        uint256 temp_ = (x_ * 1e18) / (x_ + amountIn_);
        return (temp_ * temp_) / 1e18;
    }

    // ((Y + amountIn) / Y)^2 in 1e18 fixed point: the token1-in counterpart, strictly increasing.
    function _riseRatio1e18(uint256 y_, uint256 amountIn_) internal pure returns (uint256) {
        uint256 temp_ = ((y_ + amountIn_) * 1e18) / y_;
        return (temp_ * temp_) / 1e18;
    }

    function _findDropAmount(uint256 x_, uint256 targetRatio1e18_) internal pure returns (uint256 amountIn_) {
        uint256 lo_;
        uint256 hi_ = x_;
        for (uint256 i_; i_ < 160; i_++) {
            uint256 mid_ = lo_ + (hi_ - lo_) / 2;
            if (_dropRatio1e18(x_, mid_) > targetRatio1e18_) {
                lo_ = mid_ + 1;
            } else {
                hi_ = mid_;
            }
        }
        amountIn_ = lo_;
    }

    function _findRiseAmount(uint256 y_, uint256 targetRatio1e18_) internal pure returns (uint256 amountIn_) {
        uint256 lo_;
        uint256 hi_ = y_;
        for (uint256 i_; i_ < 160; i_++) {
            uint256 mid_ = lo_ + (hi_ - lo_) / 2;
            if (_riseRatio1e18(y_, mid_) < targetRatio1e18_) {
                lo_ = mid_ + 1;
            } else {
                hi_ = mid_;
            }
        }
        amountIn_ = lo_;
    }

    function test_swapIn_PriceDropWithinBandPasses() public {
        FluidDexT1 dexPool_ = DAI_USDC.dexCol;
        // move past pool-init's timestamp so _updateOracle takes the next-block path read below.
        vm.warp(block.timestamp + 1);

        IFluidDexT1.CollateralReserves memory r_ = dexResolver.getDexCollateralReservesAdjusted(address(dexPool_));
        uint256 oldPrice_ = getCurrentPrice(dexPool_);

        // 0.9512 (4.88% drop): inside [4.77%,4.99%], clear of the 5% and the pre-fix ~4.7619% boundary.
        uint256 amountInAdjusted_ = _findDropAmount(r_.token0ImaginaryReserves, 0.9512e18);
        uint256 amountIn_ = _adjustedToNormal(amountInAdjusted_, ERC20(DAI_USDC.token0).decimals());

        vm.prank(alice);
        dexPool_.swapIn(true, amountIn_, 0, alice);

        uint256 ratio_ = (getCurrentPrice(dexPool_) * 1e18) / oldPrice_;
        assertGe(ratio_, 0.9501e18, "realised drop exceeded 4.99%");
        assertLe(ratio_, 0.9523e18, "realised drop under 4.77%");
    }

    function test_swapIn_RevertIfPriceRiseAboveBand() public {
        FluidDexT1 dexPool_ = DAI_USDC.dexCol;
        vm.warp(block.timestamp + 1);

        IFluidDexT1.CollateralReserves memory r_ = dexResolver.getDexCollateralReservesAdjusted(address(dexPool_));

        // 1.0513 (5.13% rise): inside [5.01%,5.25%], clear of the 5% and the pre-fix ~5.2632% boundary.
        uint256 amountInAdjusted_ = _findRiseAmount(r_.token1ImaginaryReserves, 1.0513e18);
        uint256 amountIn_ = _adjustedToNormal(amountInAdjusted_, ERC20(DAI_USDC.token1).decimals());

        uint256 predictedRatio_ = _riseRatio1e18(r_.token1ImaginaryReserves, amountInAdjusted_);
        assertGe(predictedRatio_, 1.0501e18, "predicted rise under 5.01%");
        assertLe(predictedRatio_, 1.0525e18, "predicted rise exceeded 5.25%");

        // a swap landing just under the production boundary must still succeed (not some other revert).
        uint256 belowThresholdAmount_ = _adjustedToNormal(
            _findRiseAmount(r_.token1ImaginaryReserves, 1.0499e18),
            ERC20(DAI_USDC.token1).decimals()
        );
        uint256 snapshot_ = vm.snapshot();
        vm.prank(alice);
        dexPool_.swapIn(false, belowThresholdAmount_, 0, alice);
        vm.revertTo(snapshot_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__OracleUpdateHugeSwapDiff)
        );
        dexPool_.swapIn(false, amountIn_, 0, alice);
    }

    function test_VERSION_IsSet() public view {
        assertEq(DAI_USDC.dexCol.VERSION(), "1.1.0");
    }

    function _mockNoVersion(FluidDexT1 dexPool_) internal {
        vm.mockCallRevert(address(dexPool_), abi.encodeWithSelector(IFluidDexT1.VERSION.selector), "");
    }

    // 4.88% drop: inside this pool's band, outside the band of pools without VERSION.
    function _dropAmountIn(FluidDexT1 dexPool_) internal returns (uint256) {
        vm.warp(block.timestamp + 1);
        IFluidDexT1.CollateralReserves memory r_ = dexResolver.getDexCollateralReservesAdjusted(address(dexPool_));
        return
            _adjustedToNormal(
                _findDropAmount(r_.token0ImaginaryReserves, 0.9512e18),
                ERC20(DAI_USDC.token0).decimals()
            );
    }

    // 5.13% rise: outside this pool's band, inside the band of pools without VERSION.
    function _riseAmountIn(FluidDexT1 dexPool_) internal returns (uint256) {
        vm.warp(block.timestamp + 1);
        IFluidDexT1.CollateralReserves memory r_ = dexResolver.getDexCollateralReservesAdjusted(address(dexPool_));
        return
            _adjustedToNormal(
                _findRiseAmount(r_.token1ImaginaryReserves, 1.0513e18),
                ERC20(DAI_USDC.token1).decimals()
            );
    }

    function test_estimateSwapIn_PriceDropWithinBandMatchesSwap() public {
        FluidDexT1 dexPool_ = DAI_USDC.dexCol;
        uint256 amountIn_ = _dropAmountIn(dexPool_);

        uint256 estimate_ = dexResolver.estimateSwapIn(address(dexPool_), true, amountIn_, 0);
        assertGt(estimate_, 0);

        vm.prank(alice);
        assertEq(dexPool_.swapIn(true, amountIn_, 0, alice), estimate_);
    }

    function test_estimateSwapIn_PriceDropZeroWithoutVersion() public {
        FluidDexT1 dexPool_ = DAI_USDC.dexCol;
        uint256 amountIn_ = _dropAmountIn(dexPool_);

        _mockNoVersion(dexPool_);
        assertEq(dexResolver.estimateSwapIn(address(dexPool_), true, amountIn_, 0), 0);
    }

    function test_estimateSwapIn_PriceRiseAboveBandZero() public {
        FluidDexT1 dexPool_ = DAI_USDC.dexCol;
        uint256 amountIn_ = _riseAmountIn(dexPool_);

        assertEq(dexResolver.estimateSwapIn(address(dexPool_), false, amountIn_, 0), 0);

        _mockNoVersion(dexPool_);
        assertGt(dexResolver.estimateSwapIn(address(dexPool_), false, amountIn_, 0), 0);
    }
}
