// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./interfaces.sol";

abstract contract ConstantVariables {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// bytes32(uint256(keccak256("FLUID_DEX_LITE_EXTRA_DATA")) - 1)
    bytes32 internal constant EXTRA_DATA_SLOT = 0x7e8134afb5ed35d36cb65e24b9a4712a52bb77d952806c1acf50970d2107797f;

    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1
    /// The exact slot which stored the admin address in infinite proxy of liquidity contracts
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    bool internal constant SWAP_SINGLE = true;
    bool internal constant SWAP_HOP = false;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;
    uint256 internal constant TOKENS_DECIMALS_PRECISION = 9;

    uint8 internal constant MIN_TOKEN_DECIMALS = 6;
    uint8 internal constant MAX_TOKEN_DECIMALS = 18;

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 20;
    uint256 internal constant BIG_COEFFICIENT_SIZE = 32;

    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 internal constant X1 = 0x1;
    uint256 internal constant X2 = 0x3;
    uint256 internal constant X5 = 0x1f;
    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X13 = 0x1fff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X28 = 0xfffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant X56 = 0xffffffffffffff;
    uint256 internal constant X60 = 0xfffffffffffffff;
    uint256 internal constant X73 = 0x1ffffffffffffffffff;
    uint256 internal constant X120 = 0xffffffffffffffffffffffffffffff;
    uint256 internal constant X128 = 0xffffffffffffffffffffffffffffffff;
   
    uint256 internal constant TWO_DECIMALS = 1e2;
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant SIX_DECIMALS = 1e6;

    uint256 internal constant PRICE_PRECISION = 1e27;

    /// after swap token0 reserves should not be less than token1InToken0 / MINIMUM_LIQUIDITY_SWAP
    /// after swap token1 reserves should not be less than token0InToken1 / MINIMUM_LIQUIDITY_SWAP
    uint256 internal constant MINIMUM_LIQUIDITY_SWAP = 1e4;

    bytes32 internal constant ESTIMATE_SWAP = keccak256(bytes("ESTIMATE_SWAP"));
}
