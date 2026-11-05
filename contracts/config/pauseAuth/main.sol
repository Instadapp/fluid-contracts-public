// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

// ==================== FluidPauseAuth ====================
//
// Pause / unpause vaults, DEXes, tokens, and users across both Fluid Liquidity and DEX layers.
//
// ACCESS:
//   - HIGH tier at AUTH_GATE (team multisig, governance): implicit level 3, admin setters, notPausable bypass
//   - MID tier (team multisig 2): implicit level 2 (manual pause; no unpause, no admin)
//   - Level 1 pause auth (bot): pause new borrows (Liquidity pause bit, DEX borrow-limit freeze) + DEX swap/arbitrage only
//   - Level 2 pause auth: level 1 + deposit/supply, withdraw, payback + pause tokens, smart lending and OracleV2
//   - Level 3 pause auth: level 2 + unpause + remove level 1
//
// CAPABILITIES:
//   - pauseVault / unpauseVault (by vault ID) — routes to PAUSE_AUTH_LIQUIDITY and PAUSE_AUTH_DEX.
//   - pauseDex / unpauseDex (by DEX ID) — routes to PAUSE_AUTH_LIQUIDITY (LL user pause)
//     and optionally PAUSE_AUTH_DEX (swap & arbitrage pause).
//   - pauseSmartLending / unpauseSmartLending — routes to PAUSE_AUTH_DEX.
//   - pauseTokens / unpauseTokens — routes to PAUSE_AUTH_LIQUIDITY.
//     Pause auths skip notPausableTokens (with event); multisig bypasses.
//   - pauseOracleV2 / unpauseOracleV2 — routes to PAUSE_AUTH_ORACLE_V2 (OracleV2 operate pause; never liquidate).
//   - pauseUserSupplyLiquidity / pauseUserBorrowLiquidity and matching unpause methods — pass-through to
//     PAUSE_AUTH_LIQUIDITY (pause: MID tier, unpause: HIGH tier)
//   - pauseUserDex / unpauseUserDex — routes to PAUSE_AUTH_DEX (pause: MID tier, unpause: HIGH tier)
//   - Batch variants: pauseVaults, unpauseVaults, pauseDexes, unpauseDexes
//
// BEHAVIOR:
//   - Liquidity user-class skip/strip applies at PAUSE_AUTH_LIQUIDITY only; DEX-layer pause is not class-gated (see SPEC).
//   - All vaults, DEXes & tokens pausable by default; opt-out via notPausableVaultIds / notPausableDexIds / notPausableTokens
//   - The multisig tier always bypasses notPausable settings
//   - Reverts on invalid inputs (bad params, not found); vaults/DEXes revert on notPausable, tokens skip
//   - DEX user pause is side-level: a whole side toggles the pool's pause bit; borrow without payback freezes the
//     user's borrow limits instead (so level 1 works on smart-debt vaults); other half sides revert 100143.
//   - All operational events are emitted here (standalone contracts return data instead of emitting)
//
// DEPLOYMENT:
//   - PAUSE_AUTH_LIQUIDITY must be set as **guardian** on Fluid Liquidity
//   - PAUSE_AUTH_DEX must be set as **global auth** on Fluid DEX Factory
//   - PAUSE_AUTH_ORACLE_V2 must be set as **guardian** on OracleV2
//   - All three standalone contracts must have this contract's address set via setPauseAuthContract before registration
// =========================================================

import { IFluidLiquidity } from "../../liquidity/interfaces/iLiquidity.sol";
import { IFluidVaultFactory } from "../../protocols/vault/interfaces/iVaultFactory.sol";
import { IFluidDexFactory } from "../../protocols/dex/interfaces/iDexFactory.sol";
import { IFluidPauseAuthLiquidity } from "./interfaces/iPauseAuthLiquidity.sol";
import { IFluidPauseAuthDex } from "./interfaces/iPauseAuthDex.sol";
import { IFluidPauseAuthOracleV2 } from "./interfaces/iPauseAuthOracleV2.sol";
import { IFluidAuthGate, IFluidAuthGateLiquidity, FluidAuthLevels } from "../authGate/interfaces/iAuthGate.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { Error } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";

interface IFluidVaultFactoryVerifier is IFluidVaultFactory {
    function isVault(address vault_) external view returns (bool);
}

interface IFluidDexFactoryVerifier is IFluidDexFactory {
    function isDex(address dex_) external view returns (bool);
}

abstract contract Events {
    // Operational event booleans report which pause states changed after routing, pre-read filtering,
    // and Liquidity user-class adjustments; they are not raw request flags.

    // Vault events — unified for both LL and DEX layers.
    event LogPauseVault(
        uint256 indexed vaultId,
        address vault,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseVault(
        uint256 indexed vaultId,
        address vault,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogSkipVaultUserClass(uint256 indexed vaultId, address vault, uint256 userClass);

    // DEX events (LL layer — pausing a DEX as a user on Liquidity).
    event LogPauseDex(
        uint256 indexed dexId,
        address dex,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseDex(
        uint256 indexed dexId,
        address dex,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogSkipDexUserClass(uint256 indexed dexId, address dex, uint256 userClass);

    // DEX swap & arbitrage events
    event LogPauseSwapAndArbitrage(uint256 indexed dexId, address dex);
    event LogUnpauseSwapAndArbitrage(uint256 indexed dexId, address dex);

    // Smart lending events
    event LogPauseSmartLending(
        uint256 indexed dexId,
        address dex,
        address smartLending,
        bool pausedSupply,
        bool pausedWithdraw
    );
    event LogUnpauseSmartLending(
        uint256 indexed dexId,
        address dex,
        address smartLending,
        bool unpausedSupply,
        bool unpausedWithdraw
    );

    // User events (Liquidity multisig pass-through) — one log per token; unused sides are false.
    event LogPauseUser(
        address indexed user,
        address indexed token,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseUser(
        address indexed user,
        address indexed token,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );
    event LogPauseDexUser(
        uint256 indexed dexId,
        address dex,
        address user,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseDexUser(
        uint256 indexed dexId,
        address dex,
        address user,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );

    // Token events
    event LogPauseToken(
        address indexed token,
        bool pausedSupply,
        bool pausedWithdraw,
        bool pausedBorrow,
        bool pausedPayback
    );
    event LogUnpauseToken(
        address indexed token,
        bool unpausedSupply,
        bool unpausedWithdraw,
        bool unpausedBorrow,
        bool unpausedPayback
    );

    // OracleV2 events
    event LogPauseOracleV2(address indexed token);
    event LogUnpauseOracleV2(address indexed token);

    // Auth & config events
    event LogSetPauseAuth(address indexed pauseAuth, uint256 authClass);
    event LogSetNotPausableVaultId(uint256 indexed vaultId, bool notPausable);
    event LogSetNotPausableDexId(uint256 indexed dexId, bool notPausable);
    event LogSetNotPausableToken(address indexed token, bool notPausable);
    event LogSkipTokenNotPausable(address indexed token);
}

abstract contract Constants is FluidAuthLevels {
    IFluidLiquidity public immutable LIQUIDITY;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    IFluidDexFactory public immutable DEX_FACTORY;

    /// @notice identity registry resolving multisig/governance tiers.
    IFluidAuthGate public immutable AUTH_GATE;

    /// @notice FluidPauseAuthLiquidity contract handling Liquidity-layer pause operations.
    IFluidPauseAuthLiquidity public immutable PAUSE_AUTH_LIQUIDITY;
    /// @notice FluidPauseAuthDex contract handling DEX-layer pause operations.
    IFluidPauseAuthDex public immutable PAUSE_AUTH_DEX;
    /// @notice FluidPauseAuthOracleV2 contract handling the OracleV2 operate pause.
    IFluidPauseAuthOracleV2 public immutable PAUSE_AUTH_ORACLE_V2;
}

abstract contract Variables is Constants {
    /// @dev allowed pause auths with levels: 0 = not auth, 1 = pause new borrows + DEX swap/arb,
    ///      2 = level 1 + supply/withdraw/payback, tokens, smart lending, 3 = level 2 + unpause/remove level 1
    mapping(address => uint256) public pauseAuths;
    /// @dev vaultId => not pausable (true = vault can NOT be paused by pause auths). All vaults pausable by default.
    mapping(uint256 => bool) public notPausableVaultIds;
    /// @dev dexId => not pausable (true = dex can NOT be paused by pause auths). All dexes pausable by default.
    mapping(uint256 => bool) public notPausableDexIds;
    /// @dev token => not pausable (true = token can NOT be paused by pause auths). All tokens pausable by default.
    mapping(address => bool) public notPausableTokens;
}

/// @notice pause-auth level ladder and its mapping onto the auth gate tiers.
abstract contract PauseAuthLevels is Variables, Error {
    uint256 internal constant PAUSE_AUTH_LEVEL_BOT = 1;
    uint256 internal constant PAUSE_AUTH_LEVEL_MANUAL = 2;
    uint256 internal constant PAUSE_AUTH_LEVEL_UNPAUSE = 3;

    modifier onlyAuthLevelHigh() {
        AUTH_GATE.requireAuthLevelHigh(msg.sender);
        _;
    }

    modifier onlyAuthLevelMid() {
        AUTH_GATE.requireAuthLevelMid(msg.sender);
        _;
    }

    modifier onlyPauseAuth(uint256 levelRequired_) {
        if (_pauseAuthLevel(msg.sender) < levelRequired_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
        _;
    }

    function _isGateAuthHigh() internal view returns (bool) {
        return AUTH_GATE.authLevel(msg.sender) >= SECURITY_LEVEL_HIGH;
    }

    /// @dev notPausable targets revert unless the caller is HIGH-tier (multisig tier bypasses the lists).
    function _revertIfNotPausable(bool notPausable_) internal view {
        if (notPausable_ && !_isGateAuthHigh()) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
    }

    /// @dev max of the local `pauseAuths` assignment and the gate tier: MID implies MANUAL, HIGH+ UNPAUSE.
    function _pauseAuthLevel(address addr_) internal view returns (uint256 level_) {
        level_ = pauseAuths[addr_];
        if (level_ >= PAUSE_AUTH_LEVEL_UNPAUSE) {
            return level_;
        }
        uint256 gateLevel_ = AUTH_GATE.authLevel(addr_);
        if (gateLevel_ >= SECURITY_LEVEL_HIGH) {
            return PAUSE_AUTH_LEVEL_UNPAUSE;
        }
        if (gateLevel_ >= SECURITY_LEVEL_MID && level_ < PAUSE_AUTH_LEVEL_MANUAL) {
            return PAUSE_AUTH_LEVEL_MANUAL;
        }
    }
}

/// @title   FluidPauseAuth
/// @notice  Single entry point for pause/unpause across Fluid Liquidity and DEX layers. Handles all authorization,
///          routes operations to FluidPauseAuthLiquidity and FluidPauseAuthDex, and emits all operational events.
contract FluidPauseAuth is PauseAuthLevels, Events, BasicValidations {
    constructor(
        address liquidity_,
        address vaultFactory_,
        address dexFactory_,
        address pauseAuthLiquidity_,
        address pauseAuthDex_,
        address pauseAuthOracleV2_,
        address authGate_
    )
        validAddress(liquidity_)
        validAddress(vaultFactory_)
        validAddress(dexFactory_)
        validAddress(pauseAuthLiquidity_)
        validAddress(pauseAuthDex_)
        validAddress(pauseAuthOracleV2_)
        validAddress(authGate_)
    {
        if (IFluidAuthGateLiquidity(authGate_).LIQUIDITY() != liquidity_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        LIQUIDITY = IFluidLiquidity(liquidity_);
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEX_FACTORY = IFluidDexFactory(dexFactory_);
        PAUSE_AUTH_LIQUIDITY = IFluidPauseAuthLiquidity(pauseAuthLiquidity_);
        PAUSE_AUTH_DEX = IFluidPauseAuthDex(pauseAuthDex_);
        PAUSE_AUTH_ORACLE_V2 = IFluidPauseAuthOracleV2(pauseAuthOracleV2_);
        AUTH_GATE = IFluidAuthGate(authGate_);
    }

    // ==================== Admin (team multisig only) ====================

    /// @notice Sets or removes a pause auth role.
    /// @dev Level 1 can pause new borrows and DEX swap/arbitrage only,
    ///      level 2 can also pause deposit/supply, withdraw, payback, tokens, and smart lending,
    ///      level 3 can also unpause/remove level 1. Gate tiers never drop below their implied level (MID 2, HIGH 3).
    /// @param pauseAuth_ address to update in the pause auth allow list.
    /// @param class_ auth level to assign: 0 = remove, 1 = bot pause, 2 = manual pause, 3 = level 2 + unpause.
    function setPauseAuth(address pauseAuth_, uint256 class_) external onlyAuthLevelHigh validAddress(pauseAuth_) {
        if (class_ > PAUSE_AUTH_LEVEL_UNPAUSE) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuths[pauseAuth_] = class_;
        emit LogSetPauseAuth(pauseAuth_, class_);
    }

    /// @notice Sets whether a vault ID is NOT pausable by pause auths. All vaults are pausable by default.
    /// @dev Reverts if `vaultId_` does not resolve to a deployed vault from the vault factory.
    /// @param vaultId_ vault ID to configure.
    /// @param notPausable_ true = vault can NOT be paused by pause auths, false = vault CAN be paused (default).
    function setNotPausableVaultId(uint256 vaultId_, bool notPausable_) external onlyAuthLevelHigh {
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
    function setNotPausableDexId(uint256 dexId_, bool notPausable_) external onlyAuthLevelHigh {
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
    function setNotPausableToken(address token_, bool notPausable_) external onlyAuthLevelHigh validAddress(token_) {
        notPausableTokens[token_] = notPausable_;
        emit LogSetNotPausableToken(token_, notPausable_);
    }

    // ==================== Level 3: remove level 1 ====================

    /// @notice Removes a level 1 pause auth.
    /// @dev Callable by level 3 pause auths or the team multisig. Intended for compromised level 1 auth removal.
    /// @param pauseAuth_ level 1 pause auth address to remove.
    function removeClass1PauseAuth(
        address pauseAuth_
    ) external validAddress(pauseAuth_) onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        if (pauseAuths[pauseAuth_] != PAUSE_AUTH_LEVEL_BOT) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        pauseAuths[pauseAuth_] = 0;
        emit LogSetPauseAuth(pauseAuth_, 0);
    }

    // ==================== Vault pause/unpause ====================

    /// @notice Pauses all vault operations by vault ID at both the Liquidity and DEX layers.
    function pauseVault(uint256 vaultId_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_MANUAL) {
        _pauseVault(vaultId_, true, true, true, true);
    }

    /// @notice Pauses a vault by vault ID at both the Liquidity and DEX layers.
    function pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_BOT) {
        _pauseVault(vaultId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
    }

    /// @notice Pauses multiple vaults at both the Liquidity and DEX layers.
    function pauseVaults(
        uint256[] calldata vaultIds_,
        bool[] calldata pauseSupply_,
        bool[] calldata pauseWithdraw_,
        bool[] calldata pauseBorrow_,
        bool[] calldata pausePayback_
    ) external onlyPauseAuth(PAUSE_AUTH_LEVEL_BOT) {
        uint256 length_ = vaultIds_.length;
        if (
            length_ != pauseSupply_.length ||
            length_ != pauseWithdraw_.length ||
            length_ != pauseBorrow_.length ||
            length_ != pausePayback_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _pauseVault(vaultIds_[i], pauseSupply_[i], pauseWithdraw_[i], pauseBorrow_[i], pausePayback_[i]);
        }
    }

    /// @notice Unpauses a vault by vault ID at both the Liquidity and DEX layers.
    function unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        _unpauseVault(vaultId_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
    }

    /// @notice Unpauses multiple vaults at both the Liquidity and DEX layers.
    function unpauseVaults(
        uint256[] calldata vaultIds_,
        bool[] calldata unpauseSupply_,
        bool[] calldata unpauseWithdraw_,
        bool[] calldata unpauseBorrow_,
        bool[] calldata unpausePayback_
    ) external onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        uint256 length_ = vaultIds_.length;
        if (
            length_ != unpauseSupply_.length ||
            length_ != unpauseWithdraw_.length ||
            length_ != unpauseBorrow_.length ||
            length_ != unpausePayback_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _unpauseVault(vaultIds_[i], unpauseSupply_[i], unpauseWithdraw_[i], unpauseBorrow_[i], unpausePayback_[i]);
        }
    }

    // ==================== DEX pause/unpause ====================

    /// @notice Pauses all DEX operations by DEX ID.
    function pauseDex(uint256 dexId_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_MANUAL) {
        _pauseDex(dexId_, true, true, true, true, true);
    }

    /// @notice Pauses a DEX by DEX ID. Routes supply/borrow pause to Liquidity layer and swap pause to DEX layer.
    function pauseDex(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool pauseSwapAndArbitrage_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_BOT) {
        _pauseDex(dexId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_, pauseSwapAndArbitrage_);
    }

    /// @notice Pauses multiple DEXes. Routes supply/borrow pause to Liquidity layer and swap pause to DEX layer.
    function pauseDexes(
        uint256[] calldata dexIds_,
        bool[] calldata pauseSupply_,
        bool[] calldata pauseWithdraw_,
        bool[] calldata pauseBorrow_,
        bool[] calldata pausePayback_,
        bool[] calldata pauseSwapAndArbitrage_
    ) external onlyPauseAuth(PAUSE_AUTH_LEVEL_BOT) {
        uint256 length_ = dexIds_.length;
        if (
            length_ != pauseSupply_.length ||
            length_ != pauseWithdraw_.length ||
            length_ != pauseBorrow_.length ||
            length_ != pausePayback_.length ||
            length_ != pauseSwapAndArbitrage_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _pauseDex(
                dexIds_[i],
                pauseSupply_[i],
                pauseWithdraw_[i],
                pauseBorrow_[i],
                pausePayback_[i],
                pauseSwapAndArbitrage_[i]
            );
        }
    }

    /// @notice Unpauses a DEX by DEX ID. Routes supply/borrow unpause to Liquidity layer and swap unpause to DEX layer.
    function unpauseDex(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_,
        bool unpauseSwapAndArbitrage_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        _unpauseDex(
            dexId_,
            unpauseSupply_,
            unpauseWithdraw_,
            unpauseBorrow_,
            unpausePayback_,
            unpauseSwapAndArbitrage_
        );
    }

    /// @notice Unpauses multiple DEXes. Routes supply/borrow unpause to Liquidity layer and swap unpause to DEX layer.
    function unpauseDexes(
        uint256[] calldata dexIds_,
        bool[] calldata unpauseSupply_,
        bool[] calldata unpauseWithdraw_,
        bool[] calldata unpauseBorrow_,
        bool[] calldata unpausePayback_,
        bool[] calldata unpauseSwapAndArbitrage_
    ) external onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        uint256 length_ = dexIds_.length;
        if (
            length_ != unpauseSupply_.length ||
            length_ != unpauseWithdraw_.length ||
            length_ != unpauseBorrow_.length ||
            length_ != unpausePayback_.length ||
            length_ != unpauseSwapAndArbitrage_.length
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        for (uint256 i; i < length_; i++) {
            _unpauseDex(
                dexIds_[i],
                unpauseSupply_[i],
                unpauseWithdraw_[i],
                unpauseBorrow_[i],
                unpausePayback_[i],
                unpauseSwapAndArbitrage_[i]
            );
        }
    }

    // ==================== Smart lending ====================

    /// @notice Pauses a DEX pool's smart lending; both flags must be set, else 100143. Respects notPausableDexIds.
    /// @param dexId_ DEX ID whose smart lending contract should be paused.
    /// @param pauseSupply_ whether to pause smart lending supply/deposit operations.
    /// @param pauseWithdraw_ whether to pause smart lending withdraw operations.
    function pauseSmartLending(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_BOT) {
        _validatePauseFlags(pauseSupply_, pauseWithdraw_, false, false);
        _revertIfNotPausable(notPausableDexIds[dexId_]);
        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = PAUSE_AUTH_DEX
            .pauseSmartLending(dexId_, pauseSupply_, pauseWithdraw_);
        if (actedSupply_ || actedWithdraw_) {
            emit LogPauseSmartLending(dexId_, dex_, smartLending_, actedSupply_, actedWithdraw_);
        }
    }

    /// @notice Unpauses a DEX pool's smart lending; both flags must be set, else 100143. Respects notPausableDexIds.
    /// @param dexId_ DEX ID whose smart lending contract should be unpaused.
    /// @param unpauseSupply_ whether to unpause smart lending supply/deposit operations.
    /// @param unpauseWithdraw_ whether to unpause smart lending withdraw operations.
    function unpauseSmartLending(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        _revertIfNotPausable(notPausableDexIds[dexId_]);
        (address dex_, address smartLending_, bool actedSupply_, bool actedWithdraw_) = PAUSE_AUTH_DEX
            .unpauseSmartLending(dexId_, unpauseSupply_, unpauseWithdraw_);
        if (actedSupply_ || actedWithdraw_) {
            emit LogUnpauseSmartLending(dexId_, dex_, smartLending_, actedSupply_, actedWithdraw_);
        }
    }

    // ==================== Token pause/unpause ====================

    /// @notice Pauses all four token operations at the Liquidity layer (token pause bitmask, bits 252-255 of exchangePricesAndConfig).
    /// @dev Team multisig can pause any token. Level 2+ auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    /// @param tokens_ token addresses to pause.
    function pauseTokens(address[] calldata tokens_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_MANUAL) {
        pauseTokens(tokens_, true, true, true, true);
    }

    /// @notice Pauses selected token operations at the Liquidity layer.
    function pauseTokens(
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_MANUAL) {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        address[] memory toProcess_ = _isGateAuthHigh() ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            (
                bool[] memory actedSupply_,
                bool[] memory actedWithdraw_,
                bool[] memory actedBorrow_,
                bool[] memory actedPayback_
            ) = PAUSE_AUTH_LIQUIDITY.pauseTokens(toProcess_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
            uint256 length_ = toProcess_.length;
            for (uint256 i; i < length_; i++) {
                if (actedSupply_[i] || actedWithdraw_[i] || actedBorrow_[i] || actedPayback_[i]) {
                    emit LogPauseToken(
                        toProcess_[i],
                        actedSupply_[i],
                        actedWithdraw_[i],
                        actedBorrow_[i],
                        actedPayback_[i]
                    );
                }
            }
        }
    }

    /// @notice Unpauses all four token operations at the Liquidity layer (token pause bitmask, bits 252-255 of exchangePricesAndConfig).
    /// @dev Team multisig can unpause any token. Level 3 auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    /// @param tokens_ token addresses to unpause.
    function unpauseTokens(address[] calldata tokens_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        unpauseTokens(tokens_, true, true, true, true);
    }

    /// @notice Unpauses selected token operations at the Liquidity layer.
    function unpauseTokens(
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) public onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        address[] memory toProcess_ = _isGateAuthHigh() ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            (
                bool[] memory actedSupply_,
                bool[] memory actedWithdraw_,
                bool[] memory actedBorrow_,
                bool[] memory actedPayback_
            ) = PAUSE_AUTH_LIQUIDITY.unpauseTokens(
                    toProcess_,
                    unpauseSupply_,
                    unpauseWithdraw_,
                    unpauseBorrow_,
                    unpausePayback_
                );
            uint256 length_ = toProcess_.length;
            for (uint256 i; i < length_; i++) {
                if (actedSupply_[i] || actedWithdraw_[i] || actedBorrow_[i] || actedPayback_[i]) {
                    emit LogUnpauseToken(
                        toProcess_[i],
                        actedSupply_[i],
                        actedWithdraw_[i],
                        actedBorrow_[i],
                        actedPayback_[i]
                    );
                }
            }
        }
    }

    // ==================== OracleV2 operate pause/unpause ====================

    /// @notice Pauses OracleV2 operate prices of `tokens_`: borrows and withdrawals with debt stop in every vault
    ///         priced with them, liquidations keep working. Emits `LogPauseOracleV2` per token paused.
    /// @dev Team multisig can pause any token. Level 2+ auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    function pauseOracleV2(address[] calldata tokens_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_MANUAL) {
        address[] memory toProcess_ = _isGateAuthHigh() ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            _emitOracleV2Events(toProcess_, PAUSE_AUTH_ORACLE_V2.pauseOperate(toProcess_), true);
        }
    }

    /// @notice Lifts the OracleV2 operate pause of `tokens_`. Emits `LogUnpauseOracleV2` per token unpaused.
    /// @dev Team multisig can unpause any token. Level 3 auths skip `notPausableTokens` (emits LogSkipTokenNotPausable).
    function unpauseOracleV2(address[] calldata tokens_) external onlyPauseAuth(PAUSE_AUTH_LEVEL_UNPAUSE) {
        address[] memory toProcess_ = _isGateAuthHigh() ? tokens_ : _filterNotPausableTokens(tokens_);
        if (toProcess_.length > 0) {
            _emitOracleV2Events(toProcess_, PAUSE_AUTH_ORACLE_V2.unpauseOperate(toProcess_), false);
        }
    }

    // ==================== User pause/unpause: Liquidity ====================

    /// @notice Pauses a user's supply side at the Liquidity layer.
    /// @dev Restricted to the MID tier at AUTH_GATE. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to pause.
    /// @param tokens_ supply tokens whose supply and withdraw operations should be paused.
    /// @param pauseSupply_ whether to pause supply operations.
    /// @param pauseWithdraw_ whether to pause withdraw operations.
    function pauseUserSupplyLiquidity(
        address user_,
        address[] calldata tokens_,
        bool pauseSupply_,
        bool pauseWithdraw_
    ) external onlyAuthLevelMid {
        (bool[] memory actedSupply_, bool[] memory actedWithdraw_) = PAUSE_AUTH_LIQUIDITY.pauseUserSupply(
            user_,
            tokens_,
            pauseSupply_,
            pauseWithdraw_
        );
        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; i++) {
            if (actedSupply_[i] || actedWithdraw_[i]) {
                emit LogPauseUser(user_, tokens_[i], actedSupply_[i], actedWithdraw_[i], false, false);
            }
        }
    }

    /// @notice Pauses a user's borrow side at the Liquidity layer.
    /// @dev Restricted to the MID tier at AUTH_GATE. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to pause.
    /// @param tokens_ borrow tokens whose borrow and payback operations should be paused.
    /// @param pauseBorrow_ whether to pause borrow operations.
    /// @param pausePayback_ whether to pause payback operations.
    function pauseUserBorrowLiquidity(
        address user_,
        address[] calldata tokens_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external onlyAuthLevelMid {
        (bool[] memory actedBorrow_, bool[] memory actedPayback_) = PAUSE_AUTH_LIQUIDITY.pauseUserBorrow(
            user_,
            tokens_,
            pauseBorrow_,
            pausePayback_
        );
        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; i++) {
            if (actedBorrow_[i] || actedPayback_[i]) {
                emit LogPauseUser(user_, tokens_[i], false, false, actedBorrow_[i], actedPayback_[i]);
            }
        }
    }

    /// @notice Unpauses a user's supply side at the Liquidity layer.
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to unpause.
    /// @param tokens_ supply tokens whose supply and withdraw operations should be unpaused.
    /// @param unpauseSupply_ whether to unpause supply operations.
    /// @param unpauseWithdraw_ whether to unpause withdraw operations.
    function unpauseUserSupplyLiquidity(
        address user_,
        address[] calldata tokens_,
        bool unpauseSupply_,
        bool unpauseWithdraw_
    ) external onlyAuthLevelHigh {
        (bool[] memory actedSupply_, bool[] memory actedWithdraw_) = PAUSE_AUTH_LIQUIDITY.unpauseUserSupply(
            user_,
            tokens_,
            unpauseSupply_,
            unpauseWithdraw_
        );
        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; i++) {
            if (actedSupply_[i] || actedWithdraw_[i]) {
                emit LogUnpauseUser(user_, tokens_[i], actedSupply_[i], actedWithdraw_[i], false, false);
            }
        }
    }

    /// @notice Unpauses a user's borrow side at the Liquidity layer.
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_LIQUIDITY.
    /// @param user_ Liquidity user address to unpause.
    /// @param tokens_ borrow tokens whose borrow and payback operations should be unpaused.
    /// @param unpauseBorrow_ whether to unpause borrow operations.
    /// @param unpausePayback_ whether to unpause payback operations.
    function unpauseUserBorrowLiquidity(
        address user_,
        address[] calldata tokens_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external onlyAuthLevelHigh {
        (bool[] memory actedBorrow_, bool[] memory actedPayback_) = PAUSE_AUTH_LIQUIDITY.unpauseUserBorrow(
            user_,
            tokens_,
            unpauseBorrow_,
            unpausePayback_
        );
        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; i++) {
            if (actedBorrow_[i] || actedPayback_[i]) {
                emit LogUnpauseUser(user_, tokens_[i], false, false, actedBorrow_[i], actedPayback_[i]);
            }
        }
    }

    // ==================== User pause/unpause: DEX ====================

    /// @notice Pauses a specific user on a DEX pool (supply/borrow sides).
    ///         Reverts if `user_` has no row on the pool for a requested side.
    /// @dev Restricted to the MID tier at AUTH_GATE. Passes through to PAUSE_AUTH_DEX.
    /// @param dexId_ DEX ID where the user should be paused.
    /// @param user_ user address to pause on the DEX.
    /// @param pauseSupply_ whether to pause the user's supply/deposit operations.
    /// @param pauseWithdraw_ whether to pause the user's withdraw operations.
    /// @param pauseBorrow_ whether to pause the user's borrow operations.
    /// @param pausePayback_ whether to pause the user's payback operations.
    function pauseUserDex(
        uint256 dexId_,
        address user_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) external onlyAuthLevelMid {
        (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = PAUSE_AUTH_DEX
            .pauseUser(dexId_, user_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        if (actedSupply_ || actedWithdraw_ || actedBorrow_ || actedPayback_) {
            emit LogPauseDexUser(dexId_, dex_, user_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
        }
    }

    /// @notice Unpauses a specific user on a DEX pool.
    ///         Reverts if `user_` has no row on the pool for a requested side.
    /// @dev Restricted to the team multisig. Passes through to PAUSE_AUTH_DEX.
    /// @param dexId_ DEX ID where the user should be unpaused.
    /// @param user_ user address to unpause on the DEX.
    /// @param unpauseSupply_ whether to unpause the user's supply/deposit operations.
    /// @param unpauseWithdraw_ whether to unpause the user's withdraw operations.
    /// @param unpauseBorrow_ whether to unpause the user's borrow operations.
    /// @param unpausePayback_ whether to unpause the user's payback operations.
    function unpauseUserDex(
        uint256 dexId_,
        address user_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) external onlyAuthLevelHigh {
        (address dex_, bool actedSupply_, bool actedWithdraw_, bool actedBorrow_, bool actedPayback_) = PAUSE_AUTH_DEX
            .unpauseUser(dexId_, user_, unpauseSupply_, unpauseWithdraw_, unpauseBorrow_, unpausePayback_);
        if (actedSupply_ || actedWithdraw_ || actedBorrow_ || actedPayback_) {
            emit LogUnpauseDexUser(dexId_, dex_, user_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
        }
    }

    // ==================== Internal: routing ====================

    /// @dev Level 1 (bot) may only pause new borrows; deposit, withdraw, and payback require level 2+.
    function _validatePauseFlags(
        bool requestedSupply_,
        bool requestedWithdraw_,
        bool,
        bool requestedPayback_
    ) internal view {
        if (
            (requestedSupply_ || requestedWithdraw_ || requestedPayback_) &&
            _pauseAuthLevel(msg.sender) < PAUSE_AUTH_LEVEL_MANUAL
        ) {
            revert FluidConfigError(ErrorTypes.PauseAuth__Unauthorized);
        }
    }

    /// @dev Pauses a vault at both LL (via PAUSE_AUTH_LIQUIDITY) and DEX (via PAUSE_AUTH_DEX) layers.
    function _pauseVault(
        uint256 vaultId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_
    ) internal {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _revertIfNotPausable(notPausableVaultIds[vaultId_]);

        _validatePauseFlags(pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
        {
            (
                address vault_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_,
                uint256 skippedClass_
            ) = PAUSE_AUTH_LIQUIDITY.pauseVault(vaultId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedWithdraw_,
                actedBorrow_,
                actedPayback_,
                skippedClass_,
                true
            );
        }
        {
            (
                address vault_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_
            ) = PAUSE_AUTH_DEX.pauseVault(vaultId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
            _emitVaultEvents(vaultId_, vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, 0, true);
        }
    }

    /// @dev Unpauses a vault at both LL (via PAUSE_AUTH_LIQUIDITY) and DEX (via PAUSE_AUTH_DEX) layers.
    function _unpauseVault(
        uint256 vaultId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_
    ) internal {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _revertIfNotPausable(notPausableVaultIds[vaultId_]);

        {
            (
                address vault_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_,
                uint256 skippedClass_
            ) = PAUSE_AUTH_LIQUIDITY.unpauseVault(
                    vaultId_,
                    unpauseSupply_,
                    unpauseWithdraw_,
                    unpauseBorrow_,
                    unpausePayback_
                );
            _emitVaultEvents(
                vaultId_,
                vault_,
                actedSupply_,
                actedWithdraw_,
                actedBorrow_,
                actedPayback_,
                skippedClass_,
                false
            );
        }
        {
            (
                address vault_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_
            ) = PAUSE_AUTH_DEX.unpauseVault(
                    vaultId_,
                    unpauseSupply_,
                    unpauseWithdraw_,
                    unpauseBorrow_,
                    unpausePayback_
                );
            _emitVaultEvents(vaultId_, vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_, 0, false);
        }
    }

    /// @dev Pauses a DEX: supply/borrow at LL (via PAUSE_AUTH_LIQUIDITY), swap at DEX (via PAUSE_AUTH_DEX).
    function _pauseDex(
        uint256 dexId_,
        bool pauseSupply_,
        bool pauseWithdraw_,
        bool pauseBorrow_,
        bool pausePayback_,
        bool pauseSwapAndArbitrage_
    ) internal {
        if (!pauseSupply_ && !pauseWithdraw_ && !pauseBorrow_ && !pausePayback_ && !pauseSwapAndArbitrage_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _revertIfNotPausable(notPausableDexIds[dexId_]);

        if (pauseSupply_ || pauseWithdraw_ || pauseBorrow_ || pausePayback_) {
            _validatePauseFlags(pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
            (
                address dex_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_,
                uint256 skippedClass_
            ) = PAUSE_AUTH_LIQUIDITY.pauseDex(dexId_, pauseSupply_, pauseWithdraw_, pauseBorrow_, pausePayback_);
            _emitDexEvents(
                dexId_,
                dex_,
                actedSupply_,
                actedWithdraw_,
                actedBorrow_,
                actedPayback_,
                skippedClass_,
                true
            );
        }

        if (pauseSwapAndArbitrage_) {
            (address dex_, bool acted_) = PAUSE_AUTH_DEX.pauseSwapAndArbitrage(dexId_);
            if (acted_) {
                emit LogPauseSwapAndArbitrage(dexId_, dex_);
            }
        }
    }

    /// @dev Unpauses a DEX: supply/borrow at LL (via PAUSE_AUTH_LIQUIDITY), swap at DEX (via PAUSE_AUTH_DEX).
    function _unpauseDex(
        uint256 dexId_,
        bool unpauseSupply_,
        bool unpauseWithdraw_,
        bool unpauseBorrow_,
        bool unpausePayback_,
        bool unpauseSwapAndArbitrage_
    ) internal {
        if (!unpauseSupply_ && !unpauseWithdraw_ && !unpauseBorrow_ && !unpausePayback_ && !unpauseSwapAndArbitrage_) {
            revert FluidConfigError(ErrorTypes.PauseAuth__InvalidParams);
        }
        _revertIfNotPausable(notPausableDexIds[dexId_]);

        if (unpauseSupply_ || unpauseWithdraw_ || unpauseBorrow_ || unpausePayback_) {
            (
                address dex_,
                bool actedSupply_,
                bool actedWithdraw_,
                bool actedBorrow_,
                bool actedPayback_,
                uint256 skippedClass_
            ) = PAUSE_AUTH_LIQUIDITY.unpauseDex(
                    dexId_,
                    unpauseSupply_,
                    unpauseWithdraw_,
                    unpauseBorrow_,
                    unpausePayback_
                );
            _emitDexEvents(
                dexId_,
                dex_,
                actedSupply_,
                actedWithdraw_,
                actedBorrow_,
                actedPayback_,
                skippedClass_,
                false
            );
        }

        if (unpauseSwapAndArbitrage_) {
            (address dex_, bool acted_) = PAUSE_AUTH_DEX.unpauseSwapAndArbitrage(dexId_);
            if (acted_) {
                emit LogUnpauseSwapAndArbitrage(dexId_, dex_);
            }
        }
    }

    // ==================== Internal: event emission helpers ====================

    function _emitVaultEvents(
        uint256 vaultId_,
        address vault_,
        bool actedSupply_,
        bool actedWithdraw_,
        bool actedBorrow_,
        bool actedPayback_,
        uint256 skippedClass_,
        bool wantsPaused_
    ) internal {
        if (actedSupply_ || actedWithdraw_ || actedBorrow_ || actedPayback_) {
            if (wantsPaused_) {
                emit LogPauseVault(vaultId_, vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
            } else {
                emit LogUnpauseVault(vaultId_, vault_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
            }
        }
        if (skippedClass_ != 0) {
            emit LogSkipVaultUserClass(vaultId_, vault_, skippedClass_);
        }
    }

    function _emitDexEvents(
        uint256 dexId_,
        address dex_,
        bool actedSupply_,
        bool actedWithdraw_,
        bool actedBorrow_,
        bool actedPayback_,
        uint256 skippedClass_,
        bool wantsPaused_
    ) internal {
        if (actedSupply_ || actedWithdraw_ || actedBorrow_ || actedPayback_) {
            if (wantsPaused_) {
                emit LogPauseDex(dexId_, dex_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
            } else {
                emit LogUnpauseDex(dexId_, dex_, actedSupply_, actedWithdraw_, actedBorrow_, actedPayback_);
            }
        }
        if (skippedClass_ != 0) {
            emit LogSkipDexUserClass(dexId_, dex_, skippedClass_);
        }
    }

    function _emitOracleV2Events(address[] memory tokens_, bool[] memory acted_, bool wantsPaused_) internal {
        uint256 length_ = tokens_.length;
        for (uint256 i; i < length_; i++) {
            if (acted_[i]) {
                if (wantsPaused_) {
                    emit LogPauseOracleV2(tokens_[i]);
                } else {
                    emit LogUnpauseOracleV2(tokens_[i]);
                }
            }
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
