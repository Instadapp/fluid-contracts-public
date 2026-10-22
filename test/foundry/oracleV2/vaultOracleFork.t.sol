// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { IFluidOracle } from "../../../contracts/oracleV2/interfaces/iFluidOracle.sol";
import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { Structs } from "../../../contracts/oracleV2/usdOracle/structs.sol";
import { FluidContractFactory } from "../../../contracts/deployer/main.sol";
import { IFluidContractFactory } from "../../../contracts/deployer/interface.sol";
import { IFluidVault } from "../../../contracts/protocols/vault/interfaces/iVault.sol";
import { VaultOracleFactory } from "../../../contracts/oracleV2/vaultOracle/factory/main.sol";
import { VaultOracleFactoryProxy } from "../../../contracts/oracleV2/vaultOracle/factory/proxy.sol";
import { VaultT1Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol";
import { VaultT1OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT1OracleLogic.sol";
import { VaultT2OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT2OracleLogic.sol";
import { VaultT3OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT3OracleLogic.sol";
import { VaultT4OracleDeploymentLogic } from "../../../contracts/oracleV2/vaultOracle/factory/deploymentLogics/vaultT4OracleLogic.sol";

interface IChainlinkAggregatorV3 {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IHasUsdOracle {
    function USD_ORACLE() external view returns (address);
}

interface IOnChainVaultResolver {
    function getVaultType(address vault_) external view returns (uint256 vaultType_);

    function getVaultVariables2Raw(address vault_) external view returns (uint256 vaultVariables2_);

    function getContractForDeployerIndex(address vault_, uint256 index_) external view returns (address);
}

interface IOwned {
    function owner() external view returns (address);
}

/// @dev Vault admin `updateOracle(address)` — delegate-called on legacy T1 proxies.
interface IVaultAdminT1 {
    function updateOracle(address newOracle_) external;
}

/// @dev Vault admin `updateOracle(uint nonce)` — delegate-called on unified T2–T4 proxies.
interface IVaultAdminT234 {
    function updateOracle(uint256 newOracleNonce_) external;
}

interface IWstEth {
    function stEthPerToken() external view returns (uint256);
}

interface IERC4626Like {
    function convertToAssets(uint256 shares_) external view returns (uint256);
}

interface IFluidOracleRate {
    function getExchangeRateOperate() external view returns (uint256);

    function getExchangeRateLiquidate() external view returns (uint256);
}

contract MockUsdOracleDetailed {
    struct PriceData {
        uint256 price;
        uint8 decimals;
        uint8 tokenType;
    }

    mapping(bytes32 => PriceData) internal _prices;

    function setPrice(
        address token_,
        bool isOperate_,
        bool isCollateral_,
        uint256 price_,
        uint8 decimals_,
        uint8 tokenType_
    ) external {
        _prices[keccak256(abi.encode(token_, isOperate_, isCollateral_))] = PriceData(price_, decimals_, tokenType_);
    }

    function getPriceDetailedView(
        address token_,
        uint256,
        bool isOperate_,
        bool isCollateral_
    ) public view returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        PriceData memory data_ = _prices[keccak256(abi.encode(token_, isOperate_, isCollateral_))];
        return (data_.price, data_.decimals, data_.tokenType);
    }

    function getPriceDetailedViewRaw(
        address token_,
        uint256 emode_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_, uint8 decimals_, uint8 tokenType_) {
        return getPriceDetailedView(token_, emode_, isOperate_, isCollateral_);
    }

    function isEmodeValid(uint256, address) external pure returns (bool) {
        return true;
    }
}

contract MockReadFromStorage {
    mapping(bytes32 => uint256) public storageValues;

    function readFromStorage(bytes32 slot_) external view returns (uint256) {
        return storageValues[slot_];
    }

    function setStorage(bytes32 slot_, uint256 value_) external {
        storageValues[slot_] = value_;
    }
}

contract MockChainlinkFeed is IChainlinkAggregatorV3 {
    IChainlinkAggregatorV3 internal immutable _referenceFeed;
    int256 internal _exchangeRate;

    constructor(IChainlinkAggregatorV3 referenceFeed_) {
        _referenceFeed = referenceFeed_;
        (, int256 exchangeRate_, , , ) = referenceFeed_.latestRoundData();
        _exchangeRate = exchangeRate_;
    }

    function setExchangeRate(int256 exchangeRate_) external {
        _exchangeRate = exchangeRate_;
    }

    function decimals() external view returns (uint8) {
        return _referenceFeed.decimals();
    }

    function description() external view returns (string memory) {
        return _referenceFeed.description();
    }

    function version() external view returns (uint256) {
        return _referenceFeed.version();
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return _referenceFeed.getRoundData(roundId_);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint80 roundId_, , uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_) = _referenceFeed
            .latestRoundData();
        return (roundId_, _exchangeRate, startedAt_, updatedAt_, answeredInRound_);
    }
}

contract MockCappedRate {
    uint256 public centerPriceValue = 1e27;
    uint256 public operateValue = 1e27;
    uint256 public operateDebtValue = 1e27;
    uint256 public liquidateValue = 1e27;
    uint256 public liquidateDebtValue = 1e27;

    function setRates(
        uint256 centerPriceValue_,
        uint256 operateValue_,
        uint256 operateDebtValue_,
        uint256 liquidateValue_,
        uint256 liquidateDebtValue_
    ) external {
        centerPriceValue = centerPriceValue_;
        operateValue = operateValue_;
        operateDebtValue = operateDebtValue_;
        liquidateValue = liquidateValue_;
        liquidateDebtValue = liquidateDebtValue_;
    }

    function centerPrice() external view returns (uint256) {
        return centerPriceValue;
    }

    function getExchangeRate() external view returns (uint256) {
        return operateValue;
    }

    function getExchangeRateOperate() external view returns (uint256) {
        return operateValue;
    }

    function getExchangeRateOperateDebt() external view returns (uint256) {
        return operateDebtValue;
    }

    function getExchangeRateLiquidate() external view returns (uint256) {
        return liquidateValue;
    }

    function getExchangeRateLiquidateDebt() external view returns (uint256) {
        return liquidateDebtValue;
    }
}

contract VaultOracleForkTest is Test, Structs {
    uint256 internal constant VAULT_T1_TYPE = 10_000;
    uint256 internal constant X30 = 0x3fffffff;

    uint8 internal constant SOURCE_NOT_SET = 0;
    uint8 internal constant SOURCE_CAPPED_RATE = 1;
    uint8 internal constant SOURCE_CHAINLINK = 2;
    uint8 internal constant SOURCE_STABLE = 3;
    uint8 internal constant SOURCE_REDSTONE = 4;
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;

    uint8 internal constant PRICE_MODE_MARKET = 1;
    uint8 internal constant PRICE_MODE_PEG = 2;

    uint8 internal constant OVERALL_CAP_MAX_OPERAND = 4;

    uint8 internal constant TOKEN_TYPE_PEG = 1;
    uint8 internal constant TOKEN_TYPE_STABLE = 2;
    uint8 internal constant TOKEN_TYPE_VOLATILE = 3;

    uint8 internal constant BUFFERED_LEG_COLLATERAL = 1;
    uint8 internal constant BUFFERED_LEG_DEBT = 2;
    uint8 internal constant BUFFERED_LEGS_BOTH = 3;

    uint256 internal constant PEG_BUFFER_SCALE = 1e6;
    /// @dev Buffers the V2 oracles under test are registered with: 0.1% operate, 0.02% liquidate.
    ///      Operate matches the legacy 0.1% used by the tight peg pools, so parity there is exact.
    uint256 internal constant V2_PEG_BUFFER_PPM_OPERATE = 1000;
    uint256 internal constant V2_PEG_BUFFER_PPM_LIQUIDATE = 200;
    uint256 internal constant LEGACY_PEG_BUFFER_PPM_T2_WBTC_CBBTC_USDC = 5000;
    uint256 internal constant LEGACY_PEG_BUFFER_PPM_T3_WSTETH_USDC_USDT = 1000;
    uint256 internal constant LEGACY_PEG_BUFFER_PPM_T4 = 1000;
    uint256 internal constant LEGACY_COL_PEG_BUFFER_T4_WSTUSR = 5000;
    uint256 internal constant LEGACY_DEBT_PEG_BUFFER_T4_WSTUSR = 1000;

    address internal constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;
    address internal constant VAULT_RESOLVER = 0xA5C3E16523eeeDDcC34706b0E6bE88b4c6EA95cC;
    /// @dev Same `FluidContractFactory` as `vault.constantsView().deployer` on T2–T4 (see deployments).
    address internal constant DEPLOYER_FACTORY = 0x4EC7b668BAF70d4A4b0FC7941a7708A07b6d45Be;

    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WSTUSR = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;
    address internal constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant VAULT_T1_WBTC_GHO = 0xe58Ed61ff0C9db46c8772FF7286B6B187D4fe68f;
    address internal constant VAULT_T2_WBTC_CBBTC_USDC = 0x4e564A29c1FC18ed9b66e5754A37fCa0C8a980ff;
    address internal constant VAULT_T3_WSTETH_USDC_USDT = 0x221E35b5655A1eEB3C42c4DeFc39648531f6C9CF;
    address internal constant VAULT_T4_WSTETH_ETH_WSTETH_ETH = 0x528CF7DBBff878e02e48E83De5097F8071af768D;
    address internal constant VAULT_T4_USDE_USDT_USDC_USDT = 0xaEac94D417BF8d8bb3A44507100Ab8c0D3b12cA1;
    address internal constant VAULT_T4_WSTUSR_USDC_USDC_USDT = 0xecB05340b48688275A3Cc8ab1314f6478C666587;

    IChainlinkAggregatorV3 internal constant CHAINLINK_REFERENCE_FEED =
        IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    IChainlinkAggregatorV3 internal constant CHAINLINK_WBTC_BTC =
        IChainlinkAggregatorV3(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    IChainlinkAggregatorV3 internal constant CHAINLINK_BTC_USD =
        IChainlinkAggregatorV3(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    IChainlinkAggregatorV3 internal constant CHAINLINK_ETH_USD =
        IChainlinkAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IChainlinkAggregatorV3 internal constant CHAINLINK_GHO_USD =
        IChainlinkAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
    IChainlinkAggregatorV3 internal constant CHAINLINK_USDC_USD =
        IChainlinkAggregatorV3(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    IChainlinkAggregatorV3 internal constant CHAINLINK_USDT_USD =
        IChainlinkAggregatorV3(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);
    IChainlinkAggregatorV3 internal constant CHAINLINK_USDE_USD =
        IChainlinkAggregatorV3(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    IChainlinkAggregatorV3 internal constant CHAINLINK_STETH_ETH =
        IChainlinkAggregatorV3(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    IChainlinkAggregatorV3 internal constant CHAINLINK_STETH_USD =
        IChainlinkAggregatorV3(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);

    IFluidOracleRate internal constant WSTUSR_CAPPED_RATE =
        IFluidOracleRate(0x1FC9a029e8e84cF0C5c7c68221bE5d1573c0FB05);

    bytes32 internal constant LIQUIDITY_GOVERNANCE_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint256 internal constant FORK_BLOCK = 24830000;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), FORK_BLOCK);
    }

    /// @dev A fresh `registerVault` uses the next `FluidContractFactory` nonce; mainnet vaults already point at an
    ///      oracle chosen earlier (T2–T4: nonce index). This fork test asserts T2–T4 only; T1 (including legacy
    ///      `IFluidVaultT1` layout) is covered in `VaultOracleFactoryTest`.
    function test_mainnetFork_factoryOracleAddress_differsFromVaultWiredOracle_t234() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        _forkAssertFactoryOracleDiffersFromWiredT2(usdOracle_);
        _forkAssertFactoryOracleDiffersFromWiredT3(usdOracle_);
        _forkAssertFactoryOracleDiffersFromWiredT4(usdOracle_);
    }

    /// @dev Registers a new oracle via the factory, then `updateOracle(address)` on legacy T1. Vault factory owner is global auth.
    function test_mainnetFork_registerThenUpdateOracle_t1_wbtcGho() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();

        uint256 wbtcPriceUsd_ = _readChainlinkComposedPrice(CHAINLINK_WBTC_BTC, CHAINLINK_BTC_USD);
        uint256 ghoPriceUsd_ = _readChainlinkPrice(CHAINLINK_GHO_USD);
        _setMockPrice(usdOracle_, WBTC, wbtcPriceUsd_, wbtcPriceUsd_, 8);
        _setMockPrice(usdOracle_, GHO, ghoPriceUsd_, ghoPriceUsd_, 18);

        VaultOracleFactory factory_ = _newVaultOracleFactory(address(usdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(factory_));
        uint256 vaultIdT1_ = IFluidVault(VAULT_T1_WBTC_GHO).VAULT_ID();
        address newOracle_ = _registerVaultAsGov(factory_, vaultIdT1_, 0);

        vm.prank(IOwned(VAULT_FACTORY).owner());
        IVaultAdminT1(VAULT_T1_WBTC_GHO).updateOracle(newOracle_);

        assertEq(_currentVaultOracle(VAULT_T1_WBTC_GHO), newOracle_);
    }

    /// @dev Registers via factory, then `updateOracle(nonce)` where nonce is `FluidContractFactory.totalContracts` after deploy.
    function test_mainnetFork_registerThenUpdateOracle_t2_wbtcCbBtcUsdc() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();

        uint256 btcPriceUsd_ = _readChainlinkPrice(CHAINLINK_BTC_USD);
        uint256 usdcPriceUsd_ = _readChainlinkPrice(CHAINLINK_USDC_USD);
        _setMockPrice(usdOracle_, WBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, CBBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, USDC, usdcPriceUsd_, usdcPriceUsd_, 6);

        VaultOracleFactory factory_ = _newVaultOracleFactory(address(usdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(factory_));
        uint256 vaultIdT2_ = IFluidVault(VAULT_T2_WBTC_CBBTC_USDC).VAULT_ID();
        address newOracle_ = _registerVaultAsGov(factory_, vaultIdT2_, 0);

        uint256 oracleNonce_ = IFluidContractFactory(DEPLOYER_FACTORY).totalContracts();
        assertEq(IFluidContractFactory(DEPLOYER_FACTORY).getContractAddress(oracleNonce_), newOracle_);

        vm.prank(IOwned(VAULT_FACTORY).owner());
        IVaultAdminT234(VAULT_T2_WBTC_CBBTC_USDC).updateOracle(oracleNonce_);

        assertEq(_currentVaultOracle(VAULT_T2_WBTC_CBBTC_USDC), newOracle_);
    }

    function test_mainnetFork_registerThenUpdateOracle_t3_wstEthUsdcUsdt() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();

        uint256 stethUsdPrice_ = _readChainlinkPrice(CHAINLINK_STETH_USD);
        uint256 wstEthPriceUsd_ = (stethUsdPrice_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        uint256 oneUsd_ = 1e27;
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsd_, wstEthPriceUsd_, 18);
        _setMockPrice(usdOracle_, USDC, oneUsd_, oneUsd_, 6);
        _setMockPrice(usdOracle_, USDT, oneUsd_, oneUsd_, 6);

        VaultOracleFactory factory_ = _newVaultOracleFactory(address(usdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(factory_));
        uint256 vaultIdT3_ = IFluidVault(VAULT_T3_WSTETH_USDC_USDT).VAULT_ID();
        address newOracle_ = _registerVaultAsGov(factory_, vaultIdT3_, 0);

        uint256 oracleNonce_ = IFluidContractFactory(DEPLOYER_FACTORY).totalContracts();
        assertEq(IFluidContractFactory(DEPLOYER_FACTORY).getContractAddress(oracleNonce_), newOracle_);

        vm.prank(IOwned(VAULT_FACTORY).owner());
        IVaultAdminT234(VAULT_T3_WSTETH_USDC_USDT).updateOracle(oracleNonce_);

        assertEq(_currentVaultOracle(VAULT_T3_WSTETH_USDC_USDT), newOracle_);
    }

    function test_mainnetFork_registerThenUpdateOracle_t4_wstEthEth_wstEthEth() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();

        uint256 ethPriceUsd_ = _readChainlinkPrice(CHAINLINK_ETH_USD);
        uint256 wstEthPriceUsd_ = (ethPriceUsd_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        _setMockPrice(usdOracle_, NATIVE_TOKEN, ethPriceUsd_, ethPriceUsd_, 18);
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsd_, wstEthPriceUsd_, 18);

        VaultOracleFactory factory_ = _newVaultOracleFactory(address(usdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(factory_));
        uint256 vaultIdT4_ = IFluidVault(VAULT_T4_WSTETH_ETH_WSTETH_ETH).VAULT_ID();
        address newOracle_ = _registerVaultAsGov(factory_, vaultIdT4_, 0);

        uint256 oracleNonce_ = IFluidContractFactory(DEPLOYER_FACTORY).totalContracts();
        assertEq(IFluidContractFactory(DEPLOYER_FACTORY).getContractAddress(oracleNonce_), newOracle_);

        vm.prank(IOwned(VAULT_FACTORY).owner());
        IVaultAdminT234(VAULT_T4_WSTETH_ETH_WSTETH_ETH).updateOracle(oracleNonce_);

        assertEq(_currentVaultOracle(VAULT_T4_WSTETH_ETH_WSTETH_ETH), newOracle_);
    }

    function _forkAssertFactoryOracleDiffersFromWiredT2(MockUsdOracleDetailed usdOracle_) internal {
        uint256 btcPriceUsd_ = _readChainlinkPrice(CHAINLINK_BTC_USD);
        uint256 usdcPriceUsd_ = _readChainlinkPrice(CHAINLINK_USDC_USD);
        _setMockPrice(usdOracle_, WBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, CBBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, USDC, usdcPriceUsd_, usdcPriceUsd_, 6);
        address wired_ = _currentVaultOracle(VAULT_T2_WBTC_CBBTC_USDC);
        address factory_ = _registerWithMock(VAULT_T2_WBTC_CBBTC_USDC, usdOracle_);
        assertNotEq(factory_, wired_, "T2: new deploy nonce != vault wired nonce");
    }

    function _forkAssertFactoryOracleDiffersFromWiredT3(MockUsdOracleDetailed usdOracle_) internal {
        uint256 stethUsdPrice_ = _readChainlinkPrice(CHAINLINK_STETH_USD);
        uint256 wstEthPriceUsd_ = (stethUsdPrice_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        uint256 oneUsd_ = 1e27;
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsd_, wstEthPriceUsd_, 18);
        _setMockPrice(usdOracle_, USDC, oneUsd_, oneUsd_, 6);
        _setMockPrice(usdOracle_, USDT, oneUsd_, oneUsd_, 6);
        address wired_ = _currentVaultOracle(VAULT_T3_WSTETH_USDC_USDT);
        address factory_ = _registerWithMock(VAULT_T3_WSTETH_USDC_USDT, usdOracle_);
        assertNotEq(factory_, wired_, "T3: new deploy nonce != vault wired nonce");
    }

    function _forkAssertFactoryOracleDiffersFromWiredT4(MockUsdOracleDetailed usdOracle_) internal {
        uint256 ethPriceUsd_ = _readChainlinkPrice(CHAINLINK_ETH_USD);
        uint256 wstEthPriceUsdT4_ = (ethPriceUsd_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        _setMockPrice(usdOracle_, NATIVE_TOKEN, ethPriceUsd_, ethPriceUsd_, 18);
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsdT4_, wstEthPriceUsdT4_, 18);
        address wired_ = _currentVaultOracle(VAULT_T4_WSTETH_ETH_WSTETH_ETH);
        address factory_ = _registerWithMock(VAULT_T4_WSTETH_ETH_WSTETH_ETH, usdOracle_);
        assertNotEq(factory_, wired_, "T4: new deploy nonce != vault wired nonce");
    }

    /// @dev Test goal: the new VaultT1Oracle must produce the same exchange rate as
    ///      the existing production oracle for vault WBTC/GHO, within 0.01%.
    ///      Token USD prices are fetched from the same Chainlink feeds the legacy oracle uses:
    ///      WBTC = WBTC/BTC × BTC/USD, GHO = GHO/USD.
    function test_mainnetFork_parity_t1_wbtcGho() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T1_WBTC_GHO);

        uint256 wbtcPriceUsd_ = _readChainlinkComposedPrice(CHAINLINK_WBTC_BTC, CHAINLINK_BTC_USD);
        uint256 ghoPriceUsd_ = _readChainlinkPrice(CHAINLINK_GHO_USD);

        _setMockPrice(usdOracle_, WBTC, wbtcPriceUsd_, wbtcPriceUsd_, 8);
        _setMockPrice(usdOracle_, GHO, ghoPriceUsd_, ghoPriceUsd_, 18);

        address newOracle_ = address(new VaultT1Oracle(address(usdOracle_), WBTC, GHO, 0, 0));
        _assertOracleParity(existingOracle_, newOracle_);
    }

    /// @dev Test goal: new T2 oracle must match existing production oracle within 0.01%.
    ///      Legacy peg oracle treats WBTC = CBBTC = BTC, so both get BTC/USD.
    ///      USDC from Chainlink USDC/USD (same feed the legacy colDebtOracle uses).
    function test_mainnetFork_parity_t2_wbtcCbBtcUsdc() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T2_WBTC_CBBTC_USDC);

        uint256 btcPriceUsd_ = _readChainlinkPrice(CHAINLINK_BTC_USD);
        uint256 usdcPriceUsd_ = _readChainlinkPrice(CHAINLINK_USDC_USD);
        _setMockPrice(usdOracle_, WBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, CBBTC, btcPriceUsd_, btcPriceUsd_, 8);
        _setMockPrice(usdOracle_, USDC, usdcPriceUsd_, usdcPriceUsd_, 6);

        address parityOracle_ = _registerWithMock(VAULT_T2_WBTC_CBBTC_USDC, usdOracle_);
        _assertOracleParityAdjustedForLegacyBuffer(
            existingOracle_,
            parityOracle_,
            LEGACY_PEG_BUFFER_PPM_T2_WBTC_CBBTC_USDC,
            BUFFERED_LEG_COLLATERAL
        );
    }

    /// @dev Test goal: new T3 oracle must match existing production oracle within 0.01%.
    ///      wstETH = stEthPerToken × stETH/USD (same Chainlink stETH/USD feed the legacy WstETHCLRSOracle uses).
    ///      USDC = USDT = $1 (1e27). The legacy peg oracle values the USDC-USDT debt DEX reserves
    ///      without any Chainlink feed — it treats both stablecoins at $1 by construction.
    function test_mainnetFork_parity_t3_wstEthDexUsdcUsdt() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T3_WSTETH_USDC_USDT);

        uint256 stethUsdPrice_ = _readChainlinkPrice(CHAINLINK_STETH_USD);
        uint256 wstEthPriceUsd_ = (stethUsdPrice_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        uint256 oneUsd_ = 1e27;
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsd_, wstEthPriceUsd_, 18);
        _setMockPrice(usdOracle_, USDC, oneUsd_, oneUsd_, 6);
        _setMockPrice(usdOracle_, USDT, oneUsd_, oneUsd_, 6);

        address parityOracle_ = _registerWithMock(VAULT_T3_WSTETH_USDC_USDT, usdOracle_);
        _assertOracleParityAdjustedForLegacyBuffer(
            existingOracle_,
            parityOracle_,
            LEGACY_PEG_BUFFER_PPM_T3_WSTETH_USDC_USDT,
            BUFFERED_LEG_DEBT
        );
    }

    /// @dev Test goal: new T4 oracle must match existing production oracle within 0.01%.
    ///      ETH price from Chainlink ETH/USD. wstETH = stEthPerToken × ETH/USD.
    ///      The legacy DexSmartT4PegOracle uses stEthPerToken() to convert wstETH→stETH≈ETH,
    ///      so we set wstETH_price = stEthPerToken × ETH_price to match the implicit stETH≈ETH peg.
    function test_mainnetFork_parity_t4_wstEthEth_wstEthEth() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T4_WSTETH_ETH_WSTETH_ETH);

        uint256 ethPriceUsd_ = _readChainlinkPrice(CHAINLINK_ETH_USD);
        uint256 wstEthPriceUsd_ = (ethPriceUsd_ * IWstEth(WSTETH).stEthPerToken()) / 1e18;
        _setMockPrice(usdOracle_, NATIVE_TOKEN, ethPriceUsd_, ethPriceUsd_, 18);
        _setMockPrice(usdOracle_, WSTETH, wstEthPriceUsd_, wstEthPriceUsd_, 18);

        address parityOracle_ = _registerWithMock(VAULT_T4_WSTETH_ETH_WSTETH_ETH, usdOracle_);
        _assertOracleParityAdjustedForLegacyBuffer(
            existingOracle_,
            parityOracle_,
            LEGACY_PEG_BUFFER_PPM_T4,
            BUFFERED_LEGS_BOTH
        );
    }

    /// @dev Test goal: new T4 oracle must match existing production oracle within 0.01%.
    ///      USDe, USDC, USDT prices from their respective Chainlink USD feeds.
    function test_mainnetFork_parity_t4_usdeUsdt_usdcUsdt() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T4_USDE_USDT_USDC_USDT);

        uint256 usdePriceUsd_ = _readChainlinkPrice(CHAINLINK_USDE_USD);
        uint256 usdcPriceUsd_ = _readChainlinkPrice(CHAINLINK_USDC_USD);
        uint256 usdtPriceUsd_ = _readChainlinkPrice(CHAINLINK_USDT_USD);
        _setMockPrice(usdOracle_, USDE, usdePriceUsd_, usdePriceUsd_, 18);
        _setMockPrice(usdOracle_, USDT, usdtPriceUsd_, usdtPriceUsd_, 6);
        _setMockPrice(usdOracle_, USDC, usdcPriceUsd_, usdcPriceUsd_, 6);

        address parityOracle_ = _registerWithMock(VAULT_T4_USDE_USDT_USDC_USDT, usdOracle_);
        _assertOracleParityAdjustedForLegacyBuffer(
            existingOracle_,
            parityOracle_,
            LEGACY_PEG_BUFFER_PPM_T4,
            BUFFERED_LEGS_BOTH
        );
    }

    /// @dev Test goal: new T4 oracle must match existing production oracle within 0.01%.
    ///      wstUSR price from the CappedRate oracle on mainnet (same source as legacy).
    ///      USDC = USDT = $1 (1e27). The legacy peg oracles for both col and debt DEX legs
    ///      value stablecoins at $1 by construction without any Chainlink feed.
    function test_mainnetFork_parity_t4_wstUsrUsdc_usdcUsdt() public {
        MockUsdOracleDetailed usdOracle_ = new MockUsdOracleDetailed();
        address existingOracle_ = _currentVaultOracle(VAULT_T4_WSTUSR_USDC_USDC_USDT);

        uint256 wstUsrOperatePrice_ = WSTUSR_CAPPED_RATE.getExchangeRateOperate();
        uint256 wstUsrLiquidatePrice_ = WSTUSR_CAPPED_RATE.getExchangeRateLiquidate();
        uint256 oneUsd_ = 1e27;
        _setMockPrice(usdOracle_, WSTUSR, wstUsrOperatePrice_, wstUsrLiquidatePrice_, 18);
        _setMockPrice(usdOracle_, USDC, oneUsd_, oneUsd_, 6);
        _setMockPrice(usdOracle_, USDT, oneUsd_, oneUsd_, 6);

        address parityOracle_ = _registerWithMock(VAULT_T4_WSTUSR_USDC_USDC_USDT, usdOracle_);
        _assertOracleParityWithSplitLegacyBuffer(
            existingOracle_,
            parityOracle_,
            LEGACY_COL_PEG_BUFFER_T4_WSTUSR,
            LEGACY_DEBT_PEG_BUFFER_T4_WSTUSR
        );
    }

    function test_mainnetFork_localUsdOracle_t1_marketCappedStableDebtAndFallbackCollateral() public {
        (FluidUsdOracle localUsdOracle_, address admin_) = _deployLocalUsdOracle();

        // 8-decimal USD reference feeds: the mock delegates `decimals()`, and the rates below are 8-decimal
        // USD values. `CHAINLINK_REFERENCE_FEED` reports 18 decimals, which would scale these down by 1e10.
        MockChainlinkFeed wbtcPrimaryFeed_ = new MockChainlinkFeed(CHAINLINK_BTC_USD);
        MockChainlinkFeed wbtcAltFeed_ = new MockChainlinkFeed(CHAINLINK_BTC_USD);
        MockChainlinkFeed ghoMarketFeed_ = new MockChainlinkFeed(CHAINLINK_GHO_USD);

        wbtcPrimaryFeed_.setExchangeRate(60_500e8);
        wbtcAltFeed_.setExchangeRate(60_000e8);
        ghoMarketFeed_.setExchangeRate(105_000_000);

        vm.startPrank(admin_);
        localUsdOracle_.setTokenType(WBTC, TOKEN_TYPE_VOLATILE);
        localUsdOracle_.setTokenType(GHO, TOKEN_TYPE_STABLE);

        localUsdOracle_.setSourceConfig(
            WBTC,
            SourceConfig(SOURCE_CHAINLINK, address(wbtcPrimaryFeed_), 0),
            _emptyCfg(),
            _emptyCfg()
        );
        localUsdOracle_.setAltSourceConfig(
            WBTC,
            SourceConfig(SOURCE_CHAINLINK, address(wbtcAltFeed_), 0),
            _emptyCfg(),
            _emptyCfg()
        );
        localUsdOracle_.setSourceConfig(
            GHO,
            SourceConfig(SOURCE_CHAINLINK, address(ghoMarketFeed_), 0),
            _emptyCfg(),
            _emptyCfg()
        );
        vm.stopPrank();

        _setPriceMode(localUsdOracle_, admin_, WBTC, true, true, PRICE_MODE_MARKET);
        _enableFallback(localUsdOracle_, admin_, WBTC, true, true);
        _enableDeviationCheck(localUsdOracle_, admin_, WBTC, true, true, 100);
        _setPriceMode(localUsdOracle_, admin_, WBTC, false, true, PRICE_MODE_MARKET);

        _setPriceMode(localUsdOracle_, admin_, GHO, true, false, PRICE_MODE_MARKET);
        _setOverallCapMaxOperand(localUsdOracle_, admin_, GHO, true, false, 100);
        _setPriceMode(localUsdOracle_, admin_, GHO, false, false, PRICE_MODE_PEG);

        address oracle_ = address(new VaultT1Oracle(address(localUsdOracle_), WBTC, GHO, 0, 0));

        (uint256 operateColPrice_, uint8 operateColDecimals_, ) = localUsdOracle_.getPriceDetailedView(
            WBTC,
            0,
            true,
            true
        );
        (uint256 operateDebtPrice_, uint8 operateDebtDecimals_, ) = localUsdOracle_.getPriceDetailedView(
            GHO,
            0,
            true,
            false
        );
        (uint256 liquidateColPrice_, uint8 liquidateColDecimals_, ) = localUsdOracle_.getPriceDetailedView(
            WBTC,
            0,
            false,
            true
        );
        (uint256 liquidateDebtPrice_, uint8 liquidateDebtDecimals_, ) = localUsdOracle_.getPriceDetailedView(
            GHO,
            0,
            false,
            false
        );

        assertEq(operateColPrice_, 60_500e27);
        assertEq(operateDebtPrice_, 105e25); // $1.05 market price; MAX_OPERAND(100) is a floor at $1, so $1.05 passes through
        assertEq(liquidateColPrice_, 60_500e27);
        assertEq(liquidateDebtPrice_, 1e27);

        uint256 expectedOperateRate_ = _computeExchangeRate(
            operateColPrice_,
            operateColDecimals_,
            operateDebtPrice_,
            operateDebtDecimals_
        );
        uint256 expectedLiquidateRate_ = _computeExchangeRate(
            liquidateColPrice_,
            liquidateColDecimals_,
            liquidateDebtPrice_,
            liquidateDebtDecimals_
        );

        assertEq(IFluidOracle(oracle_).getExchangeRateOperate(), expectedOperateRate_);
        assertEq(IFluidOracle(oracle_).getExchangeRateLiquidate(), expectedLiquidateRate_);
        assertEq(IFluidOracle(oracle_).getExchangeRate(), expectedOperateRate_);
    }

    function test_mainnetFork_localUsdOracle_t4_pegTokenMatrix_operateAndLiquidateDiverge() public {
        (FluidUsdOracle localUsdOracle_, address admin_) = _deployLocalUsdOracle();

        MockCappedRate wstUsrPegRate_ = new MockCappedRate();
        MockChainlinkFeed wstUsrMarketFeed_ = new MockChainlinkFeed(CHAINLINK_REFERENCE_FEED);

        wstUsrPegRate_.setRates(1e27, 1_010_000_000_000_000_000_000_000, 1e27, 1_003_000_000_000_000_000_000_000, 1e27);
        wstUsrMarketFeed_.setExchangeRate(103_000_000);

        vm.startPrank(admin_);
        localUsdOracle_.setTokenType(WSTUSR, TOKEN_TYPE_PEG);
        localUsdOracle_.setTokenType(USDC, TOKEN_TYPE_STABLE);
        localUsdOracle_.setTokenType(USDT, TOKEN_TYPE_STABLE);

        localUsdOracle_.setSourceConfig(
            WSTUSR,
            SourceConfig(SOURCE_CAPPED_RATE, address(wstUsrPegRate_), 0),
            _emptyCfg(),
            _emptyCfg()
        );
        localUsdOracle_.setAdditionalSourceConfig(
            WSTUSR,
            SourceConfig(SOURCE_CHAINLINK, address(wstUsrMarketFeed_), 0),
            _emptyCfg(),
            _emptyCfg()
        );
        localUsdOracle_.setSourceConfig(USDC, SourceConfig(SOURCE_STABLE, address(0), 0), _emptyCfg(), _emptyCfg());
        localUsdOracle_.setSourceConfig(USDT, SourceConfig(SOURCE_STABLE, address(0), 0), _emptyCfg(), _emptyCfg());
        vm.stopPrank();

        _setPriceMode(localUsdOracle_, admin_, WSTUSR, true, true, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, WSTUSR, false, true, PRICE_MODE_MARKET);
        _setPriceMode(localUsdOracle_, admin_, USDC, true, true, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, USDC, false, true, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, USDC, true, false, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, USDC, false, false, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, USDT, true, false, PRICE_MODE_PEG);
        _setPriceMode(localUsdOracle_, admin_, USDT, false, false, PRICE_MODE_PEG);

        VaultOracleFactory localFactory_ = _newVaultOracleFactory(address(localUsdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(localFactory_));
        uint256 vaultIdLocal_ = IFluidVault(VAULT_T4_WSTUSR_USDC_USDC_USDT).VAULT_ID();
        address oracle_ = _registerVaultAsGov(localFactory_, vaultIdLocal_, 0);

        uint256 operateRate_ = IFluidOracle(oracle_).getExchangeRateOperate();
        uint256 liquidateRate_ = IFluidOracle(oracle_).getExchangeRateLiquidate();

        assertGt(operateRate_, 0);
        assertGt(liquidateRate_, 0);
        assertNotEq(operateRate_, liquidateRate_);
        assertEq(IFluidOracle(oracle_).targetDecimals(), 27);
    }

    function _currentVaultOracle(address vault_) internal view returns (address oracle_) {
        IOnChainVaultResolver resolver_ = IOnChainVaultResolver(VAULT_RESOLVER);
        uint256 vaultType_ = resolver_.getVaultType(vault_);
        uint256 vaultVariables2_ = resolver_.getVaultVariables2Raw(vault_);

        if (vaultType_ == VAULT_T1_TYPE) {
            oracle_ = address(uint160(vaultVariables2_ >> 96));
        } else {
            uint256 oracleIndex_ = (vaultVariables2_ >> 92) & X30;
            oracle_ = resolver_.getContractForDeployerIndex(vault_, oracleIndex_);
        }
        assertTrue(oracle_ != address(0), "existing oracle missing");
    }

    function _assertOracleParity(address existingOracle_, address newOracle_) internal view {
        _assertWithinOneBps(
            IFluidOracle(existingOracle_).getExchangeRate(),
            IFluidOracle(newOracle_).getExchangeRate()
        );
        _assertWithinOneBps(
            IFluidOracle(existingOracle_).getExchangeRateOperate(),
            IFluidOracle(newOracle_).getExchangeRateOperate()
        );
        _assertWithinOneBps(
            IFluidOracle(existingOracle_).getExchangeRateLiquidate(),
            IFluidOracle(newOracle_).getExchangeRateLiquidate()
        );
    }

    function _assertOracleParityAdjustedForLegacyBuffer(
        address existingOracle_,
        address newOracle_,
        uint256 legacyPegBufferPpm_,
        uint8 bufferedLegs_
    ) internal view {
        _assertWithinOneBps(
            _adjustLegacyBufferedRate(
                IFluidOracle(existingOracle_).getExchangeRate(),
                legacyPegBufferPpm_,
                bufferedLegs_,
                true
            ),
            IFluidOracle(newOracle_).getExchangeRate()
        );
        _assertWithinOneBps(
            _adjustLegacyBufferedRate(
                IFluidOracle(existingOracle_).getExchangeRateOperate(),
                legacyPegBufferPpm_,
                bufferedLegs_,
                true
            ),
            IFluidOracle(newOracle_).getExchangeRateOperate()
        );
        _assertWithinOneBps(
            _adjustLegacyBufferedRate(
                IFluidOracle(existingOracle_).getExchangeRateLiquidate(),
                legacyPegBufferPpm_,
                bufferedLegs_,
                false
            ),
            IFluidOracle(newOracle_).getExchangeRateLiquidate()
        );
    }

    function _assertWithinOneBps(uint256 reference_, uint256 candidate_) internal pure {
        uint256 diff_ = reference_ > candidate_ ? reference_ - candidate_ : candidate_ - reference_;
        assertLe(diff_ * 10_000, reference_);
    }

    function _adjustLegacyBufferedRate(
        uint256 legacyRate_,
        uint256 legacyPegBufferPpm_,
        uint8 bufferedLegs_,
        bool isOperate_
    ) internal pure returns (uint256 adjustedRate_) {
        uint256 newPegBufferPpm_ = isOperate_ ? V2_PEG_BUFFER_PPM_OPERATE : V2_PEG_BUFFER_PPM_LIQUIDATE;
        adjustedRate_ = legacyRate_;

        if (bufferedLegs_ & BUFFERED_LEG_COLLATERAL != 0) {
            adjustedRate_ =
                (adjustedRate_ * (PEG_BUFFER_SCALE - newPegBufferPpm_)) /
                (PEG_BUFFER_SCALE - legacyPegBufferPpm_);
        }

        if (bufferedLegs_ & BUFFERED_LEG_DEBT != 0) {
            adjustedRate_ =
                (adjustedRate_ * (PEG_BUFFER_SCALE + legacyPegBufferPpm_)) /
                (PEG_BUFFER_SCALE + newPegBufferPpm_);
        }
    }

    function _assertOracleParityWithSplitLegacyBuffer(
        address existingOracle_,
        address newOracle_,
        uint256 legacyColPegBufferPpm_,
        uint256 legacyDebtPegBufferPpm_
    ) internal view {
        _assertWithinOneBps(
            _adjustLegacyBufferedRateSplit(
                IFluidOracle(existingOracle_).getExchangeRate(),
                legacyColPegBufferPpm_,
                legacyDebtPegBufferPpm_,
                true
            ),
            IFluidOracle(newOracle_).getExchangeRate()
        );
        _assertWithinOneBps(
            _adjustLegacyBufferedRateSplit(
                IFluidOracle(existingOracle_).getExchangeRateOperate(),
                legacyColPegBufferPpm_,
                legacyDebtPegBufferPpm_,
                true
            ),
            IFluidOracle(newOracle_).getExchangeRateOperate()
        );
        _assertWithinOneBps(
            _adjustLegacyBufferedRateSplit(
                IFluidOracle(existingOracle_).getExchangeRateLiquidate(),
                legacyColPegBufferPpm_,
                legacyDebtPegBufferPpm_,
                false
            ),
            IFluidOracle(newOracle_).getExchangeRateLiquidate()
        );
    }

    function _adjustLegacyBufferedRateSplit(
        uint256 legacyRate_,
        uint256 legacyColPegBufferPpm_,
        uint256 legacyDebtPegBufferPpm_,
        bool isOperate_
    ) internal pure returns (uint256 adjustedRate_) {
        uint256 newPegBufferPpm_ = isOperate_ ? V2_PEG_BUFFER_PPM_OPERATE : V2_PEG_BUFFER_PPM_LIQUIDATE;
        adjustedRate_ =
            (legacyRate_ * (PEG_BUFFER_SCALE - newPegBufferPpm_)) /
            (PEG_BUFFER_SCALE - legacyColPegBufferPpm_);
        adjustedRate_ =
            (adjustedRate_ * (PEG_BUFFER_SCALE + legacyDebtPegBufferPpm_)) /
            (PEG_BUFFER_SCALE + newPegBufferPpm_);
    }

    function _allowVaultOracleFactoryOnFluidFactory(address vaultOracleFactory_) internal {
        FluidContractFactory ff_ = FluidContractFactory(DEPLOYER_FACTORY);
        vm.prank(ff_.owner());
        ff_.updateDeployer(vaultOracleFactory_, 500);
    }

    /// @dev Deploys implementation + `VaultOracleFactoryProxy`; upgrades require Liquidity governance (`LIQUIDITY` on fork).
    function _newVaultOracleFactory(address usdOracleAddr_) internal returns (VaultOracleFactory factory_) {
        VaultOracleFactory impl_ = new VaultOracleFactory(
            LIQUIDITY,
            usdOracleAddr_,
            VAULT_FACTORY,
            DEPLOYER_FACTORY,
            address(new VaultT1OracleDeploymentLogic()),
            address(new VaultT2OracleDeploymentLogic()),
            address(new VaultT3OracleDeploymentLogic()),
            address(new VaultT4OracleDeploymentLogic())
        );
        factory_ = VaultOracleFactory(address(new VaultOracleFactoryProxy(address(impl_), "")));
    }

    function _liquidityGovernance() internal view returns (address gov_) {
        gov_ = address(uint160(uint256(vm.load(LIQUIDITY, LIQUIDITY_GOVERNANCE_SLOT))));
    }

    function _registerVaultAsGov(
        VaultOracleFactory factory_,
        uint256 vaultId_,
        uint256 eMode_
    ) internal returns (address oracle_) {
        vm.prank(_liquidityGovernance());
        oracle_ = factory_.registerVault(
            vaultId_,
            eMode_,
            eMode_,
            V2_PEG_BUFFER_PPM_OPERATE,
            V2_PEG_BUFFER_PPM_LIQUIDATE
        );
    }

    function _registerWithMock(address vault_, MockUsdOracleDetailed usdOracle_) internal returns (address oracle_) {
        VaultOracleFactory factory_ = _newVaultOracleFactory(address(usdOracle_));
        _allowVaultOracleFactoryOnFluidFactory(address(factory_));
        oracle_ = _registerVaultAsGov(factory_, IFluidVault(vault_).VAULT_ID(), 0);
    }

    function _setMockPrice(
        MockUsdOracleDetailed usdOracle_,
        address token_,
        uint256 operatePrice_,
        uint256 liquidatePrice_,
        uint8 decimals_
    ) internal {
        usdOracle_.setPrice(token_, true, true, operatePrice_, decimals_, 0);
        usdOracle_.setPrice(token_, false, true, liquidatePrice_, decimals_, 0);
        usdOracle_.setPrice(token_, true, false, operatePrice_, decimals_, 0);
        usdOracle_.setPrice(token_, false, false, liquidatePrice_, decimals_, 0);
    }

    function _readChainlinkPrice(IChainlinkAggregatorV3 feed_) internal view returns (uint256 priceUsd_) {
        (, int256 answer_, , , ) = feed_.latestRoundData();
        uint8 feedDecimals_ = feed_.decimals();
        priceUsd_ = uint256(answer_) * (10 ** (27 - uint256(feedDecimals_)));
    }

    /// @dev Compose two Chainlink feeds: (feedA answer × feedB answer) scaled to 1e27.
    ///      E.g. WBTC/BTC × BTC/USD → WBTC/USD.
    function _readChainlinkComposedPrice(
        IChainlinkAggregatorV3 feedA_,
        IChainlinkAggregatorV3 feedB_
    ) internal view returns (uint256 priceUsd_) {
        (, int256 answerA_, , , ) = feedA_.latestRoundData();
        (, int256 answerB_, , , ) = feedB_.latestRoundData();
        uint256 totalFeedDecimals_ = uint256(feedA_.decimals()) + uint256(feedB_.decimals());
        priceUsd_ = (uint256(answerA_) * uint256(answerB_) * (10 ** 27)) / (10 ** totalFeedDecimals_);
    }

    function _deployLocalUsdOracle() internal returns (FluidUsdOracle usdOracle_, address admin_) {
        admin_ = address(this);

        MockReadFromStorage liquidityMock_ = new MockReadFromStorage();

        liquidityMock_.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(admin_)));

        usdOracle_ = new FluidUsdOracle(address(liquidityMock_));
    }

    function _setPriceMode(
        FluidUsdOracle usdOracle_,
        address admin_,
        address token_,
        bool isOperate_,
        bool isCollateral_,
        uint8 priceMode_
    ) internal {
        vm.startPrank(admin_);
        usdOracle_.registerTransientOracleKey(_key(token_, 0, isOperate_, isCollateral_));
        usdOracle_.setPriceMode(priceMode_);
        vm.stopPrank();
    }

    function _setOverallCapMaxOperand(
        FluidUsdOracle usdOracle_,
        address admin_,
        address token_,
        bool isOperate_,
        bool isCollateral_,
        uint16 operand_
    ) internal {
        vm.startPrank(admin_);
        usdOracle_.registerTransientOracleKey(_key(token_, 0, isOperate_, isCollateral_));
        usdOracle_.setOverallCap(OVERALL_CAP_MAX_OPERAND, operand_);
        vm.stopPrank();
    }

    function _enableDeviationCheck(
        FluidUsdOracle usdOracle_,
        address admin_,
        address token_,
        bool isOperate_,
        bool isCollateral_,
        uint24 maxDeviationBps_
    ) internal {
        vm.startPrank(admin_);
        usdOracle_.registerTransientOracleKey(_key(token_, 0, isOperate_, isCollateral_));
        usdOracle_.enableDeviationCheck(maxDeviationBps_);
        vm.stopPrank();
    }

    function _enableFallback(
        FluidUsdOracle usdOracle_,
        address admin_,
        address token_,
        bool isOperate_,
        bool isCollateral_
    ) internal {
        vm.startPrank(admin_);
        usdOracle_.registerTransientOracleKey(_key(token_, 0, isOperate_, isCollateral_));
        usdOracle_.enableFallback();
        vm.stopPrank();
    }

    function _emptyCfg() internal pure returns (SourceConfig memory) {
        return SourceConfig({ sourceType: SOURCE_NOT_SET, source: address(0), capOperand: 0 });
    }

    function _key(
        address token_,
        uint256 eMode_,
        bool isOperate_,
        bool isCollateral_
    ) internal pure returns (OracleKey memory) {
        return OracleKey(token_, eMode_, isOperate_ ? 1 : 0, isCollateral_ ? 1 : 0);
    }

    function _computeExchangeRate(
        uint256 colPriceUsd_,
        uint8 colDecimals_,
        uint256 debtPriceUsd_,
        uint8 debtDecimals_
    ) internal pure returns (uint256 exchangeRate_) {
        exchangeRate_ = (colPriceUsd_ * (10 ** (27 + uint256(debtDecimals_) - uint256(colDecimals_)))) / debtPriceUsd_;
    }
}
