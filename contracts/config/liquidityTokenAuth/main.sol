// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Structs as AdminModuleStructs } from "../../liquidity/adminModule/structs.sol";
import { IFluidReserveContract } from "../../reserve/interfaces/iReserveContract.sol";

abstract contract Constants {
    /// @notice Fluid liquidity address
    IFluidLiquidity public immutable LIQUIDITY;

    /// @notice Team multisig allowed to trigger collecting revenue
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public constant TEAM_MULTISIG2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;

    /// @notice reserve contract for fetching allowed rebalancers
    IFluidReserveContract public immutable RESERVE_CONTRACT;

    uint256 internal constant FOUR_DECIMALS = 10000;
    uint256 internal constant X14 = 0x3fff;
}

abstract contract Events {
    /// @notice emitted when RateDataV2Params is initiated
    event LogInitiateRateDateV2Params(address token);

    /// @notice emitted when TokenConfig is initiated
    event LogInitiateTokenConfig(address token);

    /// @notice emitted when the reserve factor for a token is updated
    event LogUpdateReserveFactor(address token, uint256 oldReserveFactor, uint256 newReserveFactor);
}

/// @notice Initializes a token at Liquidity Layer if token is not already initialized and update token reserve factor
contract FluidLiquidityTokenAuth is Constants, Error, Events {
    /// @dev Validates that an address is a rebalancer (taken from reserve contract) or team multisig
    modifier onlyRebalancerOrMultisig() {
        if (!RESERVE_CONTRACT.isRebalancer(msg.sender) && msg.sender != TEAM_MULTISIG && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth__Unauthorized);
        }
        _;
    }

    /// @dev Validates that an address is a rebalancer (taken from reserve contract) or team multisig
    modifier onlyMultisig() {
        if (msg.sender != TEAM_MULTISIG && TEAM_MULTISIG2 != msg.sender) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth__Unauthorized);
        }
        _;
    }

    constructor(address liquidity_, IFluidReserveContract reserveContract_) {
        if (liquidity_ == address(0) || address(reserveContract_) == address(0)) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        RESERVE_CONTRACT = reserveContract_;
    }

    /// @notice Initializes rateDataV2 for a token at Liquidity Layer if token is not initialized and sets default token config
    function listToken(address token_) external onlyRebalancerOrMultisig {
        _initializeRateDataV2(token_);
        _initializeTokenConfig(token_);
    }

    /// @notice Updates the reserve factor for a token at Liquidity Layer
    /// @param token_ The address of the token to update
    /// @param newReserveFactor_ The new reserve factor to set (in 1e2: 100% = 10_000; 1% = 100)
    function updateReserveFactor(address token_, uint256 newReserveFactor_) external onlyMultisig {
        uint256 exchangePricesAndConfig_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                token_
            )
        );
        if (exchangePricesAndConfig_ == 0) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth__InvalidParams);
        }

        /// Next  14 bits =>  44- 57 => update on storage threshold (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
        uint256 storageUpdateThreshold_ = (exchangePricesAndConfig_ >>
            LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UPDATE_THRESHOLD) & X14;

        /// First 14 bits =>   0- 13 => max allowed utilization (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
        uint256 maxUtilization_ = FOUR_DECIMALS;

        /// Next  14 bits =>  16- 29 => fee on interest from borrowers to lenders (in 1e2: 100% = 10_000; 1% = 100 -> max value 16_383). configurable.
        uint256 oldReserveFactor_ = (exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_FEE) & X14;

        if ((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2) & 1 == 1) {
            uint256 configs2_ = LIQUIDITY.readFromStorage(
                LiquiditySlotsLink.calculateMappingStorageSlot(
                    LiquiditySlotsLink.LIQUIDITY_CONFIGS2_MAPPING_SLOT,
                    token_
                )
            );
            maxUtilization_ = configs2_ & X14;
        }

        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: token_,
            fee: newReserveFactor_,
            threshold: storageUpdateThreshold_,
            maxUtilization: maxUtilization_
        });

        LIQUIDITY.updateTokenConfigs(tokenConfigs_);

        emit LogUpdateReserveFactor(token_, oldReserveFactor_, newReserveFactor_);
    }

    /// @notice Initializes rateDataV2 for a token at Liquidity Layer if token is not initialized
    function _initializeRateDataV2(address token_) internal {
        bytes32 borrowRateDataSlot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_RATE_DATA_MAPPING_SLOT,
            token_
        );
        uint256 rateConfig_ = LIQUIDITY.readFromStorage(borrowRateDataSlot);
        if (rateConfig_ > 0) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth_AlreadyInitialized);
        }

        AdminModuleStructs.RateDataV2Params[] memory params_ = new AdminModuleStructs.RateDataV2Params[](1);
        params_[0] = AdminModuleStructs.RateDataV2Params({
            token: token_,
            kink1: 5000,
            kink2: 8000,
            rateAtUtilizationZero: 0,
            rateAtUtilizationKink1: 2000,
            rateAtUtilizationKink2: 4000,
            rateAtUtilizationMax: 10000
        });
        LIQUIDITY.updateRateDataV2s(params_);

        emit LogInitiateRateDateV2Params(token_);
    }

    /// @notice Initializes token at Liquidity Layer if not already initialized
    function _initializeTokenConfig(address token_) internal {
        uint256 exchangePricesAndConfig_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                token_
            )
        );

        if (exchangePricesAndConfig_ > 0) {
            revert FluidConfigError(ErrorTypes.LiquidityTokenAuth_AlreadyInitialized);
        }

        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: token_,
            fee: 1000,
            threshold: 30,
            maxUtilization: 10000
        });

        LIQUIDITY.updateTokenConfigs(tokenConfigs_);

        emit LogInitiateTokenConfig(token_);
    }
}
