// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { StorageRead } from "../../../../libraries/storageRead.sol";

interface ITokenDecimals {
    function decimals() external view returns (uint8);
}

abstract contract ConstantVariables is StorageRead {
    /*//////////////////////////////////////////////////////////////
                          CONSTANTS / IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address internal constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;
    address internal constant ADDRESS_DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant TOKENS_DECIMALS_PRECISION = 12;
    uint256 internal constant TOKENS_DECIMALS = 1e12;

    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 internal constant X2 = 0x3;
    uint256 internal constant X3 = 0x7;
    uint256 internal constant X5 = 0x1f;
    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X8 = 0xff;
    uint256 internal constant X9 = 0x1ff;
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X11 = 0x7ff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X17 = 0x1ffff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X22 = 0x3fffff;
    uint256 internal constant X23 = 0x7fffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X28 = 0xfffffff;
    uint256 internal constant X30 = 0x3fffffff;
    uint256 internal constant X32 = 0xffffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X40 = 0xffffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
    uint256 internal constant X96 = 0xffffffffffffffffffffffff;
    uint256 internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    uint256 internal constant TWO_DECIMALS = 1e2;
    uint256 internal constant THREE_DECIMALS = 1e3;
    uint256 internal constant FOUR_DECIMALS = 1e4;
    uint256 internal constant FIVE_DECIMALS = 1e5;
    uint256 internal constant SIX_DECIMALS = 1e6;
    uint256 internal constant EIGHT_DECIMALS = 1e8;
    uint256 internal constant NINE_DECIMALS = 1e9;

    uint256 internal constant PRICE_PRECISION = 1e27;

    uint256 internal constant ORACLE_PRECISION = 1e18; // 100%
    uint256 internal constant ORACLE_LIMIT = 5 * 1e16; // 5%

    /// after swap token0 reserves should not be less than token1InToken0 / MINIMUM_LIQUIDITY_SWAP
    /// after swap token1 reserves should not be less than token0InToken1 / MINIMUM_LIQUIDITY_SWAP
    uint256 internal constant MINIMUM_LIQUIDITY_SWAP = 1e4;

    /// after user operations (deposit, withdraw, borrow, payback) token0 reserves should not be less than token1InToken0 / MINIMUM_LIQUIDITY_USER_OPERATIONS
    /// after user operations (deposit, withdraw, borrow, payback) token1 reserves should not be less than token0InToken0 / MINIMUM_LIQUIDITY_USER_OPERATIONS
    uint256 internal constant MINIMUM_LIQUIDITY_USER_OPERATIONS = 1e6;

    /// To skip transfers in liquidity layer if token in & out is same and liquidity layer is on the winning side
    bytes32 internal constant SKIP_TRANSFERS = keccak256(bytes("SKIP_TRANSFERS"));

    function _decimals(address token_) internal view returns (uint256) {
        return (token_ == NATIVE_TOKEN) ? NATIVE_TOKEN_DECIMALS : ITokenDecimals(token_).decimals();
    }
}
