// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

abstract contract Variables {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// First 1 bit  => 0 => re-entrancy. If 0 then allow transaction to go, else throw.
    /// Next 40 bits => 1-40 => last to last stored price. BigNumber (32 bits precision, 8 bits exponent)
    /// Next 40 bits => 41-80 => last stored price of pool. BigNumber (32 bits precision, 8 bits exponent)
    /// Next 40 bits => 81-120 => center price. Center price from where the ranges will be calculated. BigNumber (32 bits precision, 8 bits exponent)
    /// Next 33 bits => 121-153 => last interaction time stamp
    /// Next 22 bits => 154-175 => max 4194303 seconds (~1165 hrs, ~48.5 days), time difference between last to last and last price stored
    /// Next 3 bits  => 176-178 => oracle checkpoint, if 0 then first slot, if 7 then last slot
    /// Next 16 bits => 179-194 => current mapping or oracle, after every 8 transaction it will increase by 1. Max capacity is 65535 but it can be lower than that check dexVariables2
    /// Next 1 bit  => 195 => is oracle active?
    uint internal dexVariables;

    /// Next  1 bit  => 0 => is smart collateral enabled?
    /// Next  1 bit  => 1 => is smart debt enabled?
    /// Next 17 bits => 2-18 => fee (1% = 10000, max value: 100000 = 10%, fee should not be more than 10%)
    /// Next  7 bits => 19-25 => revenue cut from fee (1 = 1%, 100 = 100%). If fee is 1000 = 0.1% and revenue cut is 10 = 10% then governance get 0.01% of every swap
    /// Next  1 bit  => 26 => percent active change going on or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time.
    /// Next 20 bits => 27-46 => upperPercent (1% = 10000, max value: 104.8575%) upperRange - upperRange * upperPercent = centerPrice. Hence, upperRange = centerPrice / (1 - upperPercent)
    /// Next 20 bits => 47-66 => lowerPercent. lowerRange = centerPrice - centerPrice * lowerPercent.
    /// Next  1 bit  => 67 => threshold percent active change going on or not, 0 = false, 1 = true, if true than that means governance has updated the below percents and the update should happen with a specified time.
    /// Next 10 bits => 68-77 => upper shift threshold percent, 1 = 0.1%. 1000 = 100%. if currentPrice > (centerPrice + (upperRange - centerPrice) * (1000 - upperShiftThresholdPercent) / 1000) then trigger shift
    /// Next 10 bits => 78-87 => lower shift threshold percent, 1 = 0.1%. 1000 = 100%. if currentPrice < (centerPrice - (centerPrice - lowerRange) * (1000 - lowerShiftThresholdPercent) / 1000) then trigger shift
    /// Next 24 bits => 88-111 => Shifting time (~194 days) (rate = (% up + % down) / time ?)
    /// Next 30 bits => 112-131 => Address of center price if center price should be fetched externally, for example, for wstETH <> ETH pool, fetch wstETH exchange rate into stETH from wstETH contract.
    /// Why fetch it externally? Because let's say pool width is 0.1% and wstETH temporarily got depeg of 0.5% then pool will start to shift to newer pricing
    /// but we don't want pool to shift to 0.5% because we know the depeg will recover so to avoid the loss for users.
    /// Next 30 bits => 142-171 => Hooks bits, calculate hook address by storing deployment nonce from factory.
    /// Next 28 bits => 172-199 => max center price. BigNumber (20 bits precision, 8 bits exponent)
    /// Next 28 bits => 200-227 => min center price. BigNumber (20 bits precision, 8 bits exponent)
    /// Next 10 bits => 228-237 => utilization limit of token0. Max value 1000 = 100%, if 100% then no need to check the utilization.
    /// Next 10 bits => 238-247 => utilization limit of token1. Max value 1000 = 100%, if 100% then no need to check the utilization.
    /// Next 1  bit  => 248     => is center price shift active
    /// Last 1  bit  => 255     => Pause swap & arbitrage (only perfect functions will be usable), if we need to pause entire DEX then that can be done through pausing DEX on Liquidity Layer
    uint internal dexVariables2;

    /// first 128 bits => 0-127 => total supply shares
    /// last 128 bits => 128-255 => max supply shares
    uint internal _totalSupplyShares;

    /// @dev user supply data: user -> data
    /// Aside from 1st bit, entire bits here are same as liquidity layer _userSupplyData. Hence exact same supply & borrow limit library can be used
    /// First  1 bit  =>       0 => is user allowed to supply? 0 = not allowed, 1 = allowed
    /// Next  64 bits =>   1- 64 => user supply amount/shares; BigMath: 56 | 8
    /// Next  64 bits =>  65-128 => previous user withdrawal limit; BigMath: 56 | 8
    /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  14 bits => 162-175 => expand withdrawal limit percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383).
    ///                             @dev shrinking is instant
    /// Next  24 bits => 176-199 => withdrawal limit expand duration in seconds.(Max value 16_777_215; ~4_660 hours, ~194 days)
    /// Next  18 bits => 200-217 => base withdrawal limit: below this, 100% withdrawals can be done (aka shares can be burned); BigMath: 10 | 8
    /// Next  38 bits => 218-255 => empty for future use
    mapping(address => uint) internal _userSupplyData;

    /// first 128 bits => 0-127 => total borrow shares
    /// last 128 bits => 128-255 => max borrow shares
    uint internal _totalBorrowShares;

    /// @dev user borrow data: user -> data
    /// Aside from 1st bit, entire bits here are same as liquidity layer _userBorrowData. Hence exact same supply & borrow limit library function can be used
    /// First  1 bit  =>       0 => is user allowed to borrow? 0 = not allowed, 1 = allowed
    /// Next  64 bits =>   1- 64 => user debt amount/shares; BigMath: 56 | 8
    /// Next  64 bits =>  65-128 => previous user debt ceiling; BigMath: 56 | 8
    /// Next  33 bits => 129-161 => last triggered process timestamp (enough until 16 March 2242 -> max value 8589934591)
    /// Next  14 bits => 162-175 => expand debt ceiling percentage (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383)
    ///                             @dev shrinking is instant
    /// Next  24 bits => 176-199 => debt ceiling expand duration in seconds (Max value 16_777_215; ~4_660 hours, ~194 days)
    /// Next  18 bits => 200-217 => base debt ceiling: below this, there's no debt ceiling limits; BigMath: 10 | 8
    /// Next  18 bits => 218-235 => max debt ceiling: absolute maximum debt ceiling can expand to; BigMath: 10 | 8
    /// Next  20 bits => 236-255 => empty for future use
    mapping(address => uint) internal _userBorrowData;

    /// Price difference between last swap of last block & last swap of new block
    /// If last swap happened at Block B - 4 and next swap happened after 4 blocks at Block B then it will store that difference
    /// considering time difference between these 4 blocks is 48 seconds, hence time will be stored as 48
    /// New oracle update:
    /// time to 9 bits and precision to 22 bits
    /// if time exceeds 9 bits which is 511 sec or ~8.5 min then we will use 2 oracle slot to store the data
    /// we will leave the both time slot as 0 and on first sign + precision slot we will store time and
    /// on second sign + precision slot we will store sign & precision
    /// First 9 bits =>   0-  8 => time, 511 seconds
    /// Next   1 bit  =>  9     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits =>  10- 31 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits =>  32- 40 => time, 511 seconds
    /// Next   1 bit  =>  41     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits =>  42- 63 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits =>  64- 72 => time, 511 seconds
    /// Next   1 bit  =>  73     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits =>  74- 95 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits =>  96-104 => time, 511 seconds
    /// Next   1 bit  => 105     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits => 106-127 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits => 128-136 => time, 511 seconds
    /// Next   1 bit  => 137     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits => 138-159 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits => 160-168 => time, 511 seconds
    /// Next   1 bit  => 169     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits => 170-191 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits => 192-200 => time, 511 seconds
    /// Next   1 bit  => 201     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits => 202-223 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    /// Next  9 bits => 224-232 => time, 511 seconds
    /// Next   1 bit  => 233     => sign of percent in change, if 1 then 0 or positive, else negative
    /// Next  22 bits => 234-255 => 4194303, change in price, max change is capped to 5%, so 4194303 = 5%, 1 = 0.0000011920931797249746%
    mapping(uint => uint) internal _oracle;

    /// First 20 bits =>  0-19 => old upper shift
    /// Next  20 bits => 20-39 => old lower shift
    /// Next  20 bits => 40-59 => in seconds, ~12 days max, shift can last for max ~12 days
    /// Next  33 bits => 60-92 => timestamp of when the shift has started.
    uint128 internal _rangeShift;

    /// First 10 bits =>  0- 9 => old upper shift
    /// Next  10 bits => 10-19 => empty so we can use same helper function
    /// Next  10 bits => 20-29 => old lower shift
    /// Next  10 bits => 30-39 => empty so we can use same helper function
    /// Next  20 bits => 40-59 => in seconds, ~12 days max, shift can last for max ~12 days
    /// Next  33 bits => 60-92 => timestamp of when the shift has started.
    /// Next  24 bits => 93-116 => old threshold time
    uint128 internal _thresholdShift;

    /// Shifting is fuzzy and with time it'll keep on getting closer and then eventually get over
    /// First 33 bits => 0 -32 => starting timestamp
    /// Next  20 bits => 33-52 => % shift
    /// Next  20 bits => 53-72 => time to shift that percent
    uint256 internal _centerPriceShift;
}
