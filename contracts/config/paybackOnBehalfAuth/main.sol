// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

// ==================== FluidPaybackOnBehalfAuth ====================
//
// Pay back debt on behalf of any address at the Fluid Liquidity layer.
//
// ACCESS:
//   - Team multisig only
//
// CAPABILITIES:
//   - paybackOnBehalf(token, amount, onBehalf) — wraps Liquidity.operateOnBehalfOf to repay debt
//     ERC20: multisig approves this contract, then calls. Native: send msg.value.
//   - rescueTokens — recover stuck tokens/ETH from this contract
//
// DEPLOYMENT:
//   - Must be set as **auth** on Fluid Liquidity (for operateOnBehalfOf)
// ==================================================================

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { SafeTransfer } from "../../libraries/safeTransfer.sol";

/// @title   FluidPaybackOnBehalfAuth
/// @notice  Pay back debt on behalf of any address via Liquidity.operateOnBehalfOf. Multisig only.
contract FluidPaybackOnBehalfAuth is Error {
    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint8 private constant REENTRANCY_NOT_ENTERED = 1;
    uint8 private constant REENTRANCY_ENTERED = 2;

    IFluidLiquidity public immutable LIQUIDITY;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    uint8 private _status;

    event LogPaybackOnBehalf(address indexed token, int256 paybackAmount, address indexed onBehalf);

    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender) {
            revert FluidConfigError(ErrorTypes.PaybackOnBehalfAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_) {
        if (liquidity_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PaybackOnBehalfAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        _status = REENTRANCY_NOT_ENTERED;
    }

    /// @notice Pays back debt on behalf of `onBehalf_` at the Liquidity layer. Only callable by team multisig.
    ///         For ERC20: team multisig must have approved this contract for the payback amount.
    ///         For native token: send the payback amount as msg.value.
    /// @param token_ address of token (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE for native)
    /// @param paybackAmount_ payback amount, must be negative (< 0)
    /// @param onBehalf_ the address (protocol) whose debt to pay back
    function paybackOnBehalf(
        address token_,
        int256 paybackAmount_,
        address onBehalf_
    ) external payable onlyMultisig returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_) {
        if (paybackAmount_ >= 0) {
            revert FluidConfigError(ErrorTypes.PaybackOnBehalfAuth__InvalidParams);
        }
        _status = REENTRANCY_ENTERED;
        (supplyExchangePrice_, borrowExchangePrice_) = LIQUIDITY.operateOnBehalfOf{ value: msg.value }(
            onBehalf_,
            token_,
            int256(0), // no supply
            paybackAmount_,
            new bytes(0)
        );
        _status = REENTRANCY_NOT_ENTERED;
        emit LogPaybackOnBehalf(token_, paybackAmount_, onBehalf_);
    }

    /// @dev Callback from Liquidity to transfer tokens during operate. Pulls from team multisig via approval.
    function liquidityCallback(address token_, uint256 amount_, bytes calldata) external {
        if (msg.sender != address(LIQUIDITY) || _status != REENTRANCY_ENTERED) {
            revert FluidConfigError(ErrorTypes.PaybackOnBehalfAuth__Unauthorized);
        }
        SafeTransfer.safeTransferFrom(token_, TEAM_MULTISIG, msg.sender, amount_);
    }

    /// @notice Rescues stuck tokens from this contract. Only callable by team multisig.
    function rescueTokens(address token_, uint256 amount_, address to_) external onlyMultisig {
        if (to_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PaybackOnBehalfAuth__InvalidParams);
        }
        if (token_ == NATIVE_TOKEN_ADDRESS) {
            SafeTransfer.safeTransferNative(to_, amount_);
        } else {
            SafeTransfer.safeTransfer(token_, to_, amount_);
        }
    }

    receive() external payable {}
}
