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