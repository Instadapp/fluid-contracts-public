// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { IStakedUSDe } from "./interfaces/iStakedUSDe.sol";

abstract contract Constants {
    IFluidReserveContract public immutable RESERVE_CONTRACT;
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultT1 public immutable VAULT;
    IFluidVaultT1 public immutable VAULT2;
    IStakedUSDe public immutable SUSDE;
    address public immutable BORROW_TOKEN;

    /// @notice sUSDe vesting yield reward rate percent margin that goes to lenders
    /// e.g. RATE_PERCENT_MARGIN = 10% then borrow rate for debt token ends up as 90% of the sUSDe yield.
    /// (in 1e2: 100% = 10_000; 1% = 100)
    uint256 public immutable RATE_PERCENT_MARGIN;

    /// @notice max delay in seconds for rewards update after vesting period ended, after which we assume rate is 0.
    /// e.g. 15 min
    uint256 public immutable MAX_REWARDS_DELAY;

    /// @notice utilization penalty start point (in 1e2: 100% = 10_000; 1% = 100). above this, a penalty percent
    ///         is applied, to incentivize deleveraging.
    uint256 public immutable UTILIZATION_PENALTY_START;
    /// @notice penalty percent target at 100%, on top of sUSDe yield rate if utilization is above UTILIZATION_PENALTY_START
    ///         (in 1e2: 100% = 10_000; 1% = 100)
    uint256 public immutable UTILIZATION100_PENALTY_PERCENT;

    bytes32 internal immutable _LIQUDITY_BORROW_TOKEN_EXCHANGE_PRICES_SLOT;

    /// @dev vesting period defined as private constant on StakedUSDe contract
    uint256 internal constant _SUSDE_VESTING_PERIOD = 8 hours;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X16 = 0xffff;
    uint256 internal constant _MIN_MAGNIFIER = 1e4; // min magnifier is always at least 1x (10000)
    uint256 internal constant _MAX_MAGNIFIER = 65535; // max magnifier to fit in storage slot is 65535 (16 bits)
}

abstract contract Variables is Constants {}
