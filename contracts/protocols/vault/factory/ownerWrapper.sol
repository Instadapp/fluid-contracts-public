// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

/// @notice VaultFactoryOwner — owner wrapper for FluidVaultFactory that gates position transfers.
///
/// Purpose:
///   Sits as owner of VaultFactory. Passes through all admin methods to governance unchanged.
///   Adds two restricted methods that can move position NFTs to the team multisig:
///     - transferPosition:     for allowlisted vault IDs, callable by team / governance.
///     - transferDustPosition: for tiny (<1e5 raw debt) and risky (>=50% LTV) positions,
///                             callable by dustPosAuths / team / governance.
///
/// Access control (3 tiers):
///   governance   (= Liquidity proxy admin)  → full factory admin + config + all transfers
///   team multisig                           → transferPosition, transferDustPosition (skip ratio check)
///   dustPosAuths                            → transferDustPosition only (must pass ratio check)
///
/// Transfer mechanism:
///   1. spellApprove() delegatecalled via factory.spell()  →  sets getApproved[tokenId] = this
///   2. factory.transferFrom(from, team, tokenId)          →  executes ERC721 transfer
///   3. transferFrom clears approval atomically            →  no lingering approval
///
/// Key thresholds:
///   DEBT_THRESHOLD  = 1e5      positions with raw debt > this cannot be dust-transferred
///   RATIO_THRESHOLD = 500      50% LTV; dustPosAuths can only move positions at or above this ratio

import { TickMath } from "../../../libraries/tickMath.sol";
import { AddressCalcs } from "../../../libraries/addressCalcs.sol";
import { IFluidVault } from "../interfaces/iVault.sol";
import { IFluidOracle } from "../../../oracleV1_DEPRECATED/interfaces/iFluidOracle.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { Error } from "../error.sol";

interface IFluidVaultFactory_OwnerWrapper {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);

    function getVaultAddress(uint256 vaultId_) external view returns (address vault_);

    function isVault(address vault_) external view returns (bool);

    function transferFrom(address from_, address to_, uint256 id_) external;

    function setDeployer(address deployer_, bool allowed_) external;

    function setGlobalAuth(address globalAuth_, bool allowed_) external;

    function setVaultAuth(address vault_, address vaultAuth_, bool allowed_) external;

    function setVaultDeploymentLogic(address deploymentLogic_, bool allowed_) external;

    function spell(address target_, bytes memory data_) external returns (bytes memory response_);

    function transferOwnership(address newOwner) external;
}

interface ILiquidity_OwnerWrapper {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

abstract contract Constants {
    IFluidVaultFactory_OwnerWrapper public immutable FACTORY;
    ILiquidity_OwnerWrapper public immutable LIQUIDITY;

    /// @dev EIP1967 admin slot used to read governance address from Liquidity proxy
    bytes32 internal constant _LIQUIDITY_ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @dev positions with borrow >= this threshold require vault ID to be allowlisted
    uint256 internal constant DEBT_THRESHOLD = 1e5;

    /// @dev 50% in 3-decimal precision (same as vault's collateral factor encoding: 500 = 50%)
    uint256 internal constant RATIO_THRESHOLD = 500;

    uint256 internal constant VAULT_T1_TYPE = 10000;

    uint256 internal constant X8 = 0xff;
    uint256 internal constant X19 = 0x7ffff;
    uint256 internal constant X24 = 0xffffff;
    uint256 internal constant X30 = 0x3fffffff;
    uint256 internal constant X32 = 0xffffffff;
    uint256 internal constant X64 = 0xffffffffffffffff;
}

abstract contract Variables is Constants {
    /// @dev vault IDs allowlisted by governance for transferPosition
    mapping(uint256 => bool) public vaultIdAllowlisted;

    /// @dev addresses authorized to call transferDustPosition
    mapping(address => bool) public transferDustPosAuths;
}

abstract contract Events {
    event LogSetVaultIdAllowlisted(uint256 indexed vaultId, bool indexed allowed);
    event LogSetTransferDustPosAuth(address indexed auth, bool indexed allowed);
    event LogTransferPosition(uint256 indexed tokenId, address indexed from, uint256 indexed vaultId);
    event LogTransferDustPosition(uint256 indexed tokenId, address indexed from, uint256 indexed vaultId);
    event LogTransferFactoryOwnership(address indexed newOwner);
}

/// @notice Governance auth, modifiers, factory admin passthrough, spell.
abstract contract VaultFactoryOwnerCore is Variables, Events, Error {
    modifier onlyGovernance() {
        if (msg.sender != _getGovernance()) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__Unauthorized);
        }
        _;
    }

    modifier onlyTeamOrGovernance() {
        if (msg.sender != TEAM_MULTISIG && msg.sender != _getGovernance()) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__Unauthorized);
        }
        _;
    }

    modifier onlyDustPosAuthOrTeamOrGovernance() {
        if (!transferDustPosAuths[msg.sender] && msg.sender != TEAM_MULTISIG && msg.sender != _getGovernance()) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__Unauthorized);
        }
        _;
    }

    constructor(IFluidVaultFactory_OwnerWrapper factory_, ILiquidity_OwnerWrapper liquidity_) {
        if (address(factory_) == address(0) || address(liquidity_) == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__ZeroAddress);
        }
        FACTORY = factory_;
        LIQUIDITY = liquidity_;
    }

    /// @dev Reads governance address from Liquidity's EIP1967 proxy admin slot
    function _getGovernance() internal view returns (address) {
        return address(uint160(LIQUIDITY.readFromStorage(_LIQUIDITY_ADMIN_SLOT)));
    }

    // ============ Factory Owner Passthrough (Governance Only) ============

    /// @notice Sets a deployer on VaultFactory. Governance only.
    function setDeployer(address deployer_, bool allowed_) external onlyGovernance {
        FACTORY.setDeployer(deployer_, allowed_);
    }

    /// @notice Sets a global auth on VaultFactory. Governance only.
    function setGlobalAuth(address globalAuth_, bool allowed_) external onlyGovernance {
        FACTORY.setGlobalAuth(globalAuth_, allowed_);
    }

    /// @notice Sets a vault auth on VaultFactory. Governance only.
    function setVaultAuth(address vault_, address vaultAuth_, bool allowed_) external onlyGovernance {
        FACTORY.setVaultAuth(vault_, vaultAuth_, allowed_);
    }

    /// @notice Sets a vault deployment logic on VaultFactory. Governance only.
    function setVaultDeploymentLogic(address deploymentLogic_, bool allowed_) external onlyGovernance {
        FACTORY.setVaultDeploymentLogic(deploymentLogic_, allowed_);
    }

    /// @notice Executes arbitrary delegatecall on VaultFactory. Governance only due to unrestricted power.
    function spell(address target_, bytes memory data_) external onlyGovernance returns (bytes memory) {
        return FACTORY.spell(target_, data_);
    }

    /// @notice Transfers ownership of the VaultFactory to a new address. Governance only.
    function transferFactoryOwnership(address newOwner_) external onlyGovernance {
        if (newOwner_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__ZeroAddress);
        }
        FACTORY.transferOwnership(newOwner_);
        emit LogTransferFactoryOwnership(newOwner_);
    }

    // ============ transfer helpers ============

    /// @dev When delegatecalled from VaultFactory via spell, writes ERC721 approval at getApproved storage slot 6.
    ///      Only executable in VaultFactory context (address(this) must be FACTORY).
    function spellApprove(uint256 id_, address spender_) external {
        if (address(this) != address(FACTORY)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__NotFactoryContext);
        }
        bytes32 slot_ = keccak256(abi.encode(id_, uint256(6)));
        assembly {
            sstore(slot_, spender_)
        }
    }

    /// @dev Approves this contract for the NFT via spell, then transfers to TEAM_MULTISIG.
    function _transferToTeam(address from_, uint256 tokenId_) internal {
        FACTORY.spell(address(this), abi.encodeWithSelector(this.spellApprove.selector, tokenId_, address(this)));
        FACTORY.transferFrom(from_, TEAM_MULTISIG, tokenId_);
    }
}

/// @notice transferPosition and transferDustPosition logic.
abstract contract VaultFactoryOwnerTransfer is VaultFactoryOwnerCore {
    constructor(uint256[] memory vaultIds_, address[] memory dustPosAuths_) {
        for (uint256 i; i < vaultIds_.length; i++) {
            _setVaultIdAllowlisted(vaultIds_[i], true);
        }
        for (uint256 i; i < dustPosAuths_.length; i++) {
            _setTransferDustPosAuth(dustPosAuths_[i], true);
        }
    }

    // ============ Governance Config ============

    /// @notice Allowlists or de-allowlists a vault ID for transferPosition. Governance only.
    function setVaultIdAllowlisted(uint256 vaultId_, bool allowed_) external onlyGovernance {
        _setVaultIdAllowlisted(vaultId_, allowed_);
    }

    /// @notice Sets or revokes a transferDustPosition auth address. Team or governance.
    function setTransferDustPosAuth(address auth_, bool allowed_) external onlyTeamOrGovernance {
        _setTransferDustPosAuth(auth_, allowed_);
    }

    // ============ Transfer Methods ============

    /// @notice Transfers a position NFT to team multisig. Vault must be allowlisted.
    /// @param tokenId_ The position NFT token ID to transfer
    function transferPosition(uint256 tokenId_) external onlyTeamOrGovernance {
        (address from_, uint256 vaultId_) = _resolvePosition(tokenId_);
        _resolveVault(vaultId_);

        if (!vaultIdAllowlisted[vaultId_]) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__VaultNotAllowlisted);
        }

        _transferToTeam(from_, tokenId_);

        emit LogTransferPosition(tokenId_, from_, vaultId_);
    }

    /// @notice Transfers a dust position NFT to team multisig.
    /// @dev All callers require position debt < DEBT_THRESHOLD.
    ///      dustPosAuths must also satisfy position ratio >= 50% (risky).
    ///      team multisig and governance may transfer dust positions regardless of ratio.
    /// @param tokenId_ The position NFT token ID to transfer
    function transferDustPosition(uint256 tokenId_) external onlyDustPosAuthOrTeamOrGovernance {
        (address from_, uint256 vaultId_) = _resolvePosition(tokenId_);
        (IFluidVault vault_, uint256 vaultType_) = _resolveVault(vaultId_);

        (int256 tick_, uint256 debtRaw_) = _getPositionTickAndDebtRaw(vault_, tokenId_);

        if (debtRaw_ > DEBT_THRESHOLD) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__DebtAboveThreshold);
        }

        // supply-only positions (no debt) have no meaningful tick; they are always safe
        if (debtRaw_ == 0) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__PositionTooSafe);
        }

        if (
            msg.sender != TEAM_MULTISIG &&
            msg.sender != _getGovernance() &&
            !_isPositionAboveRatioThreshold(vault_, vaultType_, tick_)
        ) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__PositionTooSafe);
        }

        _transferToTeam(from_, tokenId_);

        emit LogTransferDustPosition(tokenId_, from_, vaultId_);
    }

    // ============ Internal Helpers ============

    function _setVaultIdAllowlisted(uint256 vaultId_, bool allowed_) internal {
        if (!FACTORY.isVault(FACTORY.getVaultAddress(vaultId_))) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__InvalidVault);
        }
        vaultIdAllowlisted[vaultId_] = allowed_;
        emit LogSetVaultIdAllowlisted(vaultId_, allowed_);
    }

    function _setTransferDustPosAuth(address auth_, bool allowed_) internal {
        if (auth_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__ZeroAddress);
        }
        transferDustPosAuths[auth_] = allowed_;
        emit LogSetTransferDustPosAuth(auth_, allowed_);
    }

    /// @dev Reads tokenConfig from factory storage, extracts owner and vaultId. Reverts if NFT does not exist.
    function _resolvePosition(uint256 tokenId_) internal view returns (address from_, uint256 vaultId_) {
        uint256 tokenConfig_ = FACTORY.readFromStorage(keccak256(abi.encode(tokenId_, uint256(3))));
        from_ = address(uint160(tokenConfig_));
        vaultId_ = (tokenConfig_ >> 192) & X32;
        if (from_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__InvalidPosition);
        }
    }

    /// @dev Resolves a vault by id and determines its type.
    ///      If TYPE() is unavailable, falls back to legacy T1 semantics (vault already validated via factory).
    function _resolveVault(uint256 vaultId_) internal view returns (IFluidVault vault_, uint256 vaultType_) {
        address vaultAddress_ = FACTORY.getVaultAddress(vaultId_);
        if (vaultAddress_ == address(0)) {
            revert FluidVaultError(ErrorTypes.VaultFactoryOwner__InvalidVault);
        }

        vault_ = IFluidVault(vaultAddress_);

        try vault_.TYPE() returns (uint256 type_) {
            vaultType_ = type_;
        } catch {
            vaultType_ = VAULT_T1_TYPE;
        }
    }

    /// @dev Returns the position's current tick and total raw debt amount.
    ///      Replicates resolver logic from FluidVaultResolver.positionByNftId().
    ///      See position data layout in vaultT1/common/variables.sol (positionData mapping at storage slot 3)
    ///      and tick data layout (tickData mapping at storage slot 5).
    ///      Dust debt is NOT subtracted: DEBT_THRESHOLD is compared against total raw debt,
    ///      same as how MIN_DEBT is treated in vault core (see 5deed7f42e41).
    function _getPositionTickAndDebtRaw(
        IFluidVault vault_,
        uint256 tokenId_
    ) internal view returns (int256 tick_, uint256 debtRaw_) {
        // Read positionData from vault storage slot 3 (positionData mapping).
        // See vaultT1/common/variables.sol line 43-53 for full bit layout.
        uint256 positionData_ = vault_.readFromStorage(keccak256(abi.encode(tokenId_, uint256(3))));

        // Bit 0 of positionData: position type flag (0 = borrow position, 1 = supply-only position).
        // See vaultT1/common/variables.sol line 45: "First 1 bit => 0 => position type"
        if ((positionData_ & 1) == 1) {
            return (0, 0);
        }

        // Bits 45-108 of positionData: user's supply amount in big-number format (56-bit coefficient + 8-bit exponent).
        // See vaultT1/common/variables.sol line 50: "Next 64 bits => 45-108 => user's supply amount"
        // Big-number decoding: raw = (coefficient >> 8) << (exponent & 0xFF)
        uint256 supply_ = (positionData_ >> 45) & X64;
        supply_ = (supply_ >> 8) << (supply_ & X8);

        // Bit 1 of positionData: sign of user's tick (0 = negative, 1 = positive).
        // Bits 2-20: absolute value of user's tick (19 bits).
        // See vaultT1/common/variables.sol lines 46-47:
        //   "Next 1 bit => 1 => sign of user's tick (0 => negative; 1 => positive)"
        //   "Next 19 bits => 2-20 => absolute value of user's tick"
        tick_ = (positionData_ & 2) == 2 ? int256((positionData_ >> 2) & X19) : -int256((positionData_ >> 2) & X19);

        // Compute raw debt from tick ratio: debt = (ratio_at_tick * supply) >> 96.
        // TickMath.getRatioAtTick returns debt/supply ratio scaled by 1 << 96.
        // See FluidVaultResolver.positionByNftId() in resolvers/vault/main.sol lines 812-814.
        debtRaw_ = (TickMath.getRatioAtTick(int24(tick_)) * supply_) >> 96;

        // Read tickData from vault storage slot 5 (tickData mapping).
        // See vaultT1/common/variables.sol lines 63-74 for full bit layout.
        uint256 tickData_ = vault_.readFromStorage(keccak256(abi.encode(tick_, uint256(5))));

        // Bits 21-44 of positionData: user's tick ID (24 bits).
        // See vaultT1/common/variables.sol line 48: "Next 24 bits => 21-44 => user's tick's id"
        uint256 tickId_ = (positionData_ >> 21) & X24;

        // Check if user was liquidated:
        //   - tickData bit 0: if 1 then tick is liquidated (variables.sol line 65)
        //   - tickData bits 1-24: total IDs at this tick (variables.sol line 66).
        //     If total IDs > user's tickId, the tick was recycled and user was liquidated.
        // If liquidated, fetchLatestPosition traverses the branch tree to get current position state.
        // See FluidVaultResolver.positionByNftId() in resolvers/vault/main.sol lines 819-823.
        if (((tickData_ & 1) == 1) || (((tickData_ >> 1) & X24) > tickId_)) {
            (tick_, debtRaw_, supply_, , ) = vault_.fetchLatestPosition(tick_, tickId_, debtRaw_, tickData_);
        }
    }

    /// @dev Checks if the position's current ratio (LTV) is >= RATIO_THRESHOLD (50%).
    ///      Replicates the vault's oracle-adjusted ratio computation from vaultT1/coreModule/main.sol lines 431-457.
    ///      Uses a fixed RATIO_THRESHOLD (500 = 50%) instead of the vault's per-vault collateral factor.
    function _isPositionAboveRatioThreshold(
        IFluidVault vault_,
        uint256 vaultType_,
        int256 positionTick_
    ) internal view returns (bool) {
        // Read vaultVariables2 from vault storage slot 1.
        // See vaultT1/common/variables.sol lines 25-36 for T1 layout,
        // vaultTypesCommon/common/variables.sol lines 25-36 for non-T1 layout.
        uint256 vaultVariables2_ = vault_.readFromStorage(bytes32(uint256(1)));

        // Extract oracle address. T1 and non-T1 vaults store it differently:
        address oracle_;
        if (vaultType_ == VAULT_T1_TYPE) {
            // T1: oracle address stored directly in bits 96-255 of vaultVariables2.
            // See vaultT1/common/variables.sol line 35: "Next 160 bits => 96-255 => Oracle address"
            oracle_ = address(uint160(vaultVariables2_ >> 96));
        } else {
            // Non-T1: oracle nonce stored in bits 92-121 (30 bits) of vaultVariables2.
            // Oracle address is computed via CREATE-based address derivation from deployer + nonce.
            // See vaultTypesCommon/common/variables.sol line 34: "Next 30 bits => 92-121 => bits to calculate address of oracle"
            // See vaultTypesCommon/coreModule/mainOperate.sol line 400:
            //   AddressCalcs.addressCalc(DEPLOYER_CONTRACT, ((o_.vaultVariables2 >> 92) & X30))
            uint256 oracleNonce_ = (vaultVariables2_ >> 92) & X30;
            address deployer_ = vault_.constantsView().deployer;
            oracle_ = AddressCalcs.addressCalc(deployer_, oracleNonce_);
        }

        // Oracle returns debt token price per collateral token, scaled to 1e27.
        // See vaultT1/coreModule/main.sol line 423.
        // If oracle reverts or returns 0, assume position is risky (above threshold).
        uint256 oraclePrice_;
        try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 price_) {
            oraclePrice_ = price_;
        } catch {
            return true;
        }
        if (oraclePrice_ == 0) {
            return true;
        }

        // Validate oracle price range, mirroring vault core (main.sol line 427):
        //   "if (temp_ > 1e54 || temp_ < 1e9)" — vault reverts, here we assume risky.
        if (oraclePrice_ > 1e54 || oraclePrice_ < 1e9) {
            return true;
        }

        // Convert oracle price from exchange-price-adjusted to raw amounts.
        // See vaultT1/coreModule/main.sol line 432: "(temp_ * o_.supplyExPrice) / o_.borrowExPrice"
        (, , uint256 supplyExPrice_, uint256 borrowExPrice_) = vault_.updateExchangePrices(vaultVariables2_);
        uint256 rawOraclePrice_ = (oraclePrice_ * supplyExPrice_) / borrowExPrice_;

        // Cap raw oracle price at 1e45, mirroring vault core (main.sol line 440).
        if (rawOraclePrice_ > 1e45) {
            rawOraclePrice_ = 1e45;
        }

        // Apply RATIO_THRESHOLD to get the ratio at the threshold.
        // RATIO_THRESHOLD is in 3-decimal precision (500 = 50%), same encoding as vault's collateral factor.
        // See vaultT1/coreModule/main.sol line 445:
        //   "((temp_ * ((o_.vaultVariables2 >> 32) & X10)) / 1000)" — same formula but with per-vault CF.
        uint256 ratioAtThreshold_ = (rawOraclePrice_ * RATIO_THRESHOLD) / 1000;

        // Convert from 1e27 oracle price space to tick-ratio space (scaled by 1 << 96).
        // See vaultT1/coreModule/main.sol line 448:
        //   "((temp2_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27)"
        ratioAtThreshold_ = (ratioAtThreshold_ * TickMath.ZERO_TICK_SCALED_RATIO) / 1e27;

        // Convert ratio to corresponding tick using TickMath.
        // See vaultT1/coreModule/main.sol line 451: "TickMath.getTickAtRatio(temp2_)"
        (int tickAtThreshold_, ) = TickMath.getTickAtRatio(ratioAtThreshold_);

        // Position tick >= threshold tick means position is risky enough (LTV at or above threshold).
        // Note: vault core uses strict > for CF enforcement (main.sol line 452: "o_.tick > temp3_"),
        // here we use >= because being exactly at the threshold qualifies for dust transfer.
        return positionTick_ >= tickAtThreshold_;
    }
}

/// @notice Concrete deployment. See file-level comment for full overview.
contract VaultFactoryOwner is VaultFactoryOwnerTransfer {
    constructor(
        IFluidVaultFactory_OwnerWrapper factory_,
        ILiquidity_OwnerWrapper liquidity_,
        uint256[] memory vaultIds_,
        address[] memory dustPosAuths_
    ) VaultFactoryOwnerCore(factory_, liquidity_) VaultFactoryOwnerTransfer(vaultIds_, dustPosAuths_) {}
}
