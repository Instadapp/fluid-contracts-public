// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";

interface IFluidDexT1Admin {
    /// @notice sets a new fee and revenue cut for a certain dex
    /// @param fee_ new fee (scaled so that 1% = 10000)
    /// @param revenueCut_ new revenue cut
    function updateFeeAndRevenueCut(uint fee_, uint revenueCut_) external;
}

abstract contract Events {
    /// @notice emitted when rebalancer successfully changes the fee and revenue cut
    event LogRebalanceFeeAndRevenueCut(address dex, uint fee, uint revenueCut);
}

abstract contract Constants {
    // 1% = 10000
    uint256 internal constant FOUR_DECIMALS = 1e4;

    uint256 internal constant SCALE = 1e27;

    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X17 = 0x1ffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 public immutable MIN_FEE; // e.g. 10 -> 0.001%
    uint256 public immutable MAX_FEE; // e.g. 100 -> 0.01%
    uint256 public immutable MIN_DEVIATION; // in 1e27 scale, e.g. 3e23 -> 0.003
    uint256 public immutable MAX_DEVIATION; // in 1e27 scale, e.g. 1e24 -> 0.01

    uint256 public immutable UPDATE_FEE_TRIGGER_BUFFER = 10; // e.g. 1e4 -> 1%

    // USDC-USDT dex
    address public immutable DEX;

    IFluidReserveContract public immutable RESERVE_CONTRACT;
}

abstract contract DynamicFee is Constants, Error, Events {
    constructor(uint256 _minFee, uint256 _maxFee, uint256 _minDeviation, uint256 _maxDeviation) {
        // check for zero values
        if (_minFee == 0 || _maxFee == 0 || _minDeviation == 0 || _maxDeviation == 0)
            revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);

        // check that max fee is not greater or equal to 1%
        if (_maxFee >= 1e4) revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);

        // check that min deviation is not greater than max deviation
        if (_minDeviation > _maxDeviation) revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);

        // check that min fee is not greater than max fee
        if (_minFee > _maxFee) revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);

        MIN_FEE = _minFee;
        MAX_FEE = _maxFee;
        MIN_DEVIATION = _minDeviation;
        MAX_DEVIATION = _maxDeviation;
    }

    function _getDeviationFromPrice(uint256 price_) internal pure returns (uint256) {
        // Absolute deviation from 1e27
        return price_ > SCALE ? price_ - SCALE : SCALE - price_;
    }

    function dynamicFeeFromPrice(uint256 price) external view returns (uint256) {
        return _computeDynamicFee(_getDeviationFromPrice(price));
    }

    function dynamicFeeFromDeviation(uint256 deviation) external view returns (uint256) {
        return _computeDynamicFee(deviation);
    }

    /**
     * @dev Internal helper that implements a smooth-step curve for fee calculation
     * @param deviation Deviation from the target price in SCALE (1e27)
     * @return Fee in basis points (1e4 = 1%)
     */
    function _computeDynamicFee(uint256 deviation) internal view returns (uint256) {
        if (deviation <= MIN_DEVIATION) {
            return MIN_FEE;
        } else if (deviation >= MAX_DEVIATION) {
            return MAX_FEE;
        } else {
            // Calculate normalized position between min and max deviation (0 to 1 in SCALE)
            uint256 alpha = ((deviation - MIN_DEVIATION) * SCALE) / (MAX_DEVIATION - MIN_DEVIATION);

            // Smooth step formula: 3x² - 2x³
            // https://en.wikipedia.org/wiki/Smoothstep
            uint256 alpha2 = _scaleMul(alpha, alpha);
            uint256 alpha3 = _scaleMul(alpha2, alpha);

            uint256 smooth = _scaleMul(3 * SCALE, alpha2) - _scaleMul(2 * SCALE, alpha3);

            uint256 feeDelta = MAX_FEE - MIN_FEE;
            uint256 interpolatedFee = MIN_FEE + (_scaleMul(smooth, feeDelta));

            return interpolatedFee;
        }
    }

    function _scaleMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / SCALE;
    }
}

contract FluidDexFeeHandler is DynamicFee {
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);
        }
        _;
    }

    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.DexFeeHandler__Unauthorized);
        }
        _;
    }

    constructor(
        IFluidReserveContract reserveContract_,
        uint256 minFee_,
        uint256 maxFee_,
        uint256 minDeviation_,
        uint256 maxDeviation_,
        address dex_
    )
        validAddress(dex_)
        validAddress(address(reserveContract_))
        DynamicFee(minFee_, maxFee_, minDeviation_, maxDeviation_)
    {
        RESERVE_CONTRACT = reserveContract_;
        DEX = dex_;
    }

    /// @notice returns the fee for the dex
    function getDexFee() public view returns (uint256 fee_) {
        uint256 dexVariables2_ = IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        return (dexVariables2_ >> 2) & X17;
    }

    /// @notice returns the revenue cut for the dex
    function getDexRevenueCut() public view returns (uint256 revenueCut_) {
        uint256 dexVariables2_ = IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        return (dexVariables2_ >> 19) & X7;
    }

    /// @notice returns the fee and revenue cut for the dex
    function getDexFeeAndRevenueCut() public view returns (uint256 fee_, uint256 revenueCut_) {
        uint256 dexVariables2_ = IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        fee_ = (dexVariables2_ >> 2) & X17;
        revenueCut_ = (dexVariables2_ >> 19) & X7;
    }

    /// @notice returns the last stored prices of the pool and the last interaction time stamp
    function getDexVariable()
        public
        view
        returns (uint256 lastToLastStoredPrice_, uint256 lastStoredPriceOfPool_, uint256 lastInteractionTimeStamp_)
    {
        uint256 dexVariables_ = IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));

        lastToLastStoredPrice_ = (dexVariables_ >> 1) & X40;
        lastToLastStoredPrice_ =
            (lastToLastStoredPrice_ >> DEFAULT_EXPONENT_SIZE) <<
            (lastToLastStoredPrice_ & DEFAULT_EXPONENT_MASK);

        lastStoredPriceOfPool_ = (dexVariables_ >> 41) & X40;
        lastStoredPriceOfPool_ =
            (lastStoredPriceOfPool_ >> DEFAULT_EXPONENT_SIZE) <<
            (lastStoredPriceOfPool_ & DEFAULT_EXPONENT_MASK);

        lastInteractionTimeStamp_ = (dexVariables_ >> 121) & X33;
    }

    /// @notice returns the dynamic fee for the dex based on the last stored price of the pool
    function getDexDynamicFees() public view returns (uint256) {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = getDexVariable();

        if (lastInteractionTimeStamp_ == block.timestamp) lastStoredPriceOfPool_ = lastToLastStoredPrice_;

        return _computeDynamicFee(_getDeviationFromPrice(lastStoredPriceOfPool_));
    }

    /// @notice rebalances the fee
    function rebalance() external onlyRebalancer {
        uint256 newFee_ = getDexDynamicFees();

        (uint256 currentFee_, uint256 currentRevenueCut_) = getDexFeeAndRevenueCut();

        uint256 feePercentageChange_ = _configPercentDiff(currentFee_, newFee_);

        // should be more than 0.001% to update
        if (feePercentageChange_ > UPDATE_FEE_TRIGGER_BUFFER) {
            IFluidDexT1Admin(DEX).updateFeeAndRevenueCut(newFee_, currentRevenueCut_ * FOUR_DECIMALS);
            emit LogRebalanceFeeAndRevenueCut(DEX, newFee_, currentRevenueCut_ * FOUR_DECIMALS);
        } else {
            revert FluidConfigError(ErrorTypes.DexFeeHandler__FeeUpdateNotRequired);
        }
    }

    /// @notice returns how much new config would be different from current config in percent (100 = 1%, 1 = 0.01%).
    function configPercentDiff() public view returns (uint256) {
        uint256 newFee_ = getDexDynamicFees();
        (uint256 currentFee_, ) = getDexFeeAndRevenueCut();

        return _configPercentDiff(currentFee_, newFee_);
    }

    function _configPercentDiff(
        uint256 currentFee_,
        uint256 newFee_
    ) internal pure returns (uint256 configPercentDiff_) {
        if (currentFee_ == newFee_) {
            return 0;
        }

        if (currentFee_ > newFee_) configPercentDiff_ = currentFee_ - newFee_;
        else configPercentDiff_ = newFee_ - currentFee_;

        return (configPercentDiff_ * FOUR_DECIMALS) / currentFee_;
    }
}
