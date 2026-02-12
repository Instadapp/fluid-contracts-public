// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { CommonHelpers } from "./helpers.sol";

interface IZtakingPool {
    ///@notice Stake a specified amount of a particular supported token into the Ztaking Pool
    ///@param _token The token to deposit/stake in the Ztaking Pool
    ///@param _for The user to deposit/stake on behalf of
    ///@param _amount The amount of token to deposit/stake into the Ztaking Pool
    function depositFor(address _token, address _for, uint256 _amount) external;

    ///@notice Withdraw a specified amount of a particular supported token previously staked into the Ztaking Pool
    ///@param _token The token to withdraw from the Ztaking Pool
    ///@param _amount The amount of token to withdraw from the Ztaking Pool
    function withdraw(address _token, uint256 _amount) external;

    function balance(address token_, address staker_) external view returns (uint256);
}

/// @notice Mainnet specific implementation of CommonHelpers.
/// @dev This contract contains chain-specific logic for mainnet. It overrides the virtual methods defined in CommonHelpers (see helpers.sol).
abstract contract CommonHelpersMainnet is CommonHelpers {
    address private constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address private constant WEETHS = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    IZtakingPool private constant ZIRCUIT = IZtakingPool(0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6);

    /// @notice Hook allowing logic after assets are transferred in
    function _afterTransferIn(address token_, uint256 amount_) internal override {
        // temporary rehypo addition for weETH & weETHs: if token is weETH or weETHs -> deposit to Zircuit
        if (token_ == WEETH) {
            if (IERC20(WEETH).allowance(address(this), address(ZIRCUIT)) > 0) {
                ZIRCUIT.depositFor(WEETH, address(this), amount_);
            }
        } else if (token_ == WEETHS) {
            if ((IERC20(WEETHS).allowance(address(this), address(ZIRCUIT)) > 0)) {
                ZIRCUIT.depositFor(WEETHS, address(this), amount_);
            }
        }
        // temporary code also includes: WEETH, WEETHS & ZIRCUIT constant, IZtakingPool interface
    }

    /// @notice Hook allowing logic before assets are transferred out
    function _preTransferOut(address token_, uint256 amount_) internal override {
        // temporary rehypo addition for weETH & weETHs: if token is weETH or weETHs -> withdraw from Zircuit
        if (token_ == WEETH) {
            if ((IERC20(WEETH).balanceOf(address(this)) < amount_)) {
                ZIRCUIT.withdraw(WEETH, amount_);
            }
        } else if (token_ == WEETHS) {
            if ((IERC20(WEETHS).balanceOf(address(this)) < amount_)) {
                ZIRCUIT.withdraw(WEETHS, amount_);
            }
        }
        // temporary code also includes: WEETH, WEETHS & ZIRCUIT constant, IZtakingPool interface
    }

    function _getExternalBalances(address token_) internal view override returns (uint256 balanceOf_) {
        if (token_ == WEETH) {
            balanceOf_ += ZIRCUIT.balance(WEETH, address(this));
        } else if (token_ == WEETHS) {
            balanceOf_ += ZIRCUIT.balance(WEETHS, address(this));
        }
    }
}
