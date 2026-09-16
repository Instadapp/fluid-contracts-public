// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { DexShareResolver } from "../../../common/dexShareResolver.sol";
import { VaultT4Oracle } from "../../vaultTypes/vaultT4Oracle.sol";

/// @notice Holds `VaultT4Oracle` creation code for the factory.
contract VaultT4OracleDeploymentLogic {
    function creationCodeWithArgs(
        address usdOracle_,
        DexShareResolver.DexParams calldata colDex_,
        DexShareResolver.DexParams calldata debtDex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) external pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(VaultT4Oracle).creationCode,
                abi.encode(
                    usdOracle_,
                    colDex_,
                    debtDex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }
}
