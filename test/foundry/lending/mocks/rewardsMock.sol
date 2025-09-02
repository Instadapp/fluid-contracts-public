//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/interfaces/iLendingRewardsRateModel.sol";

contract LendingRewardsRateMockModel is IFluidLendingRewardsRateModel {
    uint256 internal _rate;
    bool internal _ended;
    uint256 internal _startTime;

    function setRate(uint256 rate_) external {
        _rate = rate_;
    }

    function setStartTime(uint256 startTime_) external {
        _startTime = startTime_;
    }

    function setEnded(bool ended_) external {
        _ended = ended_;
    }

    /// @inheritdoc IFluidLendingRewardsRateModel
    function getRate(uint256) public view returns (uint256, bool, uint256) {
        return (_rate, _ended, _startTime);
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
            address initiator_
        )
    {
        revert("Not implemented");
    }
}
