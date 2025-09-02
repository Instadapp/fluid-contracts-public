// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./helpers.sol";

abstract contract CoreInternals is Helpers {
    function _swapIn(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountIn_
    ) internal returns (uint256 amountOut_) {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];

        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }

        uint256 token0AdjustedSupply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60;
        uint256 token1AdjustedSupply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60;
        (uint256 centerPrice_, uint256 token0ImaginaryReserves_, uint256 token1ImaginaryReserves_) = 
            _getPricesAndReserves(dexKey_, dexVariables_, dexId_, token0AdjustedSupply_, token1AdjustedSupply_);

        unchecked {
            if (swap0To1_) {
                uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
                if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) {
                    amountIn_ /= _tenPow(token0Decimals_ - TOKENS_DECIMALS_PRECISION);
                } else {
                    amountIn_ *= _tenPow(TOKENS_DECIMALS_PRECISION - token0Decimals_);
                }

                if (amountIn_ < FOUR_DECIMALS || amountIn_ > X60) {
                    revert InvalidSwapAmounts(amountIn_);
                }
                if (amountIn_ > (token0ImaginaryReserves_ / 2)) {
                    revert ExcessiveSwapAmount(amountIn_, token0ImaginaryReserves_);
                }

                uint256 fee_ = (amountIn_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) & X13)) / SIX_DECIMALS;
                // amountOut = (amountIn * iReserveOut) / (iReserveIn + amountIn)
                amountOut_ = ((amountIn_ - fee_) * token1ImaginaryReserves_) / (token0ImaginaryReserves_ + (amountIn_ - fee_));
                token0AdjustedSupply_ += amountIn_ - ((fee_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) & X7)) / TWO_DECIMALS);

                if (token1AdjustedSupply_ < amountOut_) {
                    revert TokenReservesTooLow(amountOut_, token1AdjustedSupply_);
                }
                token1AdjustedSupply_ -= amountOut_;

                if (((token1AdjustedSupply_) < ((token0AdjustedSupply_ * centerPrice_) / (PRICE_PRECISION * MINIMUM_LIQUIDITY_SWAP)))) {
                    revert TokenReservesRatioTooHigh(token0AdjustedSupply_, token1AdjustedSupply_);
                }
            } else {
                uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
                if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) {
                    amountIn_ /= _tenPow(token1Decimals_ - TOKENS_DECIMALS_PRECISION);
                } else {
                    amountIn_ *= _tenPow(TOKENS_DECIMALS_PRECISION - token1Decimals_);
                }

                if (amountIn_ < FOUR_DECIMALS || amountIn_ > X60) {
                    revert InvalidSwapAmounts(amountIn_);
                }
                if (amountIn_ > (token1ImaginaryReserves_ / 2)) {
                    revert ExcessiveSwapAmount(amountIn_, token1ImaginaryReserves_);
                }

                uint256 fee_ = (amountIn_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) & X13)) / SIX_DECIMALS;
                // amountOut = (amountIn * iReserveOut) / (iReserveIn + amountIn)
                amountOut_ = ((amountIn_ - fee_) * token0ImaginaryReserves_) / (token1ImaginaryReserves_ + (amountIn_ - fee_));
                token1AdjustedSupply_ += amountIn_ - ((fee_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) & X7)) / TWO_DECIMALS);

                if (token0AdjustedSupply_ < amountOut_) {
                    revert TokenReservesTooLow(amountOut_, token0AdjustedSupply_);
                }
                token0AdjustedSupply_ -= amountOut_;

                if (((token0AdjustedSupply_) < ((token1AdjustedSupply_ * PRICE_PRECISION) / (centerPrice_ * MINIMUM_LIQUIDITY_SWAP)))) {
                    revert TokenReservesRatioTooHigh(token0AdjustedSupply_, token1AdjustedSupply_);
                }
            }
        }

        {
            uint256 rebalancingStatus_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) & X2;
            if (rebalancingStatus_ > 0) {
                // rebalancing is active
                uint256 price_;
                unchecked {
                    price_ = (swap0To1_ ? (token1ImaginaryReserves_ - amountOut_) * PRICE_PRECISION / (token0ImaginaryReserves_ + amountIn_) : 
                        (token1ImaginaryReserves_ + amountIn_) * PRICE_PRECISION / (token0ImaginaryReserves_ - amountOut_));
                }
                rebalancingStatus_ = _getRebalancingStatus(dexVariables_, dexId_, rebalancingStatus_, price_, centerPrice_);
            }
            // NOTE: we are using dexVariables_ and not _dexVariables[dexId_] here to check if the center price shift is active
            // _dexVariables[dexId_] might have become inactive in this transaction above, but still we are storing the timestamp for this transaction
            // storing the timestamp is not important, but we are still doing it because we don't want to use _dexVariables[dexId_] here because of gas
            if (rebalancingStatus_ > 1 || ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE) & X1) == 1) {
                _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X33 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) | 
                    (block.timestamp << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP);
            }
        }

        if (token0AdjustedSupply_ > X60 || token1AdjustedSupply_ > X60) {
            revert AdjustedSupplyOverflow(dexId_, token0AdjustedSupply_, token1AdjustedSupply_);
        }

        dexVariables_ = _dexVariables[dexId_] & ~(X120 << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) | 
            (token0AdjustedSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) | 
            (token1AdjustedSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED);

        _dexVariables[dexId_] = dexVariables_;

        if (swap0To1_) {
            emit LogSwap(
                (uint256(uint64(dexId_)) << DSL.BITS_DEX_LITE_SWAP_DATA_DEX_ID) | 
                (uint256(1) << DSL.BITS_DEX_LITE_SWAP_DATA_SWAP_0_TO_1) | // swap 0 to 1 bit is 1
                (amountIn_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_IN) | 
                (amountOut_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_OUT), 
                dexVariables_
            );

            uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
            if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) {
                amountOut_ *= _tenPow(token1Decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                amountOut_ /= _tenPow(TOKENS_DECIMALS_PRECISION - token1Decimals_);
            }

        } else {
            emit LogSwap(
                (uint256(uint64(dexId_)) << DSL.BITS_DEX_LITE_SWAP_DATA_DEX_ID) | 
                // swap 0 to 1 bit is 0
                (amountIn_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_IN) | 
                (amountOut_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_OUT), 
                dexVariables_
            );

            uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
            if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) {
                amountOut_ *= _tenPow(token0Decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                amountOut_ /= _tenPow(TOKENS_DECIMALS_PRECISION - token0Decimals_);
            }
        }
    }

    function _swapOut(
        DexKey calldata dexKey_,
        bool swap0To1_,
        uint256 amountOut_
    ) internal returns (uint256 amountIn_) {
        bytes8 dexId_ = bytes8(keccak256(abi.encode(dexKey_)));
        uint256 dexVariables_ = _dexVariables[dexId_];

        if (dexVariables_ == 0) {
            revert DexNotInitialized(dexId_);
        }
    
        uint256 token0AdjustedSupply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) & X60;
        uint256 token1AdjustedSupply_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED) & X60;
        (uint256 centerPrice_, uint256 token0ImaginaryReserves_, uint256 token1ImaginaryReserves_) = 
            _getPricesAndReserves(dexKey_, dexVariables_, dexId_, token0AdjustedSupply_, token1AdjustedSupply_);

        unchecked {
            if (swap0To1_) {
                uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
                if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) {
                    amountOut_ /= _tenPow(token1Decimals_ - TOKENS_DECIMALS_PRECISION);
                } else {
                    amountOut_ *= _tenPow(TOKENS_DECIMALS_PRECISION - token1Decimals_);
                }

                if (amountOut_ < FOUR_DECIMALS || amountOut_ > X60) {
                    revert InvalidSwapAmounts(amountOut_);
                }
                if (amountOut_ > (token1ImaginaryReserves_ / 2)) {
                    revert ExcessiveSwapAmount(amountOut_, token1ImaginaryReserves_);
                }

                // amountIn = (amountOut * iReserveIn) / (iReserveOut - amountOut)
                amountIn_ = (amountOut_ * token0ImaginaryReserves_) / (token1ImaginaryReserves_ - amountOut_);
                uint256 fee_ = ((amountIn_ * SIX_DECIMALS) / (SIX_DECIMALS - ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) & X13))) - amountIn_;
                amountIn_ += fee_;
                token0AdjustedSupply_ += amountIn_ - ((fee_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) & X7)) / TWO_DECIMALS);

                if (token1AdjustedSupply_ < amountOut_) {
                    revert TokenReservesTooLow(amountOut_, token1AdjustedSupply_);
                }
                token1AdjustedSupply_ -= amountOut_;

                if (((token1AdjustedSupply_) < ((token0AdjustedSupply_ * centerPrice_) / (PRICE_PRECISION * MINIMUM_LIQUIDITY_SWAP)))) {
                    revert TokenReservesRatioTooHigh(token0AdjustedSupply_, token1AdjustedSupply_);
                }
            } else {
                uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
                if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) {
                    amountOut_ /= _tenPow(token0Decimals_ - TOKENS_DECIMALS_PRECISION);
                } else {
                    amountOut_ *= _tenPow(TOKENS_DECIMALS_PRECISION - token0Decimals_);
                }
                
                if (amountOut_ < FOUR_DECIMALS || amountOut_ > X60) {
                    revert InvalidSwapAmounts(amountOut_);
                }
                if (amountOut_ > (token0ImaginaryReserves_ / 2)) {
                    revert ExcessiveSwapAmount(amountOut_, token0ImaginaryReserves_);
                }

                // amountIn = (amountOut * iReserveIn) / (iReserveOut - amountOut)
                amountIn_ = (amountOut_ * token1ImaginaryReserves_) / (token0ImaginaryReserves_ - amountOut_);
                uint256 fee_ = ((amountIn_ * SIX_DECIMALS) / (SIX_DECIMALS - ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_FEE) & X13))) - amountIn_;
                amountIn_ += fee_;
                token1AdjustedSupply_ += amountIn_ - ((fee_ * ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REVENUE_CUT) & X7)) / TWO_DECIMALS);

                if (token0AdjustedSupply_ < amountOut_) {
                    revert TokenReservesTooLow(amountOut_, token0AdjustedSupply_);
                }
                token0AdjustedSupply_ -= amountOut_;

                if (((token0AdjustedSupply_) < ((token1AdjustedSupply_ * PRICE_PRECISION) / (centerPrice_ * MINIMUM_LIQUIDITY_SWAP)))) {
                    revert TokenReservesRatioTooHigh(token0AdjustedSupply_, token1AdjustedSupply_);
                }
            }
        }

        {
            uint256 rebalancingStatus_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_REBALANCING_STATUS) & X2;
            if (rebalancingStatus_ > 0) {
                // rebalancing is active
                uint256 price_;
                unchecked {
                    price_ = (swap0To1_ ? (token1ImaginaryReserves_ - amountOut_) * PRICE_PRECISION / (token0ImaginaryReserves_ + amountIn_) : 
                        (token1ImaginaryReserves_ + amountIn_) * PRICE_PRECISION / (token0ImaginaryReserves_ - amountOut_));
                }
                rebalancingStatus_ = _getRebalancingStatus(dexVariables_, dexId_, rebalancingStatus_, price_, centerPrice_);
            }
            if (rebalancingStatus_ > 1 || ((dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_CENTER_PRICE_SHIFT_ACTIVE) & X1) == 1) {
                _centerPriceShift[dexId_] = _centerPriceShift[dexId_] & ~(X33 << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP) | 
                    (block.timestamp << DSL.BITS_DEX_LITE_CENTER_PRICE_SHIFT_LAST_INTERACTION_TIMESTAMP);
            }
        }

        if (token0AdjustedSupply_ > X60 || token1AdjustedSupply_ > X60) {
            revert AdjustedSupplyOverflow(dexId_, token0AdjustedSupply_, token1AdjustedSupply_);
        }

        dexVariables_ = _dexVariables[dexId_] & ~(X120 << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) | 
            (token0AdjustedSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_TOTAL_SUPPLY_ADJUSTED) | 
            (token1AdjustedSupply_ << DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_TOTAL_SUPPLY_ADJUSTED);

        _dexVariables[dexId_] = dexVariables_;

        if (swap0To1_) {
            emit LogSwap(
                (uint256(uint64(dexId_)) << DSL.BITS_DEX_LITE_SWAP_DATA_DEX_ID) | 
                (uint256(1) << DSL.BITS_DEX_LITE_SWAP_DATA_SWAP_0_TO_1) | // swap 0 to 1 bit is 1
                (amountIn_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_IN) | 
                (amountOut_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_OUT), 
                dexVariables_
            );

            uint256 token0Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_0_DECIMALS) & X5;
            if (token0Decimals_ > TOKENS_DECIMALS_PRECISION) {
                amountIn_ *= _tenPow(token0Decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                amountIn_ /= _tenPow(TOKENS_DECIMALS_PRECISION - token0Decimals_);
            }
        } else {
            emit LogSwap(
                (uint256(uint64(dexId_)) << DSL.BITS_DEX_LITE_SWAP_DATA_DEX_ID) | 
                // swap 0 to 1 bit is 0
                (amountIn_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_IN) | 
                (amountOut_ << DSL.BITS_DEX_LITE_SWAP_DATA_AMOUNT_OUT), 
                dexVariables_
            );

            uint256 token1Decimals_ = (dexVariables_ >> DSL.BITS_DEX_LITE_DEX_VARIABLES_TOKEN_1_DECIMALS) & X5;
            if (token1Decimals_ > TOKENS_DECIMALS_PRECISION) {
                amountIn_ *= _tenPow(token1Decimals_ - TOKENS_DECIMALS_PRECISION);
            } else {
                amountIn_ /= _tenPow(TOKENS_DECIMALS_PRECISION - token1Decimals_);
            }
        }
    }
}
