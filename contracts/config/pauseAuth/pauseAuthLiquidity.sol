// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

// ==================== FluidPauseAuthLiquidity ====================
//
// Executes pause/unpause operations at the Fluid Liquidity layer on behalf of FluidPauseAuth.
//
// ACCESS:
//   - Only callable by the FluidPauseAuth main contract (set once via setPauseAuthContract).
//
// CAPABILITIES:
//   - pauseVault / unpauseVault (by vault ID) — resolves tokens, calls LL (un)pauseUserSupply / (un)pauseUserBorrow.
//     DEX-backed sides are excluded (handled by FluidPauseAuthDex).
//   - pauseDex / unpauseDex (by DEX ID) — resolves tokens, calls LL (un)pauseUserSupply / (un)pauseUserBorrow.
//   - pauseTokens / unpauseTokens — sets/clears token pause mode on exchangePricesAndConfig at LL.
//   - pauseUserSupply / pauseUserBorrow / unpauseUserSupply / unpauseUserBorrow — pass-through to LL.
//
// BEHAVIOR:
//   - Does NOT emit operational events. Returns structured data so FluidPauseAuth can emit unified events.
//   - Liquidity user class (0/1/2) is enforced here only — not on FluidPauseAuthDex (see pauseAuth/SPEC.md).
//   - On pause: class 2 users skip Liquidity pause entirely; class 1 strips withdraw/payback (supply/borrow still pausable at LL).
//     If class stripping leaves no flags for a side, that side is skipped (Liquidity rejects all-false pause/unpause calls).
//   - Tokens with no Liquidity row for the protocol are dropped before the call; a protocol with no rows at all
//     is a silent no-op, so one unconfigured vault/DEX cannot revert an emergency batch.
//   - Token lists are forwarded unfiltered: one unlisted token reverts the whole pauseTokens / unpauseTokens call.
//   - Liquidity returns per-token flags showing which targeted token pause states changed.
//
// DEPLOYMENT:
//   - Must be set as **guardian** on Fluid Liquidity.
//   - FluidPauseAuth address set via setPauseAuthContract after deployment and before registration (locked once set).
// =================================================================

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidDexFactory } from "../../protocols/dex/interfaces/iDexFactory.sol";
import { IFluidVaultT1 } from "../../protocols/vault/interfaces/iVaultT1.sol";
import { IFluidVault } from "../../protocols/vault/interfaces/iVault.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { LiquiditySlotsLink } from "../../libraries/liquiditySlotsLink.sol";
import { FluidProtocolTypes } from "../../libraries/fluidProtocolTypes.sol";
import { IFluidPauseAuthLiquidity } from "./interfaces/iPauseAuthLiquidity.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Events {
    event LogSetPauseAuthContract(address indexed pauseAuthContract);
}

abstract contract Constants is FluidAuthLevels {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;

    /// @notice identity registry gating `setPauseAuthContract`.
    IFluidAuthGate public immutable AUTH_GATE;
}

abstract contract Variables is Constants {
    /// @notice FluidPauseAuth main contract. Set once by the MID tier, then permanently locked.
    address public pauseAuthContract;
}

/// @title   FluidPauseAuthLiquidity
/// @notice  Executes pause/unpause operations at the Fluid Liquidity layer. Callable only by the main FluidPauseAuth
///          contract. Does NOT emit operational events — the main contract handles all event emission based on return values.
contract FluidPauseAuthLiquidity is Variables, Events, Error, BasicValidations, IFluidPauseAuthLiquidity {
    modifier onlyPauseAuthContract() {
        if (msg.sender != pauseAuthContract) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    constructor(
        address liquidity_,
        address vaultFactory_,
        address dexFactory_,
        address authGate_
    ) validAddress(liquidity_) validAddress(vaultFactory_) validAddress(dexFactory_) validAddress(authGate_) {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() != liquidity_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    /// @notice Sets the FluidPauseAuth main contract address. Can only be called once (permanently locked after).
    function setPauseAuthContract(address pauseAuth_) external validAddress(pauseAuth_) {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        if (pauseAuthContract != address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuthContract = pauseAuth_;
        emit LogSetPauseAuthContract(pauseAuth_);
    }

    // ==================== Public methods ====================

    /// @inheritdoc IFluidPauseAuthLiquidity
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            address vault_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, skippedUserClass_) = _setVaultPauseState(
            vaultId_,
            pauseSupply_,
            pauseWithdraw_,
            pauseBorrow_,
            pausePayback_,
            true
        );
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            address vault_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, skippedUserClass_) = _setVaultPauseState(
            vaultId_,
            unpauseSupply_,
            unpauseWithdraw_,
            unpauseBorrow_,
            unpausePayback_,
            false
        );
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function pauseDex(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            address dex_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (dex_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, skippedUserClass_) = _setDexPauseState(
            dexId_,
            pauseSupply_,
            pauseWithdraw_,
            pauseBorrow_,
            pausePayback_,
            true
        );
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function unpauseDex(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            address dex_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (dex_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, skippedUserClass_) = _setDexPauseState(
            dexId_,
            unpauseSupply_,
            unpauseWithdraw_,
            unpauseBorrow_,
            unpausePayback_,
            false
        );
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function pauseTokens(
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        )
    {
        return LIQUIDITY.pauseTokens(tokens_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function unpauseTokens(
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (
            bool[] memory actedSupply_,
            bool[] memory actedWithdraw_,
            bool[] memory actedBorrow_,
            bool[] memory actedPayback_
        )
    {
        return LIQUIDITY.unpauseTokens(tokens_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function pauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) external override onlyPauseAuthContract returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        return LIQUIDITY.pauseUserSupply(user_, tokens_, pauseSupply_, pauseWithdraw_);
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function pauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external override onlyPauseAuthContract returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        return LIQUIDITY.pauseUserBorrow(user_, tokens_, pauseBorrow_, pausePayback_);
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function unpauseUserSupply(
        address user_,
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external override onlyPauseAuthContract returns (bool[] memory actedSupply_, bool[] memory actedWithdraw_) {
        return LIQUIDITY.unpauseUserSupply(user_, tokens_, unpauseSupply_, unpauseWithdraw_);
    }

    /// @inheritdoc IFluidPauseAuthLiquidity
    function unpauseUserBorrow(
        address user_,
        address[] calldata tokens_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external override onlyPauseAuthContract returns (bool[] memory actedBorrow_, bool[] memory actedPayback_) {
        return LIQUIDITY.unpauseUserBorrow(user_, tokens_, unpauseBorrow_, unpausePayback_);
    }

    // ==================== Internal: vault pause logic ====================

    /// @dev Shared vault pause/unpause logic. `wantsPaused_` == true -> pause, false -> unpause.
    ///      Resolves vault tokens; DEX-backed sides return empty token arrays and are skipped here.
    function _setVaultPauseState(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool wantsPaused_
    )
        internal
        returns (
            address vault_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (address[] memory supplyTokens_, address[] memory borrowTokens_) = _getVaultTokens(vault_);
        {
            (actedSupply_, actedWithdraw_, skippedUserClass_) = _setProtocolSupplyPauseState(
                vault_,
                supplyTokens_,
                pauseSupply_,
                pauseWithdraw_,
                wantsPaused_
            );
        }

        {
            uint256 skippedBorrowClass_;
            (actedBorrow_, actedPayback_, skippedBorrowClass_) = _setProtocolBorrowPauseState(
                vault_,
                borrowTokens_,
                pauseBorrow_,
                pausePayback_,
                wantsPaused_
            );
            if (skippedBorrowClass_ > skippedUserClass_) {
                skippedUserClass_ = skippedBorrowClass_;
            }
        }
    }

    /// @dev Shared DEX pause/unpause logic at the Liquidity layer. `wantsPaused_` == true -> pause, false -> unpause.
    function _setDexPauseState(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool wantsPaused_
    )
        internal
        returns (
            address dex_,
            bool actedSupply_,
            bool actedWithdraw_,
            bool actedBorrow_,
            bool actedPayback_,
            uint256 skippedUserClass_
        )
    {
        dex_ = DEX_FACTORY.getDexAddress(dexId_);
        if (dex_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (address[] memory supplyTokens_, address[] memory borrowTokens_) = _getDexTokens(dex_);
        {
            (actedSupply_, actedWithdraw_, skippedUserClass_) = _setProtocolSupplyPauseState(
                dex_,
                supplyTokens_,
                pauseSupply_,
                pauseWithdraw_,
                wantsPaused_
            );
        }

        {
            uint256 skippedBorrowClass_;
            (actedBorrow_, actedPayback_, skippedBorrowClass_) = _setProtocolBorrowPauseState(
                dex_,
                borrowTokens_,
                pauseBorrow_,
                pausePayback_,
                wantsPaused_
            );
            if (skippedBorrowClass_ > skippedUserClass_) {
                skippedUserClass_ = skippedBorrowClass_;
            }
        }
    }

    /// @dev Applies supply-side Liquidity pause state for any protocol represented as a Liquidity user.
    function _setProtocolSupplyPauseState(
        address user_,
        address[] memory tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool wantsPaused_
    ) internal returns (bool actedSupply_, bool actedWithdraw_, uint256 skippedUserClass_) {
        if (tokens_.length == 0 || (!pauseSupply_ && !pauseWithdraw_)) {
            return (false, false, 0);
        }
        tokens_ = _filterDefinedTokens(user_, tokens_, LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT);
        if (tokens_.length == 0) {
            return (false, false, 0);
        }
        if (wantsPaused_) {
            (pauseWithdraw_, skippedUserClass_) = _getSkippedUserClass(user_, pauseWithdraw_);
            if (skippedUserClass_ == 2) {
                return (false, false, 2);
            }
            // Class 1 cannot pause withdraw; stripping can leave no supply-side flags — do not call Liquidity with (false, false).
            if (!pauseSupply_ && !pauseWithdraw_) {
                return (false, false, skippedUserClass_);
            }
        }

        bool[] memory actedSupplyFlags_;
        bool[] memory actedWithdrawFlags_;
        if (wantsPaused_) {
            (actedSupplyFlags_, actedWithdrawFlags_) = LIQUIDITY.pauseUserSupply(
                user_,
                tokens_,
                pauseSupply_,
                pauseWithdraw_
            );
        } else {
            (actedSupplyFlags_, actedWithdrawFlags_) = LIQUIDITY.unpauseUserSupply(
                user_,
                tokens_,
                pauseSupply_,
                pauseWithdraw_
            );
        }
        actedSupply_ = _any(actedSupplyFlags_);
        actedWithdraw_ = _any(actedWithdrawFlags_);
    }

    /// @dev Applies borrow-side Liquidity pause state for any protocol represented as a Liquidity user.
    function _setProtocolBorrowPauseState(
        address user_,
        address[] memory tokens_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool wantsPaused_
    ) internal returns (bool actedBorrow_, bool actedPayback_, uint256 skippedUserClass_) {
        if (tokens_.length == 0 || (!pauseBorrow_ && !pausePayback_)) {
            return (false, false, 0);
        }
        tokens_ = _filterDefinedTokens(user_, tokens_, LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT);
        if (tokens_.length == 0) {
            return (false, false, 0);
        }
        if (wantsPaused_) {
            (pausePayback_, skippedUserClass_) = _getSkippedUserClass(user_, pausePayback_);
            if (skippedUserClass_ == 2) {
                return (false, false, 2);
            }
            // Class 1 cannot pause payback; stripping can leave no borrow-side flags — do not call Liquidity with (false, false).
            if (!pauseBorrow_ && !pausePayback_) {
                return (false, false, skippedUserClass_);
            }
        }

        bool[] memory actedBorrowFlags_;
        bool[] memory actedPaybackFlags_;
        if (wantsPaused_) {
            (actedBorrowFlags_, actedPaybackFlags_) = LIQUIDITY.pauseUserBorrow(
                user_,
                tokens_,
                pauseBorrow_,
                pausePayback_
            );
        } else {
            (actedBorrowFlags_, actedPaybackFlags_) = LIQUIDITY.unpauseUserBorrow(
                user_,
                tokens_,
                pauseBorrow_,
                pausePayback_
            );
        }
        actedBorrow_ = _any(actedBorrowFlags_);
        actedPayback_ = _any(actedPaybackFlags_);
    }

    /// @dev Returns the subset of `tokens_` for which `user_` has a Liquidity row at `mappingSlot_`.
    ///      Liquidity reverts `AdminModule__UserNotDefined` on an undefined (user, token) pair, which would take
    ///      down an entire emergency batch over one protocol that was never configured at Liquidity.
    function _filterDefinedTokens(
        address user_,
        address[] memory tokens_,
        uint256 mappingSlot_
    ) internal view returns (address[] memory filtered_) {
        uint256 length_ = tokens_.length;
        uint256 count_;
        bool[] memory include_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            if (
                LIQUIDITY.readFromStorage(
                    LiquiditySlotsLink.calculateDoubleMappingStorageSlot(mappingSlot_, user_, tokens_[i])
                ) != 0
            ) {
                include_[i] = true;
                count_++;
            }
        }

        if (count_ == length_) {
            return tokens_;
        }

        filtered_ = new address[](count_);
        uint256 j_;
        for (uint256 i; i < length_; i++) {
            if (include_[i]) {
                filtered_[j_] = tokens_[i];
                j_++;
            }
        }
    }

    /// @dev Returns the adjusted secondary flag and user class that requires auth-level handling for pause calls.
    function _getSkippedUserClass(
        address user_,
        bool secondary_
    ) internal view returns (bool adjustedSecondary_, uint256 skippedUserClass_) {
        adjustedSecondary_ = secondary_;
        uint256 userClass_ = LIQUIDITY.readFromStorage(
            LiquiditySlotsLink.calculateMappingStorageSlot(LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT, user_)
        );
        if (userClass_ == 2) {
            return (false, 2);
        }
        if (secondary_ && userClass_ == 1) {
            return (false, 1);
        }
    }

    function _any(bool[] memory values_) internal pure returns (bool) {
        uint256 length_ = values_.length;
        for (uint256 i; i < length_; ) {
            if (values_[i]) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @dev Returns whether `vault_` is a T1 vault. Falls back to true on revert (older vaults without TYPE()).
    function _isVaultT1(address vault_) internal view returns (bool) {
        try IFluidVault(vault_).TYPE() returns (uint256 type_) {
            return type_ == FluidProtocolTypes.VAULT_T1_TYPE;
        } catch {
            return true;
        }
    }

    /// @dev Resolves a vault to its LL-facing token arrays. DEX-backed sides return empty arrays.
    function _getVaultTokens(
        address vault_
    ) internal view returns (address[] memory supplyTokens_, address[] memory borrowTokens_) {
        if (_isVaultT1(vault_)) {
            try IFluidVaultT1(vault_).constantsView() returns (IFluidVaultT1.ConstantViews memory cv_) {
                supplyTokens_ = _buildTokenArray(cv_.supplyToken, address(0));
                borrowTokens_ = _buildTokenArray(cv_.borrowToken, address(0));
            } catch {
                revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
            }
        } else {
            try IFluidVault(vault_).constantsView() returns (IFluidVault.ConstantViews memory cv_) {
                if (cv_.supply == address(LIQUIDITY)) {
                    supplyTokens_ = _buildTokenArray(cv_.supplyToken.token0, cv_.supplyToken.token1);
                }
                if (cv_.borrow == address(LIQUIDITY)) {
                    borrowTokens_ = _buildTokenArray(cv_.borrowToken.token0, cv_.borrowToken.token1);
                }
            } catch {
                revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
            }
        }
    }

    /// @dev Resolves a DEX to its LL-facing token arrays. Reverts if unresolvable.
    function _getDexTokens(
        address dex_
    ) internal view returns (address[] memory supplyTokens_, address[] memory borrowTokens_) {
        try IFluidDexT1(dex_).constantsView() returns (IFluidDexT1.ConstantViews memory cv_) {
            try IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT)) returns (
                uint256 dexVariables2_
            ) {
                if ((dexVariables2_ & 1) == 1) {
                    supplyTokens_ = _buildTokenArray(cv_.token0, cv_.token1);
                }
                if ((dexVariables2_ & 2) == 2) {
                    borrowTokens_ = _buildTokenArray(cv_.token0, cv_.token1);
                }
            } catch {
                revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
            }
        } catch {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
    }

    /// @dev Builds a one-token or two-token array from the provided token addresses.
    /// @param token0_ first token address, always included.
    /// @param token1_ optional second token address, included when non-zero.
    /// @return tokens_ resulting token array.
    function _buildTokenArray(address token0_, address token1_) internal pure returns (address[] memory tokens_) {
        if (token1_ != address(0)) {
            tokens_ = new address[](2);
            tokens_[0] = token0_;
            tokens_[1] = token1_;
        } else {
            tokens_ = new address[](1);
            tokens_[0] = token0_;
        }
    }
}
