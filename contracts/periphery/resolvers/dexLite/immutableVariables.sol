// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "./constantVariables.sol";

abstract contract ImmutableVariables is ConstantVariables {
    // IMMUTABLE VARIABLES
    IDexLite internal immutable DEX_LITE;
    address internal immutable LIQUIDITY;
    address internal immutable DEPLOYER_CONTRACT;
}