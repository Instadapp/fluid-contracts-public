// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Owned } from "solmate/src/auth/Owned.sol";

import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH9 } from "../../protocols/lending/interfaces/external/iWETH9.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

interface InstaFlashInterface {
    function flashLoan(address[] memory tokens, uint256[] memory amts, uint route, bytes memory data, bytes memory extraData) external;
}

interface InstaFlashReceiverInterface {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _data
    ) external returns (bool);
}

contract VaultT1Liquidator is Owned {
    using SafeERC20 for IERC20;

    address constant public ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    InstaFlashInterface immutable public FLA;
    IWETH9 immutable public WETH;

    mapping (address => bool) public rebalancer; 

    error FluidVaultT1Liquidator__InvalidOperation();

    event Liquidated(
        address indexed vault,
        uint256 collateral,
        uint256 debt
    );

    event Withdraw(
        address indexed to,
        address indexed token,
        uint256 amount
    );

    event ToggleRebalancer(
        address indexed rebalancer,
        bool indexed status
    );

    struct LiquidationParams {
        address vault;
        address supply;
        address borrow;
        uint256 supplyAmount;
        uint256 borrowAmount;
        uint256 colPerUnitDebt;
        bool absorb;
        address swapRouter;
        address swapApproval;
        bytes swapData;
        uint256 route;
    }

    constructor (
        address owner_,
        address fla_,
        address weth_,
        address[] memory rebalancers_
    ) Owned(owner_) {
        FLA = InstaFlashInterface(fla_);
        WETH = IWETH9(weth_);
        for (uint256 i = 0; i < rebalancers_.length; i++) {
            rebalancer[rebalancers_[i]] = true;
            emit ToggleRebalancer(rebalancers_[i], true);
        }
    }

    modifier isRebalancer() {
        if (!rebalancer[msg.sender] && msg.sender != owner) {
            revert FluidVaultT1Liquidator__InvalidOperation();
        }
        _;
    }

    function toggleRebalancer(address rebalancer_, bool status_) public onlyOwner {
        rebalancer[rebalancer_] = status_;
        emit ToggleRebalancer(rebalancer_, status_);
    }

    function spell(address[] memory targets_, bytes[] memory calldatas_) public onlyOwner {
        for (uint256 i = 0; i < targets_.length; i++) {
            Address.functionDelegateCall(targets_[i], calldatas_[i]);
        }
    }

    function withdraw(address to_, address[] memory tokens_, uint256[] memory amounts_) public onlyOwner {
        for (uint i = 0; i < tokens_.length; i++) {
            if (tokens_[i] == ETH_ADDRESS) {
                Address.sendValue(payable(to_), amounts_[i]);
            } else {
                IERC20(tokens_[i]).safeTransfer(to_, amounts_[i]);
            }
            emit Withdraw(to_, tokens_[i], amounts_[i]);
        }
    }
    
    function liquidation(LiquidationParams memory params_) public isRebalancer {
        address[] memory tokens = new address[](1);
        uint256[] memory amts = new uint256[](1);

        // Take flashloan in borrow token of the vault
        tokens[0] = params_.borrow == ETH_ADDRESS ? address(WETH) : params_.borrow;
        amts[0] = params_.borrowAmount;

        bytes memory data_ = abi.encode(params_);

        FLA.flashLoan(tokens, amts, params_.route, data_, abi.encode());

    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _data
    ) external returns (bool) {
        if (msg.sender != address(FLA)) revert FluidVaultT1Liquidator__InvalidOperation();
        if (initiator != address(this)) revert FluidVaultT1Liquidator__InvalidOperation();
        LiquidationParams memory params_ = abi.decode(_data, (LiquidationParams));

        {
            uint256 value_;
            if (params_.borrow != ETH_ADDRESS) {
                IERC20(params_.borrow).safeApprove(params_.vault, 0);
                IERC20(params_.borrow).safeApprove(params_.vault, params_.borrowAmount);
                value_ = 0;
            } else {
                WETH.withdraw(params_.borrowAmount);
                value_ = params_.borrowAmount;
            }

            (uint256 debtAmount_, uint256 collateralAmount_) = IFluidVaultT1(params_.vault).liquidate{value: value_}(params_.borrowAmount, params_.colPerUnitDebt, address(this), params_.absorb);

            if (params_.supply != ETH_ADDRESS) {
                IERC20(params_.supply).safeApprove(params_.swapApproval, 0);
                IERC20(params_.supply).safeApprove(params_.swapApproval, params_.supplyAmount);
                value_ = 0;
            } else {
                value_ = params_.supplyAmount;
            }

            Address.functionCallWithValue(params_.swapRouter, params_.swapData, value_, "Swap: failed");
            emit Liquidated(params_.vault, collateralAmount_, debtAmount_);
        }

        uint256 flashloanAmount_ = amounts[0] + premiums[0] + 10;
        if (params_.borrow == ETH_ADDRESS) {
            uint256 wethBalance_ = WETH.balanceOf(address(this));
            if (wethBalance_ < flashloanAmount_) {
                WETH.deposit{value: flashloanAmount_ - wethBalance_}();
            }
        }
        IERC20(assets[0]).safeTransfer(msg.sender, flashloanAmount_);

        return true;
    }

    receive() payable external {}
}