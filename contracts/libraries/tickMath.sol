// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

/// @title library that calculates number "tick" and "ratioX96" from this: ratioX96 = (1.0015^tick) * 2^96
/// @notice this library is used in Fluid Vault protocol for optimiziation.
/// @dev "tick" supports between -32767 and 32767. "ratioX96" supports between 37075072 and 169307877264527972847801929085841449095838922544595
library TickMath {
    /// The minimum tick that can be passed in getRatioAtTick. 1.0015**-32767
    int24 internal constant MIN_TICK = -32767;
    /// The maximum tick that can be passed in getRatioAtTick. 1.0015**32767
    int24 internal constant MAX_TICK = 32767;

    uint256 internal constant FACTOR00 = 0x100000000000000000000000000000000;
    uint256 internal constant FACTOR01 = 0xff9dd7de423466c20352b1246ce4856f; // 2^128/1.0015**1 = 339772707859149738855091969477551883631
    uint256 internal constant FACTOR02 = 0xff3bd55f4488ad277531fa1c725a66d0; // 2^128/1.0015**2 = 339263812140938331358054887146831636176
    uint256 internal constant FACTOR03 = 0xfe78410fd6498b73cb96a6917f853259; // 2^128/1.0015**4 = 338248306163758188337119769319392490073
    uint256 internal constant FACTOR04 = 0xfcf2d9987c9be178ad5bfeffaa123273; // 2^128/1.0015**8 = 336226404141693512316971918999264834163
    uint256 internal constant FACTOR05 = 0xf9ef02c4529258b057769680fc6601b3; // 2^128/1.0015**16 = 332218786018727629051611634067491389875
    uint256 internal constant FACTOR06 = 0xf402d288133a85a17784a411f7aba082; // 2^128/1.0015**32 = 324346285652234375371948336458280706178
    uint256 internal constant FACTOR07 = 0xe895615b5beb6386553757b0352bda90; // 2^128/1.0015**64 = 309156521885964218294057947947195947664
    uint256 internal constant FACTOR08 = 0xd34f17a00ffa00a8309940a15930391a; // 2^128/1.0015**128 = 280877777739312896540849703637713172762 
    uint256 internal constant FACTOR09 = 0xae6b7961714e20548d88ea5123f9a0ff; // 2^128/1.0015**256 = 231843708922198649176471782639349113087
    uint256 internal constant FACTOR10 = 0x76d6461f27082d74e0feed3b388c0ca1; // 2^128/1.0015**512 = 157961477267171621126394973980180876449
    uint256 internal constant FACTOR11 = 0x372a3bfe0745d8b6b19d985d9a8b85bb; // 2^128/1.0015**1024 = 73326833024599564193373530205717235131
    uint256 internal constant FACTOR12 = 0x0be32cbee48979763cf7247dd7bb539d; // 2^128/1.0015**2048 = 15801066890623697521348224657638773661
    uint256 internal constant FACTOR13 = 0x8d4f70c9ff4924dac37612d1e2921e;   // 2^128/1.0015**4096 = 733725103481409245883800626999235102
    uint256 internal constant FACTOR14 = 0x4e009ae5519380809a02ca7aec77;     // 2^128/1.0015**8192 = 1582075887005588088019997442108535
    uint256 internal constant FACTOR15 = 0x17c45e641b6e95dee056ff10;         // 2^128/1.0015**16384 = 7355550435635883087458926352

    /// The minimum value that can be returned from getRatioAtTick. Equivalent to getRatioAtTick(MIN_TICK). ~ Equivalent to `(1 << 96) * (1.0015**-32767)`
    uint256 internal constant MIN_RATIOX96 = 37075072;
    /// The maximum value that can be returned from getRatioAtTick. Equivalent to getRatioAtTick(MAX_TICK).
    /// ~ Equivalent to `(1 << 96) * (1.0015**32767)`, rounding etc. leading to minor difference
    uint256 internal constant MAX_RATIOX96 = 169307877264527972847801929085841449095838922544595;

    uint256 internal constant ZERO_TICK_SCALED_RATIO = 0x1000000000000000000000000; // 1 << 96 // 79228162514264337593543950336
    uint256 internal constant _1E26 = 1e26;

    /// @notice ratioX96 = (1.0015^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return ratioX96 ratio = (debt amount/collateral amount)
    function getRatioAtTick(int tick) internal pure returns (uint256 ratioX96) {
        assembly {
            let absTick_ := sub(xor(tick, sar(255, tick)), sar(255, tick))

            if gt(absTick_, MAX_TICK) {
                revert(0, 0)
            }
            let factor_ := FACTOR00
            if and(absTick_, 0x1) {
                factor_ := FACTOR01
            }
            if and(absTick_, 0x2) {
                factor_ := shr(128, mul(factor_, FACTOR02))
            }
            if and(absTick_, 0x4) {
                factor_ := shr(128, mul(factor_, FACTOR03))
            }
            if and(absTick_, 0x8) {
                factor_ := shr(128, mul(factor_, FACTOR04))
            }
            if and(absTick_, 0x10) {
                factor_ := shr(128, mul(factor_, FACTOR05))
            }
            if and(absTick_, 0x20) {
                factor_ := shr(128, mul(factor_, FACTOR06))
            }
            if and(absTick_, 0x40) {
                factor_ := shr(128, mul(factor_, FACTOR07))
            }
            if and(absTick_, 0x80) {
                factor_ := shr(128, mul(factor_, FACTOR08))
            }
            if and(absTick_, 0x100) {
                factor_ := shr(128, mul(factor_, FACTOR09))
            }
            if and(absTick_, 0x200) {
                factor_ := shr(128, mul(factor_, FACTOR10))
            }
            if and(absTick_, 0x400) {
                factor_ := shr(128, mul(factor_, FACTOR11))
            }
            if and(absTick_, 0x800) {
                factor_ := shr(128, mul(factor_, FACTOR12))
            }
            if and(absTick_, 0x1000) {
                factor_ := shr(128, mul(factor_, FACTOR13))
            }
            if and(absTick_, 0x2000) {
                factor_ := shr(128, mul(factor_, FACTOR14))
            }
            if and(absTick_, 0x4000) {
                factor_ := shr(128, mul(factor_, FACTOR15))
            }

            let precision_ := 0
            if iszero(and(tick, 0x8000000000000000000000000000000000000000000000000000000000000000)) {
                factor_ := div(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, factor_)
                // we round up in the division so getTickAtRatio of the output price is always consistent
                if mod(factor_, 0x100000000) {
                    precision_ := 1
                }
            }
            ratioX96 := add(shr(32, factor_), precision_)
        }
    }

    /// @notice ratioX96 = (1.0015^tick) * 2^96
    /// @dev Throws if ratioX96 > max ratio || ratioX96 < min ratio
    /// @param ratioX96 The input ratio; ratio = (debt amount/collateral amount)
    /// @return tick The output tick for the above formula. Returns in round down form. if tick is 123.23 then 123, if tick is -123.23 then returns -124
    /// @return perfectRatioX96 perfect ratio for the above tick
    function getTickAtRatio(uint256 ratioX96) internal pure returns (int tick, uint perfectRatioX96) {
        assembly {
            if or(gt(ratioX96, MAX_RATIOX96), lt(ratioX96, MIN_RATIOX96)) {
                revert(0, 0)
            }

            let cond := lt(ratioX96, ZERO_TICK_SCALED_RATIO)
            let factor_

            if iszero(cond) {
                // if ratioX96 >= ZERO_TICK_SCALED_RATIO
                factor_ := div(mul(ratioX96, _1E26), ZERO_TICK_SCALED_RATIO)
            }
            if cond {
                // ratioX96 < ZERO_TICK_SCALED_RATIO
                factor_ := div(mul(ZERO_TICK_SCALED_RATIO, _1E26), ratioX96)
            }

            // put in https://www.wolframalpha.com/ whole equation: (1.0015^tick) * 2^96 * 10^26 / 79228162514264337593543950336

            // for tick = 16384
            // ratioX96 = (1.0015^16384) * 2^96 = 3665252098134783297721995888537077351735
            // 3665252098134783297721995888537077351735 * 10^26 / 79228162514264337593543950336 =
            // 4626198540796508716348404308345255985.06131964639489434655721
            if iszero(lt(factor_, 4626198540796508716348404308345255985)) {
                tick := or(tick, 0x4000)
                factor_ := div(mul(factor_, _1E26), 4626198540796508716348404308345255985)
            }
            // for tick = 8192
            // ratioX96 = (1.0015^8192) * 2^96 = 17040868196391020479062776466509865
            // 17040868196391020479062776466509865 * 10^26 / 79228162514264337593543950336 =
            // 21508599537851153911767490449162.3037648642153898377655505172
            if iszero(lt(factor_, 21508599537851153911767490449162)) {
                tick := or(tick, 0x2000)
                factor_ := div(mul(factor_, _1E26), 21508599537851153911767490449162)
            }
            // for tick = 4096
            // ratioX96 = (1.0015^4096) * 2^96 = 36743933851015821532611831851150
            // 36743933851015821532611831851150 * 10^26 / 79228162514264337593543950336 =
            // 46377364670549310883002866648.9777607649742626173648716941385
            if iszero(lt(factor_, 46377364670549310883002866649)) {
                tick := or(tick, 0x1000)
                factor_ := div(mul(factor_, _1E26), 46377364670549310883002866649)
            }
            // for tick = 2048
            // ratioX96 = (1.0015^2048) * 2^96 = 1706210527034005899209104452335
            // 1706210527034005899209104452335 * 10^26 / 79228162514264337593543950336 =
            // 2153540449365864845468344760.06357108484096046743300420319322
            if iszero(lt(factor_, 2153540449365864845468344760)) {
                tick := or(tick, 0x800)
                factor_ := div(mul(factor_, _1E26), 2153540449365864845468344760)
            }
            // for tick = 1024
            // ratioX96 = (1.0015^1024) * 2^96 = 367668226692760093024536487236
            // 367668226692760093024536487236 * 10^26 / 79228162514264337593543950336 =
            // 464062544207767844008185024.950588990554136265212906454481127
            if iszero(lt(factor_, 464062544207767844008185025)) {
                tick := or(tick, 0x400)
                factor_ := div(mul(factor_, _1E26), 464062544207767844008185025)
            }
            // for tick = 512
            // ratioX96 = (1.0015^512) * 2^96 = 170674186729409605620119663668
            // 170674186729409605620119663668 * 10^26 / 79228162514264337593543950336 =
            // 215421109505955298802281577.031879604792139232258508172947569
            if iszero(lt(factor_, 215421109505955298802281577)) {
                tick := or(tick, 0x200)
                factor_ := div(mul(factor_, _1E26), 215421109505955298802281577)
            }
            // for tick = 256
            // ratioX96 = (1.0015^256) * 2^96 = 116285004205991934861656513301
            // 116285004205991934861656513301 * 10^26 / 79228162514264337593543950336 =
            // 146772309890508740607270614.667650899656438875541505058062410
            if iszero(lt(factor_, 146772309890508740607270615)) {
                tick := or(tick, 0x100)
                factor_ := div(mul(factor_, _1E26), 146772309890508740607270615)
            }
            // for tick = 128
            // ratioX96 = (1.0015^128) * 2^96 = 95984619659632141743747099590
            // 95984619659632141743747099590 * 10^26 / 79228162514264337593543950336 =
            // 121149622323187099817270416.157248837742741760456796835775887
            if iszero(lt(factor_, 121149622323187099817270416)) {
                tick := or(tick, 0x80)
                factor_ := div(mul(factor_, _1E26), 121149622323187099817270416)
            }
            // for tick = 64
            // ratioX96 = (1.0015^64) * 2^96 = 87204845308406958006717891124
            // 87204845308406958006717891124 * 10^26 / 79228162514264337593543950336 =
            // 110067989135437147685980801.568068573422377364214113968609839
            if iszero(lt(factor_, 110067989135437147685980801)) {
                tick := or(tick, 0x40)
                factor_ := div(mul(factor_, _1E26), 110067989135437147685980801)
            }
            // for tick = 32
            // ratioX96 = (1.0015^32) * 2^96 = 83120873769022354029916374475
            // 83120873769022354029916374475 * 10^26 / 79228162514264337593543950336 =
            // 104913292358707887270979599.831816586773651266562785765558183
            if iszero(lt(factor_, 104913292358707887270979600)) {
                tick := or(tick, 0x20)
                factor_ := div(mul(factor_, _1E26), 104913292358707887270979600)
            }
            // for tick = 16
            // ratioX96 = (1.0015^16) * 2^96 = 81151180492336368327184716176
            // 81151180492336368327184716176 * 10^26 / 79228162514264337593543950336 =
            // 102427189924701091191840927.762844039579442328381455567932128
            if iszero(lt(factor_, 102427189924701091191840928)) {
                tick := or(tick, 0x10)
                factor_ := div(mul(factor_, _1E26), 102427189924701091191840928)
            }
            // for tick = 8
            // ratioX96 = (1.0015^8) * 2^96 = 80183906840906820640659903620
            // 80183906840906820640659903620 * 10^26 / 79228162514264337593543950336 =
            // 101206318935480056907421312.890625
            if iszero(lt(factor_, 101206318935480056907421313)) {
                tick := or(tick, 0x8)
                factor_ := div(mul(factor_, _1E26), 101206318935480056907421313)
            }
            // for tick = 4
            // ratioX96 = (1.0015^4) * 2^96 = 79704602139525152702959747603
            // 79704602139525152702959747603 * 10^26 / 79228162514264337593543950336 =
            // 100601351350506250000000000
            if iszero(lt(factor_, 100601351350506250000000000)) {
                tick := or(tick, 0x4)
                factor_ := div(mul(factor_, _1E26), 100601351350506250000000000)
            }
            // for tick = 2
            // ratioX96 = (1.0015^2) * 2^96 = 79466025265172787701084167660
            // 79466025265172787701084167660 * 10^26 / 79228162514264337593543950336 =
            // 100300225000000000000000000
            if iszero(lt(factor_, 100300225000000000000000000)) {
                tick := or(tick, 0x2)
                factor_ := div(mul(factor_, _1E26), 100300225000000000000000000)
            }
            // for tick = 1
            // ratioX96 = (1.0015^1) * 2^96 = 79347004758035734099934266261
            // 79347004758035734099934266261 * 10^26 / 79228162514264337593543950336 =
            // 100150000000000000000000000
            if iszero(lt(factor_, 100150000000000000000000000)) {
                tick := or(tick, 0x1)
                factor_ := div(mul(factor_, _1E26), 100150000000000000000000000)
            }
            if iszero(cond) {
                // if ratioX96 >= ZERO_TICK_SCALED_RATIO
                perfectRatioX96 := div(mul(ratioX96, _1E26), factor_)
            }
            if cond {
                // ratioX96 < ZERO_TICK_SCALED_RATIO
                tick := not(tick)
                perfectRatioX96 := div(mul(ratioX96, factor_), 100150000000000000000000000)
            }
            // perfect ratio should always be <= ratioX96
            // not sure if it can ever be bigger but better to have extra checks
            if gt(perfectRatioX96, ratioX96) {
                revert(0, 0)
            }
        }
    }
}
