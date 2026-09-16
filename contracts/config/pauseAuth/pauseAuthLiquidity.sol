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
//   - pauseVault / unpauseVault (by vault ID) — resolves tokens, calls LL pauseUser/unpauseUser.
//     DEX-backed sides are excluded (handled by FluidPauseAuthDex).
//   - pauseDex / unpauseDex (by DEX ID) — resolves tokens, calls LL pauseUser/unpauseUser.
//   - pauseTokens / unpauseTokens — sets/clears bit 255 on exchangePricesAndConfig at LL.
//     Pre-reads LL state to skip tokens already in the desired pause state.
//   - pauseUser / unpauseUser — pass-through to LL.
//
// BEHAVIOR:
//   - Does NOT emit operational events. Returns structured data so FluidPauseAuth can emit unified events.
//   - Skips class 1 users (established protocols) for pause operations.
//   - Pre-reads LL state to filter already-paused/unpaused tokens and user sides.
//
// DEPLOYMENT:
//   - Must be set as **guardian** on Fluid Liquidity.
//   - FluidPauseAuth address set post-deployment via setPauseAuthContract (locked once set).
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
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

abstract contract Events {
    event LogSetPauseAuthContract(address indexed pauseAuthContract);
}

abstract contract Constants {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;

    /// @notice Team multisig allowed to trigger admin methods.
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

abstract contract Variables is Constants {
    /// @notice FluidPauseAuth main contract. Set once by multisig, then permanently locked.
    address public pauseAuthContract;
}

/// @title   FluidPauseAuthLiquidity
/// @notice  Executes pause/unpause operations at the Fluid Liquidity layer. Callable only by the main FluidPauseAuth
///          contract. Does NOT emit operational events — the main contract handles all event emission based on return values.
contract FluidPauseAuthLiquidity is Variables, Events, Error {
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _;
    }

    modifier onlyPauseAuthContract() {
        if (msg.sender != pauseAuthContract) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    constructor(
        address liquidity_,
        address vaultFactory_,
        address dexFactory_
    ) validAddress(liquidity_) validAddress(vaultFactory_) validAddress(dexFactory_) {
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
    }

    /// @notice Sets the FluidPauseAuth main contract address. Can only be called once (permanently locked after).
    function setPauseAuthContract(address pauseAuth_) external validAddress(pauseAuth_) {
        if (msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        if (pauseAuthContract != address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuthContract = pauseAuth_;
        emit LogSetPauseAuthContract(pauseAuth_);
    }

    // ==================== Public methods ====================

    /// @notice Pauses a vault at the Liquidity layer. Returns event data (bools for supply/borrow + skip flags).
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupplyWithdraw_,
        bool pauseBorrowPayback_
    )
        external
        onlyPauseAuthContract
        returns (
            address vault_,
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        if (!pauseSupplyWithdraw_ && !pauseBorrowPayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (actedSupply_, actedBorrow_, skippedUserClass1_, supplyAlreadySet_, borrowAlreadySet_) = _setVaultPauseState(
            vault_,
            pauseSupplyWithdraw_,
            pauseBorrowPayback_,
            true
        );
    }

    /// @notice Unpauses a vault at the Liquidity layer. Returns event data.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupplyWithdraw_,
        bool unpauseBorrowPayback_
    )
        external
        onlyPauseAuthContract
        returns (
            address vault_,
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        if (!unpauseSupplyWithdraw_ && !unpauseBorrowPayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (actedSupply_, actedBorrow_, skippedUserClass1_, supplyAlreadySet_, borrowAlreadySet_) = _setVaultPauseState(
            vault_,
            unpauseSupplyWithdraw_,
            unpauseBorrowPayback_,
            false
        );
    }

    /// @notice Pauses a DEX at the Liquidity layer. Returns event data (bools for supply/borrow + skip flags).
    function pauseDex(
        uint256 dexId_,
        bool pauseSupplyWithdraw_,
        bool pauseBorrowPayback_
    )
        external
        onlyPauseAuthContract
        returns (
            address dex_,
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        if (!pauseSupplyWithdraw_ && !pauseBorrowPayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        dex_ = DEX_FACTORY.getDexAddress(dexId_);
        if (dex_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (actedSupply_, actedBorrow_, skippedUserClass1_, supplyAlreadySet_, borrowAlreadySet_) = _setDexPauseState(
            dex_,
            pauseSupplyWithdraw_,
            pauseBorrowPayback_,
            true
        );
    }

    /// @notice Unpauses a DEX at the Liquidity layer. Returns event data.
    function unpauseDex(
        uint256 dexId_,
        bool unpauseSupplyWithdraw_,
        bool unpauseBorrowPayback_
    )
        external
        onlyPauseAuthContract
        returns (
            address dex_,
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        if (!unpauseSupplyWithdraw_ && !unpauseBorrowPayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        dex_ = DEX_FACTORY.getDexAddress(dexId_);
        if (dex_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        (actedSupply_, actedBorrow_, skippedUserClass1_, supplyAlreadySet_, borrowAlreadySet_) = _setDexPauseState(
            dex_,
            unpauseSupplyWithdraw_,
            unpauseBorrowPayback_,
            false
        );
    }

    /// @notice Pauses tokens at the Liquidity layer. Returns (paused tokens, skipped tokens).
    function pauseTokens(
        address[] calldata tokens_
    ) external onlyPauseAuthContract returns (address[] memory filteredTokens_, address[] memory skippedTokens_) {
        (filteredTokens_, skippedTokens_) = _filterTokens(tokens_, true);
        if (filteredTokens_.length > 0) {
            LIQUIDITY.pauseTokens(filteredTokens_);
        }
    }

    /// @notice Unpauses tokens at the Liquidity layer. Returns (unpaused tokens, skipped tokens).
    function unpauseTokens(
        address[] calldata tokens_
    ) external onlyPauseAuthContract returns (address[] memory filteredTokens_, address[] memory skippedTokens_) {
        (filteredTokens_, skippedTokens_) = _filterTokens(tokens_, false);
        if (filteredTokens_.length > 0) {
            LIQUIDITY.unpauseTokens(filteredTokens_);
        }
    }

    /// @notice Pauses a user at the Liquidity layer (pass-through).
    function pauseUser(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) external onlyPauseAuthContract {
        LIQUIDITY.pauseUser(user_, supplyTokens_, borrowTokens_);
    }

    /// @notice Unpauses a user at the Liquidity layer (pass-through).
    function unpauseUser(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) external onlyPauseAuthContract {
        LIQUIDITY.unpauseUser(user_, supplyTokens_, borrowTokens_);
    }

    // ==================== Internal: vault pause logic ====================

    /// @dev Shared vault pause/unpause logic. `wantsPaused_` == true → pause, false → unpause.
    ///      Resolves vault tokens, filters by LL pause state, skips class 1 users on pause.
    ///      Returns booleans indicating what was acted on and what was skipped.
    function _setVaultPauseState(
        address vault_,
        bool supply_,
        bool borrow_,
        bool wantsPaused_
    )
        internal
        returns (
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        address[] memory supplyTokens_;
        address[] memory borrowTokens_;

        {
            bool supplyIsDex_;
            bool borrowIsDex_;
            (supplyTokens_, borrowTokens_, supplyIsDex_, borrowIsDex_) = _getVaultTokens(vault_);
            supplyAlreadySet_ = supply_ && !supplyIsDex_ && supplyTokens_.length > 0;
            borrowAlreadySet_ = borrow_ && !borrowIsDex_ && borrowTokens_.length > 0;
        }

        (supplyTokens_, borrowTokens_) = _filterTokensByUser(
            vault_,
            supplyTokens_,
            borrowTokens_,
            supply_,
            borrow_,
            !wantsPaused_
        );

        if (supplyTokens_.length > 0 || borrowTokens_.length > 0) {
            if (wantsPaused_) {
                if (_isUserClass1(vault_)) {
                    skippedUserClass1_ = true;
                } else {
                    LIQUIDITY.pauseUser(vault_, supplyTokens_, borrowTokens_);
                    actedSupply_ = supplyTokens_.length > 0;
                    actedBorrow_ = borrowTokens_.length > 0;
                }
            } else {
                LIQUIDITY.unpauseUser(vault_, supplyTokens_, borrowTokens_);
                actedSupply_ = supplyTokens_.length > 0;
                actedBorrow_ = borrowTokens_.length > 0;
            }
        }

        supplyAlreadySet_ = supplyAlreadySet_ && !actedSupply_ && !skippedUserClass1_;
        borrowAlreadySet_ = borrowAlreadySet_ && !actedBorrow_ && !skippedUserClass1_;
    }

    // ==================== Internal: DEX pause logic ====================

    /// @dev Shared DEX pause/unpause logic at the Liquidity layer. `wantsPaused_` == true → pause, false → unpause.
    ///      Resolves DEX tokens, filters by LL pause state, skips class 1 users on pause.
    function _setDexPauseState(
        address dex_,
        bool supply_,
        bool borrow_,
        bool wantsPaused_
    )
        internal
        returns (
            bool actedSupply_,
            bool actedBorrow_,
            bool skippedUserClass1_,
            bool supplyAlreadySet_,
            bool borrowAlreadySet_
        )
    {
        (address[] memory supplyTokens_, address[] memory borrowTokens_) = _getDexTokens(dex_);

        supplyAlreadySet_ = supply_ && supplyTokens_.length > 0;
        borrowAlreadySet_ = borrow_ && borrowTokens_.length > 0;

        (supplyTokens_, borrowTokens_) = _filterTokensByUser(
            dex_,
            supplyTokens_,
            borrowTokens_,
            supply_,
            borrow_,
            !wantsPaused_
        );

        if (supplyTokens_.length > 0 || borrowTokens_.length > 0) {
            if (wantsPaused_) {
                if (_isUserClass1(dex_)) {
                    skippedUserClass1_ = true;
                } else {
                    LIQUIDITY.pauseUser(dex_, supplyTokens_, borrowTokens_);
                    actedSupply_ = supplyTokens_.length > 0;
                    actedBorrow_ = borrowTokens_.length > 0;
                }
            } else {
                LIQUIDITY.unpauseUser(dex_, supplyTokens_, borrowTokens_);
                actedSupply_ = supplyTokens_.length > 0;
                actedBorrow_ = borrowTokens_.length > 0;
            }
        }

        supplyAlreadySet_ = supplyAlreadySet_ && !actedSupply_ && !skippedUserClass1_;
        borrowAlreadySet_ = borrowAlreadySet_ && !actedBorrow_ && !skippedUserClass1_;
    }

    // ==================== Internal helpers ====================

    /// @dev Returns whether `vault_` is a T1 vault. Falls back to true on revert (older vaults without TYPE()).
    function _isVaultT1(address vault_) internal view returns (bool) {
        try IFluidVault(vault_).TYPE() returns (uint256 type_) {
            return type_ == FluidProtocolTypes.VAULT_T1_TYPE;
        } catch {
            return true;
        }
    }

    /// @dev Resolves a vault to its LL-facing token arrays and DEX-backed side flags. Reverts if unresolvable.
    function _getVaultTokens(
        address vault_
    )
        internal
        view
        returns (address[] memory supplyTokens_, address[] memory borrowTokens_, bool supplyIsDex_, bool borrowIsDex_)
    {
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
                } else {
                    supplyTokens_ = new address[](0);
                    supplyIsDex_ = true;
                }
                if (cv_.borrow == address(LIQUIDITY)) {
                    borrowTokens_ = _buildTokenArray(cv_.borrowToken.token0, cv_.borrowToken.token1);
                } else {
                    borrowTokens_ = new address[](0);
                    borrowIsDex_ = true;
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
                } else {
                    supplyTokens_ = new address[](0);
                }
                if ((dexVariables2_ & 2) == 2) {
                    borrowTokens_ = _buildTokenArray(cv_.token0, cv_.token1);
                } else {
                    borrowTokens_ = new address[](0);
                }
            } catch {
                revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
            }
        } catch {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
    }

    /// @dev Filters supply and borrow token arrays: zeroes out sides not requested by the include flags,
    ///      then removes tokens whose LL pause state already matches `keepPaused_`.
    ///      `keepPaused_ == false` (pause flow): keeps only defined + currently-unpaused tokens.
    ///      `keepPaused_ == true` (unpause flow): keeps only defined + currently-paused tokens.
    function _filterTokensByUser(
        address user_,
        address[] memory supplyTokens_,
        address[] memory borrowTokens_,
        bool includeSupply_,
        bool includeBorrow_,
        bool keepPaused_
    ) internal view returns (address[] memory, address[] memory) {
        if (includeSupply_) {
            supplyTokens_ = _filterByPauseState(
                user_,
                supplyTokens_,
                LiquiditySlotsLink.LIQUIDITY_USER_SUPPLY_DOUBLE_MAPPING_SLOT,
                keepPaused_
            );
        } else {
            supplyTokens_ = new address[](0);
        }
        if (includeBorrow_) {
            borrowTokens_ = _filterByPauseState(
                user_,
                borrowTokens_,
                LiquiditySlotsLink.LIQUIDITY_USER_BORROW_DOUBLE_MAPPING_SLOT,
                keepPaused_
            );
        } else {
            borrowTokens_ = new address[](0);
        }
        return (supplyTokens_, borrowTokens_);
    }

    /// @dev Returns only tokens where the user is defined at LL and pause state matches `keepPaused_`.
    function _filterByPauseState(
        address user_,
        address[] memory tokens_,
        uint256 mappingSlot_,
        bool keepPaused_
    ) private view returns (address[] memory filtered_) {
        uint256 length_ = tokens_.length;
        if (length_ == 0) {
            return tokens_;
        }

        uint256 count_;
        bool[] memory include_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            bytes32 slot_ = LiquiditySlotsLink.calculateDoubleMappingStorageSlot(mappingSlot_, user_, tokens_[i]);
            uint256 userData_ = LIQUIDITY.readFromStorage(slot_);
            if (userData_ != 0 && ((userData_ >> 255) & 1 == 1) == keepPaused_) {
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

    /// @dev Returns (tokens that need toggling, tokens already in desired state).
    function _filterTokens(
        address[] calldata tokens_,
        bool wantsPaused_
    ) internal view returns (address[] memory filtered_, address[] memory skipped_) {
        uint256 length_ = tokens_.length;
        uint256 filteredCount_;
        uint256 skippedCount_;
        bool[] memory includeFiltered_ = new bool[](length_);
        bool[] memory includeSkipped_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
                LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
                tokens_[i]
            );
            uint256 data_ = LIQUIDITY.readFromStorage(slot_);
            bool isPaused_ = (data_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_PAUSE_TOKEN) & 1 == 1;
            if (isPaused_ == wantsPaused_) {
                includeSkipped_[i] = true;
                skippedCount_++;
            } else {
                includeFiltered_[i] = true;
                filteredCount_++;
            }
        }

        filtered_ = new address[](filteredCount_);
        skipped_ = new address[](skippedCount_);
        uint256 fj_;
        uint256 sj_;
        for (uint256 i; i < length_; i++) {
            if (includeFiltered_[i]) {
                filtered_[fj_++] = tokens_[i];
            } else if (includeSkipped_[i]) {
                skipped_[sj_++] = tokens_[i];
            }
        }
    }

    /// @dev Returns true if `user_` is class 1 (established protocol) at Liquidity, which can't be paused by guardians.
    function _isUserClass1(address user_) internal view returns (bool) {
        bytes32 slot_ = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_USER_CLASS_MAPPING_SLOT,
            user_
        );
        return LIQUIDITY.readFromStorage(slot_) == 1;
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
