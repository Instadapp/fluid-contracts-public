// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { LiquidityCalcs } from "../../../libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../libraries/liquiditySlotsLink.sol";
import { DexSlotsLink } from "../../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { DexOracleBase } from "./dexOracleBase.sol";

interface ICenterPrice {
    function centerPrice() external view returns (uint256);
}

abstract contract DexPricesAndExchangePrices is DexOracleBase {
    uint256 private constant X8 = 0xff;
    uint256 private constant X10 = 0x3ff;
    uint256 private constant X20 = 0xfffff;
    uint256 private constant X24 = 0xffffff;
    uint256 private constant X28 = 0xfffffff;
    uint256 private constant X30 = 0x3fffffff;
    uint256 private constant X33 = 0x1ffffffff;
    uint256 private constant X40 = 0xffffffffff;
    uint256 private constant X64 = 0xffffffffffffffff;
    uint256 private constant X128 = 0xffffffffffffffffffffffffffffffff;

    uint256 private constant THREE_DECIMALS = 1e3;
    uint256 private constant SIX_DECIMALS = 1e6;

    uint256 private constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 private constant DEFAULT_EXPONENT_MASK = 0xff;

    /// @dev This function calculates the new value of a parameter after a shifting process.
    /// @param current_ The current value is the final value where the shift ends
    /// @param old_ The old value from where shifting started.
    /// @param timePassed_ The time passed since shifting started.
    /// @param shiftDuration_ The total duration of the shift when old_ reaches current_
    /// @return The new value of the parameter after the shift.
    function _calcShiftingDone(
        uint current_,
        uint old_,
        uint timePassed_,
        uint shiftDuration_
    ) internal pure returns (uint) {
        if (current_ > old_) {
            uint diff_ = current_ - old_;
            current_ = old_ + ((diff_ * timePassed_) / shiftDuration_);
        } else {
            uint diff_ = old_ - current_;
            current_ = old_ - ((diff_ * timePassed_) / shiftDuration_);
        }
        return current_;
    }

    /// @dev Calculates the new upper and lower range values during an active range shift
    /// @param upperRange_ The target upper range value
    /// @param lowerRange_ The target lower range value
    /// @param dexVariables2_ needed in case shift is ended and we need to update dexVariables2
    /// @return The updated upper range, lower range, and dexVariables2
    /// @notice This function handles the gradual shifting of range values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcRangeShifting(
        uint upperRange_,
        uint lowerRange_,
        uint dexVariables2_
    ) internal view returns (uint, uint, uint) {
        uint rangeShift_ = DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_RANGE_THRESHOLD_SHIFTS_SLOT)) & X128;
        uint oldUpperRange_ = rangeShift_ & X20;
        uint oldLowerRange_ = (rangeShift_ >> 20) & X20;
        uint shiftDuration_ = (rangeShift_ >> 40) & X20;
        uint startTimeStamp_ = ((rangeShift_ >> 60) & X33);
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            // note: not deleting from storage as this is oracle address
            // delete _rangeShift;

            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcThresholdShifting.
            // Note: not fetching & updating on storage because this is oracle address
            dexVariables2_ = dexVariables2_ & ~uint(1 << 26);
            // dexVariables2 = dexVariables2_;
            return (upperRange_, lowerRange_, dexVariables2_);
        }
        uint timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperRange_, oldUpperRange_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerRange_, oldLowerRange_, timePassed_, shiftDuration_),
            dexVariables2_
        );
    }

    /// @dev Calculates the new upper and lower threshold values during an active threshold shift
    /// @param upperThreshold_ The target upper threshold value
    /// @param lowerThreshold_ The target lower threshold value
    /// @param thresholdTime_ The time passed since shifting started
    /// @return The updated upper threshold, lower threshold, and threshold time
    /// @notice This function handles the gradual shifting of threshold values over time
    /// @notice If the shift is complete, it updates the state and clears the shift data
    function _calcThresholdShifting(
        uint upperThreshold_,
        uint lowerThreshold_,
        uint thresholdTime_
    ) internal view returns (uint, uint, uint) {
        uint thresholdShift_ = (DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_RANGE_THRESHOLD_SHIFTS_SLOT)) >> 128) &
            X128;
        uint oldUpperThreshold_ = thresholdShift_ & X20;
        uint oldLowerThreshold_ = (thresholdShift_ >> 20) & X20;
        uint shiftDuration_ = (thresholdShift_ >> 40) & X20;
        uint startTimeStamp_ = ((thresholdShift_ >> 60) & X33);
        uint oldThresholdTime_ = (thresholdShift_ >> 93) & X24;
        if ((startTimeStamp_ + shiftDuration_) < block.timestamp) {
            // shifting fully done
            // note: not deleting from storage as this is oracle address
            // delete _thresholdShift;

            // making active shift as 0 because shift is over
            // fetching from storage and storing in storage, aside from admin module dexVariables2 only updates from this function and _calcRangeShifting.
            // note: not updating on storage because this is oracle address
            // dexVariables2 = dexVariables2 & ~uint(1 << 67);
            return (upperThreshold_, lowerThreshold_, thresholdTime_);
        }
        uint timePassed_ = block.timestamp - startTimeStamp_;
        return (
            _calcShiftingDone(upperThreshold_, oldUpperThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(lowerThreshold_, oldLowerThreshold_, timePassed_, shiftDuration_),
            _calcShiftingDone(thresholdTime_, oldThresholdTime_, timePassed_, shiftDuration_)
        );
    }

    struct PricesAndExchangePrice {
        uint lastStoredPrice; // last stored price in 1e27 decimals
        uint centerPrice; // last stored price in 1e27 decimals
        uint upperRange; // price at upper range in 1e27 decimals
        uint lowerRange; // price at lower range in 1e27 decimals
        uint geometricMean; // geometric mean of upper range & lower range in 1e27 decimals
        uint supplyToken0ExchangePrice;
        uint borrowToken0ExchangePrice;
        uint supplyToken1ExchangePrice;
        uint borrowToken1ExchangePrice;
    }

    struct CollateralReserves {
        uint token0RealReserves;
        uint token1RealReserves;
        uint token0ImaginaryReserves;
        uint token1ImaginaryReserves;
    }

    struct DebtReserves {
        uint token0Debt;
        uint token1Debt;
        uint token0RealReserves;
        uint token1RealReserves;
        uint token0ImaginaryReserves;
        uint token1ImaginaryReserves;
    }

    /// @notice Calculates and returns the current prices and exchange prices for the pool
    /// @return pex_ A struct containing the calculated prices and exchange prices:
    ///         - pex_.lastStoredPrice: The last stored price in 1e27 decimals
    ///         - pex_.centerPrice: The calculated or fetched center price in 1e27 decimals
    ///         - pex_.upperRange: The upper range price limit in 1e27 decimals
    ///         - pex_.lowerRange: The lower range price limit in 1e27 decimals
    ///         - pex_.geometricMean: The geometric mean of upper range & lower range in 1e27 decimals
    ///         - pex_.supplyToken0ExchangePrice: The current exchange price for supplying token0
    ///         - pex_.borrowToken0ExchangePrice: The current exchange price for borrowing token0
    ///         - pex_.supplyToken1ExchangePrice: The current exchange price for supplying token1
    ///         - pex_.borrowToken1ExchangePrice: The current exchange price for borrowing token1
    /// @dev This function performs the following operations:
    ///      1. Determines the center price (either from storage, external source, or calculated)
    ///      2. Retrieves the last stored price from dexVariables_
    ///      3. Calculates the upper and lower range prices based on the center price and range percentages
    ///      4. Checks if rebalancing is needed based on threshold settings
    ///      5. Adjusts prices if necessary based on the time elapsed and threshold conditions
    ///      6. Update the dexVariables2_ if changes were made
    ///      7. Returns the calculated prices and exchange prices in the PricesAndExchangePrice struct
    function _getPricesAndExchangePrices() internal view returns (PricesAndExchangePrice memory pex_) {
        uint dexVariables_ = DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES_SLOT));
        uint dexVariables2_ = DEX_.readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        uint centerPrice_;

        if (((dexVariables2_ >> 248) & 1) == 0) {
            // centerPrice_ => center price hook
            centerPrice_ = (dexVariables2_ >> 112) & X30;
            if (centerPrice_ == 0) {
                centerPrice_ = (dexVariables_ >> 81) & X40;
                centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
            } else {
                // center price should be fetched from external source. For exmaple, in case of wstETH <> ETH pool,
                // we would want the center price to be pegged to wstETH exchange rate into ETH

                // Note: commenting ICenterPrice call as oracle should be used for non peg pools so center price should not be pegged to external source
                // centerPrice_ = ICenterPrice(AddressCalcs.addressCalc(DEPLOYER_CONTRACT, centerPrice_)).centerPrice();
                revert("PricesAndExchangePrices: center price should not be pegged to external source");
            }
        } else {
            // an active centerPrice_ shift is going on

            // @Samyak please verify below. I removed the _calcCenterPrice() method completely. The reverts here are very risky if we ever add
            // a center price for any reason to an existing non-peg pool as oracle would start reverting. That should never happen but
            // very critical to remember this.

            // Note: commenting _calcCenterPrice call as oracle should be used for non peg pools so center price should not be shifting,
            // as the shift uses an external source.
            // centerPrice_ = _calcCenterPrice(dexVariables_, dexVariables2_);
            revert("PricesAndExchangePrices: center price should not be pegged to external source");
        }

        uint lastStoredPrice_ = (dexVariables_ >> 41) & X40;
        lastStoredPrice_ = (lastStoredPrice_ >> DEFAULT_EXPONENT_SIZE) << (lastStoredPrice_ & DEFAULT_EXPONENT_MASK);

        uint upperRange_ = ((dexVariables2_ >> 27) & X20);
        uint lowerRange_ = ((dexVariables2_ >> 47) & X20);
        if (((dexVariables2_ >> 26) & 1) == 1) {
            // an active range shift is going on
            (upperRange_, lowerRange_, dexVariables2_) = _calcRangeShifting(upperRange_, lowerRange_, dexVariables2_);
        }

        unchecked {
            // adding into unchecked because upperRange_ & lowerRange_ can only be > 0 & < SIX_DECIMALS
            // 1% = 1e4, 100% = 1e6
            upperRange_ = (centerPrice_ * SIX_DECIMALS) / (SIX_DECIMALS - upperRange_);
            // 1% = 1e4, 100% = 1e6
            lowerRange_ = (centerPrice_ * (SIX_DECIMALS - lowerRange_)) / SIX_DECIMALS;
        }

        bool changed_;
        {
            // goal will be to keep threshold percents 0 if center price is fetched from external source
            // checking if threshold are set non 0 then only rebalancing is on
            if (((dexVariables2_ >> 68) & X20) > 0) {
                uint upperThreshold_ = (dexVariables2_ >> 68) & X10;
                uint lowerThreshold_ = (dexVariables2_ >> 78) & X10;
                uint shiftingTime_ = (dexVariables2_ >> 88) & X24;
                if (((dexVariables2_ >> 67) & 1) == 1) {
                    // if active shift is going on for threshold then calculate threshold real time
                    (upperThreshold_, lowerThreshold_, shiftingTime_) = _calcThresholdShifting(
                        upperThreshold_,
                        lowerThreshold_,
                        shiftingTime_
                    );
                }

                unchecked {
                    if (
                        lastStoredPrice_ >
                        (centerPrice_ +
                            ((upperRange_ - centerPrice_) * (THREE_DECIMALS - upperThreshold_)) /
                            THREE_DECIMALS)
                    ) {
                        uint timeElapsed_ = block.timestamp - ((dexVariables_ >> 121) & X33);
                        // price shifting towards upper range
                        if (timeElapsed_ < shiftingTime_) {
                            centerPrice_ = centerPrice_ + ((upperRange_ - centerPrice_) * timeElapsed_) / shiftingTime_;
                        } else {
                            // 100% price shifted
                            centerPrice_ = upperRange_;
                        }
                        changed_ = true;
                    } else if (
                        lastStoredPrice_ <
                        (centerPrice_ -
                            ((centerPrice_ - lowerRange_) * (THREE_DECIMALS - lowerThreshold_)) /
                            THREE_DECIMALS)
                    ) {
                        uint timeElapsed_ = block.timestamp - ((dexVariables_ >> 121) & X33);
                        // price shifting towards lower range
                        if (timeElapsed_ < shiftingTime_) {
                            centerPrice_ = centerPrice_ - ((centerPrice_ - lowerRange_) * timeElapsed_) / shiftingTime_;
                        } else {
                            // 100% price shifted
                            centerPrice_ = lowerRange_;
                        }
                        changed_ = true;
                    }
                }
            }
        }

        // temp_ => max center price
        uint temp_ = (dexVariables2_ >> 172) & X28;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        if (centerPrice_ > temp_) {
            // if center price is greater than max center price
            centerPrice_ = temp_;
            changed_ = true;
        } else {
            // check if center price is less than min center price
            // temp_ => min center price
            temp_ = (dexVariables2_ >> 200) & X28;
            temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
            if (centerPrice_ < temp_) {
                centerPrice_ = temp_;
                changed_ = true;
            }
        }

        // if centerPrice_ is changed then calculating upper and lower range again
        if (changed_) {
            upperRange_ = ((dexVariables2_ >> 27) & X20);
            lowerRange_ = ((dexVariables2_ >> 47) & X20);
            if (((dexVariables2_ >> 26) & 1) == 1) {
                (upperRange_, lowerRange_, dexVariables2_) = _calcRangeShifting(
                    upperRange_,
                    lowerRange_,
                    dexVariables2_
                );
            }

            unchecked {
                // adding into unchecked because upperRange_ & lowerRange_ can only be > 0 & < SIX_DECIMALS
                // 1% = 1e4, 100% = 1e6
                upperRange_ = (centerPrice_ * SIX_DECIMALS) / (SIX_DECIMALS - upperRange_);
                // 1% = 1e4, 100% = 1e6
                lowerRange_ = (centerPrice_ * (SIX_DECIMALS - lowerRange_)) / SIX_DECIMALS;
            }
        }

        pex_.lastStoredPrice = lastStoredPrice_;
        pex_.centerPrice = centerPrice_;
        pex_.upperRange = upperRange_;
        pex_.lowerRange = lowerRange_;

        unchecked {
            if (upperRange_ < 1e38) {
                // 1e38 * 1e38 = 1e76 which is less than max uint limit
                pex_.geometricMean = FixedPointMathLib.sqrt(upperRange_ * lowerRange_);
            } else {
                // upperRange_ price is pretty large hence lowerRange_ will also be pretty large
                pex_.geometricMean = FixedPointMathLib.sqrt((upperRange_ / 1e18) * (lowerRange_ / 1e18)) * 1e18;
            }
        }

        // Exchange price will remain same as Liquidity Layer
        (pex_.supplyToken0ExchangePrice, pex_.borrowToken0ExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(EXCHANGE_PRICE_TOKEN_0_SLOT)
        );

        (pex_.supplyToken1ExchangePrice, pex_.borrowToken1ExchangePrice) = LiquidityCalcs.calcExchangePrices(
            LIQUIDITY.readFromStorage(EXCHANGE_PRICE_TOKEN_1_SLOT)
        );
    }

    /// @dev getting reserves outside range.
    /// @param gp_ is geometric mean pricing of upper percent & lower percent
    /// @param pa_ price of upper range or lower range
    /// @param rx_ real reserves of token0 or token1
    /// @param ry_ whatever is rx_ the other will be ry_
    function _calculateReservesOutsideRange(
        uint gp_,
        uint pa_,
        uint rx_,
        uint ry_
    ) internal pure returns (uint xa_, uint yb_) {
        // equations we have:
        // 1. x*y = k
        // 2. xa*ya = k
        // 3. xb*yb = k
        // 4. Pa = ya / xa = upperRange_ (known)
        // 5. Pb = yb / xb = lowerRange_ (known)
        // 6. x - xa = rx = real reserve of x (known)
        // 7. y - yb = ry = real reserve of y (known)
        // With solving we get:
        // ((Pa*Pb)^(1/2) - Pa)*xa^2 + (rx * (Pa*Pb)^(1/2) + ry)*xa + rx*ry = 0
        // yb = yb = xa * (Pa * Pb)^(1/2)

        // xa = (GP⋅rx + ry + (-rx⋅ry⋅4⋅(GP - Pa) + (GP⋅rx + ry)^2)^0.5) / (2Pa - 2GP)
        // multiply entire equation by 1e27 to remove the price decimals precision of 1e27
        // xa = (GP⋅rx + ry⋅1e27 + (rx⋅ry⋅4⋅(Pa - GP)⋅1e27 + (GP⋅rx + ry⋅1e27)^2)^0.5) / 2*(Pa - GP)
        // dividing the equation with 2*(Pa - GP). Pa is always > GP so answer will be positive.
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅4⋅(Pa - GP)⋅1e27) / 4*(Pa - GP)^2) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)
        // xa = (((GP⋅rx + ry⋅1e27) / 2*(Pa - GP)) + (((rx⋅ry⋅1e27) / (Pa - GP)) + ((GP⋅rx + ry⋅1e27) / 2*(Pa - GP))^2)^0.5)

        // dividing in 3 parts for simplification:
        // part1 = (Pa - GP)
        // part2 = (GP⋅rx + ry⋅1e27) / (2*part1)
        // part3 = rx⋅ry
        // note: part1 will almost always be < 1e28 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e29
        uint p1_ = pa_ - gp_;
        uint p2_ = ((gp_ * rx_) + (ry_ * 1e27)) / (2 * p1_);
        uint p3_ = rx_ * ry_;
        // to avoid overflowing
        p3_ = (p3_ < 1e50) ? ((p3_ * 1e27) / p1_) : (p3_ / p1_) * 1e27;

        // xa = part2 + (part3 + (part2 * part2))^(1/2)
        // yb = xa_ * gp_
        xa_ = p2_ + FixedPointMathLib.sqrt((p3_ + (p2_ * p2_)));
        yb_ = (xa_ * gp_) / 1e27;
    }

    /// @dev Retrieves collateral amount from liquidity layer for a given token
    /// @param supplyTokenSlot_ The storage slot for the supply token data
    /// @param tokenExchangePrice_ The exchange price of the token
    /// @param isToken0_ Boolean indicating if the token is token0 (true) or token1 (false)
    /// @return tokenSupply_ The calculated liquidity collateral amount
    function _getLiquidityCollateral(
        bytes32 supplyTokenSlot_,
        uint tokenExchangePrice_,
        bool isToken0_
    ) internal view returns (uint tokenSupply_) {
        uint tokenSupplyData_ = LIQUIDITY.readFromStorage(supplyTokenSlot_);
        tokenSupply_ = (tokenSupplyData_ >> LiquiditySlotsLink.BITS_USER_SUPPLY_AMOUNT) & X64;
        tokenSupply_ = (tokenSupply_ >> DEFAULT_EXPONENT_SIZE) << (tokenSupply_ & DEFAULT_EXPONENT_MASK);

        if (tokenSupplyData_ & 1 == 1) {
            // supply with interest is on
            unchecked {
                tokenSupply_ = (tokenSupply_ * tokenExchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        unchecked {
            tokenSupply_ = isToken0_
                ? ((tokenSupply_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION)
                : ((tokenSupply_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION);
        }
    }

    /// @notice Calculates the real and imaginary reserves for collateral tokens
    /// @dev This function retrieves the supply of both tokens from the liquidity layer,
    ///      adjusts them based on exchange prices, and calculates imaginary reserves
    ///      based on the geometric mean and price range
    /// @param geometricMean_ The geometric mean of the token prices
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0SupplyExchangePrice_ The exchange price for token0 from liquidity layer
    /// @param token1SupplyExchangePrice_ The exchange price for token1 from liquidity layer
    /// @return c_ A struct containing the calculated real and imaginary reserves for both tokens:
    ///         - token0RealReserves: The real reserves of token0
    ///         - token1RealReserves: The real reserves of token1
    ///         - token0ImaginaryReserves: The imaginary reserves of token0
    ///         - token1ImaginaryReserves: The imaginary reserves of token1
    function _getCollateralReserves(
        uint geometricMean_,
        uint upperRange_,
        uint lowerRange_,
        uint token0SupplyExchangePrice_,
        uint token1SupplyExchangePrice_
    ) internal view returns (CollateralReserves memory c_) {
        uint token0Supply_ = _getLiquidityCollateral(SUPPLY_TOKEN_0_SLOT, token0SupplyExchangePrice_, true);
        uint token1Supply_ = _getLiquidityCollateral(SUPPLY_TOKEN_1_SLOT, token1SupplyExchangePrice_, false);

        if (geometricMean_ < 1e27) {
            (c_.token0ImaginaryReserves, c_.token1ImaginaryReserves) = _calculateReservesOutsideRange(
                geometricMean_,
                upperRange_,
                token0Supply_,
                token1Supply_
            );
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (c_.token1ImaginaryReserves, c_.token0ImaginaryReserves) = _calculateReservesOutsideRange(
                (1e54 / geometricMean_),
                (1e54 / lowerRange_),
                token1Supply_,
                token0Supply_
            );
        }

        c_.token0RealReserves = token0Supply_;
        c_.token1RealReserves = token1Supply_;
        unchecked {
            c_.token0ImaginaryReserves += token0Supply_;
            c_.token1ImaginaryReserves += token1Supply_;
        }
    }

    /// @notice Calculates the real and imaginary debt reserves for both tokens
    /// @dev This function uses a quadratic equation to determine the debt reserves
    ///      based on the geometric mean price and the current debt amounts
    /// @param gp_ The geometric mean price of upper range & lower range
    /// @param pb_ The price of lower range
    /// @param dx_ The debt amount of one token
    /// @param dy_ The debt amount of the other token
    /// @return rx_ The real debt reserve of the first token
    /// @return ry_ The real debt reserve of the second token
    /// @return irx_ The imaginary debt reserve of the first token
    /// @return iry_ The imaginary debt reserve of the second token
    function _calculateDebtReserves(
        uint gp_,
        uint pb_,
        uint dx_,
        uint dy_
    ) internal pure returns (uint rx_, uint ry_, uint irx_, uint iry_) {
        // Assigning letter to knowns:
        // c = debtA
        // d = debtB
        // e = upperPrice
        // f = lowerPrice
        // g = upperPrice^1/2
        // h = lowerPrice^1/2

        // c = 1
        // d = 2000
        // e = 2222.222222
        // f = 1800
        // g = 2222.222222^1/2
        // h = 1800^1/2

        // Assigning letter to unknowns:
        // w = realDebtReserveA
        // x = realDebtReserveB
        // y = imaginaryDebtReserveA
        // z = imaginaryDebtReserveB
        // k = k

        // below quadratic will give answer of realDebtReserveB
        // A, B, C of quadratic equation:
        // A = h
        // B = dh - cfg
        // C = -cfdh

        // A = lowerPrice^1/2
        // B = debtB⋅lowerPrice^1/2 - debtA⋅lowerPrice⋅upperPrice^1/2
        // C = -(debtA⋅lowerPrice⋅debtB⋅lowerPrice^1/2)

        // x = (cfg − dh + (4cdf(h^2)+(cfg−dh)^2))^(1/2)) / 2h
        // simplifying dividing by h, note h = f^1/2
        // x = ((c⋅g⋅(f^1/2) − d) / 2 + ((4⋅c⋅d⋅f⋅f) / (4h^2) + ((c⋅f⋅g) / 2h − (d⋅h) / 2h)^2))^(1/2))
        // x = ((c⋅g⋅(f^1/2) − d) / 2 + ((c⋅d⋅f) + ((c⋅g⋅(f^1/2) − d) / 2)^2))^(1/2))

        // dividing in 3 parts for simplification:
        // part1 = (c⋅g⋅(f^1/2) − d) / 2
        // part2 = (c⋅d⋅f)
        // x = (part1 + (part2 + part1^2)^(1/2))
        // note: part1 will almost always be < 1e27 but in case it goes above 1e27 then it's extremely unlikely it'll go above > 1e28

        // part1 = ((debtA * upperPrice^1/2 * lowerPrice^1/2) - debtB) / 2
        // note: upperPrice^1/2 * lowerPrice^1/2 = geometric mean
        // part1 = ((debtA * geometricMean) - debtB) / 2
        // part2 = debtA * debtB * lowerPrice

        // converting decimals properly as price is in 1e27 decimals
        // part1 = ((debtA * geometricMean) - (debtB * 1e27)) / (2 * 1e27)
        // part2 = (debtA * debtB * lowerPrice) / 1e27
        // final x equals:
        // x = (part1 + (part2 + part1^2)^(1/2))
        int p1_ = (int(dx_ * gp_) - int(dy_ * 1e27)) / (2 * 1e27);
        uint p2_ = (dx_ * dy_);
        p2_ = p2_ < 1e50 ? (p2_ * pb_) / 1e27 : (p2_ / 1e27) * pb_;
        ry_ = uint(p1_ + int(FixedPointMathLib.sqrt((p2_ + uint(p1_ * p1_)))));

        // finding z:
        // x^2 - zx + cfz = 0
        // z*(x - cf) = x^2
        // z = x^2 / (x - cf)
        // z = x^2 / (x - debtA * lowerPrice)
        // converting decimals properly as price is in 1e27 decimals
        // z = (x^2 * 1e27) / ((x * 1e27) - (debtA * lowerPrice))

        iry_ = ((ry_ * 1e27) - (dx_ * pb_));
        if (iry_ < SIX_DECIMALS) {
            // almost impossible situation to ever get here
            revert("Debt reserves too low");
        }
        if (ry_ < 1e25) {
            iry_ = (ry_ * ry_ * 1e27) / iry_;
        } else {
            // note: it can never result in negative as final result will always be in positive
            iry_ = (ry_ * ry_) / (iry_ / 1e27);
        }

        // finding y
        // x = z * c / (y + c)
        // y + c = z * c / x
        // y = (z * c / x) - c
        // y = (z * debtA / x) - debtA
        irx_ = ((iry_ * dx_) / ry_) - dx_;

        // finding w
        // w = y * d / (z + d)
        // w = (y * debtB) / (z + debtB)
        rx_ = (irx_ * dy_) / (iry_ + dy_);
    }

    /// @notice Calculates the debt amount for a given token from liquidity layer
    /// @param borrowTokenSlot_ The storage slot for the token's borrow data
    /// @param tokenExchangePrice_ The current exchange price of the token
    /// @param isToken0_ Boolean indicating if this is for token0 (true) or token1 (false)
    /// @return tokenDebt_ The calculated debt amount for the token
    function _getLiquidityDebt(
        bytes32 borrowTokenSlot_,
        uint tokenExchangePrice_,
        bool isToken0_
    ) internal view returns (uint tokenDebt_) {
        uint tokenBorrowData_ = LIQUIDITY.readFromStorage(borrowTokenSlot_);

        tokenDebt_ = (tokenBorrowData_ >> LiquiditySlotsLink.BITS_USER_BORROW_AMOUNT) & X64;
        tokenDebt_ = (tokenDebt_ >> 8) << (tokenDebt_ & X8);

        if (tokenBorrowData_ & 1 == 1) {
            // borrow with interest is on
            unchecked {
                tokenDebt_ = (tokenDebt_ * tokenExchangePrice_) / LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
            }
        }

        unchecked {
            tokenDebt_ = isToken0_
                ? ((tokenDebt_ * TOKEN_0_NUMERATOR_PRECISION) / TOKEN_0_DENOMINATOR_PRECISION)
                : ((tokenDebt_ * TOKEN_1_NUMERATOR_PRECISION) / TOKEN_1_DENOMINATOR_PRECISION);
        }
    }

    /// @notice Calculates the debt reserves for both tokens
    /// @param geometricMean_ The geometric mean of the upper and lower price ranges
    /// @param upperRange_ The upper price range
    /// @param lowerRange_ The lower price range
    /// @param token0BorrowExchangePrice_ The exchange price of token0 from liquidity layer
    /// @param token1BorrowExchangePrice_ The exchange price of token1 from liquidity layer
    /// @return d_ The calculated debt reserves for both tokens, containing:
    ///         - token0Debt: The debt amount of token0
    ///         - token1Debt: The debt amount of token1
    ///         - token0RealReserves: The real reserves of token0 derived from token1 debt
    ///         - token1RealReserves: The real reserves of token1 derived from token0 debt
    ///         - token0ImaginaryReserves: The imaginary debt reserves of token0
    ///         - token1ImaginaryReserves: The imaginary debt reserves of token1
    function _getDebtReserves(
        uint geometricMean_,
        uint upperRange_,
        uint lowerRange_,
        uint token0BorrowExchangePrice_,
        uint token1BorrowExchangePrice_
    ) internal view returns (DebtReserves memory d_) {
        uint token0Debt_ = _getLiquidityDebt(BORROW_TOKEN_0_SLOT, token0BorrowExchangePrice_, true);
        uint token1Debt_ = _getLiquidityDebt(BORROW_TOKEN_1_SLOT, token1BorrowExchangePrice_, false);

        d_.token0Debt = token0Debt_;
        d_.token1Debt = token1Debt_;

        if (geometricMean_ < 1e27) {
            (
                d_.token0RealReserves,
                d_.token1RealReserves,
                d_.token0ImaginaryReserves,
                d_.token1ImaginaryReserves
            ) = _calculateDebtReserves(geometricMean_, lowerRange_, token0Debt_, token1Debt_);
        } else {
            // inversing, something like `xy = k` so for calculation we are making everything related to x into y & y into x
            // 1 / geometricMean for new geometricMean
            // 1 / lowerRange will become upper range
            // 1 / upperRange will become lower range
            (
                d_.token1RealReserves,
                d_.token0RealReserves,
                d_.token1ImaginaryReserves,
                d_.token0ImaginaryReserves
            ) = _calculateDebtReserves((1e54 / geometricMean_), (1e54 / upperRange_), token1Debt_, token0Debt_);
        }
    }

    function _calculateNewColReserves(
        PricesAndExchangePrice memory pex_,
        CollateralReserves memory currentCollateralReserves_,
        uint newPrice_
    ) internal pure returns (CollateralReserves memory newCollateralReserves_) {
        uint k_ = currentCollateralReserves_.token0ImaginaryReserves *
            currentCollateralReserves_.token1ImaginaryReserves;

        uint token0OutsideRange_ = currentCollateralReserves_.token0ImaginaryReserves -
            currentCollateralReserves_.token0RealReserves;
        uint token1OutsideRange_ = currentCollateralReserves_.token1ImaginaryReserves -
            currentCollateralReserves_.token1RealReserves;

        uint x_;
        uint y_;

        if (pex_.upperRange < newPrice_) {
            x_ = token0OutsideRange_;
            y_ = k_ / x_;
        } else if (pex_.lowerRange > newPrice_) {
            y_ = token1OutsideRange_;
            x_ = k_ / y_;
        } else {
            // y_/x_ = newPrice_
            // y_ = newPrice_* x_
            // y_ * x_ = k_
            // (newPrice_* x_) * x_ = k_
            // x_^2 = k_ / newPrice_
            // x_ = sqrt(k_ / newPrice_)
            if (k_ < 1e50) {
                x_ = FixedPointMathLib.sqrt((k_ * 1e27) / newPrice_);
            } else {
                x_ = FixedPointMathLib.sqrt((k_ / newPrice_) * 1e27);
            }
            y_ = (newPrice_ * x_) / 1e27;
        }

        newCollateralReserves_.token0RealReserves = x_ - token0OutsideRange_;
        newCollateralReserves_.token1RealReserves = y_ - token1OutsideRange_;
        newCollateralReserves_.token0ImaginaryReserves = x_;
        newCollateralReserves_.token1ImaginaryReserves = y_;
    }

    function _calculateNewDebtReserves(
        PricesAndExchangePrice memory pex_,
        DebtReserves memory currentDebtReserves_,
        uint newPrice_
    ) internal pure returns (DebtReserves memory newDebtReserves_) {
        uint k_ = currentDebtReserves_.token0ImaginaryReserves * currentDebtReserves_.token1ImaginaryReserves;
        uint token0OutsideRange_ = currentDebtReserves_.token0ImaginaryReserves -
            currentDebtReserves_.token0RealReserves;
        uint token1OutsideRange_ = currentDebtReserves_.token1ImaginaryReserves -
            currentDebtReserves_.token1RealReserves;

        uint x_;
        uint y_;
        if (pex_.upperRange < newPrice_) {
            x_ = token0OutsideRange_;
            y_ = k_ / x_;
        } else if (pex_.lowerRange > newPrice_) {
            y_ = token1OutsideRange_;
            x_ = k_ / y_;
        } else {
            // y_/x_ = newPrice_
            // y_ = newPrice_* x_
            // y_ * x_ = k_
            // (newPrice_* x_) * x_ = k_
            // x_^2 = k_ / newPrice_
            // x_ = sqrt(k_ / newPrice_)
            if (k_ < 1e50) {
                x_ = FixedPointMathLib.sqrt((k_ * 1e27) / newPrice_);
            } else {
                x_ = FixedPointMathLib.sqrt((k_ / newPrice_) * 1e27);
            }
            y_ = (newPrice_ * x_) / 1e27;
        }

        newDebtReserves_.token0RealReserves = x_ - token0OutsideRange_;
        newDebtReserves_.token1RealReserves = y_ - token1OutsideRange_;
        newDebtReserves_.token0ImaginaryReserves = x_;
        newDebtReserves_.token1ImaginaryReserves = y_;

        // Both numerator and denominator are scaled to 1e6 to factor in fee scaling.
        uint256 numerator_ = newDebtReserves_.token0RealReserves * currentDebtReserves_.token1ImaginaryReserves;
        uint256 denominator_ = currentDebtReserves_.token0ImaginaryReserves - newDebtReserves_.token0RealReserves;

        // Using the swap formula: (AmountOut * iReserveX) / (iReserveY - AmountOut)
        newDebtReserves_.token1Debt = numerator_ / denominator_;

        numerator_ = newDebtReserves_.token1RealReserves * currentDebtReserves_.token0ImaginaryReserves;
        denominator_ = currentDebtReserves_.token1ImaginaryReserves - newDebtReserves_.token1RealReserves;

        // Using the swap formula: (AmountOut * iReserveX) / (iReserveY - AmountOut)
        newDebtReserves_.token0Debt = numerator_ / denominator_;
    }
}
