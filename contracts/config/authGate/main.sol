// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { BasicUpgradeable } from "../../libraries/access/basicUpgradeable.sol";
import { BasicValidations } from "../../libraries/utils/basicValidations.sol";
import { IFluidAuthGate, FluidAuthLevels } from "./interfaces/iAuthGate.sol";

/// @title   FluidAuthGate
/// @notice  Identity registry for privileged Fluid actors: is an address Liquidity governance, or a team
///          multisig of at least a given security level. Consumers query the gate instead of hardcoding
///          multisigs, so a rotation is one upgrade here instead of redeploying every consumer.
/// @dev     UUPS behind an ERC1967 proxy; LL governance is the only upgrader. Identities are immutables
///          on the implementation — rotation = deploy a new implementation and upgrade.
///
///          Current auth tier levels:
///          MAX      -> governance
///          CRITICAL -> TEAM_MULTISIG_TIMELOCK (team multisig via timelock)
///          HIGH     -> TEAM_MULTISIG
///          MID      -> TEAM_MULTISIG2
///          LOW      -> none as of now
contract FluidAuthGate is BasicUpgradeable, BasicValidations, FluidAuthLevels, IFluidAuthGate {
    /// @notice thrown when upgrading to an implementation bound to a different Liquidity
    error AuthGate__ImplementationLiquidityMismatch();

    /// @notice main team multisig, security level `SECURITY_LEVEL_HIGH`.
    address public immutable TEAM_MULTISIG;
    /// @notice team multisig 2, security level `SECURITY_LEVEL_MID`.
    address public immutable TEAM_MULTISIG2;
    /// @notice timelock controlled by the main team multisig, security level `SECURITY_LEVEL_CRITICAL`.
    address public immutable TEAM_MULTISIG_TIMELOCK;

    // ------------ storage from inherited contracts (Initializable) --------
    // - slot 0: uint8 _initialized; bool _initializing;
    // no own storage.

    /// @param liquidity_ Liquidity proxy whose EIP-1967 admin is governance for this contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address liquidity_,
        address teamMultisig_,
        address teamMultisig2_,
        address teamMultisigTimelock_
    )
        BasicUpgradeable(liquidity_)
        validAddress(teamMultisig_)
        validAddress(teamMultisig2_)
        validAddress(teamMultisigTimelock_)
    {
        // an equal pair would silently take the first match's level; equality with governance is fine
        if (
            teamMultisig_ == teamMultisig2_ ||
            teamMultisig_ == teamMultisigTimelock_ ||
            teamMultisig2_ == teamMultisigTimelock_
        ) {
            revert Access__Unauthorized();
        }
        TEAM_MULTISIG = teamMultisig_;
        TEAM_MULTISIG2 = teamMultisig2_;
        TEAM_MULTISIG_TIMELOCK = teamMultisigTimelock_;
    }

    /// @notice current governance (EIP-1967 admin of `LIQUIDITY`).
    function governance() public view returns (address) {
        return _governance();
    }

    /// @notice whether `addr_` is Liquidity Layer governance.
    function isGovernance(address addr_) public view returns (bool) {
        return addr_ == _governance();
    }

    /// @notice reverts `Access__Unauthorized` unless `authLevel(addr_)` is non-zero and
    ///         >= `minSecurityLevel_`. `SECURITY_LEVEL_MAX` is governance-only.
    function requireAuthLevel(address addr_, uint256 minSecurityLevel_) public view {
        uint256 level_ = authLevel(addr_);
        if (level_ == 0 || level_ < minSecurityLevel_) {
            revert Access__Unauthorized();
        }
    }

    /// @notice `requireAuthLevel` at `SECURITY_LEVEL_LOW`.
    function requireAuthLevelLow(address addr_) public view {
        requireAuthLevel(addr_, SECURITY_LEVEL_LOW);
    }

    /// @notice `requireAuthLevel` at `SECURITY_LEVEL_MID`.
    function requireAuthLevelMid(address addr_) public view {
        requireAuthLevel(addr_, SECURITY_LEVEL_MID);
    }

    /// @notice `requireAuthLevel` at `SECURITY_LEVEL_HIGH`.
    function requireAuthLevelHigh(address addr_) public view {
        requireAuthLevel(addr_, SECURITY_LEVEL_HIGH);
    }

    /// @notice `requireAuthLevel` at `SECURITY_LEVEL_CRITICAL`.
    function requireAuthLevelCritical(address addr_) public view {
        requireAuthLevel(addr_, SECURITY_LEVEL_CRITICAL);
    }

    /// @notice `requireAuthLevel` at `SECURITY_LEVEL_MAX`.
    function requireAuthLevelMax(address addr_) public view {
        requireAuthLevel(addr_, SECURITY_LEVEL_MAX);
    }

    /// @notice security level of `addr_`; governance is `SECURITY_LEVEL_MAX`, 0 for unknown addresses.
    /// @dev governance resolves first so a team identity that also is governance still gets MAX (L2s).
    function authLevel(address addr_) public view returns (uint256) {
        if (addr_ == _governance()) {
            return SECURITY_LEVEL_MAX;
        }
        if (addr_ == TEAM_MULTISIG_TIMELOCK) {
            return SECURITY_LEVEL_CRITICAL;
        }
        if (addr_ == TEAM_MULTISIG) {
            return SECURITY_LEVEL_HIGH;
        }
        if (addr_ == TEAM_MULTISIG2) {
            return SECURITY_LEVEL_MID;
        }
        return 0;
    }

    /// @dev `LIQUIDITY` is an implementation immutable, so an implementation built against a different
    ///      Liquidity would move `onlyGovernance` to that chain of custody and lock this gate — and with it
    ///      every consumer — permanently.
    function _authorizeUpgrade(address newImplementation_) internal override onlyGovernance {
        if (FluidAuthGate(newImplementation_).LIQUIDITY() != LIQUIDITY) {
            revert AuthGate__ImplementationLiquidityMismatch();
        }
    }
}
