// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { IFluidContractFactory } from "../../../contracts/deployer/interface.sol";
import { FluidContractFactory } from "../../../contracts/deployer/main.sol";
import { IFluidVault } from "../../../contracts/protocols/vault/interfaces/iVault.sol";
import { IFluidVaultT1 } from "../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { IFluidDexT1 } from "../../../contracts/protocols/dex/interfaces/iDexT1.sol";
import { VaultOracleFactory } from "../../../contracts/oracleV2/vaultOracle/factory/main.sol";
import { VaultOracleFactoryProxy } from "../../../contracts/oracleV2/vaultOracle/factory/proxy.sol";
import { Error } from "../../../contracts/oracleV2/vaultOracle/error.sol";
import { ErrorTypes } from "../../../contracts/oracleV2/vaultOracle/errorTypes.sol";
import { DexShareResolver } from "../../../contracts/oracleV2/common/dexShareResolver.sol";
import { VaultOracleBase } from "../../../contracts/oracleV2/vaultOracle/base.sol";
import { VaultT1Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol";
import { VaultT2Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT2Oracle.sol";
import { VaultT3Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT3Oracle.sol";
import { VaultT4Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT4Oracle.sol";
import { VaultT1OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT1OracleLogic.sol";
import { VaultT2OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT2OracleLogic.sol";
import { VaultT3OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT3OracleLogic.sol";
import { VaultT4OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT4OracleLogic.sol";

/// @dev Minimal bytecode deploy via `FluidContractFactory` to advance `totalContracts` in nonce tests.
contract EmptyFactoryChild {

}

contract MockVaultFactory {
    mapping(address => bool) internal _isVault;
    mapping(uint256 => address) internal _vaultAtId;

    function setIsVault(address vault_, bool isVault_) external {
        _isVault[vault_] = isVault_;
    }

    function setVaultAtId(uint256 vaultId_, address vault_) external {
        _vaultAtId[vaultId_] = vault_;
    }

    function isVault(address vault_) external view returns (bool) {
        return _isVault[vault_];
    }

    function getVaultAddress(uint256 vaultId_) external view returns (address) {
        return _vaultAtId[vaultId_];
    }
}

contract MockVault {
    IFluidVault.ConstantViews internal _constantsView;

    constructor(IFluidVault.ConstantViews memory constantsView_) {
        _constantsView = constantsView_;
    }

    function TYPE() external view returns (uint256) {
        return _constantsView.vaultType;
    }

    function VAULT_ID() external view returns (uint256) {
        return _constantsView.vaultId;
    }

    function constantsView() external view returns (IFluidVault.ConstantViews memory constantsView_) {
        return _constantsView;
    }
}

/// @dev Mirrors legacy mainnet `FluidVaultT1`: `IFluidVaultT1` views only (no `IFluidVault.TYPE` / unified `constantsView`).
contract MockLegacyVaultT1 {
    IFluidVaultT1.ConstantViews internal _constantsView;

    constructor(IFluidVaultT1.ConstantViews memory constantsView_) {
        _constantsView = constantsView_;
    }

    function VAULT_ID() external view returns (uint256) {
        return _constantsView.vaultId;
    }

    function constantsView() external view returns (IFluidVaultT1.ConstantViews memory constantsView_) {
        return _constantsView;
    }
}

contract MockDex {
    IFluidDexT1.ConstantViews internal _constantsView;
    IFluidDexT1.ConstantViews2 internal _constantsView2;
    uint256 internal _upperRange;
    uint256 internal _lowerRange;

    constructor(IFluidDexT1.ConstantViews memory constantsView_, IFluidDexT1.ConstantViews2 memory constantsView2_) {
        _constantsView = constantsView_;
        _constantsView2 = constantsView2_;
    }

    function setPrices(uint256 upperRange_, uint256 lowerRange_) external {
        _upperRange = upperRange_;
        _lowerRange = lowerRange_;
    }

    function getPricesAndExchangePrices() external {
        revert IFluidDexT1.FluidDexPricesAndExchangeRates(
            IFluidDexT1.PricesAndExchangePrice({
                lastStoredPrice: 0,
                centerPrice: 0,
                upperRange: _upperRange,
                lowerRange: _lowerRange,
                geometricMean: 0,
                supplyToken0ExchangePrice: 0,
                borrowToken0ExchangePrice: 0,
                supplyToken1ExchangePrice: 0,
                borrowToken1ExchangePrice: 0
            })
        );
    }

    function constantsView() external view returns (IFluidDexT1.ConstantViews memory constantsView_) {
        return _constantsView;
    }

    function constantsView2() external view returns (IFluidDexT1.ConstantViews2 memory constantsView2_) {
        return _constantsView2;
    }
}

contract MockTokenMetadata {
    string internal _symbol;
    uint8 internal _decimals;

    constructor(string memory symbol_, uint8 decimals_) {
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/// @dev Minimal `IUSDOracle` for factory `isEmodeValid` checks (tests only).
contract MockUsdOracleAcceptsAllEmode {
    function isEmodeValid(uint256, address) external pure returns (bool) {
        return true;
    }
}

/// @dev Always rejects eMode (tests `VaultOracleFactory__InvalidEMode`).
contract MockUsdOracleRejectsAllEmode {
    function isEmodeValid(uint256, address) external pure returns (bool) {
        return false;
    }
}

/// @dev Configurable `isEmodeValid` response by (emode, token) pair.
contract MockUsdOracleSelective {
    mapping(bytes32 => bool) internal _valid;

    function setIsValid(uint256 emode_, address token_, bool valid_) external {
        _valid[keccak256(abi.encode(emode_, token_))] = valid_;
    }

    function isEmodeValid(uint256 emode_, address token_) external view returns (bool) {
        return _valid[keccak256(abi.encode(emode_, token_))];
    }
}

/// @dev Minimal Liquidity stand-in: governance address via `readFromStorage` at the canonical governance slot.
contract MockLiquidityGovernance {
    bytes32 internal constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address public governance;

    constructor(address governance_) {
        governance = governance_;
    }

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_) {
        if (slot_ == GOVERNANCE_SLOT) {
            return uint256(uint160(governance));
        }
        return 0;
    }

    function setGovernance(address governance_) external {
        governance = governance_;
    }
}

contract VaultOracleFactoryTest is Test {
    /// @dev Standard DEX share peg buffers used across these tests: 0.1% operate, 0.02% liquidate.
    uint256 internal constant PEG_BUF_OP = 1000;
    uint256 internal constant PEG_BUF_LIQ = 200;

    struct ExpectedOracleConfig {
        address usdOracle;
        address supplyToken0;
        address supplyToken1;
        address borrowToken0;
        address borrowToken1;
        address supplyDexPool;
        address borrowDexPool;
        uint256 supplyEMode;
        uint256 borrowEMode;
    }

    event LogVaultOracleRegistered(
        address indexed vault,
        address indexed vaultOracle,
        uint256 vaultType,
        uint256 indexed vaultId,
        uint256 deployNonce
    );
    event LogVaultOracleDeployerSet(address indexed vaultOracleDeployer, bool allowed);

    uint256 internal constant VAULT_T1_TYPE = 10000;
    uint256 internal constant VAULT_T2_TYPE = 20000;
    uint256 internal constant VAULT_T3_TYPE = 30000;
    uint256 internal constant VAULT_T4_TYPE = 40000;

    MockUsdOracleAcceptsAllEmode internal usdOracle;

    MockVaultFactory internal vaultFactoryMock;
    MockLiquidityGovernance internal liquidityMock;
    VaultOracleFactory internal factory;
    address internal fluidContractFactory;

    MockTokenMetadata internal wstEth;
    MockTokenMetadata internal usdc;
    MockTokenMetadata internal usdt;

    uint256 internal vaultIdSeq;

    address internal t1OracleLogic;
    address internal t2OracleLogic;
    address internal t3OracleLogic;
    address internal t4OracleLogic;

    /// @dev Deploys a factory impl with the shared per-type oracle deployment logics.
    function _newFactoryImpl(
        address liquidity_,
        address usdOracle_,
        address vaultFactory_,
        address deployerFactory_
    ) internal returns (VaultOracleFactory) {
        return
            new VaultOracleFactory(
                liquidity_,
                usdOracle_,
                vaultFactory_,
                deployerFactory_,
                t1OracleLogic,
                t2OracleLogic,
                t3OracleLogic,
                t4OracleLogic
            );
    }

    function setUp() public {
        usdOracle = new MockUsdOracleAcceptsAllEmode();
        vaultFactoryMock = new MockVaultFactory();
        liquidityMock = new MockLiquidityGovernance(address(this));
        fluidContractFactory = address(new FluidContractFactory(address(this)));
        t1OracleLogic = address(new VaultT1OracleDeploymentLogic());
        t2OracleLogic = address(new VaultT2OracleDeploymentLogic());
        t3OracleLogic = address(new VaultT3OracleDeploymentLogic());
        t4OracleLogic = address(new VaultT4OracleDeploymentLogic());
        VaultOracleFactory impl_ = _newFactoryImpl(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        factory = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
        FluidContractFactory(fluidContractFactory).updateDeployer(address(factory), 10_000);

        wstEth = new MockTokenMetadata("wstETH", 18);
        usdc = new MockTokenMetadata("USDC", 6);
        usdt = new MockTokenMetadata("USDT", 6);
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        _newFactoryImpl(address(0), address(usdOracle), address(vaultFactoryMock), fluidContractFactory);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        _newFactoryImpl(address(liquidityMock), address(0), address(vaultFactoryMock), fluidContractFactory);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        _newFactoryImpl(address(liquidityMock), address(usdOracle), address(0), fluidContractFactory);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        _newFactoryImpl(address(liquidityMock), address(usdOracle), address(vaultFactoryMock), address(0));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        new VaultOracleFactory(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory,
            address(0),
            t2OracleLogic,
            t3OracleLogic,
            t4OracleLogic
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        new VaultOracleFactory(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory,
            t1OracleLogic,
            address(0),
            t3OracleLogic,
            t4OracleLogic
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        new VaultOracleFactory(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory,
            t1OracleLogic,
            t2OracleLogic,
            address(0),
            t4OracleLogic
        );

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        new VaultOracleFactory(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory,
            t1OracleLogic,
            t2OracleLogic,
            t3OracleLogic,
            address(0)
        );
    }

    function test_registerVault_revertsForInvalidVault() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__InvalidVault)
        );
        factory.registerVault(999_999, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsForUnsupportedType() public {
        IFluidVault.ConstantViews memory constantsView_;
        constantsView_.supplyToken = IFluidVault.Tokens({ token0: address(wstEth), token1: address(0) });
        constantsView_.borrowToken = IFluidVault.Tokens({ token0: address(usdc), token1: address(0) });
        constantsView_.vaultType = 123456;
        constantsView_.deployer = fluidContractFactory;
        constantsView_.vaultId = _nextVaultId();

        address vault = _deployVault(constantsView_);
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__UnsupportedType)
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsWhenAlreadyRegistered() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__AlreadyRegistered
            )
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsOnDeployerMismatch_t234() public {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        IFluidVault.ConstantViews memory c_ = _t2Constants(
            address(dex),
            address(usdc),
            address(wstEth),
            address(usdc),
            _nextVaultId()
        );
        c_.deployer = makeAddr("wrongDeployer");
        address vault = _deployVault(c_);
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__DeployerMismatch
            )
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_deploysT1OracleViaDeployerFactory() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        uint256 tBefore_ = IFluidContractFactory(fluidContractFactory).totalContracts();
        address expectedOracle = _expectedNextFluidFactoryOracle();
        uint256 expectedNonce_ = tBefore_ + 1;

        vm.expectEmit(true, true, true, true);
        emit LogVaultOracleRegistered(vault, expectedOracle, VAULT_T1_TYPE, vaultId_, expectedNonce_);

        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        assertEq(oracle, expectedOracle);
        assertEq(IFluidContractFactory(fluidContractFactory).totalContracts(), tBefore_ + 1);
        assertEq(factory.vaultIdToOracleDeployNonce(vaultId_), expectedNonce_);
        assertEq(
            IFluidContractFactory(fluidContractFactory).getContractAddress(
                factory.vaultIdToOracleDeployNonce(vaultId_)
            ),
            oracle
        );
        (address v_, uint256 oracleNonce_, address o_) = factory.getVaultOracleDeployment(vaultId_);
        assertEq(v_, vault);
        assertEq(oracleNonce_, expectedNonce_);
        assertEq(o_, oracle);
        _assertOracleConfig(
            oracle,
            ExpectedOracleConfig({
                usdOracle: address(usdOracle),
                supplyToken0: address(wstEth),
                supplyToken1: address(0),
                borrowToken0: address(usdc),
                borrowToken1: address(0),
                supplyDexPool: address(0),
                borrowDexPool: address(0),
                supplyEMode: 0,
                borrowEMode: 0
            })
        );
        assertEq(VaultT1Oracle(oracle).infoName(), "USDC / 1 wstETH");
        assertEq(VaultT1Oracle(oracle).targetDecimals(), 15);
    }

    function test_registerVault_deploysT2OracleAndCachesDexParams() public {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        DexShareResolver.DexParams memory dexParams_ = _dexParams(address(dex), address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        uint256 tBefore_ = IFluidContractFactory(fluidContractFactory).totalContracts();

        address expectedOracle = _expectedNextFluidFactoryOracle();
        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        assertEq(IFluidContractFactory(fluidContractFactory).totalContracts(), tBefore_ + 1);
        assertEq(factory.vaultIdToOracleDeployNonce(vaultId_), tBefore_ + 1);
        assertEq(oracle, expectedOracle);
        assertEq(
            IFluidContractFactory(fluidContractFactory).getContractAddress(
                factory.vaultIdToOracleDeployNonce(vaultId_)
            ),
            oracle
        );
        _assertOracleConfig(
            oracle,
            ExpectedOracleConfig({
                usdOracle: address(usdOracle),
                supplyToken0: address(wstEth),
                supplyToken1: address(usdc),
                borrowToken0: address(usdc),
                borrowToken1: address(0),
                supplyDexPool: address(dex),
                borrowDexPool: address(0),
                supplyEMode: 0,
                borrowEMode: 0
            })
        );
        assertEq(VaultT2Oracle(oracle).targetDecimals(), 15);
    }

    function test_registerVault_deploysT3OracleAndCachesDexParams() public {
        MockDex dex = _deployDex(address(usdc), address(usdt));
        address vault = _deployVault(
            _t3Constants(address(wstEth), address(dex), address(usdc), address(usdt), _nextVaultId())
        );
        DexShareResolver.DexParams memory dexParams_ = _dexParams(address(dex), address(usdc), address(usdt));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        uint256 tBefore_ = IFluidContractFactory(fluidContractFactory).totalContracts();

        address expectedOracle = _expectedNextFluidFactoryOracle();
        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        assertEq(IFluidContractFactory(fluidContractFactory).totalContracts(), tBefore_ + 1);
        assertEq(factory.vaultIdToOracleDeployNonce(vaultId_), tBefore_ + 1);
        assertEq(oracle, expectedOracle);
        _assertOracleConfig(
            oracle,
            ExpectedOracleConfig({
                usdOracle: address(usdOracle),
                supplyToken0: address(wstEth),
                supplyToken1: address(0),
                borrowToken0: address(usdc),
                borrowToken1: address(usdt),
                supplyDexPool: address(0),
                borrowDexPool: address(dex),
                supplyEMode: 0,
                borrowEMode: 0
            })
        );
        assertEq(VaultT3Oracle(oracle).targetDecimals(), 27);
    }

    function test_registerVault_deploysT4OracleAndCachesBothDexSides() public {
        MockDex colDex = _deployDex(address(wstEth), address(usdc));
        MockDex debtDex = _deployDex(address(usdc), address(usdt));
        address vault = _deployVault(
            _t4Constants(
                address(colDex),
                address(debtDex),
                address(wstEth),
                address(usdc),
                address(usdt),
                _nextVaultId()
            )
        );
        DexShareResolver.DexParams memory colDexParams_ = _dexParams(address(colDex), address(wstEth), address(usdc));
        DexShareResolver.DexParams memory debtDexParams_ = _dexParams(address(debtDex), address(usdc), address(usdt));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        uint256 tBefore_ = IFluidContractFactory(fluidContractFactory).totalContracts();

        address expectedOracle = _expectedNextFluidFactoryOracle();
        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        assertEq(IFluidContractFactory(fluidContractFactory).totalContracts(), tBefore_ + 1);
        assertEq(factory.vaultIdToOracleDeployNonce(vaultId_), tBefore_ + 1);
        assertEq(oracle, expectedOracle);
        _assertOracleConfig(
            oracle,
            ExpectedOracleConfig({
                usdOracle: address(usdOracle),
                supplyToken0: address(wstEth),
                supplyToken1: address(usdc),
                borrowToken0: address(usdc),
                borrowToken1: address(usdt),
                supplyDexPool: address(colDex),
                borrowDexPool: address(debtDex),
                supplyEMode: 0,
                borrowEMode: 0
            })
        );
        assertEq(VaultT4Oracle(oracle).targetDecimals(), 27);
    }

    function test_getVaultOracleDeployment_revertsWhenNotRegistered() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__NotRegistered)
        );
        factory.getVaultOracleDeployment(999_999);
    }

    function test_registerVault_revertsWhenVaultIdZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__VaultIdZero)
        );
        factory.registerVault(0, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsUnauthorized() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__Unauthorized)
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_succeedsForAllowlistedDeployer() public {
        address deployer_ = makeAddr("oracleDeployer");
        factory.setVaultOracleDeployer(deployer_, true);
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        vm.prank(deployer_);
        address oracle_ = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        assertTrue(oracle_ != address(0));
    }

    function test_registerVault_teamMultisig_maySetDeployer() public {
        address deployer_ = makeAddr("oracleDeployerB");
        vm.prank(factory.TEAM_MULTISIG());
        factory.setVaultOracleDeployer(deployer_, true);
        assertTrue(factory.vaultOracleDeployer(deployer_));
    }

    function test_setVaultOracleDeployer_revertsOnZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__AddressZero)
        );
        factory.setVaultOracleDeployer(address(0), true);
    }

    function test_setVaultOracleDeployer_revertsForUnauthorized() public {
        vm.prank(makeAddr("notAllowed"));
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__Unauthorized)
        );
        factory.setVaultOracleDeployer(makeAddr("oracleDeployerC"), true);
    }

    function test_setVaultOracleDeployer_governanceMaySetDeployer() public {
        address deployer_ = makeAddr("oracleDeployerGov");
        factory.setVaultOracleDeployer(deployer_, true);
        assertTrue(factory.vaultOracleDeployer(deployer_));
    }

    function test_setVaultOracleDeployer_emitsEvent() public {
        address deployer_ = makeAddr("oracleDeployerEvent");
        vm.expectEmit(true, true, true, true);
        emit LogVaultOracleDeployerSet(deployer_, true);
        factory.setVaultOracleDeployer(deployer_, true);
    }

    function test_registerVault_teamMultisigMayRegister() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        vm.prank(factory.TEAM_MULTISIG());
        address oracle_ = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        assertTrue(oracle_ != address(0));
    }

    function test_registerVault_revertsInvalidEMode() public {
        MockUsdOracleRejectsAllEmode badUsd_ = new MockUsdOracleRejectsAllEmode();
        VaultOracleFactory impl_ = _newFactoryImpl(
            address(liquidityMock),
            address(badUsd_),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        VaultOracleFactory fBad_ = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
        FluidContractFactory(fluidContractFactory).updateDeployer(address(fBad_), 10_000);

        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__InvalidEMode)
        );
        fBad_.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsInvalidEMode_whenSupplyValidBorrowInvalid() public {
        MockUsdOracleSelective selective_ = new MockUsdOracleSelective();
        selective_.setIsValid(11, address(wstEth), true);
        selective_.setIsValid(22, address(usdc), false);

        VaultOracleFactory impl_ = _newFactoryImpl(
            address(liquidityMock),
            address(selective_),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        VaultOracleFactory fSelective_ = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
        FluidContractFactory(fluidContractFactory).updateDeployer(address(fSelective_), 10_000);

        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__InvalidEMode)
        );
        fSelective_.registerVault(vaultId_, 11, 22, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsInvalidEMode_whenBorrowValidSupplyInvalid() public {
        MockUsdOracleSelective selective_ = new MockUsdOracleSelective();
        selective_.setIsValid(11, address(wstEth), false);
        selective_.setIsValid(22, address(usdc), true);

        VaultOracleFactory impl_ = _newFactoryImpl(
            address(liquidityMock),
            address(selective_),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        VaultOracleFactory fSelective_ = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
        FluidContractFactory(fluidContractFactory).updateDeployer(address(fSelective_), 10_000);

        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__InvalidEMode)
        );
        fSelective_.registerVault(vaultId_, 11, 22, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsDexIsNotPeg_t2() public {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        dex.setPrices(2e27, 1e27);
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__DexIsNotPeg)
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsDexIsNotPeg_t3() public {
        MockDex dex = _deployDex(address(usdc), address(usdt));
        dex.setPrices(2e27, 1e27);
        address vault = _deployVault(
            _t3Constants(address(wstEth), address(dex), address(usdc), address(usdt), _nextVaultId())
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__DexIsNotPeg)
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsDexIsNotPeg_t4() public {
        MockDex colDex = _deployDex(address(wstEth), address(usdc));
        MockDex debtDex = _deployDex(address(usdc), address(usdt));
        debtDex.setPrices(2e27, 1e27);
        address vault = _deployVault(
            _t4Constants(
                address(colDex),
                address(debtDex),
                address(wstEth),
                address(usdc),
                address(usdt),
                _nextVaultId()
            )
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__DexIsNotPeg)
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsDexPriceReadFailed_uninitializedDex() public {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        dex.setPrices(0, 0);
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__DexPriceReadFailed
            )
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    function test_registerVault_succeedsWithTightDexBand_t2() public {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        dex.setPrices(1.01e27, 0.99e27);
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        assertTrue(oracle != address(0));
    }

    function test_registerVault_revertsWhenPegBufferAboveMax_t2() public {
        uint256 vaultId_ = _tightBandT2VaultId();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__InvalidPegBuffer
            )
        );
        factory.registerVault(vaultId_, 0, 0, 10_001, PEG_BUF_LIQ);
    }

    function test_registerVault_revertsWhenLiquidateBufferExceedsOperate_t2() public {
        uint256 vaultId_ = _tightBandT2VaultId();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__InvalidPegBuffer
            )
        );
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_LIQ, PEG_BUF_OP);
    }

    function test_registerVault_acceptsEqualOperateAndLiquidateBuffers_t2() public {
        uint256 vaultId_ = _tightBandT2VaultId();

        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_OP);
        assertTrue(oracle != address(0));
    }

    /// @dev `MAX_PEG_BUFFER_PPM` itself (1%) is inclusive.
    function test_registerVault_acceptsMaxPegBuffer_t2() public {
        uint256 vaultId_ = _tightBandT2VaultId();

        address oracle = factory.registerVault(vaultId_, 0, 0, 10_000, PEG_BUF_LIQ);
        assertTrue(oracle != address(0));
    }

    /// @dev T1 has no DEX share leg, but the bounds are still enforced so callers cannot pass junk.
    function test_registerVault_validatesPegBuffersForT1Too() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultOracleError.selector,
                ErrorTypes.VaultOracleFactory__InvalidPegBuffer
            )
        );
        factory.registerVault(vaultId_, 0, 0, 999_999, 999_999);
    }

    function _tightBandT2VaultId() internal returns (uint256) {
        MockDex dex = _deployDex(address(wstEth), address(usdc));
        dex.setPrices(1.01e27, 0.99e27);
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        return IFluidVault(vault).VAULT_ID();
    }

    function test_registerVault_eModeValidation_usesToken1Fallback() public {
        MockUsdOracleSelective selective_ = new MockUsdOracleSelective();
        selective_.setIsValid(11, address(wstEth), false);
        selective_.setIsValid(11, address(usdc), true);
        selective_.setIsValid(22, address(usdc), true);

        VaultOracleFactory impl_ = _newFactoryImpl(
            address(liquidityMock),
            address(selective_),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        VaultOracleFactory fSelective_ = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
        FluidContractFactory(fluidContractFactory).updateDeployer(address(fSelective_), 10_000);

        MockDex dex = _deployDex(address(wstEth), address(usdc));
        address vault = _deployVault(
            _t2Constants(address(dex), address(usdc), address(wstEth), address(usdc), _nextVaultId())
        );
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();

        address oracle_ = fSelective_.registerVault(vaultId_, 11, 22, PEG_BUF_OP, PEG_BUF_LIQ);
        assertTrue(oracle_ != address(0));
    }

    function test_registerVaultForce_redeploysAndUpdatesNonce() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        address firstOracle_ = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        uint256 nonceAfterFirst_ = factory.vaultIdToOracleDeployNonce(vaultId_);

        address secondOracle_ = factory.registerVaultForce(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        assertNotEq(firstOracle_, secondOracle_);
        assertEq(
            factory.vaultIdToOracleDeployNonce(vaultId_),
            IFluidContractFactory(fluidContractFactory).totalContracts()
        );
        assertGt(factory.vaultIdToOracleDeployNonce(vaultId_), nonceAfterFirst_);
        assertEq(
            secondOracle_,
            IFluidContractFactory(fluidContractFactory).getContractAddress(factory.vaultIdToOracleDeployNonce(vaultId_))
        );
    }

    function test_registerVaultForce_revertsForNonGovernance() public {
        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
        vm.prank(factory.TEAM_MULTISIG());
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__Unauthorized)
        );
        factory.registerVaultForce(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);
    }

    /// @dev Owner deploys another contract on the same `FluidContractFactory` first; oracle nonce must still match `totalContracts` after registration.
    function test_registerVault_nonceMatchesAfterUnrelatedFactoryDeploy() public {
        FluidContractFactory f = FluidContractFactory(fluidContractFactory);
        uint256 t0 = f.totalContracts();
        f.deployContract(abi.encodePacked(type(EmptyFactoryChild).creationCode));
        assertEq(f.totalContracts(), t0 + 1);

        address vault = _deployLegacyT1Vault(address(wstEth), address(usdc));
        uint256 vaultId_ = IFluidVault(vault).VAULT_ID();
        uint256 tBeforeOracle_ = f.totalContracts();

        address oracle = factory.registerVault(vaultId_, 0, 0, PEG_BUF_OP, PEG_BUF_LIQ);

        assertEq(f.totalContracts(), tBeforeOracle_ + 1);
        assertEq(factory.vaultIdToOracleDeployNonce(vaultId_), tBeforeOracle_ + 1);
        assertEq(f.getContractAddress(factory.vaultIdToOracleDeployNonce(vaultId_)), oracle);
        (address v_, uint256 oracleNonce_, address o_) = factory.getVaultOracleDeployment(vaultId_);
        assertEq(v_, vault);
        assertEq(oracleNonce_, tBeforeOracle_ + 1);
        assertEq(o_, oracle);
    }

    function test_upgradeToAndCall_revertsForUnauthorizedCaller() public {
        VaultOracleFactory newImpl_ = _newFactoryImpl(
            address(liquidityMock),
            address(usdOracle),
            address(vaultFactoryMock),
            fluidContractFactory
        );
        address attacker_ = makeAddr("attacker");

        vm.prank(attacker_);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultOracleError.selector, ErrorTypes.VaultOracleFactory__Unauthorized)
        );
        factory.upgradeToAndCall(address(newImpl_), "");
    }

    function _nextVaultId() internal returns (uint256 id_) {
        id_ = ++vaultIdSeq;
    }

    function _deployVault(IFluidVault.ConstantViews memory constantsView_) internal returns (address vault_) {
        vault_ = address(new MockVault(constantsView_));
        vaultFactoryMock.setIsVault(vault_, true);
        vaultFactoryMock.setVaultAtId(constantsView_.vaultId, vault_);
    }

    function _legacyT1Constants(
        address supplyToken_,
        address borrowToken_,
        uint256 vaultId_
    ) internal pure returns (IFluidVaultT1.ConstantViews memory c_) {
        c_.supplyToken = supplyToken_;
        c_.borrowToken = borrowToken_;
        c_.vaultId = vaultId_;
    }

    function _deployLegacyT1Vault(address supplyToken_, address borrowToken_) internal returns (address vault_) {
        uint256 vid_ = _nextVaultId();
        vault_ = address(new MockLegacyVaultT1(_legacyT1Constants(supplyToken_, borrowToken_, vid_)));
        vaultFactoryMock.setIsVault(vault_, true);
        vaultFactoryMock.setVaultAtId(vid_, vault_);
    }

    function _deployDex(address token0_, address token1_) internal returns (MockDex dex_) {
        dex_ = new MockDex(
            IFluidDexT1.ConstantViews({
                dexId: 1,
                liquidity: address(0),
                factory: address(0),
                implementations: IFluidDexT1.Implementations(
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0)
                ),
                deployerContract: address(0),
                token0: token0_,
                token1: token1_,
                supplyToken0Slot: bytes32(uint256(11)),
                borrowToken0Slot: bytes32(uint256(22)),
                supplyToken1Slot: bytes32(uint256(33)),
                borrowToken1Slot: bytes32(uint256(44)),
                exchangePriceToken0Slot: bytes32(uint256(55)),
                exchangePriceToken1Slot: bytes32(uint256(66)),
                oracleMapping: 0
            }),
            IFluidDexT1.ConstantViews2({
                token0NumeratorPrecision: 1e12,
                token0DenominatorPrecision: 1e8,
                token1NumeratorPrecision: 1e12,
                token1DenominatorPrecision: 1e6
            })
        );
        dex_.setPrices(1.01e27, 0.99e27);
    }

    function _t2Constants(
        address supplyDex_,
        address borrowToken_,
        address token0_,
        address token1_,
        uint256 vaultId_
    ) internal view returns (IFluidVault.ConstantViews memory c_) {
        c_.supply = supplyDex_;
        c_.borrowToken = IFluidVault.Tokens({ token0: borrowToken_, token1: address(0) });
        c_.supplyToken = IFluidVault.Tokens({ token0: token0_, token1: token1_ });
        c_.vaultType = VAULT_T2_TYPE;
        c_.deployer = fluidContractFactory;
        c_.vaultId = vaultId_;
    }

    function _t3Constants(
        address supplyToken_,
        address borrowDex_,
        address token0_,
        address token1_,
        uint256 vaultId_
    ) internal view returns (IFluidVault.ConstantViews memory c_) {
        c_.borrow = borrowDex_;
        c_.supplyToken = IFluidVault.Tokens({ token0: supplyToken_, token1: address(0) });
        c_.borrowToken = IFluidVault.Tokens({ token0: token0_, token1: token1_ });
        c_.vaultType = VAULT_T3_TYPE;
        c_.deployer = fluidContractFactory;
        c_.vaultId = vaultId_;
    }

    function _t4Constants(
        address supplyDex_,
        address borrowDex_,
        address colToken0_,
        address colToken1_,
        address debtToken1_,
        uint256 vaultId_
    ) internal view returns (IFluidVault.ConstantViews memory c_) {
        c_.supply = supplyDex_;
        c_.borrow = borrowDex_;
        c_.supplyToken = IFluidVault.Tokens({ token0: colToken0_, token1: colToken1_ });
        c_.borrowToken = IFluidVault.Tokens({ token0: colToken1_, token1: debtToken1_ });
        c_.vaultType = VAULT_T4_TYPE;
        c_.deployer = fluidContractFactory;
        c_.vaultId = vaultId_;
    }

    function _dexParams(
        address dexPool_,
        address token0_,
        address token1_
    ) internal pure returns (DexShareResolver.DexParams memory d_) {
        d_ = DexShareResolver.DexParams({
            dexPool: dexPool_,
            token0: token0_,
            token1: token1_,
            supplyToken0Slot: bytes32(uint256(11)),
            supplyToken1Slot: bytes32(uint256(33)),
            borrowToken0Slot: bytes32(uint256(22)),
            borrowToken1Slot: bytes32(uint256(44)),
            exchangePriceToken0Slot: bytes32(uint256(55)),
            exchangePriceToken1Slot: bytes32(uint256(66)),
            token0NumeratorPrecision: 1e12,
            token0DenominatorPrecision: 1e8,
            token1NumeratorPrecision: 1e12,
            token1DenominatorPrecision: 1e6
        });
    }

    /// @dev Next `FluidContractFactory.deployContract` uses nonce `totalContracts + 1` (see `getContractAddress`).
    function _expectedNextFluidFactoryOracle() internal view returns (address expected_) {
        uint256 nextNonce_ = IFluidContractFactory(fluidContractFactory).totalContracts() + 1;
        expected_ = IFluidContractFactory(fluidContractFactory).getContractAddress(nextNonce_);
    }

    function _assertOracleConfig(address oracle_, ExpectedOracleConfig memory exp_) internal view {
        (
            address usdOracle_,
            address supplyToken0_,
            address supplyToken1_,
            address borrowToken0_,
            address borrowToken1_,
            address supplyDexPool_,
            address borrowDexPool_,
            uint256 supplyEMode_,
            uint256 borrowEMode_
        ) = VaultOracleBase(oracle_).getOracleConfig();
        assertEq(usdOracle_, exp_.usdOracle);
        assertEq(supplyToken0_, exp_.supplyToken0);
        assertEq(supplyToken1_, exp_.supplyToken1);
        assertEq(borrowToken0_, exp_.borrowToken0);
        assertEq(borrowToken1_, exp_.borrowToken1);
        assertEq(supplyDexPool_, exp_.supplyDexPool);
        assertEq(borrowDexPool_, exp_.borrowDexPool);
        assertEq(supplyEMode_, exp_.supplyEMode);
        assertEq(borrowEMode_, exp_.borrowEMode);
    }
}
