// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { AddressCalcs } from "../../libraries/addressCalcs.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";

interface IFluidDexT1Admin {
    /// @notice sets a new fee and revenue cut for a certain dex
    /// @param fee_ new fee (scaled so that 1% = 10000)
    /// @param revenueCut_ new revenue cut
    function updateFeeAndRevenueCut(uint fee_, uint revenueCut_) external;
}

interface ICenterPrice {
    /// @notice Retrieves the center price for the pool
    /// @dev This function is marked as non-constant (potentially state-changing) to allow flexibility in price fetching mechanisms.
    ///      While typically used as a read-only operation, this design permits write operations if needed for certain token pairs
    ///      (e.g., fetching up-to-date exchange rates that may require state changes).
    /// @return price The current price ratio of token1 to token0, expressed with 27 decimal places
    function centerPrice() external returns (uint price);
}

abstract contract Events is Error {
    /// @notice emitted when rebalancer successfully changes the fee and revenue cut
    event LogRebalanceFeeAndRevenueCut(address dex, uint fee, uint revenueCut);
}

abstract contract Constants is Events {
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant SIX_DECIMALS = 1e6;

    uint256 internal constant SCALE = 1e27;

    /// @notice Whether the center price is active
    bool public immutable CENTER_PRICE_ACTIVE;

    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X17 = 0x1ffff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X28 = 0xfffffff;
    uint256 internal constant X30 = 0x3fffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev Address of contract used for deploying center price & hook related contract
    address internal immutable DEPLOYER_CONTRACT;

    uint256 public immutable MIN_FEE; // e.g. 10 -> 0.001%
    uint256 public immutable MAX_FEE; // e.g. 100 -> 0.01%
    uint256 public immutable MIN_DEVIATION; // in 1e27 scale, e.g. 3e23 -> 0.003
    uint256 public immutable MAX_DEVIATION; // in 1e27 scale, e.g. 1e24 -> 0.01

    uint256 public immutable UPDATE_FEE_TRIGGER_BUFFER = 10; // e.g. 1e4 -> 1%

    address public immutable DEX;

    IFluidReserveContract public immutable RESERVE_CONTRACT;
}

abstract contract DexHelpers is Constants {
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.DexFeeHandler__InvalidParams);
        }
        _;
    }

    constructor(
        address dex_,
        address deployerContract_,
        bool isCenterPriceActive_
    ) validAddress(dex_) validAddress(deployerContract_) {
        DEX = dex_;
        DEPLOYER_CONTRACT = deployerContract_;
        CENTER_PRICE_ACTIVE = isCenterPriceActive_;
    }

    function _getCenterPriceShift() internal view returns (uint256) {
        return IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_CENTER_PRICE_SHIFT_SLOT));
    }

    function _getDexVariables() internal view returns (uint256) {
        return IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));
    }

    function _getDexVariables2() internal view returns (uint256) {
        return IFluidDexT1(DEX).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
    }

    function _getCenterPriceFromCenterPriceAddress(uint256 centerPriceNonce_) internal view returns (uint256) {
        address centerPriceAddress_ = AddressCalcs.addressCalc(DEPLOYER_CONTRACT, centerPriceNonce_);
        (bool success_, bytes memory data_) = centerPriceAddress_.staticcall(
            abi.encodeWithSelector(ICenterPrice.centerPrice.selector)
        );
        require(success_, "Static call failed");
        return abi.decode(data_, (uint256));
    }

    function _calcCenterPrice(uint dexVariables_, uint centerPriceNonce_) internal view returns (uint newCenterPrice_) {
        uint oldCenterPrice_ = (dexVariables_ >> 81) & X40;
        oldCenterPrice_ = (oldCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (oldCenterPrice_ & DEFAULT_EXPONENT_MASK);

        uint centerPriceShift_ = _getCenterPriceShift();

        uint startTimeStamp_ = centerPriceShift_ & X33;
        uint percent_ = (centerPriceShift_ >> 33) & X20;
        uint time_ = (centerPriceShift_ >> 53) & X20;

        uint fromTimeStamp_ = (dexVariables_ >> 121) & X33;
        fromTimeStamp_ = fromTimeStamp_ > startTimeStamp_ ? fromTimeStamp_ : startTimeStamp_;

        newCenterPrice_ = _getCenterPriceFromCenterPriceAddress(centerPriceNonce_);
        uint priceShift_ = (oldCenterPrice_ * percent_ * (block.timestamp - fromTimeStamp_)) / (time_ * SIX_DECIMALS);

        if (newCenterPrice_ > oldCenterPrice_) {
            // shift on positive side
            oldCenterPrice_ += priceShift_;
            if (newCenterPrice_ > oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            }
        } else {
            unchecked {
                oldCenterPrice_ = oldCenterPrice_ > priceShift_ ? oldCenterPrice_ - priceShift_ : 0;
                // In case of oldCenterPrice_ ending up 0, which could happen when a lot of time has passed (pool has no swaps for many days or weeks)
                // then below we get into the else logic which will fully conclude shifting and return newCenterPrice_
                // as it was fetched from the external center price source.
                // not ideal that this would ever happen unless the pool is not in use and all/most users have left leaving not enough liquidity to trade on
            }
            if (newCenterPrice_ < oldCenterPrice_) {
                newCenterPrice_ = oldCenterPrice_;
            }
        }
    }

    function _fetchCenterPrice() internal view returns (uint256 centerPrice_) {
        (uint256 dexVariables_, uint256 dexVariables2_) = (_getDexVariables(), _getDexVariables2());

        // centerPrice_ => center price hook
        centerPrice_ = (dexVariables2_ >> 112) & X30;

        // whether centerPrice shift is active or not
        if (((dexVariables2_ >> 248) & 1) == 0) {
            if (centerPrice_ == 0) {
                centerPrice_ = (dexVariables_ >> 81) & X40;
                centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
            } else {
                // center price should be fetched from external source. For exmaple, in case of wstETH <> ETH pool,
                // we would want the center price to be pegged to wstETH exchange rate into ETH
                centerPrice_ = _getCenterPriceFromCenterPriceAddress(centerPrice_);
            }
        } else {
            // an active centerPrice_ shift is going on
            centerPrice_ = _calcCenterPrice(dexVariables_, centerPrice_);
        }

        {
            uint maxCenterPrice_ = (dexVariables2_ >> 172) & X28;
            maxCenterPrice_ = (maxCenterPrice_ >> DEFAULT_EXPONENT_SIZE) << (maxCenterPrice_ & DEFAULT_EXPONENT_MASK);

            if (centerPrice_ > maxCenterPrice_) {
                // if center price is greater than max center price
                centerPrice_ = maxCenterPrice_;
            } else {
                // check if center price is less than min center price
                uint minCenterPrice_ = (dexVariables2_ >> 200) & X28;
                minCenterPrice_ =
                    (minCenterPrice_ >> DEFAULT_EXPONENT_SIZE) <<
                    (minCenterPrice_ & DEFAULT_EXPONENT_MASK);
                if (centerPrice_ < minCenterPrice_) {
                    centerPrice_ = minCenterPrice_;
                }
            }
        }
    }

    function _getDexFee() internal view returns (uint256 fee_) {
        return (_getDexVariables2() >> 2) & X17;
    }

    function getDexCenterPrice() public view returns (uint256) {
        return _fetchCenterPrice();
    }

    /// @notice returns the revenue cut for the dex
    function getDexRevenueCut() public view returns (uint256 revenueCut_) {
        return (_getDexVariables2() >> 19) & X7;
    }

    /// @notice returns the fee and revenue cut for the dex
    function getDexFeeAndRevenueCut() public view returns (uint256 fee_, uint256 revenueCut_) {
        uint256 dexVariables2_ = _getDexVariables2();

        fee_ = (dexVariables2_ >> 2) & X17;
        revenueCut_ = (dexVariables2_ >> 19) & X7;
    }

    /// @notice returns the last stored prices of the pool and the last interaction time stamp
    function getDexVariables()
        public
        view
        returns (uint256 lastToLastStoredPrice_, uint256 lastStoredPriceOfPool_, uint256 lastInteractionTimeStamp_)
    {
        uint256 dexVariables_ = _getDexVariables();

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
}

abstract contract DynamicFee is DexHelpers {
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

    /// @notice Calculates the deviation from the given price.
    function getDeviationFromPrice(uint256 price_) public view returns (uint256) {
        if (CENTER_PRICE_ACTIVE) {
            uint256 centerPrice_ = _fetchCenterPrice();
            uint256 deviation_ = price_ > centerPrice_ ? price_ - centerPrice_ : centerPrice_ - price_;
            return (deviation_ * SCALE) / centerPrice_;
        } else {
            return price_ > SCALE ? price_ - SCALE : SCALE - price_;
        }
    }

    /// @notice Calculates the dynamic fee based on the given price.
    function dynamicFeeFromPrice(uint256 price) external view returns (uint256) {
        return _computeDynamicFee(getDeviationFromPrice(price));
    }

    /// @notice Calculates the dynamic fee based on the given deviation.
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

abstract contract FluidDexFeeHandlerHelpers is DynamicFee {
    modifier onlyRebalancer() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender)) {
            revert FluidConfigError(ErrorTypes.DexFeeHandler__Unauthorized);
        }
        _;
    }

    constructor(
        uint256 minFee_,
        uint256 maxFee_,
        uint256 minDeviation_,
        uint256 maxDeviation_,
        address dex_,
        address deployerContract_,
        IFluidReserveContract reserveContract_,
        bool centerPriceActive_
    )
        validAddress(address(reserveContract_))
        DexHelpers(dex_, deployerContract_, centerPriceActive_)
        DynamicFee(minFee_, maxFee_, minDeviation_, maxDeviation_)
    {
        RESERVE_CONTRACT = reserveContract_;
    }

    /// @notice returns the dynamic fee for the dex based on the last stored price of the pool
    function getDexDynamicFee() public view returns (uint256) {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = getDexVariables();

        if (lastInteractionTimeStamp_ == block.timestamp) lastStoredPriceOfPool_ = lastToLastStoredPrice_;

        return _computeDynamicFee(getDeviationFromPrice(lastStoredPriceOfPool_));
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

contract FluidDexFeeHandler is FluidDexFeeHandlerHelpers {
    constructor(
        uint256 minFee_,
        uint256 maxFee_,
        uint256 minDeviation_,
        uint256 maxDeviation_,
        address dex_,
        address deployerContract_,
        IFluidReserveContract reserveContract_,
        bool centerPriceActive_
    )
        FluidDexFeeHandlerHelpers(
            minFee_,
            maxFee_,
            minDeviation_,
            maxDeviation_,
            dex_,
            deployerContract_,
            reserveContract_,
            centerPriceActive_
        )
    {}

    /// @notice rebalances the fee
    function rebalance() external onlyRebalancer {
        uint256 newFee_ = getDexDynamicFee();

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
    function relativeConfigPercentDiff() public view returns (uint256) {
        return _configPercentDiff(_getDexFee(), getDexDynamicFee());
    }

    /// @notice returns how much new config would be different from current config.
    function absoluteConfigDiff() public view returns (uint256) {
        uint256 newFee_ = getDexDynamicFee();
        uint256 oldFee_ = _getDexFee();

        return newFee_ > oldFee_ ? newFee_ - oldFee_ : oldFee_ - newFee_;
    }

    /// @notice returns the new calculated fee
    function newConfig() public view returns (uint256) {
        return getDexDynamicFee();
    }

    /// @notice returns the currently configured fee
    function currentConfig() public view returns (uint256) {
        return _getDexFee();
    }
}
