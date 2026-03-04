//SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <=0.8.29;

interface IZtakingPool {
    function balance(address token_, address staker_) external view returns (uint256);
}

abstract contract ResolverHelpers {
    // -------------------------------------- ONLY MAINNET RELEVANT ----------------------------------------
    address private constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address private constant WEETHS = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    IZtakingPool private constant ZIRCUIT = IZtakingPool(0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6);
    // -----------------------------------------------------------------------------------------------------

    /// @notice Returns the Liquidity Layers balance of the given token currently re-hypothecated or otherwise sitting externally.
    /// @param token_ The address of the token to check.
    /// @param liquidity_ The address of the Liquidity layer.
    /// @return balanceOf_ The total balance of the contract re-hypothecated assets.
    function _getLiquidityExternalBalances(
        address token_,
        address liquidity_
    ) internal view returns (uint256 balanceOf_) {
        if (block.chainid != 1) {
            return 0; // no rehypo except on mainnet
        }

        if (token_ == WEETH) {
            balanceOf_ += ZIRCUIT.balance(WEETH, liquidity_);
        } else if (token_ == WEETHS) {
            balanceOf_ += ZIRCUIT.balance(WEETHS, liquidity_);
        }
    }
}
