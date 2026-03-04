// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21 <=0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Variables } from "../common/variables.sol";

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

/// @dev This contract is for Ethereum mainnet only!
contract FluidLiquidityZircuitTransferModuleMainnet is Variables {
    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    IERC20 internal constant WEETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IERC20 internal constant WEETHS = IERC20(0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88);
    IZtakingPool internal constant ZIRCUIT = IZtakingPool(0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6);

    /// @dev Returns the current admin (governance).
    function _getGovernanceAddr() internal view returns (address governance_) {
        assembly {
            governance_ := sload(GOVERNANCE_SLOT)
        }
    }

    /// @notice deposit all WEETH funds to Zircuit and sets approved allowance to max uint256.
    /// @dev Only delegate callable on Liquidity, by Governance
    function depositZircuitWeETH() external {
        if (_getGovernanceAddr() != msg.sender || address(this) != LIQUIDITY) {
            revert();
        }

        SafeERC20.safeApprove(WEETH, address(ZIRCUIT), type(uint256).max);

        ZIRCUIT.depositFor(address(WEETH), address(this), WEETH.balanceOf(address(this)));
    }

    /// @notice withdraw all WEETH funds from Zircuit and sets approved allowance to 0.
    /// @dev Only delegate callable on Liquidity, Governance and Guardians (for emergency)
    function withdrawZircuitWeETH() external {
        if ((_isGuardian[msg.sender] & 1 != 1 && _getGovernanceAddr() != msg.sender) || address(this) != LIQUIDITY) {
            revert();
        }

        ZIRCUIT.withdraw(address(WEETH), ZIRCUIT.balance(address(WEETH), address(this)));

        // remove approval
        SafeERC20.safeApprove(WEETH, address(ZIRCUIT), 0);
    }

    /// @notice deposit all WEETHS funds to Zircuit and sets approved allowance to max uint256.
    /// @dev Only delegate callable on Liquidity, by Governance
    function depositZircuitWeETHs() external {
        if (_getGovernanceAddr() != msg.sender || address(this) != LIQUIDITY) {
            revert();
        }

        SafeERC20.safeApprove(WEETHS, address(ZIRCUIT), type(uint256).max);

        ZIRCUIT.depositFor(address(WEETHS), address(this), WEETHS.balanceOf(address(this)));
    }

    /// @notice withdraw all WEETHS funds from Zircuit and sets approved allowance to 0.
    /// @dev Only delegate callable on Liquidity, Governance and Guardians (for emergency)
    function withdrawZircuitWeETHs() external {
        if ((_isGuardian[msg.sender] & 1 != 1 && _getGovernanceAddr() != msg.sender) || address(this) != LIQUIDITY) {
            revert();
        }

        ZIRCUIT.withdraw(address(WEETHS), ZIRCUIT.balance(address(WEETHS), address(this)));

        // remove approval
        SafeERC20.safeApprove(WEETHS, address(ZIRCUIT), 0);
    }
}
