//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAllowanceTransfer } from "../../../../contracts/protocols/lending/interfaces/permit2/iAllowanceTransfer.sol";

/// @dev etched at the Permit2 address so tests need no fork; `transferFrom` moves real tokens and records its args
contract Permit2Mock {
    address public lastFrom;
    address public lastTo;
    uint160 public lastAmount;
    address public lastToken;
    uint256 public transferFromCallCount;

    function permit(address, IAllowanceTransfer.PermitSingle memory, bytes calldata) external {}

    function transferFrom(address from_, address to_, uint160 amount_, address token_) external {
        lastFrom = from_;
        lastTo = to_;
        lastAmount = amount_;
        lastToken = token_;
        transferFromCallCount++;
        IERC20(token_).transferFrom(from_, to_, amount_);
    }
}
