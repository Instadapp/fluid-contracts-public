// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Constants {
    /// @notice Fluid liquidity address
    IFluidLiquidity public immutable LIQUIDITY;

    /// @notice Team multisig allowed to trigger collecting revenue
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @notice Fluid reserve contract, allowed rebalancers there are allowed to trigger collecting revenue
    IFluidReserveContract public immutable RESERVE_CONTRACT;
}

abstract contract Events {
    /// @notice emitted when revenue is collected
    event LogCollectRevenue(address[]);
}

/// @notice Collects the revenue from the Fluid Liquidity layer to the configured revenue collector
contract FluidCollectRevenueAuth is Constants, Error, Events {
    /// @dev Validates that an address is a rebalancer (taken from reserve contract) or team multisig
    modifier onlyRebalancerOrMultisig() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender) && msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.CollectRevenueAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_, address reserveContract_) {
        if (liquidity_ == address(0) || reserveContract_ == address(0)) {
            revert FluidConfigError(ErrorTypes.CollectRevenueAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        RESERVE_CONTRACT = IFluidReserveContract(reserveContract_);
    }

    /// @notice calls the collectRevenue method in the liquidity layer for `tokens_`
    function collectRevenue(address[] calldata tokens_) external onlyRebalancerOrMultisig {
        LIQUIDITY.collectRevenue(tokens_);

        emit LogCollectRevenue(tokens_);
    }
}
