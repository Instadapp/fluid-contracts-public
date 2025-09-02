// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

contract Variables {
    /// @dev Storage slot with the admin of the contract. Logic from "proxy.sol".
    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
    /// validated in the constructor.
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev Ignoring leap years
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    // constants used for BigMath conversion from and to storage
    uint256 internal constant SMALL_COEFFICIENT_SIZE = 10;
    uint256 internal constant DEFAULT_COEFFICIENT_SIZE = 56;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    uint256 internal constant FOUR_DECIMALS = 10000;
    uint256 internal constant X8 = 0xff;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X33 = 0x1ffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;

    /// @notice address of the liquidity contract
    IFluidLiquidity public immutable LIQUIDITY;

    constructor(IFluidLiquidity liquidity_) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
    }
}
