// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IFluidContractFactory } from "../../../deployer/interface.sol";
import { IFluidDexT1 } from "../../../protocols/dex/interfaces/iDexT1.sol";
import { IFluidVault } from "../../../protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "../../../protocols/vault/interfaces/iVaultT1.sol";
import { IFluidVaultFactory } from "../../../protocols/vault/interfaces/iVaultFactory.sol";

import { BytesSliceAndConcat } from "../../../libraries/bytesSliceAndConcat.sol";
import { DexShareResolver } from "../../common/dexShareResolver.sol";
import { IUSDOracle } from "../../interfaces/iUSDOracle.sol";
import { Error as VaultError } from "../error.sol";
import { ErrorTypes } from "../errorTypes.sol";
import { VaultT1OracleDeploymentLogic } from "./deploymentLogics/vaultT1OracleLogic.sol";
import { VaultT2OracleDeploymentLogic } from "./deploymentLogics/vaultT2OracleLogic.sol";
import { VaultT3OracleDeploymentLogic } from "./deploymentLogics/vaultT3OracleLogic.sol";
import { VaultT4OracleDeploymentLogic } from "./deploymentLogics/vaultT4OracleLogic.sol";

/// @dev Reads a storage word from the Liquidity infinite proxy (same pattern as `FluidUsdOracle`).
interface IReadFromStorage {
    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);
}

/// @dev Vault type identifiers (must match `IFluidVault.TYPE()` on T2–T4).
abstract contract VaultOracleFactoryConstants {
    /// @dev Same slot as Liquidity governance / EIP-1967 proxy admin (`GOVERNANCE_SLOT` in `liquidity/common/variables.sol`).
    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant VAULT_T1_TYPE = 10000;
    uint256 internal constant VAULT_T2_SMART_COL_TYPE = 20000;
    uint256 internal constant VAULT_T3_SMART_DEBT_TYPE = 30000;
    uint256 internal constant VAULT_T4_SMART_COL_SMART_DEBT_TYPE = 40000;

    /// @dev DEX range prices (`upperRange`/`lowerRange`) are 1e27; used to scale the band ratio.
    uint256 internal constant DEX_PRICE_SCALE = 1e27;
    /// @dev Max DEX band ratio (`upperRange / lowerRange`, 1e27) for a DEX-share oracle. 1.5e27 keeps worst-case
    ///      skew <0.5%; real peg pools sit ≤ ~1.02, volatile pools far wider.
    uint256 internal constant MAX_DEX_RANGE_RATIO = 1.5e27;

    /// @dev Upper bound (ppm on 1e6) for either DEX share peg buffer. The buffer only covers pricing uncertainty
    ///      the USD oracle feeds cannot correct, so anything above 1% signals a misconfiguration, not a risk choice.
    uint256 internal constant MAX_PEG_BUFFER_PPM = 10_000;

    /// @notice Liquidity protocol contract — used to resolve current governance for UUPS upgrades (`readFromStorage`).
    address public immutable LIQUIDITY;
    address public immutable USD_ORACLE;
    IFluidVaultFactory public immutable VAULT_FACTORY;
    /// @notice Shared `FluidContractFactory` — must match `IFluidVault.constantsView().deployer` on T2–T4 vaults.
    IFluidContractFactory public immutable DEPLOYER_FACTORY;

    /// @notice Per-type oracle deployment logics.
    VaultT1OracleDeploymentLogic public immutable T1_ORACLE_LOGIC;
    VaultT2OracleDeploymentLogic public immutable T2_ORACLE_LOGIC;
    VaultT3OracleDeploymentLogic public immutable T3_ORACLE_LOGIC;
    VaultT4OracleDeploymentLogic public immutable T4_ORACLE_LOGIC;
    /// @notice Team multisig — may `setVaultOracleDeployer` together with governance (same hardcoded address as `contracts/config` auth contracts).
    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
}

abstract contract VaultOracleFactoryEvents {
    event LogVaultOracleRegistered(
        address indexed vault,
        address indexed vaultOracle,
        uint256 vaultType,
        uint256 indexed vaultId,
        uint256 deployNonce
    );

    event LogVaultOracleDeployerSet(address indexed account, bool allowed);
}

abstract contract VaultOracleFactoryVariables {
    /// @notice Vault factory `VAULT_ID` => `FluidContractFactory.totalContracts` nonce used for that vault's oracle deploy.
    ///         Oracle address is always `DEPLOYER_FACTORY.getContractAddress(vaultIdToOracleDeployNonce[vaultId])`.
    mapping(uint256 => uint256) public vaultIdToOracleDeployNonce;

    /// @notice Allow-listed addresses that may call `registerVault` (governance and `TEAM_MULTISIG` may always).
    mapping(address => bool) public vaultOracleDeployer;
}

/// @title VaultOracleFactory
/// @notice Deploys per-vault oracles via `FluidContractFactory` so the oracle lands at
///         `AddressCalcs.addressCalc(DEPLOYER_FACTORY, nonce)`. T2–T4 vault admin uses `updateOracle(uint)`; T1 uses
///         `updateOracle(address)` with that address. The `FluidContractFactory` must allow-list this contract via
///         `updateDeployer(address(this), count)` (owner-only).
///
///         `registerVault` is restricted to governance, `TEAM_MULTISIG`, or `vaultOracleDeployer` allow-list entries.
///         Governance may `registerVaultForce` to redeploy and replace the recorded nonce for a vault ID.
///
/// @dev **Proxy deployment (see `factory/proxy.sol`, README, spec §8.0):** In production this implementation is placed
///      behind `VaultOracleFactoryProxy` (ERC1967 UUPS) so (1) logic can be upgraded without changing the factory address,
///      (2) `vaultIdToOracleDeployNonce` stays at a stable address across upgrades, and (3) integrators and allow-lists
///      can keep a single canonical factory address per network. Not the “infinite” meta-proxy pattern. Upgrades are
///      allowed only by **Liquidity governance** (same address as resolved on `LIQUIDITY` via `readFromStorage`).
///
/// @dev **Nonce tracking:** For each `VAULT_ID`, `vaultIdToOracleDeployNonce` stores the global `FluidContractFactory`
///      deploy nonce for that vault's oracle. The oracle address is `DEPLOYER_FACTORY.getContractAddress(nonce)`;
///      off-chain handlers can verify `updateOracle` targets the canonical deployment via that nonce.
///
/// @dev T2–T4 DEX share peg buffers are per-oracle immutables set at `registerVault`
///      (`pegBufferPpmOperate_`, `pegBufferPpmLiquidate_`; factory max 1%). T1 uses `0, 0`.
///      T1 uses `IFluidVaultT1.constantsView()` only; T2–T4 use `IFluidVault` views and a deployer check.
contract VaultOracleFactory is
    VaultError,
    VaultOracleFactoryConstants,
    VaultOracleFactoryEvents,
    VaultOracleFactoryVariables,
    UUPSUpgradeable
{
    constructor(
        address liquidity_,
        address usdOracle_,
        address vaultFactory_,
        address deployerFactory_,
        address t1OracleLogic_,
        address t2OracleLogic_,
        address t3OracleLogic_,
        address t4OracleLogic_
    ) {
        if (
            liquidity_ == address(0) ||
            usdOracle_ == address(0) ||
            vaultFactory_ == address(0) ||
            deployerFactory_ == address(0) ||
            t1OracleLogic_ == address(0) ||
            t2OracleLogic_ == address(0) ||
            t3OracleLogic_ == address(0) ||
            t4OracleLogic_ == address(0)
        ) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__AddressZero);
        }
        LIQUIDITY = liquidity_;
        USD_ORACLE = usdOracle_;
        VAULT_FACTORY = IFluidVaultFactory(vaultFactory_);
        DEPLOYER_FACTORY = IFluidContractFactory(deployerFactory_);
        T1_ORACLE_LOGIC = VaultT1OracleDeploymentLogic(t1OracleLogic_);
        T2_ORACLE_LOGIC = VaultT2OracleDeploymentLogic(t2OracleLogic_);
        T3_ORACLE_LOGIC = VaultT3OracleDeploymentLogic(t3OracleLogic_);
        T4_ORACLE_LOGIC = VaultT4OracleDeploymentLogic(t4OracleLogic_);
    }

    /// @notice Allow-list or remove an address allowed to call `registerVault`. Callable by governance or `TEAM_MULTISIG`.
    function setVaultOracleDeployer(address _deployer, bool allowed_) external {
        if (_deployer == address(0)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__AddressZero);
        }
        if (msg.sender != _getGovernanceAddr() && msg.sender != TEAM_MULTISIG) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__Unauthorized);
        }
        vaultOracleDeployer[_deployer] = allowed_;
        emit LogVaultOracleDeployerSet(_deployer, allowed_);
    }

    /// @notice Deploys a vault oracle for `vaultId_` with immutable supply/borrow eModes and DEX share peg buffers
    ///         baked into the oracle.
    /// @param pegBufferPpmOperate_ Operate-path reserve adjustment for T2-T4 DEX share legs; ignored for T1.
    /// @param pegBufferPpmLiquidate_ Liquidate-path equivalent; must not exceed `pegBufferPpmOperate_`.
    function registerVault(
        uint256 vaultId_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) external returns (address vaultOracle_) {
        if (msg.sender != _getGovernanceAddr() && msg.sender != TEAM_MULTISIG && !vaultOracleDeployer[msg.sender]) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__Unauthorized);
        }
        if (vaultIdToOracleDeployNonce[vaultId_] != 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__AlreadyRegistered);
        }
        return _registerVaultCore(vaultId_, supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_);
    }

    /// @notice Same as `registerVault` but governance-only; may replace an existing oracle nonce for `vaultId_`.
    function registerVaultForce(
        uint256 vaultId_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) external returns (address vaultOracle_) {
        if (msg.sender != _getGovernanceAddr()) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__Unauthorized);
        }
        return _registerVaultCore(vaultId_, supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_);
    }

    /// @notice Resolves vault ID to vault address, recorded FluidContractFactory oracle deploy nonce, and oracle address.
    /// @dev Reverts if no oracle was registered for `vaultId_`, or if stored data is inconsistent.
    function getVaultOracleDeployment(
        uint256 vaultId_
    ) external view returns (address vault_, uint256 oracleNonce_, address vaultOracle_) {
        vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        oracleNonce_ = vaultIdToOracleDeployNonce[vaultId_];
        if (oracleNonce_ == 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__NotRegistered);
        }
        vaultOracle_ = DEPLOYER_FACTORY.getContractAddress(oracleNonce_);
        if (IFluidVault(vault_).VAULT_ID() != vaultId_) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DeploymentInvariantFailed);
        }
    }

    /// @dev Current governance address on Liquidity (same read path as `FluidUsdOracle._getGovernanceAddr`).
    function _getGovernanceAddr() internal view returns (address governance_) {
        governance_ = address(uint160(IReadFromStorage(LIQUIDITY).readFromStorage(LIQUIDITY_GOVERNANCE_SLOT)));
    }

    function _authorizeUpgrade(address) internal override {
        if (msg.sender != _getGovernanceAddr()) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__Unauthorized);
        }
    }

    function _registerVaultCore(
        uint256 vaultId_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) internal returns (address vaultOracle_) {
        if (vaultId_ == 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__VaultIdZero);
        }

        address vault_ = VAULT_FACTORY.getVaultAddress(vaultId_);
        if (vault_ == address(0) || !VAULT_FACTORY.isVault(vault_)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__InvalidVault);
        }
        if (IFluidVault(vault_).VAULT_ID() != vaultId_) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DeploymentInvariantFailed);
        }

        uint256 vaultType_ = _isVaultT1(vault_) ? VAULT_T1_TYPE : IFluidVault(vault_).TYPE();
        if (
            vaultType_ != VAULT_T1_TYPE &&
            vaultType_ != VAULT_T2_SMART_COL_TYPE &&
            vaultType_ != VAULT_T3_SMART_DEBT_TYPE &&
            vaultType_ != VAULT_T4_SMART_COL_SMART_DEBT_TYPE
        ) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__UnsupportedType);
        }
        if (!_isValidEmodeForVault(vault_, vaultType_, supplyEMode_, borrowEMode_)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__InvalidEMode);
        }
        if (pegBufferPpmOperate_ > MAX_PEG_BUFFER_PPM || pegBufferPpmLiquidate_ > pegBufferPpmOperate_) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__InvalidPegBuffer);
        }

        if (vaultType_ == VAULT_T1_TYPE) {
            vaultOracle_ = _deployT1(vault_, supplyEMode_, borrowEMode_);
        } else {
            IFluidVault.ConstantViews memory c_ = IFluidVault(vault_).constantsView();
            _verifyDeployerMatchesVault(c_.deployer);

            if (vaultType_ == VAULT_T2_SMART_COL_TYPE) {
                vaultOracle_ = _deployT2(c_, supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_);
            } else if (vaultType_ == VAULT_T3_SMART_DEBT_TYPE) {
                vaultOracle_ = _deployT3(c_, supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_);
            } else {
                vaultOracle_ = _deployT4(c_, supplyEMode_, borrowEMode_, pegBufferPpmOperate_, pegBufferPpmLiquidate_);
            }
        }

        _finalizeOracleRegistration(vaultId_, vault_, vaultOracle_, vaultType_);
    }

    function _deployT1(address vault_, uint256 supplyEMode_, uint256 borrowEMode_) internal returns (address) {
        IFluidVaultT1.ConstantViews memory c_ = IFluidVaultT1(vault_).constantsView();
        return
            DEPLOYER_FACTORY.deployContract(
                T1_ORACLE_LOGIC.creationCodeWithArgs(
                    USD_ORACLE,
                    c_.supplyToken,
                    c_.borrowToken,
                    supplyEMode_,
                    borrowEMode_
                )
            );
    }

    function _deployT2(
        IFluidVault.ConstantViews memory c_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) internal returns (address) {
        DexShareResolver.DexParams memory dex_ = _readDexData(c_.supply);
        _assertDexIsPeg(dex_.dexPool);
        return
            DEPLOYER_FACTORY.deployContract(
                T2_ORACLE_LOGIC.creationCodeWithArgs(
                    USD_ORACLE,
                    c_.borrowToken.token0,
                    dex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }

    function _deployT3(
        IFluidVault.ConstantViews memory c_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) internal returns (address) {
        DexShareResolver.DexParams memory dex_ = _readDexData(c_.borrow);
        _assertDexIsPeg(dex_.dexPool);
        return
            DEPLOYER_FACTORY.deployContract(
                T3_ORACLE_LOGIC.creationCodeWithArgs(
                    USD_ORACLE,
                    c_.supplyToken.token0,
                    dex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }

    function _deployT4(
        IFluidVault.ConstantViews memory c_,
        uint256 supplyEMode_,
        uint256 borrowEMode_,
        uint256 pegBufferPpmOperate_,
        uint256 pegBufferPpmLiquidate_
    ) internal returns (address) {
        DexShareResolver.DexParams memory colDex_ = _readDexData(c_.supply);
        DexShareResolver.DexParams memory debtDex_ = _readDexData(c_.borrow);
        _assertDexIsPeg(colDex_.dexPool);
        _assertDexIsPeg(debtDex_.dexPool);
        return
            DEPLOYER_FACTORY.deployContract(
                T4_ORACLE_LOGIC.creationCodeWithArgs(
                    USD_ORACLE,
                    colDex_,
                    debtDex_,
                    supplyEMode_,
                    borrowEMode_,
                    pegBufferPpmOperate_,
                    pegBufferPpmLiquidate_
                )
            );
    }

    /// @dev Returns true when supply and borrow eModes are each valid for at least one token on their respective side.
    function _isValidEmodeForVault(
        address vault_,
        uint256 vaultType_,
        uint256 supplyEMode_,
        uint256 borrowEMode_
    ) internal view returns (bool) {
        address supplyToken0_;
        address supplyToken1_;
        address borrowToken0_;
        address borrowToken1_;

        if (vaultType_ == VAULT_T1_TYPE) {
            IFluidVaultT1.ConstantViews memory cT1_ = IFluidVaultT1(vault_).constantsView();
            supplyToken0_ = cT1_.supplyToken;
            borrowToken0_ = cT1_.borrowToken;
        } else {
            IFluidVault.ConstantViews memory c_ = IFluidVault(vault_).constantsView();
            supplyToken0_ = c_.supplyToken.token0;
            supplyToken1_ = c_.supplyToken.token1;
            borrowToken0_ = c_.borrowToken.token0;
            borrowToken1_ = c_.borrowToken.token1;
        }

        return
            _isEmodeValidForTokenPair(supplyToken0_, supplyToken1_, supplyEMode_) &&
            _isEmodeValidForTokenPair(borrowToken0_, borrowToken1_, borrowEMode_);
    }

    function _isEmodeValidForTokenPair(address token0_, address token1_, uint256 emode_) internal view returns (bool) {
        if (token0_ != address(0) && IUSDOracle(USD_ORACLE).isEmodeValid(emode_, token0_)) {
            return true;
        }
        return token1_ != address(0) && IUSDOracle(USD_ORACLE).isEmodeValid(emode_, token1_);
    }

    /// @dev Records registry + per-vault-ID nonce. `nonce_` must equal `DEPLOYER_FACTORY.totalContracts()` after deploy.
    function _finalizeOracleRegistration(
        uint256 vaultId_,
        address vault_,
        address vaultOracle_,
        uint256 vaultType_
    ) internal {
        if (IFluidVault(vault_).VAULT_ID() != vaultId_) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DeploymentInvariantFailed);
        }
        uint256 nonce_ = DEPLOYER_FACTORY.totalContracts();
        if (vaultOracle_ != DEPLOYER_FACTORY.getContractAddress(nonce_)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DeploymentInvariantFailed);
        }
        vaultIdToOracleDeployNonce[vaultId_] = nonce_;
        emit LogVaultOracleRegistered(vault_, vaultOracle_, vaultType_, vaultId_, nonce_);
    }

    /// @dev T1 if `TYPE()` reverts (no `TYPE()` on legacy vaults) or returns `VAULT_T1_TYPE`.
    function _isVaultT1(address vault_) internal view returns (bool) {
        try IFluidVault(vault_).TYPE() returns (uint256 type_) {
            return type_ == VAULT_T1_TYPE;
        } catch {
            return true;
        }
    }

    /// @dev T2–T4 only: `deployer_` must be `DEPLOYER_FACTORY` so the oracle address matches `AddressCalcs.addressCalc`.
    function _verifyDeployerMatchesVault(address deployer_) internal view {
        if (deployer_ != address(DEPLOYER_FACTORY)) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DeployerMismatch);
        }
    }

    /// @dev Reads DEX pool constants into a DexParams struct.
    function _readDexData(address dexPool_) internal view returns (DexShareResolver.DexParams memory dex_) {
        IFluidDexT1.ConstantViews memory cv_ = IFluidDexT1(dexPool_).constantsView();
        IFluidDexT1.ConstantViews2 memory cv2_ = IFluidDexT1(dexPool_).constantsView2();

        dex_ = DexShareResolver.DexParams({
            dexPool: dexPool_,
            token0: cv_.token0,
            token1: cv_.token1,
            supplyToken0Slot: cv_.supplyToken0Slot,
            supplyToken1Slot: cv_.supplyToken1Slot,
            borrowToken0Slot: cv_.borrowToken0Slot,
            borrowToken1Slot: cv_.borrowToken1Slot,
            exchangePriceToken0Slot: cv_.exchangePriceToken0Slot,
            exchangePriceToken1Slot: cv_.exchangePriceToken1Slot,
            token0NumeratorPrecision: cv2_.token0NumeratorPrecision,
            token0DenominatorPrecision: cv2_.token0DenominatorPrecision,
            token1NumeratorPrecision: cv2_.token1NumeratorPrecision,
            token1DenominatorPrecision: cv2_.token1DenominatorPrecision
        });
    }

    /// @dev Filters out volatile DEX pools: a wide band lets a flash-skew inflate DEX-share value, so revert
    ///      unless the band is tight enough to be a peg pool. One-time check at registration.
    function _assertDexIsPeg(address dexPool_) internal {
        IFluidDexT1.PricesAndExchangePrice memory pex_ = _getDexPrices(dexPool_);
        if (pex_.upperRange == 0 || pex_.lowerRange == 0) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DexPriceReadFailed);
        }
        if ((pex_.upperRange * DEX_PRICE_SCALE) / pex_.lowerRange > MAX_DEX_RANGE_RATIO) {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DexIsNotPeg);
        }
    }

    /// @dev Reads DEX center/range prices via the `getPricesAndExchangePrices()` revert-data pattern (same as
    ///      `FluidDexReservesResolver`). The call always reverts with `FluidDexPricesAndExchangeRates(pex_)`.
    function _getDexPrices(address dexPool_) internal returns (IFluidDexT1.PricesAndExchangePrice memory pex_) {
        try IFluidDexT1(dexPool_).getPricesAndExchangePrices() {
            revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DexPriceReadFailed);
        } catch (bytes memory data_) {
            bytes4 selector_;
            assembly {
                selector_ := mload(add(data_, 0x20))
            }
            if (selector_ != IFluidDexT1.FluidDexPricesAndExchangeRates.selector) {
                revert FluidVaultOracleError(ErrorTypes.VaultOracleFactory__DexPriceReadFailed);
            }
            pex_ = abi.decode(
                BytesSliceAndConcat.bytesSlice(data_, 4, data_.length - 4),
                (IFluidDexT1.PricesAndExchangePrice)
            );
        }
    }
}
