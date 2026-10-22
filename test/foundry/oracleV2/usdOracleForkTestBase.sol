//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.36;

import { Test } from "forge-std/Test.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { FluidUsdOracleProxy } from "../../../contracts/oracleV2/usdOracle/proxy.sol";
import { ErrorTypes as UsdOracleErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/usdOracle/error.sol";
import { Structs } from "../../../contracts/oracleV2/usdOracle/structs.sol";

interface IChainlinkAggregatorV3 {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @dev Minimal mock that implements readFromStorage so the oracle can read governance and eMode data.
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
    IChainlinkAggregatorV3 chainlinkFeed;
    int256 exchangeRate;
    uint8 customDecimals = 27;

    constructor(IChainlinkAggregatorV3 originalChainLinkFeed) {
        chainlinkFeed = originalChainLinkFeed;
        (, int256 exchangeRate_, , , ) = chainlinkFeed.latestRoundData();
        exchangeRate = exchangeRate_;
    }

    function setExchangeRate(int256 newExchangeRate_) external {
        exchangeRate = newExchangeRate_;
    }

    function setDecimals(uint8 newDecimals_) external {
        customDecimals = newDecimals_;
    }

    function decimals() external view returns (uint8) {
        return customDecimals;
    }

    function description() external view returns (string memory) {
        return chainlinkFeed.description();
    }

    function version() external view returns (uint256) {
        return chainlinkFeed.version();
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return chainlinkFeed.getRoundData(_roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint80 roundIdOrg, , uint256 startedAtOrg, uint256 updatedAtOrg, uint80 answeredInRoundOrg) = chainlinkFeed
            .latestRoundData();
        return (roundIdOrg, exchangeRate, startedAtOrg, updatedAtOrg, answeredInRoundOrg);
    }
}

contract MockCappedRate {
    uint256 public centerPriceValue = 1e27;
    uint256 public operateValue = 2e27;
    uint256 public operateDebtValue = 3e27;
    uint256 public liquidateValue = 4e27;
    uint256 public liquidateDebtValue = 5e27;

    bool public revertCenterPrice;
    bool public revertOperate;
    bool public revertOperateDebt;
    bool public revertLiquidate;
    bool public revertLiquidateDebt;

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

    function setReverts(
        bool revertCenterPrice_,
        bool revertOperate_,
        bool revertOperateDebt_,
        bool revertLiquidate_,
        bool revertLiquidateDebt_
    ) external {
        revertCenterPrice = revertCenterPrice_;
        revertOperate = revertOperate_;
        revertOperateDebt = revertOperateDebt_;
        revertLiquidate = revertLiquidate_;
        revertLiquidateDebt = revertLiquidateDebt_;
    }

    function centerPrice() external view returns (uint256) {
        if (revertCenterPrice) revert();
        return centerPriceValue;
    }

    function getExchangeRate() external view returns (uint256) {
        return operateValue;
    }

    function getExchangeRateOperate() external view returns (uint256) {
        if (revertOperate) revert();
        return operateValue;
    }

    function getExchangeRateOperateDebt() external view returns (uint256) {
        if (revertOperateDebt) revert();
        return operateDebtValue;
    }

    function getExchangeRateLiquidate() external view returns (uint256) {
        if (revertLiquidate) revert();
        return liquidateValue;
    }

    function getExchangeRateLiquidateDebt() external view returns (uint256) {
        if (revertLiquidateDebt) revert();
        return liquidateDebtValue;
    }

    function infoName() external pure returns (string memory) {
        return "mock";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

/// @dev CLX-style Fluid oracle with debt getters but no `centerPrice()` (fails `SOURCE_CAPPED_RATE` probe).
contract MockFluidOracleWithDebt {
    uint256 public operateValue = 2e27;
    uint256 public operateDebtValue = 3e27;
    uint256 public liquidateValue = 4e27;
    uint256 public liquidateDebtValue = 5e27;

    bool public revertOperate;
    bool public revertOperateDebt;

    function setRates(
        uint256 operateValue_,
        uint256 operateDebtValue_,
        uint256 liquidateValue_,
        uint256 liquidateDebtValue_
    ) external {
        operateValue = operateValue_;
        operateDebtValue = operateDebtValue_;
        liquidateValue = liquidateValue_;
        liquidateDebtValue = liquidateDebtValue_;
    }

    function setReverts(bool revertOperate_, bool revertOperateDebt_) external {
        revertOperate = revertOperate_;
        revertOperateDebt = revertOperateDebt_;
    }

    function getExchangeRate() external view returns (uint256) {
        return operateValue;
    }

    function getExchangeRateOperate() external view returns (uint256) {
        if (revertOperate) revert();
        return operateValue;
    }

    function getExchangeRateOperateDebt() external view returns (uint256) {
        if (revertOperateDebt) revert();
        return operateDebtValue;
    }

    function getExchangeRateLiquidate() external view returns (uint256) {
        return liquidateValue;
    }

    function getExchangeRateLiquidateDebt() external view returns (uint256) {
        return liquidateDebtValue;
    }

    function getExchangeRateOperateRaw() external view returns (uint256) {
        return operateValue;
    }

    function getExchangeRateLiquidateRaw() external view returns (uint256) {
        return liquidateValue;
    }

    function getExchangeRateRaw() external view returns (uint256) {
        return operateValue;
    }

    function infoName() external pure returns (string memory) {
        return "mock-fluid-oracle";
    }

    function targetDecimals() external pure returns (uint8) {
        return 27;
    }
}

contract MockTokenWithoutSymbol {
    function symbol() external pure returns (string memory) {
        revert("no symbol");
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

/// @dev Dispatch for harness-only helpers (mainnet tests use `FluidUsdOracleHarness`, L2 tests use `FluidUsdOracleL2Harness`).
interface IUsdOracleReadHarness {
    function readSourceOrRevert(
        Structs.SourceConfig memory cfg_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256);

    function readComposedPriceOrRevert(
        Structs.SourceConfig memory s1_,
        Structs.SourceConfig memory s2_,
        Structs.SourceConfig memory s3_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256);
}

interface IOracleAdminMulticall {
    function multicall(bytes[] calldata data_) external returns (bytes[] memory results_);
}

/// @dev Mirrors the Bootstrap `multicall` (self-delegatecall, `msg.sender` preserved). Final
///      `FluidUsdOracle` / `FluidUsdOracleL2` carry no batch entry, leaving tests no other way to
///      reproduce the single-transaction shape every production caller uses for a key session.
abstract contract OracleAdminMulticall {
    function multicall(bytes[] calldata data_) external returns (bytes[] memory results_) {
        uint256 length_ = data_.length;
        results_ = new bytes[](length_);
        for (uint256 i_ = 0; i_ < length_; ) {
            results_[i_] = Address.functionDelegateCall(address(this), data_[i_]);
            unchecked {
                ++i_;
            }
        }
    }
}

/// @dev Production `FluidUsdOracle` keeps source reads internal; this harness exposes them for unit tests.
contract FluidUsdOracleHarness is FluidUsdOracle, OracleAdminMulticall {
    constructor(address liquidity_) FluidUsdOracle(liquidity_) {}

    receive() external payable {}

    function readSourceOrRevert(
        SourceConfig memory cfg_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 rate_) {
        rate_ = _readSource(
            cfg_.sourceType,
            cfg_.source,
            _deriveMultiplierForCfg(cfg_.sourceType, cfg_.source),
            isOperate_,
            isCollateral_,
            true
        );
    }

    function readComposedPriceOrRevert(
        SourceConfig memory s1_,
        SourceConfig memory s2_,
        SourceConfig memory s3_,
        bool isOperate_,
        bool isCollateral_
    ) external view returns (uint256 price_) {
        price_ = _readSource(
            s1_.sourceType,
            s1_.source,
            _deriveMultiplierForCfg(s1_.sourceType, s1_.source),
            isOperate_,
            isCollateral_,
            true
        );
        if (s2_.sourceType == SOURCE_NOT_SET) {
            return price_;
        }
        uint256 r2_ = _readSource(
            s2_.sourceType,
            s2_.source,
            _deriveMultiplierForCfg(s2_.sourceType, s2_.source),
            isOperate_,
            isCollateral_,
            true
        );
        price_ = (price_ * r2_) / ORACLE_PRECISION;
        if (s3_.sourceType == SOURCE_NOT_SET) {
            return price_;
        }
        uint256 r3_ = _readSource(
            s3_.sourceType,
            s3_.source,
            _deriveMultiplierForCfg(s3_.sourceType, s3_.source),
            isOperate_,
            isCollateral_,
            true
        );
        price_ = (price_ * r3_) / ORACLE_PRECISION;
        if (price_ == 0) {
            revert FluidUsdOracleError(UsdOracleErrorTypes.UsdOracle__RateZero);
        }
    }

    function _deriveMultiplierForCfg(uint8 sourceType_, address source_) internal view returns (int8) {
        if (
            sourceType_ == SOURCE_CAPPED_RATE ||
            sourceType_ == SOURCE_FLUID_ORACLE ||
            sourceType_ == SOURCE_STABLE ||
            sourceType_ == SOURCE_NOT_SET
        ) {
            return 0;
        }
        return int8(int256(uint256(27)) - int256(uint256(IChainlinkAggregatorV3(source_).decimals())));
    }
}

abstract contract UsdOracleForkTestBase is Test, Structs {
    uint8 internal constant PRICE_MODE_MARKET = 1;
    uint8 internal constant PRICE_MODE_PEG = 2;
    uint8 internal constant TOKEN_TYPE_PEG = 1;

    uint8 internal constant SOURCE_CAP_NONE = 0;
    uint8 internal constant SOURCE_CAP_MIN = 1;
    uint8 internal constant SOURCE_CAP_MAX = 2;
    uint8 internal constant OVERALL_CAP_NONE = 0;
    uint8 internal constant OVERALL_CAP_MIN_CROSS_PATH = 1;
    uint8 internal constant OVERALL_CAP_MAX_CROSS_PATH = 2;
    uint8 internal constant OVERALL_CAP_MIN_OPERAND = 3;
    uint8 internal constant OVERALL_CAP_MAX_OPERAND = 4;

    uint8 internal constant SOURCE_NOT_SET = 0;
    uint8 internal constant SOURCE_CAPPED_RATE = 1;
    uint8 internal constant SOURCE_CHAINLINK = 2;
    uint8 internal constant SOURCE_STABLE = 3;
    uint8 internal constant SOURCE_REDSTONE = 4;
    uint8 internal constant SOURCE_FLUID_ORACLE = 5;
    FluidUsdOracle public usdOracle;
    MockChainlinkFeed public clOracle;
    MockReadFromStorage public liquidityMock;

    address admin;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant DUMMY_TOKEN = address(0x123);
    /// @dev Listed PEG token for cross-path / peg-chain tests (see cap + vault matrix tests).
    address internal pegToken;

    bytes32 constant LIQUIDITY_GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // USDC / ETH feed
    IChainlinkAggregatorV3 CHAINLINK_FEED = IChainlinkAggregatorV3(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);

    event OracleConfigSet(
        address indexed token,
        uint256 indexed eMode,
        uint8 indexed isOperate,
        uint8 isCollateral,
        uint8 sourceType1,
        address source1,
        int8 multiplier1,
        uint8 sourceType2,
        address source2,
        int8 multiplier2,
        uint8 sourceType3,
        address source3,
        int8 multiplier3
    );

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        admin = makeAddr("admin");

        liquidityMock = new MockReadFromStorage();

        // Store admin as governance in the liquidity mock
        liquidityMock.setStorage(LIQUIDITY_GOVERNANCE_SLOT, uint256(uint160(admin)));

        usdOracle = new FluidUsdOracleHarness(address(liquidityMock));
        clOracle = new MockChainlinkFeed(IChainlinkAggregatorV3(address(CHAINLINK_FEED)));

        // List all tokens used in tests
        vm.mockCall(DUMMY_TOKEN, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        pegToken = makeAddr("pegToken");
        vm.mockCall(pegToken, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.startPrank(admin);
        usdOracle.setTokenType(USDC, 2); // STABLE
        usdOracle.setTokenType(USDT, 2); // STABLE
        usdOracle.setTokenType(DAI, 2); // STABLE
        usdOracle.setTokenType(DUMMY_TOKEN, 3); // VOLATILE
        usdOracle.setTokenType(pegToken, 1); // PEG
        vm.stopPrank();
    }

    // ==================== Helpers ====================

    function _emptyCfg() internal pure returns (SourceConfig memory) {
        return SourceConfig({ sourceType: 0, source: address(0), capOperand: 0 });
    }

    function _key(
        address token_,
        uint256 eMode_,
        uint8 isOperate_,
        uint8 isCollateral_
    ) internal pure returns (OracleKey memory) {
        return OracleKey(token_, eMode_, isOperate_, isCollateral_);
    }

    /// @dev Runs a key session as one transaction, the only shape production produces: Bootstrap
    ///      `multicall`, timelock `executeBatch` and Avocado/Safe batches all call
    ///      `registerTransientOracleKey` and its setters as sub-calls of a single tx. Split across
    ///      top-level calls it only survives while the runner draws no transaction boundary between
    ///      them, since `_tToken` is cleared per EIP-1153 as soon as one is drawn.
    function _adminSession(address caller_, bytes[] memory calls_) internal {
        vm.prank(caller_);
        IOracleAdminMulticall(address(usdOracle)).multicall(calls_);
    }

    /// @dev Registers key and sets config in one transaction.
    function _registerAndSetConfig(
        address caller_,
        address token_,
        uint256 eMode_,
        uint8 isOperate_,
        uint8 isCollateral_,
        SourceConfig memory src1_,
        SourceConfig memory src2_,
        SourceConfig memory src3_
    ) internal {
        vm.prank(caller_);
        usdOracle.setSourceConfig(token_, src1_, src2_, src3_);

        bytes[] memory calls_ = new bytes[](2);
        calls_[0] = abi.encodeWithSelector(
            usdOracle.registerTransientOracleKey.selector,
            _key(token_, eMode_, isOperate_, isCollateral_)
        );
        calls_[1] = abi.encodeWithSelector(usdOracle.setPriceMode.selector, PRICE_MODE_MARKET);
        _adminSession(caller_, calls_);
    }

    function _assertPauseState(address token_, bool operatePaused_, bool liquidatePaused_) internal view {
        (bool operatePaused, bool liquidatePaused, , ) = usdOracle.getTokenConfig(token_);
        assertEq(operatePaused, operatePaused_, "Unexpected operate pause state");
        assertEq(liquidatePaused, liquidatePaused_, "Unexpected liquidate pause state");
    }

    function _getSingleConfiguredOracle(address token_) internal view returns (ConfiguredTokenOracle memory info_) {
        ConfiguredTokenOracle[] memory infos = usdOracle.getConfiguredTokenOracles(token_);
        assertEq(infos.length, 1, "Expected exactly one configured oracle");
        return infos[0];
    }

    function _readHarness() internal view returns (IUsdOracleReadHarness) {
        return IUsdOracleReadHarness(address(usdOracle));
    }

    function _chainlinkSrc(uint16 capOp_) internal view returns (SourceConfig memory) {
        return SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: capOp_ });
    }

    function _stableSrc(uint16 capOp_) internal pure returns (SourceConfig memory) {
        return SourceConfig({ sourceType: 3, source: address(0), capOperand: capOp_ });
    }

    function _registerFullKey(
        address token_,
        uint256 eMode_,
        uint8 isOperate_,
        uint8 isCollateral_,
        uint8 priceMode_,
        uint8 sourceCap_,
        uint8 overallMode_,
        uint16 overallOp_
    ) internal {
        bytes[] memory calls_ = new bytes[](4);
        calls_[0] = abi.encodeWithSelector(
            usdOracle.registerTransientOracleKey.selector,
            _key(token_, eMode_, isOperate_, isCollateral_)
        );
        calls_[1] = abi.encodeWithSelector(usdOracle.setPriceMode.selector, priceMode_);
        calls_[2] = abi.encodeWithSelector(usdOracle.setSourceCapMode.selector, sourceCap_);
        calls_[3] = abi.encodeWithSelector(usdOracle.setOverallCap.selector, overallMode_, overallOp_);
        _adminSession(admin, calls_);
    }

    function _configureVolatileFourKeys(address token_) internal {
        SourceConfig memory src = _chainlinkSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(token_, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerAndSetConfig(admin, token_, 0, 1, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, token_, 0, 1, 0, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, token_, 0, 0, 1, src, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, token_, 0, 0, 0, src, _emptyCfg(), _emptyCfg());
    }

    function _configureStableFourKeys(address token_) internal {
        SourceConfig memory src = _chainlinkSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(token_, src, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
        _registerFullKey(token_, 0, 1, 1, PRICE_MODE_MARKET, SOURCE_CAP_NONE, OVERALL_CAP_MIN_OPERAND, 100);
        _registerFullKey(token_, 0, 1, 0, PRICE_MODE_MARKET, SOURCE_CAP_NONE, OVERALL_CAP_MAX_OPERAND, 100);
        _registerFullKey(token_, 0, 0, 1, PRICE_MODE_PEG, SOURCE_CAP_NONE, OVERALL_CAP_NONE, 0);
        _registerFullKey(token_, 0, 0, 0, PRICE_MODE_PEG, SOURCE_CAP_NONE, OVERALL_CAP_NONE, 0);
    }

    function _setupPegTokenSources(address token_) internal {
        MockCappedRate cr = new MockCappedRate();
        cr.setRates(1e27, 102e25, 102e25, 102e25, 102e25);
        SourceConfig memory pegLeg = SourceConfig({ sourceType: 1, source: address(cr), capOperand: 0 });
        SourceConfig memory mkt = _chainlinkSrc(0);
        vm.startPrank(admin);
        usdOracle.setSourceConfig(token_, pegLeg, _emptyCfg(), _emptyCfg());
        usdOracle.setAdditionalSourceConfig(token_, mkt, _emptyCfg(), _emptyCfg());
        vm.stopPrank();
    }

    function _configurePegCollateralFourKeys(address token_) internal {
        _setupPegTokenSources(token_);
        _registerFullKey(token_, 0, 1, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 1, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 0, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 0, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);
    }

    function _configurePegDebtFourKeys(address token_) internal {
        _setupPegTokenSources(token_);
        _registerFullKey(token_, 0, 1, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 1, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 0, 1, PRICE_MODE_PEG, SOURCE_CAP_MIN, OVERALL_CAP_MIN_CROSS_PATH, 0);
        _registerFullKey(token_, 0, 0, 0, PRICE_MODE_PEG, SOURCE_CAP_MAX, OVERALL_CAP_MAX_CROSS_PATH, 0);
    }
}
