// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { DexShareResolver } from "../../../common/dexShareResolver.sol";
import { VaultT2Oracle } from "../../vaultTypes/vaultT2Oracle.sol";

/// @notice Holds `VaultT2Oracle` creation code for the factory.
contract VaultT2OracleDeploymentLogic {
    function creationCodeWithArgs(
        address usdOracle_,
        address borrowToken_,
        DexShareResolver.DexParams calldata dex_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) external pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(VaultT2Oracle).creationCode,
                abi.encode(
                    usdOracle_,
                    borrowToken_,
                    dex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }
}
