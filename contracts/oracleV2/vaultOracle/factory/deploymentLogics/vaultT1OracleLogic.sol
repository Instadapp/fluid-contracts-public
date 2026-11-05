// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { VaultT1Oracle } from "../../vaultTypes/vaultT1Oracle.sol";

/// @notice Holds `VaultT1Oracle` creation code for the factory.
contract VaultT1OracleDeploymentLogic {
    function creationCodeWithArgs(
        address usdOracle_,
        address supplyToken_,
        address borrowToken_,
        uint256 supplyEMode_,
        uint256 borrowEMode_
    ) external pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(VaultT1Oracle).creationCode,
                abi.encode(usdOracle_, supplyToken_, borrowToken_, supplyEMode_, borrowEMode_)
            );
    }
}
