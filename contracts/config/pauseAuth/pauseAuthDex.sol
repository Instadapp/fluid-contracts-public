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
//   - pauseVault / unpauseVault (by vault ID) — pauses vault as user on its connected DEX supply/borrow sides.
//   - pauseSmartLending / unpauseSmartLending (by DEX ID) — pauses smart lending as supply-side user on DEX.
//   - pauseUser / unpauseUser — direct pass-through to DEX admin.
//
// BEHAVIOR:
//   - Does NOT emit operational events. Returns structured data so FluidPauseAuth can emit unified events.
//   - Pre-reads DEX storage (dexVariables2, userSupplyData, userBorrowData) to skip already-in-state ops.
//
// DEPLOYMENT:
//   - Must be set as **global auth** (or per-dex auth) on Fluid DEX Factory.
//   - FluidPauseAuth address set post-deployment via setPauseAuthContract (locked once set).
// =============================================================

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidDexFactory } from "../../protocols/dex/interfaces/iDexFactory.sol";
import { IFluidVault } from "../../protocols/vault/interfaces/iVault.sol";
import { FluidProtocolTypes } from "../../libraries/fluidProtocolTypes.sol";
import { DexSlotsLink } from "../../libraries/dexSlotsLink.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidDexFactoryVerifier {
    function isDex(address dex_) external view returns (bool);
}

interface IFluidDexT1Admin {
    function pauseSwapAndArbitrage() external;

    function unpauseSwapAndArbitrage() external;

    function pauseUser(address user_, bool pauseSupply_, bool pauseBorrow_) external;

    function unpauseUser(address user_, bool unpauseSupply_, bool unpauseBorrow_) external;

    function readFromStorage(bytes32 slot_) external view returns (uint256);
}

interface IFluidSmartLendingFactory {
    function getSmartLendingAddress(uint256 dexId_) external view returns (address);
}

abstract contract Events {
    event LogSetPauseAuthContract(address indexed pauseAuthContract);
}

abstract contract Constants {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;
    IFluidSmartLendingFactory public immutable SMART_LENDING_FACTORY;

    /// @notice Team multisig allowed to trigger admin methods.
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

abstract contract Variables is Constants {
    /// @notice FluidPauseAuth main contract. Set once by multisig, then permanently locked.
    address public pauseAuthContract;
}

/// @title   FluidPauseAuthDex
/// @notice  Executes pause/unpause operations at the DEX layer. Callable only by the main FluidPauseAuth contract.
///          Does NOT emit operational events — the main contract handles all event emission based on return values.
contract FluidPauseAuthDex is Variables, Events, Error {
    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        _;
    }

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
        address smartLendingFactory_
    )
        validAddress(liquidity_)
        validAddress(vaultFactory_)
        validAddress(dexFactory_)
        validAddress(smartLendingFactory_)
    {
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
        SMART_LENDING_FACTORY = IFluidSmartLendingFactory(smartLendingFactory_);
    }

    /// @notice Sets the FluidPauseAuth main contract address. Can only be called once (permanently locked after).
    function setPauseAuthContract(address pauseAuth_) external validAddress(pauseAuth_) {
        if (msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__Unauthorized);
        }
        if (pauseAuthContract != address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        pauseAuthContract = pauseAuth_;
        emit LogSetPauseAuthContract(pauseAuth_);
    }

    // ==================== Public methods ====================

    /// @notice Pauses a vault at the DEX layer. Returns event data.
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseBorrow_
    )
        external
        onlyPauseAuthContract
        returns (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_)
    {
        return _setVaultPauseState(vaultId_, pauseSupply_, pauseBorrow_, true);
    }

    /// @notice Unpauses a vault at the DEX layer. Returns event data.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseBorrow_
    )
        external
        onlyPauseAuthContract
        returns (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_)
    {
        return _setVaultPauseState(vaultId_, unpauseSupply_, unpauseBorrow_, false);
    }

    /// @notice Pauses swap and arbitrage on a DEX pool. Returns event data.
    function pauseSwapAndArbitrage(
        uint256 dexId_
    ) external onlyPauseAuthContract returns (address dex_, bool alreadySet_) {
        return _setSwapPauseState(dexId_, true);
    }

    /// @notice Unpauses swap and arbitrage on a DEX pool. Returns event data.
    function unpauseSwapAndArbitrage(
        uint256 dexId_
    ) external onlyPauseAuthContract returns (address dex_, bool alreadySet_) {
        return _setSwapPauseState(dexId_, false);
    }

    /// @notice Pauses the smart lending contract on a DEX pool. Returns event data.
    function pauseSmartLending(
        uint256 dexId_
    ) external onlyPauseAuthContract returns (address dex_, address smartLending_, bool alreadySet_) {
        return _setSmartLendingPauseState(dexId_, true);
    }

    /// @notice Unpauses the smart lending contract on a DEX pool. Returns event data.
    function unpauseSmartLending(
        uint256 dexId_
    ) external onlyPauseAuthContract returns (address dex_, address smartLending_, bool alreadySet_) {
        return _setSmartLendingPauseState(dexId_, false);
    }

    /// @notice Pauses a specific user on a DEX pool. Returns the resolved dex address.
    function pauseUser(
        uint256 dexId_,
        address user_,
        bool pauseSupply_,
        bool pauseBorrow_
    ) external onlyPauseAuthContract returns (address dex_) {
        if (!pauseSupply_ && !pauseBorrow_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        dex_ = _getDexAddress(dexId_);
        IFluidDexT1Admin(dex_).pauseUser(user_, pauseSupply_, pauseBorrow_);
    }

    /// @notice Unpauses a specific user on a DEX pool. Returns the resolved dex address.
    function unpauseUser(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseBorrow_
    ) external onlyPauseAuthContract returns (address dex_) {
        if (!unpauseSupply_ && !unpauseBorrow_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }
        dex_ = _getDexAddress(dexId_);
        IFluidDexT1Admin(dex_).unpauseUser(user_, unpauseSupply_, unpauseBorrow_);
    }

    // ==================== Internal: shared state logic ====================

    /// @dev Shared swap & arbitrage pause/unpause logic. `wantsPaused_` == true → pause, false → unpause.
    function _setSwapPauseState(uint256 dexId_, bool wantsPaused_) internal returns (address dex_, bool alreadySet_) {
        dex_ = _getDexAddress(dexId_);

        if (_isDexSwapPaused(dex_) == wantsPaused_) {
            alreadySet_ = true;
            return (dex_, alreadySet_);
        }

        if (wantsPaused_) {
            IFluidDexT1Admin(dex_).pauseSwapAndArbitrage();
        } else {
            IFluidDexT1Admin(dex_).unpauseSwapAndArbitrage();
        }
    }

    /// @dev Shared vault pause/unpause logic at DEX layer. `wantsPaused_` == true → pause, false → unpause.
    function _setVaultPauseState(
        uint256 vaultId_,
        bool supply_,
        bool borrow_,
        bool wantsPaused_
    )
        internal
        returns (address vault_, bool actedSupply_, bool actedBorrow_, bool supplySkipped_, bool borrowSkipped_)
    {
        if (!supply_ && !borrow_) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        (address supplyDex_, address borrowDex_) = _getVaultDexes(vault_);
        if (supplyDex_ == address(0) && borrowDex_ == address(0)) {
            return (vault_, false, false, false, false);
        }

        bool supplyEligible_ = supply_ && supplyDex_ != address(0) && _isDexPausable(supplyDex_);
        bool borrowEligible_ = borrow_ && borrowDex_ != address(0) && _isDexPausable(borrowDex_);

        actedSupply_ =
            supplyEligible_ &&
            _dexUserNeedsToggle(supplyDex_, vault_, DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, wantsPaused_);
        actedBorrow_ =
            borrowEligible_ &&
            _dexUserNeedsToggle(borrowDex_, vault_, DexSlotsLink.DEX_USER_BORROW_MAPPING_SLOT, wantsPaused_);

        if (actedSupply_ || actedBorrow_) {
            if (actedSupply_ && actedBorrow_ && supplyDex_ == borrowDex_) {
                if (wantsPaused_) {
                    IFluidDexT1Admin(supplyDex_).pauseUser(vault_, true, true);
                } else {
                    IFluidDexT1Admin(supplyDex_).unpauseUser(vault_, true, true);
                }
            } else {
                if (actedSupply_) {
                    if (wantsPaused_) {
                        IFluidDexT1Admin(supplyDex_).pauseUser(vault_, true, false);
                    } else {
                        IFluidDexT1Admin(supplyDex_).unpauseUser(vault_, true, false);
                    }
                }
                if (actedBorrow_) {
                    if (wantsPaused_) {
                        IFluidDexT1Admin(borrowDex_).pauseUser(vault_, false, true);
                    } else {
                        IFluidDexT1Admin(borrowDex_).unpauseUser(vault_, false, true);
                    }
                }
            }
        }

        supplySkipped_ = supplyEligible_ && !actedSupply_;
        borrowSkipped_ = borrowEligible_ && !actedBorrow_;
    }

    /// @dev Shared smart lending pause/unpause logic. `wantsPaused_` == true → pause, false → unpause.
    function _setSmartLendingPauseState(
        uint256 dexId_,
        bool wantsPaused_
    ) internal returns (address dex_, address smartLending_, bool alreadySet_) {
        dex_ = _getDexAddress(dexId_);

        smartLending_ = SMART_LENDING_FACTORY.getSmartLendingAddress(dexId_);
        if (smartLending_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuthDex__InvalidParams);
        }

        if (!_dexUserNeedsToggle(dex_, smartLending_, DexSlotsLink.DEX_USER_SUPPLY_MAPPING_SLOT, wantsPaused_)) {
            alreadySet_ = true;
            return (dex_, smartLending_, alreadySet_);
        }

        if (wantsPaused_) {
            IFluidDexT1Admin(dex_).pauseUser(smartLending_, true, false);
        } else {
            IFluidDexT1Admin(dex_).unpauseUser(smartLending_, true, false);
        }
    }

    // ==================== Internal: DEX helpers ====================

    /// @dev Resolves DEX address from factory. Reverts if not found.
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

    /// @dev Returns whether swap & arbitrage is currently paused on a DEX.
    function _isDexSwapPaused(address dex_) internal view returns (bool) {
        // dexVariables2: Last 1 bit => 255 => Pause swap & arbitrage. 1 = paused, 0 = not paused.
        uint256 dexVariables2_ = IFluidDexT1Admin(dex_).readFromStorage(bytes32(DexSlotsLink.DEX_VARIABLES2_SLOT));
        return (dexVariables2_ >> 255) == 1;
    }

    /// @dev Checks whether a user side on a DEX needs toggling. Returns true if the user is defined
    ///      and not already in the desired state.
    function _dexUserNeedsToggle(
        address dex_,
        address user_,
        uint256 mappingSlot_,
        bool wantsPaused_
    ) internal view returns (bool) {
        bytes32 slot_ = DexSlotsLink.calculateMappingStorageSlot(mappingSlot_, user_);
        // _userSupplyData / _userBorrowData: First 1 bit => 0 => is user allowed? 0 = not allowed (paused), 1 = allowed (unpaused)
        uint256 data_ = IFluidDexT1Admin(dex_).readFromStorage(slot_);
        if (data_ == 0) {
            return false;
        }
        bool isUnpaused_ = data_ & 1 == 1;
        return wantsPaused_ ? isUnpaused_ : !isUnpaused_;
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
