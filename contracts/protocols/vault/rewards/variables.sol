// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidReserveContract } from "../../../reserve/interfaces/iReserveContract.sol";
import { IFluidVaultT1 } from "../interfaces/iVaultT1.sol";
import { IFluidLiquidity } from "../../../liquidity/interfaces/iLiquidity.sol";

abstract contract Constants {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidReserveContract public immutable RESERVE_CONTRACT;
    IFluidVaultT1 public immutable VAULT;
    uint256 public immutable REWARDS_AMOUNT;
    uint256 public immutable REWARDS_AMOUNT_PER_YEAR;
    uint256 public immutable DURATION;
    address public immutable INITIATOR;
    address public immutable VAULT_COLLATERAL_TOKEN;

    bytes32 internal immutable LIQUIDITY_TOTAL_AMOUNTS_COLLATERAL_TOKEN_SLOT;
    bytes32 internal immutable LIQUIDITY_EXCHANGE_PRICE_COLLATERAL_TOKEN_SLOT;
    uint256 internal constant FOUR_DECIMALS = 10000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xff;
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;
    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
}

abstract contract Variables is Constants {
    bool public ended; // when rewards are ended
    uint96 public startTime;
    uint96 public endTime;
}
