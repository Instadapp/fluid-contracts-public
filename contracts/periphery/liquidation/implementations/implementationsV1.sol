// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { IFluidVaultT2 } from "../../../protocols/vault/interfaces/iVaultT2.sol";
import { IFluidVaultT3 } from "../../../protocols/vault/interfaces/iVaultT3.sol";
import { IFluidVaultT4 } from "../../../protocols/vault/interfaces/iVaultT4.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IWETH9 } from "../../../protocols/lending/interfaces/external/iWETH9.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeTransfer } from "../../../libraries/safeTransfer.sol";
import { SafeApprove } from "../../../libraries/safeApprove.sol";

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

contract VaultLiquidatorImplementationV1 {
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant X20 = 0xfffff;
    address constant public ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    InstaFlashInterface immutable public FLA;
    IWETH9 immutable public WETH;
    address internal immutable ADDRESS_THIS = address(this);


    error FluidVaultLiquidator__InvalidOperation();
    error FluidVaultLiquidator__InvalidTimestamp();
    error FluidVaultLiquidator__InvalidTopTick();

    event Liquidated(
        address indexed vault,
        uint256 collateral,
        uint256 debt
    );

    struct LiquidationParams {
        address vault; // address of the vault to liquidate
        uint256 vaultType; // 1 for T1, 2 for T2, 3 for T3, 4 for T4
        uint256 expiration; // 0 if no expiration
        int256 topTick; // type(int256).min if no topTick

        uint256 route; // Flashloan Route
        address flashloanToken; // Debt Token
        uint256 flashloanAmount; // Amount of debt token to payback

        uint256 token0DebtAmt;
        uint256 token1DebtAmt;
        uint256 debtSharesMin;
        uint256 colPerUnitDebt; // col per unit is w.r.t debt shares and not token0/1 debt amount
        uint256 token0ColAmtPerUnitShares; // in 1e18
        uint256 token1ColAmtPerUnitShares; // in 1e18
        bool absorb;

        address swapToken; // Collateral Token
        uint256 swapAmount; // Collateral amount to swap
        address swapRouter; // Dex Aggregator Router Contract
        address swapApproval; // Dex Aggregator Approval Contract
        bytes swapData; // Data to swap collateral token
    }

    struct LiquidationDustParams {
        address vault; // address of the vault to liquidate
        uint256 vaultType; // 1 for T1, 2 for T2, 3 for T3, 4 for T4
        uint256 expiration; // 0 if no expiration
        int256 topTick; // type(int256).min if no topTick

        address debtToken; // Debt Token
        uint256 debtAmount; // Amount of debt token to payback

        uint256 token0DebtAmt;
        uint256 token1DebtAmt;
        uint256 debtSharesMin;
        uint256 colPerUnitDebt; // col per unit is w.r.t debt shares and not token0/1 debt amount
        uint256 token0ColAmtPerUnitShares; // in 1e18
        uint256 token1ColAmtPerUnitShares; // in 1e18
        bool absorb;
    }

    constructor (
        address fla_,
        address weth_
    ) {
        FLA = InstaFlashInterface(fla_);
        WETH = IWETH9(weth_);
    }

    modifier _onlyDelegateCall() {
        if (address(this) == ADDRESS_THIS) {
            revert FluidVaultLiquidator__InvalidOperation();
        }
        _;
    }

    function _tickHelper(uint tickRaw_) internal pure returns (int tick) {
        require(tickRaw_ < X20, "invalid-number");
        if (tickRaw_ > 0) {
            tick = tickRaw_ & 1 == 1 ? int((tickRaw_ >> 1) & X19) : -int((tickRaw_ >> 1) & X19);
        } else {
            tick = type(int).min;
        }
    }

    function _validateParams(LiquidationParams memory params_) internal view {
        if (params_.expiration > 0 && params_.expiration < block.timestamp) revert FluidVaultLiquidator__InvalidTimestamp();

        uint256 vaultVariables_ = IFluidVaultT1(params_.vault).readFromStorage(0);

        int256 topTick_ = _tickHelper(((vaultVariables_ >> 2) & X20));

        if (params_.topTick > topTick_ && params_.topTick != type(int256).min) revert FluidVaultLiquidator__InvalidTopTick();
    }

    function liquidateDust(LiquidationDustParams memory params_) public _onlyDelegateCall {
        LiquidationParams memory param_;
        param_.expiration = params_.expiration;
        param_.topTick = params_.topTick;
        param_.vault = params_.vault;
        param_.vaultType = params_.vaultType;

        _validateParams(param_);

        uint256 value_;
        if (params_.debtToken != ETH_ADDRESS) {
            SafeApprove.safeApprove(params_.debtToken, params_.vault, 0);
            SafeApprove.safeApprove(params_.debtToken, params_.vault, params_.debtAmount);
            value_ = 0;
        } else {
            value_ = params_.debtAmount;
        }

        uint256 debtAmount_;
        uint256 collateralAmount_;
        if (params_.vaultType == 1) {
            (debtAmount_, collateralAmount_) = IFluidVaultT1(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.colPerUnitDebt, address(this), params_.absorb);
        } else if (params_.vaultType == 2) {
            (debtAmount_, collateralAmount_, , ) = IFluidVaultT2(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.colPerUnitDebt, params_.token0ColAmtPerUnitShares, params_.token1ColAmtPerUnitShares, address(this), params_.absorb);
        } else if (params_.vaultType == 3) {
            (debtAmount_, collateralAmount_) = IFluidVaultT3(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.token1DebtAmt, params_.debtSharesMin, params_.colPerUnitDebt, address(this), params_.absorb);
        } else if (params_.vaultType == 4) {
            (debtAmount_, collateralAmount_, , ) = IFluidVaultT4(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.token1DebtAmt, params_.debtSharesMin, params_.colPerUnitDebt, params_.token0ColAmtPerUnitShares, params_.token1ColAmtPerUnitShares, address(this), params_.absorb);
        }
    }

    function liquidation(LiquidationParams memory params_) public _onlyDelegateCall {
        _validateParams(params_);

        address[] memory tokens = new address[](1);
        uint256[] memory amts = new uint256[](1);

        // Take flashloan in borrow token of the vault
        tokens[0] = params_.flashloanToken == ETH_ADDRESS ? address(WETH) : params_.flashloanToken;
        amts[0] = params_.flashloanAmount;

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
        if (msg.sender != address(FLA)) revert FluidVaultLiquidator__InvalidOperation();
        if (initiator != address(this)) revert FluidVaultLiquidator__InvalidOperation();
        LiquidationParams memory params_ = abi.decode(_data, (LiquidationParams));

        {
            uint256 value_;
            if (params_.flashloanToken != ETH_ADDRESS) {
                SafeApprove.safeApprove(params_.flashloanToken, params_.vault, 0);
                SafeApprove.safeApprove(params_.flashloanToken, params_.vault, params_.flashloanAmount);
                value_ = 0;
            } else {
                WETH.withdraw(params_.flashloanAmount);
                value_ = params_.flashloanAmount;
            }

            uint256 debtAmount_;
            uint256 collateralAmount_;
            if (params_.vaultType == 1) {
                (debtAmount_, collateralAmount_) = IFluidVaultT1(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.colPerUnitDebt, address(this), params_.absorb);
            } else if (params_.vaultType == 2) {
                (debtAmount_, collateralAmount_, , ) = IFluidVaultT2(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.colPerUnitDebt, params_.token0ColAmtPerUnitShares, params_.token1ColAmtPerUnitShares, address(this), params_.absorb);
            } else if (params_.vaultType == 3) {
                (debtAmount_, collateralAmount_) = IFluidVaultT3(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.token1DebtAmt, params_.debtSharesMin, params_.colPerUnitDebt, address(this), params_.absorb);
            } else if (params_.vaultType == 4) {
                (debtAmount_, collateralAmount_, , ) = IFluidVaultT4(params_.vault).liquidate{value: value_}(params_.token0DebtAmt, params_.token1DebtAmt, params_.debtSharesMin, params_.colPerUnitDebt, params_.token0ColAmtPerUnitShares, params_.token1ColAmtPerUnitShares, address(this), params_.absorb);
            }

            if (params_.flashloanToken != params_.swapToken) {
                if (params_.swapToken != ETH_ADDRESS) {
                    SafeApprove.safeApprove(params_.swapToken, params_.swapApproval, 0);
                    SafeApprove.safeApprove(params_.swapToken, params_.swapApproval, params_.swapAmount);
                    value_ = 0;
                } else {
                    value_ = params_.swapAmount;
                }

                Address.functionCallWithValue(params_.swapRouter, params_.swapData, value_, "Swap: failed");
            }

            emit Liquidated(params_.vault, collateralAmount_, debtAmount_);
        }

        uint256 flashloanAmount_ = amounts[0] + premiums[0] + 10;

        if (params_.flashloanToken == ETH_ADDRESS) {
            uint256 wethBalance_ = WETH.balanceOf(address(this));
            if (wethBalance_ < flashloanAmount_) {
                WETH.deposit{value: flashloanAmount_ - wethBalance_}();
            }
        }

        SafeTransfer.safeTransfer(assets[0], msg.sender, flashloanAmount_);

        return true;
    }

    receive() payable external {}
}