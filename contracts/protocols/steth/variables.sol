// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { ILidoWithdrawalQueue } from "./interfaces/external/iLidoWithdrawalQueue.sol";
import { Structs } from "./structs.sol";

abstract contract Constants {
    /// @dev hundred percent at 1e2 precision
    uint256 internal constant HUNDRED_PERCENT = 1e4;

    /// @dev precision for exchange prices in Liquidity
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @dev address that is mapped to the chain native token at Liquidity
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev dust amount to borrow from Liquidity at initialize()
    uint256 internal constant DUST_BORROW_AMOUNT = 1e12;

    /// @notice address of the Liquidity contract.
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @notice address of the Lido Withdrawal Queue contract (0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1)
    ILidoWithdrawalQueue internal immutable LIDO_WITHDRAWAL_QUEUE;

    /// @notice address of the StETH contract.
    IERC20 internal immutable STETH;

    /// @dev slot id in Liquidity contract for exchange prices storage slot for NATIVE_TOKEN_ADDRESS.
    bytes32 internal immutable LIQUIDITY_EXCHANGE_PRICES_SLOT;

    constructor(IFluidLiquidity liquidity_, ILidoWithdrawalQueue lidoWithdrawalQueue_, IERC20 stETH_) {
        LIQUIDITY = liquidity_;

        LIDO_WITHDRAWAL_QUEUE = lidoWithdrawalQueue_;

        STETH = stETH_;

        LIQUIDITY_EXCHANGE_PRICES_SLOT = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            NATIVE_TOKEN_ADDRESS
        );
    }

    /// @notice returns the constant values for LIQUIDITY, LIDO_WITHDRAWAL_QUEUE, STETH
    function constantsView() external view returns (IFluidLiquidity, ILidoWithdrawalQueue, IERC20) {
        return (LIQUIDITY, LIDO_WITHDRAWAL_QUEUE, STETH);
    }
}

abstract contract Variables is Initializable, OwnableUpgradeable, Constants, Structs {
    // ------------ storage variables from inherited contracts (Initializable, OwnableUpgradeable) come before vars here --------
    // @dev variables here start at storage slot 101, before is:
    // - Initializable with storage slot 0:
    // uint8 private _initialized;
    // bool private _initializing;
    // - OwnableUpgradeable with slots 1 to 100:
    // uint256[50] private __gap; (from ContextUpgradeable, slot 1 until slot 50)
    // address private _owner; (at slot 51)
    // uint256[49] private __gap; (slot 52 until slot 100)

    // ----------------------- slot 101 ---------------------------

    /// @notice maps claimTo address and requestIdFrom to the Claim struct containing necessary information for executing the claim process.
    mapping(address => mapping(uint256 => Claim)) public claims;

    // ----------------------- slot 102 ---------------------------

    /// @dev status for reentrancy guard
    uint8 internal _status;

    /// @notice maximum allowed percentage of LTV (loan-to-value). E.g. 90% -> max. 90 ETH can be borrowed with 100 stETH
    /// as collateral in withdrawal queue. ETH will be received at time of claim to cover the paid borrowed ETH amount.
    /// In 1e2 (1% = 100, 90% = 9_000, 100% = 10_000).
    /// Configurable by auths.
    uint16 public maxLTV;

    /// @notice flag whether allow list behavior is enabled or not.
    bool public allowListActive;

    // 28 bytes free

    // ----------------------- slot 103 ---------------------------
    /// @dev auths can update maxLTV.
    /// owner can add/remove auths.
    /// Owner is auth by default.
    mapping(address => uint256) internal _auths;

    // ----------------------- slot 104 ---------------------------
    /// @dev guardians can pause/unpause queue() and claim().
    /// owner can add/remove guardians.
    /// Owner is guardian by default.
    mapping(address => uint256) internal _guardians;

    // ----------------------- slot 105 ---------------------------
    /// @dev allowed users can use the StETH protocol (if `allowListActive` is true, then use is open for everyone).
    /// owner and auths can add/remove allowed users.
    mapping(address => uint256) internal _allowed;

    constructor(
        IFluidLiquidity liquidity_,
        ILidoWithdrawalQueue lidoWithdrawalQueue_,
        IERC20 stETH_
    ) Constants(liquidity_, lidoWithdrawalQueue_, stETH_) {}
}
