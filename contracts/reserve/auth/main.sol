// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface IFluidReserveContract {
    function updateRebalancer(address rebalancer_, bool isRebalancer_) external;
}

contract FluidReserveContractAuthHandler {
    event LogUpdateRebalancer(address indexed rebalancer, bool isRebalancer);

    IFluidReserveContract public constant RESERVE = IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    function updateRebalancer(address rebalancer_, bool isRebalancer_) external {
        require(msg.sender == TEAM_MULTISIG, "not-team-multisig");
        RESERVE.updateRebalancer(rebalancer_, isRebalancer_);

        emit LogUpdateRebalancer(rebalancer_, isRebalancer_);
    }
}
