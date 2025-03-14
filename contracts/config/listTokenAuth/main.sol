// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";

abstract contract Constants {
    /// @notice Fluid liquidity address
    IFluidLiquidity public immutable LIQUIDITY;

    /// @notice Team multisig allowed to trigger collecting revenue
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

abstract contract Events {
    /// @notice emitted when RateDataV2Params is initiated
    event LogInitiateRateDateV2Params(address token);

    /// @notice emitted when TokenConfig is initiated
    event LogInitiateTokenConfig(address token);
}

/// @notice Initializes a token at Liquidity Layer if token is not already initialized
contract FluidListTokenAuth is Constants, Error, Events {
    /// @dev Validates that an address is a multisig (taken from reserve auth)
    modifier onlyMultisig() {
        if (TEAM_MULTISIG != msg.sender) {
            revert FluidConfigError(ErrorTypes.ListTokenAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_) {
        if (liquidity_ == address(0)) {
            revert FluidConfigError(ErrorTypes.ListTokenAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
    }

    /// @notice Initializes rateDataV2 for a token at Liquidity Layer if token is not initialized
    function initializeRateDataV2(address token_) external onlyMultisig {
        bytes32 borrowRateDataSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
            token_
        );
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(borrowRateDataSlot);
        if (rateConfig_ > 0) {
            revert FluidConfigError(ErrorTypes.ListTokenAuth_AlreadyInitialized);
        }

        AdminModuleStructs.RateDataV2Params memory rateData_ = AdminModuleStructs.RateDataV2Params({
            token: token_,
            kink1: 2000,
            kink2: 4000,
            rateAtUtilizationZero: 0,
            rateAtUtilizationKink1: 5000,
            rateAtUtilizationKink2: 8000,
            rateAtUtilizationMax: 10000
        });

        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = rateData_;
        LIQUIDITY.updateRateDataV2s(params_);

        emit LogInitiateRateDateV2Params(token_);
    }

    /// @notice Initializes token at Liquidity Layer if not already initialized
    function initializeTokenConfig(address token_) external onlyMultisig {
        uint256 exchangePricesAndConfig_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                token_
            )
        );

        if (exchangePricesAndConfig_ > 0) {
            revert FluidConfigError(ErrorTypes.ListTokenAuth_AlreadyInitialized);
        }

        AdminModuleStructs.TokenConfig memory tokenConfig_ = AdminModuleStructs.TokenConfig({
            token: token_,
            fee: 1000,
            threshold: 30,
            maxUtilization: 10000
        });

        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = tokenConfig_;

        LIQUIDITY.updateTokenConfigs(tokenConfigs_);

        emit LogInitiateTokenConfig(token_);
    }
}
