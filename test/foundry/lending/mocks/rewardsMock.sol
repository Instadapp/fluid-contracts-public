//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";

contract LendingRewardsRateMockModel is IFluidLendingRewardsRateModel {
    int256 internal _rate;
    bool internal _ended;
    uint256 internal _startTime;
    uint256 internal _endTime;

    function setRate(uint256 rate_) external {
        _rate = int256(rate_);
    }

    /// @dev Allows negative rates to exercise fToken ±MAX_REWARDS_RATE clamp / floor paths.
    function setSignedRate(int256 rate_) external {
        _rate = rate_;
    }

    function setStartTime(uint256 startTime_) external {
        _startTime = startTime_;
    }

    function setEnded(bool ended_) external {
        _ended = ended_;
    }

    function setEndTime(uint256 endTime_) external {
        _endTime = endTime_;
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    function getRate(uint256) public view returns (uint256, bool, uint256) {
        uint256 legacyRate_ = _rate > 0 ? uint256(_rate) : 0;
        return (_ended ? 0 : legacyRate_, _ended, _startTime);
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    function getRateV2(uint256) public view returns (int256, bool, uint256, uint256) {
        return (_rate, _ended, _startTime, _endTime);
    }

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
        revert("Not implemented");
    }
}
