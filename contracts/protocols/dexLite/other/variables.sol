// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./immutableVariables.sol";

abstract contract Variables is ImmutableVariables {
    /// @dev admin address
    mapping(address => uint256) internal _isAuth;

    /// @dev dexes list
    DexKey[] internal _dexesList;

    // First 13 bits => 0   - 12  => fee (1% = 10000, max value: 8191 = .8191%)
    // Next  7  bits => 13  - 19  => revenue cut (1 = 1%)
    // Next  2  bit  => 20  - 21  => rebalancing status (0 = off, 1 = on but not active, 2 = rebalancing active towards upper range, 3 = rebalancing active towards lower range)
    // Next  1  bit  => 22        => is center price shift active
    // Next  40 bits => 23  - 62  => center price. Center price from where the ranges will be calculated. BigNumber (32 bits precision, 8 bits exponent)
    // Next  19 bits => 63  - 81  => center price contract address (Deployment Factory Nonce)
    // Next  1  bit  => 82        => range percent shift active or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time
    // Next  14 bits => 83  - 96  => upperPercent (1% = 100) upperRange - upperRange * upperPercent = centerPrice. Hence, upperRange = centerPrice / (1 - upperPercent)
    // Next  14 bits => 97  - 110 => lowerPercent (1% = 100) lowerRange = centerPrice - centerPrice * lowerPercent
    // Next  1  bit  => 111       => threshold percent shift active or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time
    // Next  7 bits  => 112 - 118 => upper shift threshold percent, 1 = 1%. 100 = 100%. if currentPrice > (centerPrice + (upperRange - centerPrice) * (100 - upperShiftThresholdPercent) / 100) then trigger shift
    // Next  7 bits  => 119 - 125 => lower shift threshold percent, 1 = 1%. 100 = 100%. if currentPrice < (centerPrice - (centerPrice - lowerRange) * (100 - lowerShiftThresholdPercent) / 100) then trigger shift
    // Next  5  bits => 126 - 130 => token 0 decimals
    // Next  5  bits => 131 - 135 => token 1 decimals
    // Next  60 bits => 136 - 195 => total token 0 adjusted amount
    // Next  60 bits => 196 - 255 => total token 1 adjusted amount
    /// @dev dex id => dex variables
    mapping(bytes8 => uint256) internal _dexVariables;

    /// NOTE: Center price shift is always fuzzy, and can shift because of rebalancing or center price shift
    // First 33 bits => 0   - 32  => last interaction timestamp (only stored when either rebalancing or center price shift is active)
    /// REBALANCING RELATED THINGS
    // First 24 bits => 33  - 56  => shifting time (max ~194 days)
    // Next  28 bits => 57  - 84  => max center price. BigNumber (20 bits precision, 8 bits exponent)
    // Next  28 bits => 85  - 112 => min center price. BigNumber (20 bits precision, 8 bits exponent)
    /// CENTER PRICE SHIFT RELATED THINGS
    // First 20 bits => 113 - 132 => % shift (1% = 1000)
    // Next  20 bits => 133 - 152 => time to shift that percent, ~12 days max
    // Next  33 bits => 153 - 185 => timestamp of when the shift started
    // Last 70 bits empty
    /// @dev dex id => center price shift
    mapping(bytes8 => uint256) internal _centerPriceShift;

    /// Range Shift (first 128 bits)
    // First 14 bits => 0  - 13 => old upper range percent
    // Next  14 bits => 14 - 27 => old lower range percent
    // Next  20 bits => 28 - 47 => time to shift in seconds, ~12 days max, shift can last for max ~12 days
    // Next  33 bits => 48 - 80 => timestamp of when the shift has started.
    // Last 175 bits empty
    /// @dev dex id => range shift
    mapping(bytes8 => uint256) internal _rangeShift;

    // First 7  bits => 0  - 6  => old upper threshold percent
    // Next  7  bits => 7  - 13 => old lower threshold percent
    // Next  20 bits => 14 - 33 => time to shift in seconds, ~12 days max, shift can last for max ~12 days
    // Next  33 bits => 34 - 66 => timestamp of when the shift has started
    // Last 189 bits empty
    /// @dev dex id => threshold shift
    mapping(bytes8 => uint256) internal _thresholdShift;
}
