// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidOracle } from "./interfaces/iFluidOracle.sol";
import { FluidCenterPrice } from "./fluidCenterPrice.sol";

import { Error as OracleError } from "./error.sol";
import { ErrorTypes } from "./errorTypes.sol";

abstract contract Events {
    /// @notice emitted when rebalancer successfully changes the contract rate
    event LogRebalanceRate(uint256 oldRate, uint256 newRate);
}

abstract contract Constants {
    /// @dev external exchange rate source contract
    address internal immutable _RATE_SOURCE;

    /// @dev Minimum difference to trigger update in percent 1e4 decimals, 10000 = 1%
    uint256 internal immutable _MIN_UPDATE_DIFF_PERCENT;

    /// @dev Minimum time after which an update can trigger, even if it does not reach `_MIN_UPDATE_DIFF_PERCENT`
    uint256 internal immutable _MIN_HEART_BEAT;
}

abstract contract Variables is Constants {
    /// @dev exchange rate in 1e27 decimals
    uint216 internal _rate;

    /// @dev time when last update for rate happened
    uint40 internal _lastUpdateTime;
}

/// @notice This contract stores an exchange rate in intervals to optimize gas cost.
/// @notice Properly implements all interfaces for use as IFluidCenterPrice and IFluidOracle.
abstract contract FluidContractRate is IFluidOracle, FluidCenterPrice, Variables, Events {
    /// @dev Validates that an address is not the zero address
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidOracleError(ErrorTypes.ContractRate__InvalidParams);
        }
        _;
    }

    constructor(
        string memory infoName_,
        address rateSource_,
        uint256 minUpdateDiffPercent_,
        uint256 minHeartBeat_
    ) validAddress(rateSource_) FluidCenterPrice(infoName_) {
        if (minUpdateDiffPercent_ == 0 || minUpdateDiffPercent_ > 1e5 || minHeartBeat_ == 0) {
            // revert if > 10% or 0
            revert FluidOracleError(ErrorTypes.ContractRate__InvalidParams);
        }
        _RATE_SOURCE = rateSource_;
        _MIN_UPDATE_DIFF_PERCENT = minUpdateDiffPercent_;
        _MIN_HEART_BEAT = minHeartBeat_;

        _rate = uint216(_getNewRate1e27());
        _lastUpdateTime = uint40(block.timestamp);
    }

    /// @dev read the exchange rate from the external contract e.g. wstETH or rsETH exchange rate, scaled to 1e27
    /// To be implemented by inheriting contract
    function _getNewRate1e27() internal view virtual returns (uint256 exchangeRate_);

    /// @inheritdoc FluidCenterPrice
    function infoName() public view override(IFluidOracle, FluidCenterPrice) returns (string memory) {
        return super.infoName();
    }

    /// @inheritdoc IFluidOracle
    function targetDecimals() public pure override(IFluidOracle, FluidCenterPrice) returns (uint8) {
        return _TARGET_DECIMALS;
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

    /// @notice Rebalance the contract rate by updating the stored rate with the current rate from the external contract.
    /// @dev The rate is only updated if the difference between the current rate and the new rate is greater than or
    ///      equal to the minimum update difference percentage.
    function rebalance() external {
        uint256 curRate_ = _rate;
        uint256 newRate_ = _getNewRate1e27();
        if (newRate_ == 0) {
            revert FluidOracleError(ErrorTypes.ContractRate__NewRateZero);
        }

        uint256 rateDiffPercent;
        unchecked {
            if (curRate_ > newRate_) {
                rateDiffPercent = ((curRate_ - newRate_) * 1e6) / curRate_;
            } else if (newRate_ > curRate_) {
                rateDiffPercent = ((newRate_ - curRate_) * 1e6) / curRate_;
            }
        }
        if (rateDiffPercent < _MIN_UPDATE_DIFF_PERCENT) {
            revert FluidOracleError(ErrorTypes.ContractRate__MinUpdateDiffNotReached);
        }

        _rate = uint216(newRate_);
        _lastUpdateTime = uint40(block.timestamp);

        emit LogRebalanceRate(curRate_, newRate_);
    }

    /// @inheritdoc FluidCenterPrice
    function centerPrice() external override returns (uint256 price_) {
        // heart beat check update for Dex swaps
        if (_lastUpdateTime + _MIN_HEART_BEAT < block.timestamp) {
            uint256 curRate_ = _rate;
            uint256 newRate_ = _getNewRate1e27();
            if (newRate_ == 0) {
                revert FluidOracleError(ErrorTypes.ContractRate__NewRateZero);
            }

            _rate = uint216(newRate_);
            _lastUpdateTime = uint40(block.timestamp);

            emit LogRebalanceRate(curRate_, newRate_);
        }

        return _rate;
    }

    /// @notice returns how much the new rate would be different from current rate in percent (10000 = 1%, 1 = 0.0001%).
    function configPercentDiff() public view virtual returns (uint256 configPercentDiff_) {
        uint256 curRate_ = _rate;
        uint256 newRate_ = _getNewRate1e27();

        unchecked {
            if (curRate_ > newRate_) {
                configPercentDiff_ = ((curRate_ - newRate_) * 1e6) / curRate_;
            } else if (newRate_ > curRate_) {
                configPercentDiff_ = ((newRate_ - curRate_) * 1e6) / curRate_;
            }
        }
    }

    /// @notice returns all config vars, last update timestamp, and external rate source oracle address
    function configData()
        external
        view
        returns (uint256 minUpdateDiffPercent_, uint256 minHeartBeat_, uint40 lastUpdateTime_, address rateSource_)
    {
        return (_MIN_UPDATE_DIFF_PERCENT, _MIN_HEART_BEAT, _lastUpdateTime, _RATE_SOURCE);
    }
}
