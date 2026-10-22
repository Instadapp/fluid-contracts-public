// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.36;

import { Variables } from "./variables.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

/// @dev Checks global pause status and blocks reentrant Liquidity entry.
/// Based on OpenZeppelin ReentrancyGuard:
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/security/ReentrancyGuard.sol
abstract contract StatusGuard is Variables, Error {
    uint8 internal constant REENTRANCY_NOT_ENTERED = 0;
    uint8 internal constant REENTRANCY_ENTERED = 1;
    uint8 internal constant LIQUIDITY_STATUS_NORMAL = 1;
    uint8 internal constant LIQUIDITY_STATUS_PAUSED = 2;

    constructor() {
        // on logic contracts, switch to paused and entered so no call is possible (forces delegatecall)
        _status = LIQUIDITY_STATUS_PAUSED;
        _reentrancyStatus = REENTRANCY_ENTERED;
    }

    /// @dev Prevents calls while paused or already inside a guarded Liquidity operation.
    modifier checkStatus() {
        // Status 0 means it was never set (proxies deploy without it) and is treated as running.
        if (_status == LIQUIDITY_STATUS_PAUSED || _reentrancyStatus == REENTRANCY_ENTERED) {
            revert FluidLiquidityError(ErrorTypes.LiquidityHelpers__Reentrancy);
        }

        _reentrancyStatus = REENTRANCY_ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _reentrancyStatus = REENTRANCY_NOT_ENTERED;
    }
}

abstract contract CommonHelpers is StatusGuard {
    address internal constant WSTUSR_MAINNET_ADDRESS = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;

    /// @dev Returns the current admin (governance).
    function _getGovernanceAddr() internal view returns (address governance_) {
        assembly {
            governance_ := sload(GOVERNANCE_SLOT)
        }
    }

    /// @dev wstUSR blacklists Liquidity, so withdraw / revenue transfers of it are skipped; remove once claims settle
    function _isWstUsrToken(address token_) internal view returns (bool) {
        return block.chainid == 1 && token_ == WSTUSR_MAINNET_ADDRESS;
    }

    /// @notice Hook invoked after assets are transferred into the contract. Must be implemented for chain specific implementation version.
    /// @dev ATTENTION: THIS IS NOT CALLED FOR NATIVE TOKEN (e.g. ETH).
    /// @param token_ The address of the transferred-in token.
    /// @param amount_ The amount of tokens transferred in.
    function _afterTransferIn(address token_, uint256 amount_) internal virtual;

    /// @notice Hook invoked before assets are transferred out of the contract. Must be implemented for chain specific implementation version.
    /// @dev ATTENTION: THIS IS NOT CALLED FOR NATIVE TOKEN (e.g. ETH).
    /// @param token_ The address of the token to be transferred out.
    /// @param amount_ The amount of tokens to be transferred out.
    function _preTransferOut(address token_, uint256 amount_) internal virtual;

    /// @notice Returns the contract's own balance of the given token currently re-hypothecated or otherwise sitting externally.
    /// @param token_ The address of the token to check.
    /// @return The total balance of the contract re-hypothecated assets.
    function _getExternalBalances(address token_) internal view virtual returns (uint256);
}
