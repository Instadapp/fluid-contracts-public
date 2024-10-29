// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWstETH } from "../../interfaces/external/IWstETH.sol";
import { IFluidOracle } from "../../interfaces/iFluidOracle.sol";
import { FluidCenterPrice } from "../../fluidCenterPrice.sol";

import { Error as OracleError } from "../../error.sol";
import { ErrorTypes } from "../../errorTypes.sol";

abstract contract Events {
    /// @notice emitted when rebalancer successfully changes the contract rate
    event LogRebalanceRate(uint256 oldRate, uint256 newRate);
}

abstract contract Constants {
    /// @dev WSTETH contract; on mainnet 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
    IWstETH internal immutable _WSTETH;

    /// @dev Minimum difference to trigger update in percent 1e4 decimals, 10000 = 1%
    uint256 internal immutable _MIN_UPDATE_DIFF_PERCENT;
}

abstract contract Variables is Constants {
    /// @dev amount of stETH for 1 wstETH, in 1e27 decimals
    uint256 internal _rate;
}

/// @notice This contract stores the rate of stETH for 1 wstETH in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
contract WstETHContractRate is IWstETH, IFluidOracle, FluidCenterPrice, Variables, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidOracleError(ErrorTypes.ContractRate__InvalidParams);
        }
        _;
    }

    constructor(
        string memory infoName_,
        IWstETH wstETH_,
        uint256 minUpdateDiffPercent_
    ) validAddress(address(wstETH_)) FluidCenterPrice(infoName_) {
        if (minUpdateDiffPercent_ == 0 || minUpdateDiffPercent_ > 1e5) {
            // revert if > 10% or 0
            revert FluidOracleError(ErrorTypes.ContractRate__InvalidParams);
        }
        _WSTETH = wstETH_;
        _MIN_UPDATE_DIFF_PERCENT = minUpdateDiffPercent_;
        _rate = _WSTETH.stEthPerToken() * 1e9;
    }

    /// @inheritdoc FluidCenterPrice
    function infoName() public view override(IFluidOracle, FluidCenterPrice) returns (string memory) {
        return super.infoName();
    }

    /// @notice Rebalance the contract rate by updating the stored rate with the current rate from the WSTETH contract.
    /// @dev The rate is only updated if the difference between the current rate and the new rate is greater than or
    ///      equal to the minimum update difference percentage.
    function rebalance() external {
        uint256 curRate_ = _rate;
        uint256 newRate_ = _WSTETH.stEthPerToken() * 1e9; // scale to 1e27
        uint256 rateDiffPercent;
        unchecked {
            if (curRate_ > newRate_) {
                rateDiffPercent = ((curRate_ - newRate_) * 1e4) / curRate_;
            } else if (newRate_ > curRate_) {
                rateDiffPercent = ((newRate_ - curRate_) * 1e4) / curRate_;
            }
        }

        if (rateDiffPercent < _MIN_UPDATE_DIFF_PERCENT) {
            revert FluidOracleError(ErrorTypes.ContractRate__MinUpdateDiffNotReached);
        }

        _rate = newRate_;

        emit LogRebalanceRate(curRate_, newRate_);
    }

    /// @inheritdoc IWstETH
    function stEthPerToken() external view override returns (uint256) {
        return _rate / 1e9; // scale to 1e18
    }

    /// @inheritdoc IWstETH
    function tokensPerStEth() external view override returns (uint256) {
        return 1e45 / _rate; // scale to 1e18
    }

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external view override returns (uint256 price_) {
        return _rate;
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRate() external view virtual returns (uint256 exchangeRate_) {
        return _rate;
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateOperate() external view virtual returns (uint256 exchangeRate_) {
        return _rate;
    }

    /// @inheritdoc IFluidOracle
    function getExchangeRateLiquidate() external view virtual returns (uint256 exchangeRate_) {
        return _rate;
    }
}
