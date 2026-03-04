// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { CommonHelpers } from "./helpers.sol";

/// @notice NON-mainnet (others) specific implementation of CommonHelpers.
/// @dev This contract contains chain-specific logic. It overrides the virtual methods defined in CommonHelpers (see helpers.sol).
abstract contract CommonHelpersOthers is CommonHelpers {
    function _afterTransferIn(address token_, uint256 amount_) internal override {}

    function _preTransferOut(address token_, uint256 amount_) internal override {}

    function _getExternalBalances(address /** token_ **/) internal pure override returns (uint256) {
        return 0;
    }
}
