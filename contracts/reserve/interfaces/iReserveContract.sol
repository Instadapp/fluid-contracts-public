// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";

interface IFluidReserveContract {
    function isRebalancer(address user) external returns (bool);

    function initialize(
        address[] memory _auths,
        address[] memory _rebalancers,
        IFluidLiquidity liquidity_,
        address owner_
    ) external;

    function rebalanceFToken(address protocol_) external;

    function rebalanceVault(address protocol_) external;

    function transferFunds(address token_) external;

    function getProtocolTokens(address protocol_) external;

    function updateAuth(address auth_, bool isAuth_) external;

    function updateRebalancer(address rebalancer_, bool isRebalancer_) external;

    function approve(address[] memory protocols_, address[] memory tokens_, uint256[] memory amounts_) external;

    function revoke(address[] memory protocols_, address[] memory tokens_) external;
}
