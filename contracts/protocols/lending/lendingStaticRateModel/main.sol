// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLendingStaticRateModel } from "../interfaces/iLendingStaticRateModel.sol";
import { IFTokenAdmin } from "../interfaces/iFToken.sol";

import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

abstract contract Constants {
    /// @dev precision decimals for static rate offset (`1e12` = 1%)
    uint256 internal constant RATE_PRECISION = 1e12;

    /// @dev max |offset| is 50%. no config outside ± this should be possible.
    uint256 internal constant MAX_RATE = 50 * RATE_PRECISION; // 1e12 = 1%

    /// @dev address which has access to manage the static rate
    address internal immutable CONFIGURATOR;

    /// @notice address of the fTokens where these rewards are supposed to be set
    address public immutable FTOKEN;
    address public immutable FTOKEN2;
    address public immutable FTOKEN3;
}

abstract contract Variables is Constants {
    // ----------------------- slot 0 ---------------------------
    // packed: staticRate (184 signed) | duration (32) | startTime (40)

    /// @dev signed APR offset vs Liquidity supply yield (`1e12` = 1%). fToken applies
    ///      `liquidityYield ± offset` when compounding the share exchange price.
    int184 internal _staticRate;

    /// @dev duration for which the current static rate runs (seconds)
    uint32 internal _duration;

    /// @dev when current static rate accrual started
    uint40 internal _startTime;
}

abstract contract Events {
    /// @notice Emitted when the static rate offset is updated.
    event LogSetStaticRate(int256 rate, uint256 duration);

    /// @notice Emitted when the static rate program is stopped early.
    event LogStopStaticRate();
}

/// @title LendingStaticRateModel
/// @notice Returns a signed APR offset (`1e12` = 1%) for wired fTokens. The fToken itself applies
///         Liquidity-layer supply yield ± this offset when compounding the share exchange price.
/// @dev Also exposes legacy streaming `getRate` / `getConfig` as zero stubs (same selectors) so older
///      LendingResolvers that always call those do not revert on static-wired fTokens. `getRateV2` matches
///      the streaming model's signed ABI (`int256 rate`) so fTokens use one call path for both model types.
contract FluidLendingStaticRateModel is Variables, IFluidLendingStaticRateModel, Events, Error {
    /// @dev Validates that an address is the configurator (team multisig)
    modifier onlyConfigurator() {
        if (msg.sender != CONFIGURATOR) {
            revert FluidLendingError(ErrorTypes.LendingStaticRateModel__Unauthorized);
        }
        _;
    }

    /// @notice Sets variables for static rate configuration.
    /// @param configurator_ The address with authority to configure the static rate.
    /// @param fToken_ The address of the associated fToken contract.
    /// @param fToken2_ The address of the associated fToken contract 2, optional.
    /// @param fToken3_ The address of the associated fToken contract 3, optional.
    /// @param initialRate_ Signed APR offset (`1e12` = 1%), within ±`MAX_RATE`.
    /// @param duration_ Duration in seconds for which the rate runs.
    constructor(
        address configurator_,
        address fToken_,
        address fToken2_,
        address fToken3_,
        int256 initialRate_,
        uint256 duration_
    ) {
        if (
            configurator_ == address(0) ||
            fToken_ == address(0) ||
            _isOutsideMaxRate(initialRate_) ||
            duration_ == 0 ||
            duration_ > type(uint32).max
        ) {
            revert FluidLendingError(ErrorTypes.LendingStaticRateModel__InvalidParams);
        }

        CONFIGURATOR = configurator_;
        FTOKEN = fToken_;
        FTOKEN2 = fToken2_;
        FTOKEN3 = fToken3_;
        _staticRate = int184(initialRate_);
        _startTime = uint40(block.timestamp);
        _duration = uint32(duration_);
    }

    /// @inheritdoc IFluidLendingStaticRateModel
    function getStaticConfig()
        external
        view
        returns (int256 staticRate_, uint256 duration_, uint256 startTime_, address configurator_, uint256 maxRate_)
    {
        return (int256(_staticRate), _duration, _startTime, CONFIGURATOR, MAX_RATE);
    }

    /// @dev Legacy streaming config shape. Always zeros: use `getStaticConfig`.
    function getConfig()
        external
        pure
        returns (
            uint256 duration_,
            uint256 startTime_,
            uint256 endTime_,
            uint256 startTvl_,
            uint256 maxRate_,
            uint256 rewardAmount_,
            address configurator_
        )
    {
        return (0, 0, 0, 0, 0, 0, address(0));
    }

    /// @dev Legacy streaming rate stub. Accrual uses signed `getRateV2` on the fToken static path.
    function getRate(
        uint256 /** totalAssets_ */
    ) external pure returns (uint256 rate_, bool ended_, uint256 startTime_) {
        return (0, false, 0);
    }

    /// @inheritdoc IFluidLendingStaticRateModel
    /// @dev Returns the configured signed offset only. fToken combines it with Liquidity yield.
    function getRateV2(
        uint256 /** totalAssets_ */
    ) public view returns (int256 rate_, bool ended_, uint256 startTime_, uint256 endTime_) {
        startTime_ = _startTime;
        unchecked {
            endTime_ = startTime_ + _duration;
        }
        rate_ = int256(_staticRate);
        ended_ = block.timestamp > endTime_;
    }

    /// @notice Updates the signed APR offset and duration. Callable only by configurator.
    /// @param rate_ signed APR offset with `1e12` = 1% (e.g. `1e12` = +1% on Liquidity, `-3e12` = −3%)
    /// @param duration_ duration in seconds
    function setStaticRate(int256 rate_, uint256 duration_) external onlyConfigurator {
        if (_isOutsideMaxRate(rate_)) {
            revert FluidLendingError(ErrorTypes.LendingStaticRateModel__MaxRate);
        }
        if (duration_ == 0 || duration_ > type(uint32).max) {
            revert FluidLendingError(ErrorTypes.LendingStaticRateModel__InvalidParams);
        }

        // settle accrual on the fTokens under the OLD rate first (updateStaticRewards -> updateRates()),
        // otherwise the new rate would apply retroactively since each fToken's last exchange price update.
        IFluidLendingStaticRateModel staticRateModel_ = IFluidLendingStaticRateModel(address(this));
        IFTokenAdmin(FTOKEN).updateStaticRewards(staticRateModel_);
        if (FTOKEN2 != address(0)) IFTokenAdmin(FTOKEN2).updateStaticRewards(staticRateModel_);
        if (FTOKEN3 != address(0)) IFTokenAdmin(FTOKEN3).updateStaticRewards(staticRateModel_);

        _staticRate = int184(rate_);
        _startTime = uint40(block.timestamp);
        _duration = uint32(duration_);

        emit LogSetStaticRate(rate_, duration_);
    }

    /// @notice Stops the current static rate program instantly. Mirrors streaming `stopRewards()`.
    ///         Settles fToken accrual via `updateRates()` only (does not re-wire the model on the fToken).
    function stopStaticRate() external onlyConfigurator {
        if (_startTime == 0 || block.timestamp > _startTime + _duration) {
            revert FluidLendingError(ErrorTypes.LendingStaticRateModel__AlreadyStopped);
        }

        IFTokenAdmin(FTOKEN).updateRates();
        if (FTOKEN2 != address(0)) IFTokenAdmin(FTOKEN2).updateRates();
        if (FTOKEN3 != address(0)) IFTokenAdmin(FTOKEN3).updateRates();

        _duration = (block.timestamp - 1) > _startTime ? uint32(block.timestamp - _startTime - 1) : 0;

        emit LogStopStaticRate();
    }

    function _isOutsideMaxRate(int256 rate_) internal pure returns (bool) {
        return rate_ > int256(MAX_RATE) || rate_ < -int256(MAX_RATE);
    }
}
