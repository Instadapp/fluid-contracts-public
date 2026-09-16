// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

// ==================== FluidPauseAuth ====================
//
// Pause / unpause vaults, DEXes, tokens, and users across both Fluid Liquidity and DEX layers.
//
// ACCESS:
//   - Team multisig: full access + admin setters (setPauseAuth, setNotPausable*, removeClass1PauseAuth)
//   - Class 1 pause auth: pause only
//   - Class 2 pause auth: pause + unpause + remove class 1
//
// CAPABILITIES:
//   - pauseVault / unpauseVault (by vault ID) — routes to PAUSE_AUTH_LIQUIDITY and PAUSE_AUTH_DEX.
//   - pauseDex / unpauseDex (by DEX ID) — routes to PAUSE_AUTH_LIQUIDITY (LL user pause)
//     and optionally PAUSE_AUTH_DEX (swap & arbitrage pause).
//   - pauseSmartLending / unpauseSmartLending — routes to PAUSE_AUTH_DEX.
//   - pauseTokens / unpauseTokens — routes to PAUSE_AUTH_LIQUIDITY.
//     Pause auths skip notPausableTokens (with event); multisig bypasses.
//   - pauseUserLiquidity / unpauseUserLiquidity — pass-through to PAUSE_AUTH_LIQUIDITY (multisig only)
//   - pauseUserDex / unpauseUserDex — routes to PAUSE_AUTH_DEX (multisig only)
//   - Batch variants: pauseVaults, unpauseVaults, pauseDexes, unpauseDexes
//
// BEHAVIOR:
//   - All vaults, DEXes & tokens pausable by default; opt-out via notPausableVaultIds / notPausableDexIds / notPausableTokens
//   - Team multisig always bypasses notPausable settings
//   - Reverts on invalid inputs (bad params, not found); vaults/DEXes revert on notPausable, tokens skip
//   - All operational events are emitted here (standalone contracts return data instead of emitting)
//
// DEPLOYMENT:
//   - PAUSE_AUTH_LIQUIDITY must be set as **guardian** on Fluid Liquidity
//   - PAUSE_AUTH_DEX must be set as **global auth** on Fluid DEX Factory
//   - Both standalone contracts must have this contract's address set via setPauseAuthContract
// =========================================================

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidDexFactory } from "../../protocols/dex/interfaces/iDexFactory.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidVaultFactoryVerifier is IFluidVaultFactory {
    function isVault(address vault_) external view returns (bool);
}

interface IFluidDexFactoryVerifier is IFluidDexFactory {
    function isDex(address dex_) external view returns (bool);
}

interface IFluidPauseAuthLiquidity {
    function pauseVault(uint256, bool, bool) external returns (address, bool, bool, bool, bool, bool);

    function unpauseVault(uint256, bool, bool) external returns (address, bool, bool, bool, bool, bool);

    function pauseDex(uint256, bool, bool) external returns (address, bool, bool, bool, bool, bool);

    function unpauseDex(uint256, bool, bool) external returns (address, bool, bool, bool, bool, bool);

    function pauseTokens(address[] calldata) external returns (address[] memory, address[] memory);

    function unpauseTokens(address[] calldata) external returns (address[] memory, address[] memory);

    function pauseUser(address, address[] calldata, address[] calldata) external;

    function unpauseUser(address, address[] calldata, address[] calldata) external;
}

interface IFluidPauseAuthDex {
    function pauseVault(uint256, bool, bool) external returns (address, bool, bool, bool, bool);

    function unpauseVault(uint256, bool, bool) external returns (address, bool, bool, bool, bool);

    function pauseSwapAndArbitrage(uint256) external returns (address, bool);

    function unpauseSwapAndArbitrage(uint256) external returns (address, bool);

    function pauseSmartLending(uint256) external returns (address, address, bool);

    function unpauseSmartLending(uint256) external returns (address, address, bool);

    function pauseUser(uint256, address, bool, bool) external returns (address);

    function unpauseUser(uint256, address, bool, bool) external returns (address);
}

abstract contract Events {
    // Vault events — unified for both LL and DEX layers
    event LogPauseVault(uint256 indexed vaultId, address vault, bool pausedSupply, bool pausedBorrow);
    event LogUnpauseVault(uint256 indexed vaultId, address vault, bool unpausedSupply, bool unpausedBorrow);
    event LogSkipVaultAlreadySet(
        uint256 indexed vaultId,
        address vault,
        bool wantsPaused,
        bool setSupplySkipped,
        bool setBorrowSkipped
    );
    event LogSkipVaultUserClass1(uint256 indexed vaultId, address vault);

    // DEX events (LL layer — pausing a DEX as a user on Liquidity)
    event LogPauseDex(uint256 indexed dexId, address dex, bool pausedSupply, bool pausedBorrow);
    event LogUnpauseDex(uint256 indexed dexId, address dex, bool unpausedSupply, bool unpausedBorrow);
    event LogSkipDexAlreadySet(
        uint256 indexed dexId,
        address dex,
        bool wantsPaused,
        bool setSupplySkipped,
        bool setBorrowSkipped
    );
    event LogSkipDexUserClass1(uint256 indexed dexId, address dex);

    // DEX swap & arbitrage events
    event LogPauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogUnpauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogSkipSwapAndArbitrageAlreadySet(uint256 indexed dexId, address dex, bool wantsPaused);

    // Smart lending events
    event LogPauseSmartLending(uint256 indexed dexId, address dex, address smartLending);
    event LogUnpauseSmartLending(uint256 indexed dexId, address dex, address smartLending);
    event LogSkipSmartLendingAlreadySet(uint256 indexed dexId, address dex, address smartLending, bool wantsPaused);

    // User events
    event LogPauseUser(address indexed user, address[] supplyTokens, address[] borrowTokens);
    event LogUnpauseUser(address indexed user, address[] supplyTokens, address[] borrowTokens);
    event LogPauseDexUser(uint256 indexed dexId, address dex, address user, bool pauseSupply, bool pauseBorrow);
    event LogUnpauseDexUser(uint256 indexed dexId, address dex, address user, bool unpauseSupply, bool unpauseBorrow);

    // Token events
    event LogPauseToken(address[] tokens);
    event LogUnpauseToken(address[] tokens);
    event LogSkipTokenAlreadySet(address indexed token, bool wantsPaused);

    // Auth & config events
    event LogSetPauseAuth(address indexed pauseAuth, uint256 authClass);
    event LogSetNotPausableVaultId(uint256 indexed vaultId, bool notPausable);
    event LogSetNotPausableDexId(uint256 indexed dexId, bool notPausable);
    event LogSetNotPausableToken(address indexed token, bool notPausable);
    event LogSkipTokenNotPausable(address indexed token);
}

abstract contract Constants {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;

    /// @notice Team multisig allowed to trigger methods.
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @notice FluidPauseAuthLiquidity contract handling Liquidity-layer pause operations.
    IFluidPauseAuthLiquidity public immutable PAUSE_AUTH_LIQUIDITY;
    /// @notice FluidPauseAuthDex contract handling DEX-layer pause operations.
    IFluidPauseAuthDex public immutable PAUSE_AUTH_DEX;
}

abstract contract Variables is Constants {
    /// @dev allowed pause auths with class: 0 = not auth, 1 = class 1 (pause only), 2 = class 2 (unpause + remove class 1)
    mapping(address => uint256) public pauseAuths;
    /// @dev vaultId => not pausable (true = vault can NOT be paused by pause auths). All vaults pausable by default.
    mapping(uint256 => bool) public notPausableVaultIds;
    /// @dev dexId => not pausable (true = dex can NOT be paused by pause auths). All dexes pausable by default.
    mapping(uint256 => bool) public notPausableDexIds;
    /// @dev token => not pausable (true = token can NOT be paused by pause auths). All tokens pausable by default.
    mapping(address => bool) public notPausableTokens;
}

/// @title   FluidPauseAuth
/// @notice  Single entry point for pause/unpause across Fluid Liquidity and DEX layers. Handles all authorization,
///          routes operations to FluidPauseAuthLiquidity and FluidPauseAuthDex, and emits all operational events.
contract FluidPauseAuth is Variables, Events, Error {
    // ==================== Modifiers ====================

    modifier validAddress(address value_) {
        if (value_ == address(0)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _;
    }

    modifier onlyMultisig() {
        if (msg.sender != TEAM_MULTISIG) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    modifier onlyPauseAuth() {
        if (msg.sender != TEAM_MULTISIG && pauseAuths[msg.sender] == 0) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    modifier onlyUnpauseAuth() {
        if (msg.sender != TEAM_MULTISIG && pauseAuths[msg.sender] != 2) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    constructor(
        address liquidity_,
        address vaultFactory_,
        address dexFactory_,
        address pauseAuthLiquidity_,
        address pauseAuthDex_
    )
        validAddress(liquidity_)
        validAddress(vaultFactory_)
        validAddress(dexFactory_)
        validAddress(pauseAuthLiquidity_)
        validAddress(pauseAuthDex_)
    {
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
        PAUSE_AUTH_LIQUIDITY = IFluidPauseAuthLiquidity(pauseAuthLiquidity_);
        PAUSE_AUTH_DEX = IFluidPauseAuthDex(pauseAuthDex_);
    }

    // ==================== Admin (team multisig only) ====================

    /// @notice Sets or removes a pause auth role.
    /// @dev Class 1 can only pause, class 2 can unpause and remove class 1 auths, and class 0 removes auth.
    /// @param pauseAuth_ address to update in the pause auth allow list.
    /// @param class_ auth class to assign: 0 = remove, 1 = pause only, 2 = pause and unpause.
    function setPauseAuth(address pauseAuth_, uint256 class_) external onlyMultisig validAddress(pauseAuth_) {
        if (class_ > 2) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuths[pauseAuth_] = class_;
        emit LogSetPauseAuth(pauseAuth_, class_);
    }

    /// @notice Sets whether a vault ID is NOT pausable by pause auths. All vaults are pausable by default.
    /// @dev Reverts if `vaultId_` does not resolve to a deployed vault from the vault factory.
    /// @param vaultId_ vault ID to configure.
    /// @param notPausable_ true = vault can NOT be paused by pause auths, false = vault CAN be paused (default).
    function setNotPausableVaultId(uint256 vaultId_, bool notPausable_) external onlyMultisig {
        address vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (!IFluidVaultFactoryVerifier(address(VAULT_FACTORY)).isVault(vault_)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        notPausableVaultIds[vaultId_] = notPausable_;
        emit LogSetNotPausableVaultId(vaultId_, notPausable_);
    }

    /// @notice Sets whether a DEX ID is NOT pausable by pause auths. All DEXes are pausable by default.
    /// @dev Reverts if `dexId_` does not resolve to a deployed DEX from the DEX factory.
    /// @param dexId_ DEX ID to configure.
    /// @param notPausable_ true = DEX can NOT be paused by pause auths, false = DEX CAN be paused (default).
    function setNotPausableDexId(uint256 dexId_, bool notPausable_) external onlyMultisig {
        address dex_ = DEX_FACTORY.getDexAddress(dexId_);
        if (!IFluidDexFactoryVerifier(address(DEX_FACTORY)).isDex(dex_)) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        notPausableDexIds[dexId_] = notPausable_;
        emit LogSetNotPausableDexId(dexId_, notPausable_);
    }

    /// @notice Sets whether a token is NOT pausable by pause auths. All tokens are pausable by default.
    /// @param token_ token address to configure.
    /// @param notPausable_ true = token can NOT be paused by pause auths, false = token CAN be paused (default).
    function setNotPausableToken(address token_, bool notPausable_) external onlyMultisig validAddress(token_) {
        notPausableTokens[token_] = notPausable_;
        emit LogSetNotPausableToken(token_, notPausable_);
    }

    // ==================== Class 2: remove class 1 ====================

    /// @notice Removes a class 1 pause auth.
    /// @dev Callable by class 2 pause auths or the team multisig. Intended for compromised class 1 auth removal.
    /// @param pauseAuth_ class 1 pause auth address to remove.
    function removeClass1PauseAuth(address pauseAuth_) external validAddress(pauseAuth_) onlyUnpauseAuth {
        if (pauseAuths[pauseAuth_] != 1) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuths[pauseAuth_] = 0;
        emit LogSetPauseAuth(pauseAuth_, 0);
    }

    // ==================== Vault pause/unpause ====================

    /// @notice Pauses a vault by vault ID at both the Liquidity and DEX layers.
    function pauseVault(uint256 vaultId_, bool pauseSupplyWithdraw_, bool pauseBorrowPayback_) public onlyPauseAuth {
        _pauseVault(vaultId_, pauseSupplyWithdraw_, pauseBorrowPayback_);
    }

    /// @notice Pauses multiple vaults at both the Liquidity and DEX layers.
    function pauseVaults(
        uint256[] calldata vaultIds_,
        bool[] calldata pauseSupplyWithdraw_,
        bool[] calldata pauseBorrowPayback_
    ) external onlyPauseAuth {
        uint256 length_ = vaultIds_.length;
        if (length_ != pauseSupplyWithdraw_.length || length_ != pauseBorrowPayback_.length) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _pauseVault(vaultIds_[i], pauseSupplyWithdraw_[i], pauseBorrowPayback_[i]);
        }
    }

    /// @notice Unpauses a vault by vault ID at both the Liquidity and DEX layers.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupplyWithdraw_,
        bool unpauseBorrowPayback_
    ) public onlyUnpauseAuth {
        _unpauseVault(vaultId_, unpauseSupplyWithdraw_, unpauseBorrowPayback_);
    }

    /// @notice Unpauses multiple vaults at both the Liquidity and DEX layers.
    function unpauseVaults(
        uint256[] calldata vaultIds_,
        bool[] calldata unpauseSupplyWithdraw_,
        bool[] calldata unpauseBorrowPayback_
    ) external onlyUnpauseAuth {
        uint256 length_ = vaultIds_.length;
        if (length_ != unpauseSupplyWithdraw_.length || length_ != unpauseBorrowPayback_.length) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _unpauseVault(vaultIds_[i], unpauseSupplyWithdraw_[i], unpauseBorrowPayback_[i]);
        }
    }

    // ==================== DEX pause/unpause ====================

    /// @notice Pauses a DEX by DEX ID. Routes supply/borrow pause to Liquidity layer and swap pause to DEX layer.
    function pauseDex(
        uint256 dexId_,
        bool pauseSupplyWithdraw_,
        bool pauseBorrowPayback_,
        bool pauseSwapAndArbitrage_
    ) public onlyPauseAuth {
        _pauseDex(dexId_, pauseSupplyWithdraw_, pauseBorrowPayback_, pauseSwapAndArbitrage_);
    }

    /// @notice Pauses multiple DEXes. Routes supply/borrow pause to Liquidity layer and swap pause to DEX layer.
    function pauseDexes(
        uint256[] calldata dexIds_,
        bool[] calldata pauseSupplyWithdraw_,
        bool[] calldata pauseBorrowPayback_,
        bool[] calldata pauseSwapAndArbitrage_
    ) external onlyPauseAuth {
        uint256 length_ = dexIds_.length;
        if (
            length_ != pauseSupplyWithdraw_.length ||
            length_ != pauseBorrowPayback_.length ||
            length_ != pauseSwapAndArbitrage_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _pauseDex(dexIds_[i], pauseSupplyWithdraw_[i], pauseBorrowPayback_[i], pauseSwapAndArbitrage_[i]);
        }
    }

    /// @notice Unpauses a DEX by DEX ID. Routes supply/borrow unpause to Liquidity layer and swap unpause to DEX layer.
    function unpauseDex(
        uint256 dexId_,
        bool unpauseSupplyWithdraw_,
        bool unpauseBorrowPayback_,
        bool unpauseSwapAndArbitrage_
    ) public onlyUnpauseAuth {
        _unpauseDex(dexId_, unpauseSupplyWithdraw_, unpauseBorrowPayback_, unpauseSwapAndArbitrage_);
    }

    /// @notice Unpauses multiple DEXes. Routes supply/borrow unpause to Liquidity layer and swap unpause to DEX layer.
    function unpauseDexes(
        uint256[] calldata dexIds_,
        bool[] calldata unpauseSupplyWithdraw_,
        bool[] calldata unpauseBorrowPayback_,
        bool[] calldata unpauseSwapAndArbitrage_
    ) external onlyUnpauseAuth {
        uint256 length_ = dexIds_.length;
        if (
            length_ != unpauseSupplyWithdraw_.length ||
            length_ != unpauseBorrowPayback_.length ||
            length_ != unpauseSwapAndArbitrage_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _unpauseDex(dexIds_[i], unpauseSupplyWithdraw_[i], unpauseBorrowPayback_[i], unpauseSwapAndArbitrage_[i]);
        }
    }

    // ==================== Smart lending ====================

    /// @notice Pauses the smart lending contract on a DEX pool. Respects notPausableDexIds.
    /// @param dexId_ DEX ID whose smart lending contract should be paused.
    function pauseSmartLending(uint256 dexId_) external onlyPauseAuth {
        if (msg.sender != TEAM_MULTISIG && notPausableDexIds[dexId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        (address dex_, address smartLending_, bool alreadySet_) = PAUSE_AUTH_DEX.pauseSmartLending(dexId_);
        if (alreadySet_) {
            emit LogSkipSmartLendingAlreadySet(dexId_, dex_, smartLending_, true);
        } else {
            emit LogPauseSmartLending(dexId_, dex_, smartLending_);
        }
    }

    /// @notice Unpauses the smart lending contract on a DEX pool. Respects notPausableDexIds.
    /// @param dexId_ DEX ID whose smart lending contract should be unpaused.
    function unpauseSmartLending(uint256 dexId_) external onlyUnpauseAuth {
        if (msg.sender != TEAM_MULTISIG && notPausableDexIds[dexId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        (address dex_, address smartLending_, bool alreadySet_) = PAUSE_AUTH_DEX.unpauseSmartLending(dexId_);
        if (alreadySet_) {
            emit LogSkipSmartLendingAlreadySet(dexId_, dex_, smartLending_, false);
        } else {
            emit LogUnpauseSmartLending(dexId_, dex_, smartLending_);
        }
    }

    // ==================== Token pause/unpause ====================

    /// @notice Pauses tokens at the Liquidity layer by setting bit 255 of exchangePricesAndConfig.
    /// @dev Team multisig can pause any token. Pause auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    ///      Tokens already paused at LL are skipped (emits LogSkipTokenAlreadySet).
    /// @param tokens_ token addresses to pause.
    function pauseTokens(address[] calldata tokens_) external onlyPauseAuth {
        address[] memory toProcess_ = msg.sender == TEAM_MULTISIG ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            (address[] memory paused_, address[] memory skipped_) = PAUSE_AUTH_LIQUIDITY.pauseTokens(toProcess_);
            _emitTokenEvents(paused_, skipped_, true);
        }
    }

    /// @notice Unpauses tokens at the Liquidity layer by clearing bit 255 of exchangePricesAndConfig.
    /// @dev Team multisig can unpause any token. Class 2 auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    ///      Tokens already unpaused at LL are skipped (emits LogSkipTokenAlreadySet).
    /// @param tokens_ token addresses to unpause.
    function unpauseTokens(address[] calldata tokens_) external onlyUnpauseAuth {
        address[] memory toProcess_ = msg.sender == TEAM_MULTISIG ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            (address[] memory unpaused_, address[] memory skipped_) = PAUSE_AUTH_LIQUIDITY.unpauseTokens(toProcess_);
            _emitTokenEvents(unpaused_, skipped_, false);
        }
    }

    // ==================== User pause/unpause: Liquidity ====================

    /// @notice Pauses a user at the Liquidity layer.
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to pause.
    /// @param supplyTokens_ supply tokens whose supply and withdraw operations should be paused.
    /// @param borrowTokens_ borrow tokens whose borrow and payback operations should be paused.
    function pauseUserLiquidity(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) external onlyMultisig {
        PAUSE_AUTH_LIQUIDITY.pauseUser(user_, supplyTokens_, borrowTokens_);
        emit LogPauseUser(user_, supplyTokens_, borrowTokens_);
    }

    /// @notice Unpauses a user at the Liquidity layer.
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to unpause.
    /// @param supplyTokens_ supply tokens whose supply and withdraw operations should be unpaused.
    /// @param borrowTokens_ borrow tokens whose borrow and payback operations should be unpaused.
    function unpauseUserLiquidity(
        address user_,
        address[] calldata supplyTokens_,
        address[] calldata borrowTokens_
    ) external onlyMultisig {
        PAUSE_AUTH_LIQUIDITY.unpauseUser(user_, supplyTokens_, borrowTokens_);
        emit LogUnpauseUser(user_, supplyTokens_, borrowTokens_);
    }

    // ==================== User pause/unpause: DEX ====================

    /// @notice Pauses a specific user on a DEX pool (supply/borrow sides).
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_DEX.
    /// @param dexId_ DEX ID where the user should be paused.
    /// @param user_ user address to pause on the DEX.
    /// @param pauseSupply_ whether to pause the user's supply side.
    /// @param pauseBorrow_ whether to pause the user's borrow side.
    function pauseUserDex(uint256 dexId_, address user_, bool pauseSupply_, bool pauseBorrow_) external onlyMultisig {
        address dex_ = PAUSE_AUTH_DEX.pauseUser(dexId_, user_, pauseSupply_, pauseBorrow_);
        emit LogPauseDexUser(dexId_, dex_, user_, pauseSupply_, pauseBorrow_);
    }

    /// @notice Unpauses a specific user on a DEX pool (supply/borrow sides).
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_DEX.
    /// @param dexId_ DEX ID where the user should be unpaused.
    /// @param user_ user address to unpause on the DEX.
    /// @param unpauseSupply_ whether to unpause the user's supply side.
    /// @param unpauseBorrow_ whether to unpause the user's borrow side.
    function unpauseUserDex(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseBorrow_
    ) external onlyMultisig {
        address dex_ = PAUSE_AUTH_DEX.unpauseUser(dexId_, user_, unpauseSupply_, unpauseBorrow_);
        emit LogUnpauseDexUser(dexId_, dex_, user_, unpauseSupply_, unpauseBorrow_);
    }

    // ==================== Internal: routing ====================

    /// @dev Pauses a vault at both LL (via PAUSE_AUTH_LIQUIDITY) and DEX (via PAUSE_AUTH_DEX) layers.
    function _pauseVault(uint256 vaultId_, bool pauseSupply_, bool pauseBorrow_) internal {
        if (!pauseSupply_ && !pauseBorrow_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        if (msg.sender != TEAM_MULTISIG && notPausableVaultIds[vaultId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }

        {
            (
                address vault_,
                bool actedSupply_,
                bool actedBorrow_,
                bool skippedClass1_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_LIQUIDITY.pauseVault(vaultId_, pauseSupply_, pauseBorrow_);
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedBorrow_,
                skippedClass1_,
                supplyAlreadySet_,
                borrowAlreadySet_,
                true
            );
        }

        {
            (
                address vault_,
                bool actedSupply_,
                bool actedBorrow_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_DEX.pauseVault(vaultId_, pauseSupply_, pauseBorrow_);
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedBorrow_,
                false,
                supplyAlreadySet_,
                borrowAlreadySet_,
                true
            );
        }
    }

    /// @dev Unpauses a vault at both LL (via PAUSE_AUTH_LIQUIDITY) and DEX (via PAUSE_AUTH_DEX) layers.
    function _unpauseVault(uint256 vaultId_, bool unpauseSupply_, bool unpauseBorrow_) internal {
        if (!unpauseSupply_ && !unpauseBorrow_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        if (msg.sender != TEAM_MULTISIG && notPausableVaultIds[vaultId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }

        {
            (
                address vault_,
                bool actedSupply_,
                bool actedBorrow_,
                bool skippedClass1_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_LIQUIDITY.unpauseVault(vaultId_, unpauseSupply_, unpauseBorrow_);
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedBorrow_,
                skippedClass1_,
                supplyAlreadySet_,
                borrowAlreadySet_,
                false
            );
        }

        {
            (
                address vault_,
                bool actedSupply_,
                bool actedBorrow_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_DEX.unpauseVault(vaultId_, unpauseSupply_, unpauseBorrow_);
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedBorrow_,
                false,
                supplyAlreadySet_,
                borrowAlreadySet_,
                false
            );
        }
    }

    /// @dev Pauses a DEX: supply/borrow at LL (via PAUSE_AUTH_LIQUIDITY), swap at DEX (via PAUSE_AUTH_DEX).
    function _pauseDex(uint256 dexId_, bool pauseSupply_, bool pauseBorrow_, bool pauseSwapAndArbitrage_) internal {
        if (!pauseSupply_ && !pauseBorrow_ && !pauseSwapAndArbitrage_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        if (msg.sender != TEAM_MULTISIG && notPausableDexIds[dexId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }

        if (pauseSupply_ || pauseBorrow_) {
            (
                address dex_,
                bool actedSupply_,
                bool actedBorrow_,
                bool skippedClass1_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_LIQUIDITY.pauseDex(dexId_, pauseSupply_, pauseBorrow_);
            _emitDexEvents(
                dexId_,
                dex_,
                actedSupply_,
                actedBorrow_,
                skippedClass1_,
                supplyAlreadySet_,
                borrowAlreadySet_,
                true
            );
        }

        if (pauseSwapAndArbitrage_) {
            (address dex_, bool alreadySet_) = PAUSE_AUTH_DEX.pauseSwapAndArbitrage(dexId_);
            if (alreadySet_) {
                emit LogSkipSwapAndArbitrageAlreadySet(dexId_, dex_, true);
            } else {
                emit LogPauseSwapAndArbitrage(dexId_, dex_);
            }
        }
    }

    /// @dev Unpauses a DEX: supply/borrow at LL (via PAUSE_AUTH_LIQUIDITY), swap at DEX (via PAUSE_AUTH_DEX).
    function _unpauseDex(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseBorrow_,
        bool unpauseSwapAndArbitrage_
    ) internal {
        if (!unpauseSupply_ && !unpauseBorrow_ && !unpauseSwapAndArbitrage_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        if (msg.sender != TEAM_MULTISIG && notPausableDexIds[dexId_]) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }

        if (unpauseSupply_ || unpauseBorrow_) {
            (
                address dex_,
                bool actedSupply_,
                bool actedBorrow_,
                bool skippedClass1_,
                bool supplyAlreadySet_,
                bool borrowAlreadySet_
            ) = PAUSE_AUTH_LIQUIDITY.unpauseDex(dexId_, unpauseSupply_, unpauseBorrow_);
            _emitDexEvents(
                dexId_,
                dex_,
                actedSupply_,
                actedBorrow_,
                skippedClass1_,
                supplyAlreadySet_,
                borrowAlreadySet_,
                false
            );
        }

        if (unpauseSwapAndArbitrage_) {
            (address dex_, bool alreadySet_) = PAUSE_AUTH_DEX.unpauseSwapAndArbitrage(dexId_);
            if (alreadySet_) {
                emit LogSkipSwapAndArbitrageAlreadySet(dexId_, dex_, false);
            } else {
                emit LogUnpauseSwapAndArbitrage(dexId_, dex_);
            }
        }
    }

    // ==================== Internal: event emission helpers ====================

    function _emitVaultEvents(
        uint256 vaultId_,
        address vault_,
        bool actedSupply_,
        bool actedBorrow_,
        bool skippedClass1_,
        bool supplyAlreadySet_,
        bool borrowAlreadySet_,
        bool wantsPaused_
    ) internal {
        if (actedSupply_ || actedBorrow_) {
            if (wantsPaused_) {
                emit LogPauseVault(vaultId_, vault_, actedSupply_, actedBorrow_);
            } else {
                emit LogUnpauseVault(vaultId_, vault_, actedSupply_, actedBorrow_);
            }
        } else if (skippedClass1_) {
            emit LogSkipVaultUserClass1(vaultId_, vault_);
        }

        if (supplyAlreadySet_ || borrowAlreadySet_) {
            emit LogSkipVaultAlreadySet(vaultId_, vault_, wantsPaused_, supplyAlreadySet_, borrowAlreadySet_);
        }
    }

    function _emitDexEvents(
        uint256 dexId_,
        address dex_,
        bool actedSupply_,
        bool actedBorrow_,
        bool skippedClass1_,
        bool supplyAlreadySet_,
        bool borrowAlreadySet_,
        bool wantsPaused_
    ) internal {
        if (actedSupply_ || actedBorrow_) {
            if (wantsPaused_) {
                emit LogPauseDex(dexId_, dex_, actedSupply_, actedBorrow_);
            } else {
                emit LogUnpauseDex(dexId_, dex_, actedSupply_, actedBorrow_);
            }
        } else if (skippedClass1_) {
            emit LogSkipDexUserClass1(dexId_, dex_);
        }

        if (supplyAlreadySet_ || borrowAlreadySet_) {
            emit LogSkipDexAlreadySet(dexId_, dex_, wantsPaused_, supplyAlreadySet_, borrowAlreadySet_);
        }
    }

    function _emitTokenEvents(
        address[] memory actionedTokens_,
        address[] memory skippedTokens_,
        bool wantsPaused_
    ) internal {
        if (actionedTokens_.length > 0) {
            if (wantsPaused_) {
                emit LogPauseToken(actionedTokens_);
            } else {
                emit LogUnpauseToken(actionedTokens_);
            }
        }

        for (uint256 i; i < skippedTokens_.length; i++) {
            emit LogSkipTokenAlreadySet(skippedTokens_[i], wantsPaused_);
        }
    }

    // ==================== Internal: token filtering ====================

    /// @dev Filters out `notPausableTokens` for non-multisig callers, emitting LogSkipTokenNotPausable for each skip.
    function _filterNotPausableTokens(address[] calldata tokens_) internal returns (address[] memory filtered_) {
        uint256 length_ = tokens_.length;
        uint256 count_;
        bool[] memory include_ = new bool[](length_);

        for (uint256 i; i < length_; i++) {
            if (notPausableTokens[tokens_[i]]) {
                emit LogSkipTokenNotPausable(tokens_[i]);
                continue;
            }
            include_[i] = true;
            count_++;
        }

        if (count_ == 0) return filtered_;

        filtered_ = new address[](count_);
        uint256 j_;
        for (uint256 i; i < length_; i++) {
            if (include_[i]) {
                filtered_[j_] = tokens_[i];
                j_++;
            }
        }
    }
}
