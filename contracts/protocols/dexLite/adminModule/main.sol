// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import { BigMathMinified as BM } from "../../../libraries/bigMathMinified.sol";
import "./helpers.sol";

contract FluidDexLiteAdminModule is AdminModuleHelpers {
    constructor(address liquidity_, address deployerContract_) {
        THIS_ADDRESS = address(this);
        LIQUIDITY = IFluidLiquidity(liquidity_);
        DEPLOYER_CONTRACT = deployerContract_;
    }

    /// @dev update the auth for the dex
    /// @param auth_ the address to update auth for
    /// @param isAuth_ the auth status
    function updateAuth(address auth_, bool isAuth_) external _onlyDelegateCall {
        _isAuth[auth_] = isAuth_ ? 1 : 0;
        
        emit LogUpdateAuth(auth_, isAuth_);
    }

    /// @dev initialize the dex
    /// @param i_ the initialize params
    function initialize(InitializeParams memory i_) external payable _onlyDelegateCall {
        if (i_.dexKey.token0 == address(0) || i_.dexKey.token1 == address(0) || i_.dexKey.token0 >= i_.dexKey.token1) {
            revert InvalidTokenOrder(i_.dexKey.token0, i_.dexKey.token1);
        }

        InitializeVariables memory v_;

        v_.dexId = bytes8(keccak256(abi.encode(i_.dexKey)));
        if (_dexVariables[v_.dexId] != 0) {
            revert DexAlreadyInitialized(v_.dexId);
        }

        v_.token0Decimals = i_.dexKey.token0 == NATIVE_TOKEN ? NATIVE_TOKEN_DECIMALS : IERC20WithDecimals(i_.dexKey.token0).decimals();
        v_.token1Decimals = i_.dexKey.token1 == NATIVE_TOKEN ? NATIVE_TOKEN_DECIMALS : IERC20WithDecimals(i_.dexKey.token1).decimals();

        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (i_.revenueCut != 0 && i_.revenueCut < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert InvalidRevenueCut(i_.revenueCut);
        }

        i_.revenueCut = i_.revenueCut / FOUR_DECIMALS;

        i_.upperPercent = i_.upperPercent / TWO_DECIMALS;
        i_.lowerPercent = i_.lowerPercent / TWO_DECIMALS;

        i_.upperShiftThreshold = i_.upperShiftThreshold / FOUR_DECIMALS;
        i_.lowerShiftThreshold = i_.lowerShiftThreshold / FOUR_DECIMALS;

        if (
            (i_.fee > X13) ||
            (i_.revenueCut > TWO_DECIMALS) ||
            (i_.centerPrice <= i_.minCenterPrice) ||
            (i_.centerPrice >= i_.maxCenterPrice) ||
            (i_.centerPriceContract > X19) ||
            (i_.upperPercent > (FOUR_DECIMALS - TWO_DECIMALS)) || // capping range to 99%
            (i_.lowerPercent > (FOUR_DECIMALS - TWO_DECIMALS)) || // capping range to 99%
            (i_.upperPercent == 0) ||
            (i_.lowerPercent == 0) ||
            (i_.upperShiftThreshold > TWO_DECIMALS) ||
            (i_.lowerShiftThreshold > TWO_DECIMALS) ||
            ((i_.upperShiftThreshold == 0) && (i_.lowerShiftThreshold > 0)) ||
            ((i_.upperShiftThreshold > 0) && (i_.lowerShiftThreshold == 0)) ||
            (i_.shiftTime == 0) ||
            (i_.shiftTime > X24) ||
            (i_.minCenterPrice == 0) || 
            (v_.token0Decimals < MIN_TOKEN_DECIMALS) ||
            (v_.token0Decimals > MAX_TOKEN_DECIMALS) ||
            (v_.token1Decimals < MIN_TOKEN_DECIMALS) ||
            (v_.token1Decimals > MAX_TOKEN_DECIMALS)
        ) {
            revert InvalidParams();
        }

        _transferTokenIn(i_.dexKey.token0, i_.token0Amount);
        _transferTokenIn(i_.dexKey.token1, i_.token1Amount);

        (v_.token0NumeratorPrecision, v_.token0DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token0Decimals);
        (v_.token1NumeratorPrecision, v_.token1DenominatorPrecision) = _calculateNumeratorAndDenominatorPrecisions(v_.token1Decimals);

        _dexVariables[v_.dexId] = 
            (i_.fee << DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) |
            (i_.revenueCut << DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) |
            ((i_.rebalancingStatus ? uint256(1) : uint256(0)) << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) |
            (BM.toBigNumber(i_.centerPrice, BIG_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BM.ROUND_DOWN) << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) |
            (i_.centerPriceContract << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) |
            (i_.upperPercent << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) |
            (i_.lowerPercent << DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) |
            (i_.upperShiftThreshold << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) |
            (i_.lowerShiftThreshold << DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT) |
            (v_.token0Decimals << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) |
            (v_.token1Decimals << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) |
            (((i_.token0Amount * v_.token0NumeratorPrecision) / v_.token0DenominatorPrecision) << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) |
            (((i_.token1Amount * v_.token1NumeratorPrecision) / v_.token1DenominatorPrecision) << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED);

        _centerPriceShift[v_.dexId] = 
            (block.timestamp << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) |
            (i_.shiftTime << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME) |
            (BM.toBigNumber(i_.maxCenterPrice, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BM.ROUND_UP) << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE) |
            (BM.toBigNumber(i_.minCenterPrice, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BM.ROUND_DOWN) << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE);
        
        _dexesList.push(i_.dexKey);
        
        emit LogInitialize(i_.dexKey, v_.dexId, _dexVariables[v_.dexId], _centerPriceShift[v_.dexId], i_);
    }

    /// @dev update the fee and revenue cut for the dex
    /// @param dexKey_ the dex key
    /// @param fee_ in 4 decimals, 10000 = 1%
    /// @param revenueCut_ in 4 decimals, 10000 = 1%
    function updateFeeAndRevenueCut(DexKey calldata dexKey_, uint256 fee_, uint256 revenueCut_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        // cut is an integer in storage slot which is more than enough
        // but from UI we are allowing to send in 4 decimals to maintain consistency & avoid human error in future
        if (revenueCut_ != 0 && revenueCut_ < FOUR_DECIMALS) {
            // human input error. should send 0 for wanting 0, not 0 because of precision reduction.
            revert InvalidRevenueCut(revenueCut_);
        }

        revenueCut_ = revenueCut_ / FOUR_DECIMALS;

        if (fee_ > X13 || revenueCut_ > TWO_DECIMALS) {
            revert InvalidParams();
        }

        _dexVariables[dexId_] = (dexVariables_ & ~(X20 << DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE)) | 
            (fee_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) |
            (revenueCut_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT);

        emit LogUpdateFeeAndRevenueCut(dexKey_, dexId_, _dexVariables[dexId_], fee_, revenueCut_ * FOUR_DECIMALS);
    }

    /// @dev update the rebalancing status for the dex
    /// @param dexKey_ the dex key
    /// @param rebalancingStatus_ the rebalancing status (true = on, false = off)
    function updateRebalancingStatus(DexKey calldata dexKey_, bool rebalancingStatus_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }
        
        _dexVariables[dexId_] = (dexVariables_ & ~(X2 << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS)) |
            (rebalancingStatus_ ? uint256(1) : uint256(0)) << DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS;

        emit LogUpdateRebalancingStatus(dexKey_, dexId_, _dexVariables[dexId_], rebalancingStatus_);
    }

    /// @dev update the range percents for the dex
    /// @param dexKey_ the dex key
    /// @param upperPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerPercent_ in 4 decimals, 10000 = 1%
    /// @param shiftTime_ in secs, in how much time the upper percent configs change should be fully done
    function updateRangePercents(
        DexKey calldata dexKey_,
        uint256 upperPercent_,
        uint256 lowerPercent_,
        uint256 shiftTime_
    ) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        upperPercent_ = upperPercent_ / TWO_DECIMALS;
        lowerPercent_ = lowerPercent_ / TWO_DECIMALS;

        if (
            (upperPercent_ > (FOUR_DECIMALS - TWO_DECIMALS)) || // capping range to 99%
            (lowerPercent_ > (FOUR_DECIMALS - TWO_DECIMALS)) || // capping range to 99%
            (upperPercent_ == 0) ||
            (lowerPercent_ == 0) ||
            (shiftTime_ > X20) ||
            (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) & X1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert InvalidParams();
        }

        _dexVariables[dexId_] = (dexVariables_ & ~(X28 << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT)) |
            ((shiftTime_ > 0 ? uint256(1) : uint256(0)) << DSL.BITS_DEX_LITE_DEX_VARIABLES_RANGE_PERCENT_SHIFT_ACTIVE) |
            (upperPercent_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) |
            (lowerPercent_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT);

        uint256 oldUpperPercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_PERCENT) & X14;
        uint256 oldLowerPercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_PERCENT) & X14;

        if (shiftTime_ > 0) {
            _rangeShift[dexId_] = 
                (oldUpperPercent_ << DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_UPPER_RANGE_PERCENT) | 
                (oldLowerPercent_ << DSL.BITS_DEX_LITE_RANGE_SHIFT_OLD_LOWER_RANGE_PERCENT) | 
                (shiftTime_ << DSL.BITS_DEX_LITE_RANGE_SHIFT_TIME_TO_SHIFT) | 
                (block.timestamp << DSL.BITS_DEX_LITE_RANGE_SHIFT_TIMESTAMP);
        }
        // Note _rangeShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateRangePercents(dexKey_, dexId_, _dexVariables[dexId_], _rangeShift[dexId_], upperPercent_ * TWO_DECIMALS, lowerPercent_ * TWO_DECIMALS, shiftTime_);
    }

    /// @dev update the shift time for the dex for rebalancing
    /// @param dexKey_ the dex key
    /// @param shiftTime_ in secs, in how much time rebalancing should be fully done.
    function updateShiftTime(DexKey calldata dexKey_, uint256 shiftTime_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }
        
        if (shiftTime_ == 0 || shiftTime_ > X24) {
            revert InvalidParams();
        }

        _centerPriceShift[dexId_] = (_centerPriceShift[dexId_] & ~(X24 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME)) | 
            (shiftTime_ << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_SHIFTING_TIME);

        emit LogUpdateShiftTime(dexKey_, dexId_, _centerPriceShift[dexId_], shiftTime_);
    }

    /// @dev update the center price limits for the dex
    /// @param dexKey_ the dex key
    /// @param maxCenterPrice_ 1:1 means 1e27 
    /// @param minCenterPrice_ 1:1 means 1e27
    function updateCenterPriceLimits(DexKey calldata dexKey_, uint256 maxCenterPrice_, uint256 minCenterPrice_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        uint256 centerPrice_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE) & X40;
        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);

        if (
            (maxCenterPrice_ <= minCenterPrice_) ||
            (centerPrice_ <= minCenterPrice_) ||
            (centerPrice_ >= maxCenterPrice_) ||
            (minCenterPrice_ == 0)
        ) {
            revert InvalidParams();
        }

        _centerPriceShift[dexId_] = (_centerPriceShift[dexId_] & ~(X56 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE)) | 
            (BM.toBigNumber(maxCenterPrice_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BM.ROUND_UP) << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MAX_CENTER_PRICE) |
            (BM.toBigNumber(minCenterPrice_, SMALL_COEFFICIENT_SIZE, DEFAULT_EXPONENT_SIZE, BM.ROUND_DOWN) << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_MIN_CENTER_PRICE);

        emit LogUpdateCenterPriceLimits(dexKey_, dexId_, _centerPriceShift[dexId_], maxCenterPrice_, minCenterPrice_);
    }

    /// @dev update the threshold percent for the dex
    /// @param dexKey_ the dex key
    /// @param upperThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param lowerThresholdPercent_ in 4 decimals, 10000 = 1%
    /// @param shiftTime_ in secs, in how much time the upper config changes should be fully done.
    function updateThresholdPercent(
        DexKey calldata dexKey_,
        uint256 upperThresholdPercent_,
        uint256 lowerThresholdPercent_,
        uint256 shiftTime_
    ) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        // thresholds are with 1% precision, hence removing last 4 decimals.
        // we are allowing to send in 4 decimals to maintain consistency with other params
        upperThresholdPercent_ = upperThresholdPercent_ / FOUR_DECIMALS;
        lowerThresholdPercent_ = lowerThresholdPercent_ / FOUR_DECIMALS;
        if (
            (upperThresholdPercent_ > TWO_DECIMALS) ||
            (lowerThresholdPercent_ > TWO_DECIMALS) ||
            ((upperThresholdPercent_ == 0) && (lowerThresholdPercent_ > 0)) ||
            ((upperThresholdPercent_ > 0) && (lowerThresholdPercent_ == 0)) ||
            (shiftTime_ > X20) ||
            (((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE) & X1) == 1) // if last shift is still active then don't allow a newer shift
        ) {
            revert InvalidParams();
        }

        _dexVariables[dexId_] =
            (dexVariables_ & ~(X14 << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT)) |
            ((shiftTime_ > 0 ? uint256(1) : uint256(0)) << DSL.BITS_DEX_LITE_DEX_VARIABLES_THRESHOLD_PERCENT_SHIFT_ACTIVE) |
            (upperThresholdPercent_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) |
            (lowerThresholdPercent_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT);

        uint oldUpperThresholdPercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_UPPER_SHIFT_THRESHOLD_PERCENT) & X7;
        uint oldLowerThresholdPercent_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_LOWER_SHIFT_THRESHOLD_PERCENT) & X7;

        if (shiftTime_ > 0) {
            _thresholdShift[dexId_] = 
                (oldUpperThresholdPercent_ << DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_UPPER_THRESHOLD_PERCENT) |
                (oldLowerThresholdPercent_ << DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_OLD_LOWER_THRESHOLD_PERCENT) |
                (shiftTime_ << DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIME_TO_SHIFT) |
                (block.timestamp << DSL.BITS_DEX_LITE_THRESHOLD_SHIFT_TIMESTAMP);
        }
        // Note _thresholdShift is reset when the previous shift is fully completed, which is forced to have happened through if check above

        emit LogUpdateThresholdPercent(dexKey_, dexId_, _dexVariables[dexId_], _thresholdShift[dexId_], upperThresholdPercent_ * FOUR_DECIMALS, lowerThresholdPercent_ * FOUR_DECIMALS, shiftTime_);
    }

    /// @dev update the center price address (nonce) for the dex
    /// @param dexKey_ the dex key
    /// @param centerPriceAddress_ nonce < X19, this nonce will be used to calculate contract address
    /// @param percent_ in 4 decimals, 10000 = 1%
    /// @param time_ in secs, in how much time the center price should be fully shifted.
    function updateCenterPriceAddress(
        DexKey calldata dexKey_,
        uint256 centerPriceAddress_,
        uint256 percent_,
        uint256 time_
    ) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        if ((centerPriceAddress_ > X19) || (percent_ == 0) || (percent_ > X20) || (time_ == 0) || (time_ > X20)) {
            revert InvalidParams();
        }

        if (centerPriceAddress_ > 0) {
            address centerPrice_ = AC.addressCalc(DEPLOYER_CONTRACT, centerPriceAddress_);
            _checkIsContract(centerPrice_);
            // note: if address is made 0 then as well in the last swap currentPrice is updated on storage, so code will start using that automatically
            _dexVariables[dexId_] =
                (dexVariables_ & ~(X19 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS)) |
                (centerPriceAddress_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS) |
                (uint256(1) << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE);

            _centerPriceShift[dexId_] = (_centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT)) |
                (percent_ << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT) |
                (time_ << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIME_TO_SHIFT) |
                (block.timestamp << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_TIMESTAMP);
        } else {
            _dexVariables[dexId_] = (_dexVariables[dexId_] & ~(X19 << DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_CONTRACT_ADDRESS));

            _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X73 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_PERCENT);
        }

        emit LogUpdateCenterPriceAddress(dexKey_, dexId_, _dexVariables[dexId_], _centerPriceShift[dexId_], centerPriceAddress_, percent_, time_);
    }

    /// @dev deposit tokens into the dex
    /// @param dexKey_ the dex key
    /// @param token0Amount_ the token0 amount
    /// @param token1Amount_ the token1 amount
    function deposit(DexKey calldata dexKey_, uint256 token0Amount_, uint256 token1Amount_, uint256 priceMax_, uint256 priceMin_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        _transferTokenIn(dexKey_.token0, token0Amount_);
        _transferTokenIn(dexKey_.token1, token1Amount_);

        uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
        if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) token0Amount_ /= 10 ** (token0Decimals_ - TOKENS_DECIMALS_PRECISION);
        else token0Amount_ *= 10 ** (TOKENS_DECIMALS_PRECISION - token0Decimals_);

        uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
        if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) token1Amount_ /= 10 ** (token1Decimals_ - TOKENS_DECIMALS_PRECISION);
        else token1Amount_ *= 10 ** (TOKENS_DECIMALS_PRECISION - token1Decimals_);

        uint256 token0TotalSupply_ = ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60) + token0Amount_;
        uint256 token1TotalSupply_ = ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60) + token1Amount_;

        dexVariables_ = (dexVariables_ & ~(X120 << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED)) |
            (token0TotalSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) |
            (token1TotalSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED);

        _dexVariables[dexId_] = dexVariables_;
        
        uint256 price_ = _getPrice(dexKey_, dexVariables_, dexId_, token0TotalSupply_, token1TotalSupply_);

        if (price_ > priceMax_ || price_ < priceMin_) revert SlippageLimitExceeded(price_, priceMax_, priceMin_);

        emit LogDeposit(dexKey_, dexId_, dexVariables_, token0Amount_, token1Amount_);
    }

    /// @dev withdraw tokens from the dex
    /// @param dexKey_ the dex key
    /// @param token0Amount_ the token0 amount
    /// @param token1Amount_ the token1 amount
    /// @param to_ the address to send the tokens to
    function withdraw(DexKey calldata dexKey_, uint256 token0Amount_, uint256 token1Amount_, address to_, uint256 priceMax_, uint256 priceMin_) public _onlyDelegateCall {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];
        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        _transferTokenOut(dexKey_.token0, token0Amount_, to_);
        _transferTokenOut(dexKey_.token1, token1Amount_, to_);

        uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
        if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) token0Amount_ /= 10 ** (token0Decimals_ - TOKENS_DECIMALS_PRECISION);
        else token0Amount_ *= 10 ** (TOKENS_DECIMALS_PRECISION - token0Decimals_);

        uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
        if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) token1Amount_ /= 10 ** (token1Decimals_ - TOKENS_DECIMALS_PRECISION);
        else token1Amount_ *= 10 ** (TOKENS_DECIMALS_PRECISION - token1Decimals_);

        uint256 token0TotalSupply_ = ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60) - token0Amount_;
        uint256 token1TotalSupply_ = ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60) - token1Amount_;

        dexVariables_ = (dexVariables_ & ~(X120 << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED)) |
            (token0TotalSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) |
            (token1TotalSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED);
        
        _dexVariables[dexId_] = dexVariables_;

        uint256 price_ = _getPrice(dexKey_, dexVariables_, dexId_, token0TotalSupply_, token1TotalSupply_);
        if (price_ > priceMax_ || price_ < priceMin_) revert SlippageLimitExceeded(price_, priceMax_, priceMin_);

        emit LogWithdraw(dexKey_, dexId_, dexVariables_, token0Amount_, token1Amount_);
    }

    /// @dev update the extra data address in storage slot
    /// @param extraDataAddress_ the address to set in the extra data slot
    function updateExtraDataAddress(address extraDataAddress_) public _onlyDelegateCall {
        assembly {
            sstore(EXTRA_DATA_SLOT, extraDataAddress_)
        }

        emit LogUpdateExtraDataAddress(extraDataAddress_);
    }

    /// @dev collect revenue from the dex
    /// @param tokens_ the tokens to collect revenue from
    /// @param amounts_ the amounts of tokens to collect revenue from
    /// @param to_ the address to send the tokens to
    function collectRevenue(address[] calldata tokens_, uint256[] calldata amounts_, address to_) public _onlyDelegateCall {
        for (uint256 i = 0; i < tokens_.length; ) {
            _transferTokenOut(tokens_[i], amounts_[i], to_);
            unchecked {++i;}
        }

        emit LogCollectRevenue(tokens_, amounts_, to_);
    }
}

