// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";

interface IFluidDexT1Admin {
    /// @notice sets a new fee and revenue cut for a certain dex
    /// @param fee_ new fee (scaled so that 1% = 10000)
    /// @param revenueCut_ new revenue cut
    function updateFeeAndRevenueCut(uint fee_, uint revenueCut_) external;
}

abstract contract Events {
    /// @notice emitted when the fee is updated
    event LogSetFee(address dex, uint oldFee, uint newFee);
}

abstract contract Constants {
    uint256 internal constant FOUR_DECIMALS = 1e4;

    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X17 = 0x1ffff;

    /// @notice Team multisig allowed to trigger collecting revenue
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

contract FluidDexFeeHandler is Constants, Error, Events {
    /// @dev Validates that an address is team multisig
    modifier onlyMultisig() {
        if (msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.DexFeeAuth__Unauthorized);
        }
        _;
    }

    function getDexFeeAndRevenueCut(address dex_) public view returns (uint256 fee_, uint256 revenueCut_) {
        uint256 dexVariables2_ = IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        fee_ = (dexVariables2_ >> 2) & X17;
        revenueCut_ = (dexVariables2_ >> 19) & X7;
    }

    function setDexFee(address dex_, uint256 newFee_) external onlyMultisig {
        (uint256 currentFee_, uint256 currentRevenueCut_) = getDexFeeAndRevenueCut(dex_);

        IFluidDexT1Admin(dex_).updateFeeAndRevenueCut(newFee_, currentRevenueCut_ * FOUR_DECIMALS);

        emit LogSetFee(dex_, currentFee_, newFee_);
    }
}
