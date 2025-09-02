// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;
import "./constantVariables.sol";

// TODO
// import { IFluidDexFactory } from "../../interfaces/iDexFactory.sol";
// import { Error } from "../../error.sol";
// import { ErrorTypes } from "../../errorTypes.sol";

abstract contract ImmutableVariables is ConstantVariables {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of liquidity contract
    IFluidLiquidity internal immutable LIQUIDITY;

    /// @dev Address of contract used for deploying center price & hook related contract
    address internal immutable DEPLOYER_CONTRACT;
}
