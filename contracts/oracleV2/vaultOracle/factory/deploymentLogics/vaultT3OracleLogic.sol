// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { DexShareResolver } from "../../../common/dexShareResolver.sol";
import { VaultT3Oracle } from "../../vaultTypes/vaultT3Oracle.sol";

/// @notice Holds `VaultT3Oracle` creation code for the factory.
contract VaultT3OracleDeploymentLogic {
    function creationCodeWithArgs(
        address usdOracle_,
        address supplyToken_,
        DexShareResolver.DexParams calldata dex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) external pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(VaultT3Oracle).creationCode,
                abi.encode(
                    usdOracle_,
                    supplyToken_,
                    dex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }
}
