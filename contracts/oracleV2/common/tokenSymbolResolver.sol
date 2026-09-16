// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title TokenSymbolResolver
/// @notice Shared helper for human-readable token symbols: native asset per chain, ERC20 `symbol()`, or `"UNK"`.
///
/// @dev Native sentinel must match Liquidity / `NATIVE_TOKEN_ADDRESS` in sibling modules (same `0xEeee…` address).
abstract contract TokenSymbolResolver {
    address private constant _NATIVE_TOKEN_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function _tokenSymbol(address token_) internal view returns (string memory symbol_) {
        if (token_ == _NATIVE_TOKEN_SENTINEL) {
            if (block.chainid == 137) {
                return "POL";
            }
            if (block.chainid == 9745) {
                return "XPL";
            }
            if (block.chainid == 56) {
                return "BNB";
            }
            return "ETH";
        }
        try IERC20Metadata(token_).symbol() returns (string memory sym_) {
            return sym_;
        } catch {
            return "UNK";
        }
    }
}
