// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

// ==================== FluidPauseAuthDex ====================
//
// Executes pause/unpause operations at the DEX layer on behalf of FluidPauseAuth.
//
// ACCESS:
//   - Only callable by the FluidPauseAuth main contract (set once via setPauseAuthContract).
//
// CAPABILITIES:
//   - pauseSwapAndArbitrage / unpauseSwapAndArbitrage (by DEX ID) — toggles bit 255 of dexVariables2.
//   - pauseVault / unpauseVault (by vault ID) — pauses vault as user on its connected DEX operations.
//   - pauseSmartLending / unpauseSmartLending (by DEX ID) — pauses smart lending as supply-side user on DEX.
//   - pauseUser / unpauseUser — direct pass-through to DEX admin.
//
// BEHAVIOR:
//   - Emits no pause events; FluidPauseAuth emits from the returned flags. Only the borrow-limit freeze emits here.
//   - Every DEX revert propagates. This contract is a **global** auth on the DEX factory, so `DexT1__NotAnAuth`
//     means a broken deployment, not a pool to skip.
//   - User pause calls return flags from a pre-call storage read; a side already in the requested state, or a
//     user with no row on the pool, skips the admin call and reports acted-false.
//   - DEX-layer pause does not apply Liquidity user-class rules (see SPEC). Smart lending is not user-class aware.
//   - DEX T1 user pause is side-level on every pool: a whole side (supply+withdraw, borrow+payback) toggles its bit.
//   - Borrow without payback is a borrow-limit freeze: the user's borrow config is set to governance's parking
//     preset and the previous bits kept in `dexUserBorrowSnapshot`; the matching unpause restores them, or just drops
//     them if the pool no longer carries the preset. Payback and liquidations keep working.
//   - Supply or withdraw alone, or payback alone, revert `PauseAuthDex__PartialSideNotSupported`.
//
// DEPLOYMENT:
//   - Must be set as **global auth** on Fluid DEX Factory.
//   - FluidPauseAuth address set via setPauseAuthContract after deployment and before registration (locked once set).
// =============================================================

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidDexFactory } from "../../protocols/dex/interfaces/iDexFactory.sol";
import { IFluidDexT1 } from "../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidDexT1Admin } from "../../protocols/dex/interfaces/iDexT1Admin.sol";
import { Structs as AdminModuleStructs } from "../../protocols/dex/poolT1/adminModule/structs.sol";
import { IFluidVault } from "../../protocols/vault/interfaces/iVault.sol";
import { FluidProtocolTypes } from "../../libraries/fluidProtocolTypes.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { BigMathMinified } from "../../libraries/bigMathMinified.sol";
import { IFluidPauseAuthDex } from "./interfaces/iPauseAuthDex.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidDexFactoryVerifier {
    function isDex(address dex_) external view returns (bool);
}

interface IFluidSmartLendingFactory {
    function getSmartLendingAddress(uint256 dexId_) external view returns (address);
}

abstract contract Events {
    event LogSetPauseAuthContract(address indexed pauseAuthContract);

    /// @notice borrow limits frozen; `snapshot` holds the config bits restored on unpause
    event LogFreezeDexUserBorrow(address indexed dex, address indexed user, uint256 snapshot);

    /// @notice frozen borrow limits written back from `snapshot`
    event LogRestoreDexUserBorrow(address indexed dex, address indexed user, uint256 snapshot);
}

abstract contract Constants is FluidAuthLevels {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;
    IFluidSmartLendingFactory public immutable SMART_LENDING_FACTORY;

    /// @notice identity registry gating `setPauseAuthContract`.
    IFluidAuthGate public immutable AUTH_GATE;

    uint256 internal constant X14 = 0x3fff;
    uint256 internal constant X18 = 0x3ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant DEFAULT_EXPONENT_SIZE = 8;
    uint256 internal constant DEFAULT_EXPONENT_MASK = 0xFF;

    /// @dev bits 162-235 of the user borrow word: the config `updateUserBorrowConfigs` rewrites
    uint256 internal constant USER_BORROW_CONFIG_MASK = ((1 << 74) - 1) << DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT;

    /// @dev governance's parking preset (see inst-governance `setBorrowProtocolLimitsPausedDex`); the dust max caps
    ///      the limit outright, expansion and base are backups
    uint256 internal constant FREEZE_EXPAND_PERCENT = 1;
    uint256 internal constant FREEZE_EXPAND_DURATION = X24;
    uint256 internal constant FREEZE_BASE_DEBT_CEILING = 10;
    uint256 internal constant FREEZE_MAX_DEBT_CEILING = 20;

    /// @dev the preset as the pool stores it; 10 and 20 fit a BigNumber coefficient, so they encode as value << exponent bits
    uint256 internal constant FREEZE_CONFIG_BITS =
        (FREEZE_EXPAND_PERCENT << DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) |
            (FREEZE_EXPAND_DURATION << DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) |
            ((FREEZE_BASE_DEBT_CEILING << DEFAULT_EXPONENT_SIZE) << DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) |
            ((FREEZE_MAX_DEBT_CEILING << DEFAULT_EXPONENT_SIZE) << DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT);
}

abstract contract Variables is Constants {
    /// @notice FluidPauseAuth main contract. Set once by the MID tier, then permanently locked.
    address public pauseAuthContract;

    /// @notice borrow config bits saved by a freeze; cleared by the next borrow unpause
    mapping(address => mapping(address => uint256)) public dexUserBorrowSnapshot;
}

/// @title   FluidPauseAuthDex
/// @notice  Executes pause/unpause operations at the DEX layer. Callable only by the main FluidPauseAuth contract.
///          Emits only the borrow-limit freeze / restore events; the main contract emits the rest from return values.
contract FluidPauseAuthDex is Variables, Events, Error, BasicValidations, IFluidPauseAuthDex {
    modifier onlyPauseAuthContract() {
        if (msg.sender != pauseAuthContract) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__Unauthorized);
        }
        _;
    }

    constructor(
        address liquidity_,
        address vaultFactory_,
        address dexFactory_,
        address smartLendingFactory_,
        address authGate_
    )
        validAddress(liquidity_)
        validAddress(vaultFactory_)
        validAddress(dexFactory_)
        validAddress(smartLendingFactory_)
        validAddress(authGate_)
    {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() != liquidity_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
        SMART_LENDING_FACTORY = IFluidSmartLendingFactory(smartLendingFactory_);
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    /// @notice Sets the FluidPauseAuth main contract address. Can only be called once (permanently locked after).
    function setPauseAuthContract(address pauseAuth_) external validAddress(pauseAuth_) {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        if (pauseAuthContract != address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        pauseAuthContract = pauseAuth_;
        emit LogSetPauseAuthContract(pauseAuth_);
    }

    /// @notice Whether `user_`'s borrow limits on `dex_` are frozen by this contract: a snapshot is held and the pool
    ///         carries the preset. The preset alone means governance parked the user; nothing is restored then.
    ///         False if the config changed under a held snapshot; the next unpause then only drops it.
    function isDexUserBorrowFrozen(address dex_, address user_) external view returns (bool) {
        return dexUserBorrowSnapshot[dex_][user_] != 0 && _isFreezeConfig(_dexUserBorrowData(dex_, user_));
    }

    // ==================== Public methods ====================

    /// @inheritdoc IFluidPauseAuthDex
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
        returns (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_)
    {
        return _setVaultPauseState(vaultId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_, true);
    }

    /// @inheritdoc IFluidPauseAuthDex
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
        returns (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_)
    {
        return _setVaultPauseState(vaultId_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_, false);
    }

    /// @inheritdoc IFluidPauseAuthDex
    function pauseSwapAndArbitrage(
        uint256 dexId_
    ) external override onlyPauseAuthContract returns (address dex_, bool acted_) {
        return _setSwapPauseState(dexId_, true);
    }

    /// @inheritdoc IFluidPauseAuthDex
    function unpauseSwapAndArbitrage(
        uint256 dexId_
    ) external override onlyPauseAuthContract returns (address dex_, bool acted_) {
        return _setSwapPauseState(dexId_, false);
    }

    /// @inheritdoc IFluidPauseAuthDex
    function pauseSmartLending(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_
    )
        external
        override
        onlyPauseAuthContract
        returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_)
    {
        return _setSmartLendingPauseState(dexId_, pauseSupply_, pauseWithdraw_, true);
    }

    /// @inheritdoc IFluidPauseAuthDex
    function unpauseSmartLending(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    )
        external
        override
        onlyPauseAuthContract
        returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_)
    {
        return _setSmartLendingPauseState(dexId_, unpauseSupply_, unpauseWithdraw_, false);
    }

    /// @inheritdoc IFluidPauseAuthDex
    function pauseUser(
        uint256 dexId_,
        address user_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_)
    {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        dex_ = _getDexAddress(dexId_);
        _revertIfNoDexUserRow(dex_, user_, pauseSupply_ && pauseWithdraw_, pauseBorrow_);
        (actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_) = _setDexUserPauseState(
            dex_,
            user_,
            pauseSupply_,
            pauseWithdraw_,
            pauseBorrow_,
            pausePayback_,
            true
        );
    }

    /// @inheritdoc IFluidPauseAuthDex
    function unpauseUser(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    )
        external
        override
        onlyPauseAuthContract
        returns (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_)
    {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        dex_ = _getDexAddress(dexId_);
        _revertIfNoDexUserRow(dex_, user_, unpauseSupply_ && unpauseWithdraw_, unpauseBorrow_);
        (actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_) = _setDexUserPauseState(
            dex_,
            user_,
            unpauseSupply_,
            unpauseWithdraw_,
            unpauseBorrow_,
            unpausePayback_,
            false
        );
    }

    // ==================== Internal: shared state logic ====================

    /// @dev Shared swap & arbitrage pause/unpause logic. `wantsPaused_` == true → pause, false → unpause.
    function _setSwapPauseState(uint256 dexId_, bool wantsPaused_) internal returns (address dex_, bool acted_) {
        dex_ = _getDexAddress(dexId_);
        bool currentlyPaused_ = (IFluidDexT1(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT)) >> 255) ==
            1;
        if (currentlyPaused_ == wantsPaused_) {
            return (dex_, false);
        }

        if (wantsPaused_) {
            IFluidDexT1Admin(dex_).pauseSwapAndArbitrage();
        } else {
            IFluidDexT1Admin(dex_).unpauseSwapAndArbitrage();
        }
        acted_ = true;
    }

    /// @dev Shared vault pause/unpause logic at DEX layer. `wantsPaused_` == true → pause, false → unpause.
    function _setVaultPauseState(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool wantsPaused_
    ) internal returns (address vault_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        (address supplyDex_, address borrowDex_) = _getVaultDexes(vault_);

        if ((pauseSupply_ || pauseWithdraw_) && _isDexPausable(supplyDex_)) {
            (actedSupply_, actedWithdraw_, , ) = _setDexUserPauseState(
                supplyDex_,
                vault_,
                pauseSupply_,
                pauseWithdraw_,
                false,
                false,
                wantsPaused_
            );
        }
        if ((pauseBorrow_ || pausePayback_) && _isDexPausable(borrowDex_)) {
            (, , actedBorrow_, actedPayback_) = _setDexUserPauseState(
                borrowDex_,
                vault_,
                false,
                false,
                pauseBorrow_,
                pausePayback_,
                wantsPaused_
            );
        }
    }

    /// @dev whole sides toggle the pause bit; borrow without payback freezes limits; other half sides revert
    function _setDexUserPauseState(
        address dex_,
        address user_,
        bool actSupply_,
        bool actWithdraw_,
        bool actBorrow_,
        bool actPayback_,
        bool wantsPaused_
    ) internal returns (bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) {
        if (actSupply_ != actWithdraw_ || (actPayback_ && !actBorrow_)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__PartialSideNotSupported);
        }
        if (!actSupply_ && !actBorrow_) {
            return (false, false, false, false);
        }

        if (actSupply_) {
            actedSupply_ = _dexUserSideChanges(dex_, user_, false, wantsPaused_);
            actedWithdraw_ = actedSupply_;
        }
        if (actPayback_) {
            // payback never comes alone, so this gates on the whole side
            actedBorrow_ = _dexUserSideChanges(dex_, user_, true, wantsPaused_);
            actedPayback_ = actedBorrow_;
        }

        // actedBorrow_ is only set for a whole-side request, so borrow-only never reaches the pause bit
        if (actedSupply_ || actedBorrow_) {
            if (wantsPaused_) {
                IFluidDexT1Admin(dex_).pauseUser(user_, actedSupply_, actedBorrow_);
            } else {
                IFluidDexT1Admin(dex_).unpauseUser(user_, actedSupply_, actedBorrow_);
            }
        }

        if (actBorrow_) {
            if (wantsPaused_ && !actPayback_) {
                // the bit was never touched, so the freeze alone decides whether anything changed
                actedBorrow_ = _freezeDexUserBorrow(dex_, user_);
            } else if (!wantsPaused_) {
                // borrow-only and whole side alike restore, so limits never stay frozen behind an open pause bit
                // keep after the unpause above: restoring first re-opens the side, then `unpauseUser` reverts
                actedBorrow_ = _restoreDexUserBorrow(dex_, user_) || actedBorrow_;
            }
        }
    }

    /// @dev no-op for a missing row, a paused side (already stronger) and a leg already carrying the preset
    function _freezeDexUserBorrow(address dex_, address user_) internal returns (bool) {
        uint256 userData_ = _dexUserBorrowData(dex_, user_);
        if (userData_ == 0 || userData_ & 1 == 0 || _isFreezeConfig(userData_)) {
            return false;
        }

        AdminModuleStructs.UserBorrowConfig[] memory configs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        configs_[0] = AdminModuleStructs.UserBorrowConfig(
            user_,
            FREEZE_EXPAND_PERCENT,
            FREEZE_EXPAND_DURATION,
            FREEZE_BASE_DEBT_CEILING,
            FREEZE_MAX_DEBT_CEILING
        );
        IFluidDexT1Admin(dex_).updateUserBorrowConfigs(configs_);

        uint256 snapshot_ = userData_ & USER_BORROW_CONFIG_MASK;
        dexUserBorrowSnapshot[dex_][user_] = snapshot_;
        emit LogFreezeDexUserBorrow(dex_, user_, snapshot_);
        return true;
    }

    /// @dev a pool off the preset was re-configured behind the freeze by another auth; that newer config wins
    function _restoreDexUserBorrow(address dex_, address user_) internal returns (bool) {
        uint256 snapshot_ = dexUserBorrowSnapshot[dex_][user_];
        if (snapshot_ == 0) {
            return false;
        }

        uint256 userData_ = _dexUserBorrowData(dex_, user_);
        if (!_isFreezeConfig(userData_)) {
            delete dexUserBorrowSnapshot[dex_][user_];
            return false;
        }

        // snapshot values are BigNumber-rounded already, so re-encoding them on the pool is lossless
        AdminModuleStructs.UserBorrowConfig[] memory configs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        configs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: user_,
            expandPercent: (snapshot_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_PERCENT) & X14,
            expandDuration: (snapshot_ >> DexSlotsLink.BITS_USER_BORROW_EXPAND_DURATION) & X24,
            baseDebtCeiling: BigMathMinified.fromBigNumber(
                (snapshot_ >> DexSlotsLink.BITS_USER_BORROW_BASE_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            ),
            maxDebtCeiling: BigMathMinified.fromBigNumber(
                (snapshot_ >> DexSlotsLink.BITS_USER_BORROW_MAX_BORROW_LIMIT) & X18,
                DEFAULT_EXPONENT_SIZE,
                DEFAULT_EXPONENT_MASK
            )
        });
        IFluidDexT1Admin(dex_).updateUserBorrowConfigs(configs_);

        if (userData_ & 1 == 0) {
            // config write re-enabled the side; a failed re-pause must revert rather than leave it open
            IFluidDexT1Admin(dex_).pauseUser(user_, false, true);
        }

        delete dexUserBorrowSnapshot[dex_][user_];
        emit LogRestoreDexUserBorrow(dex_, user_, snapshot_);
        return true;
    }

    /// @dev the pass-throughs name an exact pair, so like Liquidity's they revert for a side with no row
    function _revertIfNoDexUserRow(address dex_, address user_, bool supplySide_, bool borrowSide_) internal view {
        if (
            (supplySide_ &&
                IFluidDexT1(dex_).readFromStorage(
                    DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, user_)
                ) ==
                0) || (borrowSide_ && _dexUserBorrowData(dex_, user_) == 0)
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
    }

    function _dexUserBorrowData(address dex_, address user_) internal view returns (uint256) {
        return
            IFluidDexT1(dex_).readFromStorage(
                DexSlotsLink.calculateMappingStorageSlot(DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT, user_)
            );
    }

    function _isFreezeConfig(uint256 userBorrowData_) internal pure returns (bool) {
        return userBorrowData_ & USER_BORROW_CONFIG_MASK == FREEZE_CONFIG_BITS;
    }

    /// @dev Whether the whole `isBorrow_` side of `user_` on `dex_` would change state. False for an
    ///      undefined user, whose side cannot be toggled.
    function _dexUserSideChanges(
        address dex_,
        address user_,
        bool isBorrow_,
        bool wantsPaused_
    ) internal view returns (bool) {
        uint256 userData_ = IFluidDexT1(dex_).readFromStorage(
            DexSlotsLink.calculateMappingStorageSlot(
                isBorrow_ ? DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT : DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT,
                user_
            )
        );
        if (userData_ == 0) {
            return false;
        }

        // bit 0 = side's primary action state (0 = whole side paused); both operations share it
        bool sidePaused_ = userData_ & 1 == 0;
        bool sideChanges_ = sidePaused_ != wantsPaused_;
        return sideChanges_;
    }

    /// @dev Shared smart lending pause/unpause logic. `wantsPaused_` == true → pause, false → unpause.
    function _setSmartLendingPauseState(
        uint256 dexId_,
        bool actSupply_,
        bool actWithdraw_,
        bool wantsPaused_
    ) internal returns (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) {
        if (!actSupply_ && !actWithdraw_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        dex_ = _getDexAddress(dexId_);

        smartLending_ = SMART_LENDING_FACTORY.getSmartLendingAddress(dexId_);
        if (smartLending_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        (actedSupply_, actedWithdraw_, , ) = _setDexUserPauseState(
            dex_,
            smartLending_,
            actSupply_,
            actWithdraw_,
            false,
            false,
            wantsPaused_
        );
    }

    // ==================== Internal: DEX helpers ====================

    /// @dev Reverts only for id 0; an undeployed id resolves to a codeless address that reverts on first call.
    function _getDexAddress(uint256 dexId_) internal view returns (address dex_) {
        dex_ = DEX_FACTORY.getDexAddress(dexId_);
        if (dex_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
    }

    /// @dev Returns whether a DEX address is a deployed DEX that can be interacted with.
    function _isDexPausable(address dex_) internal view returns (bool) {
        if (dex_ == address(0)) {
            return false;
        }
        try IFluidDexFactoryVerifier(address(DEX_FACTORY)).isDex(dex_) returns (bool isDex_) {
            return isDex_;
        } catch {
            return false;
        }
    }

    /// @dev Returns whether `vault_` is a T1 vault. Falls back to true on revert (older vaults without TYPE()).
    function _isVaultT1(address vault_) internal view returns (bool) {
        try IFluidVault(vault_).TYPE() returns (uint256 type_) {
            return type_ == FluidProtocolTypes.VAULT_T1_TYPE;
        } catch {
            return true;
        }
    }

    /// @dev Resolves a vault to its connected supply-side and borrow-side DEX addresses. Reverts if unresolvable.
    ///      Returns `address(0)` for sides that go through Liquidity instead of a DEX.
    ///      T1 vaults always use Liquidity directly, so both returned values are `address(0)`.
    function _getVaultDexes(address vault_) internal view returns (address supplyDex_, address borrowDex_) {
        if (_isVaultT1(vault_)) {
            return (address(0), address(0));
        }

        try IFluidVault(vault_).constantsView() returns (IFluidVault.ConstantViews memory cv_) {
            if (cv_.supply != address(LIQUIDITY)) {
                supplyDex_ = cv_.supply;
            }
            if (cv_.borrow != address(LIQUIDITY)) {
                borrowDex_ = cv_.borrow;
            }
        } catch {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
    }
}
