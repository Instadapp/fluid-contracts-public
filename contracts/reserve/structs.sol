// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract Structs {
    struct TokenAllowance {
        address token;
        uint256 allowance;
    }

    struct ProtocolTokenAllowance {
        address protocol;
        TokenAllowance[] tokenAllowances;
    }
}
