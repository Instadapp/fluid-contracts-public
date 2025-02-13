//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibString} from "solmate/src/utils/LibString.sol";
import {LiquidityBaseTest} from "../../liquidity/liquidityBaseTest.t.sol";
import {IFluidLiquidityLogic} from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import {MockOracle} from "../../../../contracts/mocks/mockOracle.sol";
import {FluidLiquidityResolver} from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import {IFluidLiquidity} from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import {FluidDexReservesResolver} from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";
import {Structs as PoolStructs} from "../../../../contracts/periphery/resolvers/dexReserves/structs.sol";

import {TickMath} from "../../../../contracts/libraries/tickMath.sol";
import {LiquidityCalcs} from "../../../../contracts/libraries/liquidityCalcs.sol";
import {LiquiditySlotsLink} from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import {BigMathMinified} from "../../../../contracts/libraries/bigMathMinified.sol";

import {IFluidDexT1} from "../../../../contracts/protocols/dex/interfaces/iDexT1.sol";
import {FluidDexT1} from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import {Error as FluidDexErrors} from "../../../../contracts/protocols/dex/error.sol";
import {ErrorTypes as FluidDexTypes} from "../../../../contracts/protocols/dex/errorTypes.sol";

import {FluidDexT1Admin} from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import {Structs as DexStrcuts} from "../../../../contracts/protocols/dex/poolT1/coreModule/structs.sol";
import {Structs as DexAdminStrcuts} from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import {FluidContractFactory} from "../../../../contracts/deployer/main.sol";

import {ConstantVariables as FluidDexT1ConstantVariables} from
    "../../../../contracts/protocols/dex/poolT1/common/constantVariables.sol";

import {MockProtocol} from "../../../../contracts/mocks/mockProtocol.sol";

import {MockDexCenterPrice} from "../../../../contracts/mocks/mockDexCenterPrice.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import {FluidLendingRewardsRateModel} from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import {DexFactoryBaseTest} from "./factory/dexFactory.t.sol";
import {FluidLiquidityUserModule} from "../../../../contracts/liquidity/userModule/main.sol";

import {Events as FluidLiquidityUserModuleEvents} from "../../../../contracts/liquidity/userModule/events.sol";

contract PoolT1BaseTest is DexFactoryBaseTest {
    using stdStorage for StdStorage;

    uint256 internal constant X3 = 0x7;
    uint256 internal constant X9 = 0x1ff;
    uint256 internal constant X10 = 0x3ff;
    uint256 internal constant X20 = 0xfffff;
    uint256 internal constant X22 = 0x3fffff;
    uint256 internal constant X32 = 0xffffffff;
    uint256 internal constant ORACLE_PRECISION = 1e18;

    uint256 internal constant X7 = 0x7f;
    uint256 internal constant X17 = 0x1ffff;
    uint256 internal constant X28 = 0xfffffff;
    uint256 internal constant X30 = 0x3fffffff;
    uint256 internal constant X128 = 0xffffffffffffffffffffffffffffffff;

    FluidDexReservesResolver public dexResolver;

    struct DexParams {
        FluidDexT1 dexColDebt;
        FluidDexT1 dexCol;
        FluidDexT1 dexDebt;
        address token0;
        address token1;
        uint256 token0Wei;
        uint256 token1Wei;
        string poolName;
    }

    DexParams DAI_USDC;
    DexParams DAI_USDC_WITH_LESS_THAN_ONE;
    DexParams DAI_USDC_WITH_MORE_THAN_ONE;
    DexParams DAI_USDC_WITH_LESS_ORACLE;
    DexParams DAI_USDC_WITH_LESS_THRESHOLD;
    DexParams DAI_USDC_WITH_80_20;
    DexParams DAI_USDC_WITH_50_5;
    DexParams DAI_USDC_WITH_10_1;
    DexParams USDT_USDC;
    DexParams DAI_SUSDE;
    DexParams USDT_SUSDE;
    DexParams USDC_ETH;

    enum DexType {
        NormalPool,
        SmartCol,
        SmartDebt,
        SmartColAndDebt
    }

    function setUp() public virtual override {
        super.setUp();
        dexResolver = new FluidDexReservesResolver(address(dexFactory), address(liquidity), address(resolver));
        console.log("USDT", address(USDT));
        console.log("USDC", address(USDC));
        console.log("SUSDE", address(SUSDE));
        console.log("DAI", address(DAI));

        DAI_USDC = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC", 1e4); // 18, 6
        DAI_USDC_WITH_LESS_THAN_ONE = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_LESS_THAN_ONE", 1e4); // 18, 6
        DAI_USDC_WITH_MORE_THAN_ONE = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_MORE_THAN_ONE", 1e4); // 18, 6
        USDT_USDC = _deployPoolT1(address(USDT), address(USDC), "USDT_USDC", 5 * 1e3); // 6, 6
        DAI_SUSDE = _deployPoolT1(address(DAI), address(SUSDE), "DAI_SUSDE", 1e3); // 18, 18
        USDT_SUSDE = _deployPoolT1(address(USDT), address(SUSDE), "USDT_SUSDE", 1e3); // 6, 18
        USDC_ETH = _deployPoolT1(address(USDC), address(NATIVE_TOKEN_ADDRESS), "USDC_ETH", 1e3); // 6, 18

        DAI_USDC_WITH_LESS_ORACLE = _deployPoolT1(address(DAI), address(USDC), "USDC_ETH_WITH_LESS_ORACLE", 12); // 18, 6
        DAI_USDC_WITH_LESS_THRESHOLD = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_WITH_LESS_THRESHOLD", 12); // 18, 6
        DAI_USDC_WITH_80_20 = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_WITH_80_20", 12); // 18, 6
        DAI_USDC_WITH_50_5 = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_WITH_50_5", 12); // 18, 6
        DAI_USDC_WITH_10_1 = _deployPoolT1(address(DAI), address(USDC), "DAI_USDC_WITH_10_1", 12); // 18, 6

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(SUSDE), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(NATIVE_TOKEN_ADDRESS), address(mockProtocol));

        _supply(mockProtocol, address(USDT), alice, 1e6 * 1e6);
        _supply(mockProtocol, address(USDC), alice, 1e6 * 1e6);
        _supply(mockProtocol, address(DAI), alice, 1e6 * 1e18);
        _supply(mockProtocol, address(SUSDE), alice, 1e6 * 1e18);
        _supplyNative(mockProtocol, alice, 1e6 * 1e18);

        DexAdminStrcuts.InitializeVariables memory i_;

        _setUpDexParams(DAI_USDC, 1e27, 1e4 * DAI_USDC.token0Wei, 1e4 * DAI_USDC.token0Wei, i_);
        _setUpDexParams(
            DAI_USDC_WITH_LESS_THAN_ONE,
            1.1 * 1e27,
            1e4 * DAI_USDC_WITH_LESS_THAN_ONE.token0Wei,
            1e4 * DAI_USDC_WITH_LESS_THAN_ONE.token0Wei,
            i_
        );
        _setUpDexParams(
            DAI_USDC_WITH_MORE_THAN_ONE,
            0.9 * 1e27,
            1e4 * DAI_USDC_WITH_MORE_THAN_ONE.token0Wei,
            1e4 * DAI_USDC_WITH_MORE_THAN_ONE.token0Wei,
            i_
        );
        _setUpDexParams(USDT_USDC, 1e27, 1e4 * USDT_USDC.token0Wei, 1e4 * USDT_USDC.token0Wei, i_);
        _setUpDexParams(DAI_SUSDE, 1e27, 1e4 * DAI_SUSDE.token0Wei, 1e4 * DAI_SUSDE.token0Wei, i_);
        _setUpDexParams(USDT_SUSDE, 1e27, 1e4 * USDT_SUSDE.token0Wei, 1e4 * USDT_SUSDE.token0Wei, i_);
        _setUpDexParams(USDC_ETH, 1e27, 1e4 * USDC_ETH.token0Wei, 1e4 * USDC_ETH.token0Wei, i_);
        _setUpDexParams(
            DAI_USDC_WITH_LESS_ORACLE,
            1e27,
            1e4 * DAI_USDC_WITH_LESS_ORACLE.token0Wei,
            1e4 * DAI_USDC_WITH_LESS_ORACLE.token0Wei,
            i_
        );

        {
            DexAdminStrcuts.InitializeVariables memory ci_;
            // ci_.upperPercent = 80 * 1e4;
            // ci_.lowerPercent = 20 * 1e4;
            ci_.upperPercent = 4 * 1e4;
            ci_.lowerPercent = 1 * 1e4;
            ci_.upperShiftThreshold = 80 * 1e4;
            ci_.lowerShiftThreshold = 80 * 1e4;

            _setUpDexParams(
                DAI_USDC_WITH_80_20, 1e27, 1e4 * DAI_USDC_WITH_80_20.token0Wei, 1e4 * DAI_USDC_WITH_80_20.token0Wei, ci_
            );
        }

        {
            DexAdminStrcuts.InitializeVariables memory ci_;

            // ci_.upperPercent = 50 * 1e4;
            // ci_.lowerPercent = 5 * 1e4;
            ci_.upperPercent = 0.5 * 1e4;
            ci_.lowerPercent = 2.5 * 1e4;
            ci_.upperShiftThreshold = 80 * 1e4;
            ci_.lowerShiftThreshold = 80 * 1e4;

            _setUpDexParams(
                DAI_USDC_WITH_50_5, 1e27, 1e4 * DAI_USDC_WITH_50_5.token0Wei, 1e4 * DAI_USDC_WITH_50_5.token0Wei, ci_
            );
        }

        {
            DexAdminStrcuts.InitializeVariables memory ci_;

            // ci_.upperPercent = 10 * 1e4;
            // ci_.lowerPercent = 1 * 1e4;
            ci_.upperPercent = 2.5 * 1e4;
            ci_.lowerPercent = 0.25 * 1e4;
            ci_.upperShiftThreshold = 80 * 1e4;
            ci_.lowerShiftThreshold = 80 * 1e4;

            _setUpDexParams(
                DAI_USDC_WITH_10_1, 1e27, 1e4 * DAI_USDC_WITH_10_1.token0Wei, 1e4 * DAI_USDC_WITH_10_1.token0Wei, ci_
            );
        }

        {
            DexAdminStrcuts.InitializeVariables memory ci_;

            ci_.upperShiftThreshold = 80 * 1e4;
            ci_.lowerShiftThreshold = 80 * 1e4;

            _setUpDexParams(
                DAI_USDC_WITH_LESS_THRESHOLD,
                1e27,
                1e4 * DAI_USDC_WITH_LESS_THRESHOLD.token0Wei,
                1e4 * DAI_USDC_WITH_LESS_THRESHOLD.token0Wei,
                ci_
            );
        }

        // console2.log("alice", address(alice));
        // console2.log("bob", address(bob));
        // console2.log("--------------------------------------------\n");
    }

    function _deployPoolT1(address tokenZero, address tokenOne, string memory poolName, uint256 oracleSlots_)
        internal
        returns (DexParams memory dex)
    {
        dex.poolName = poolName;
        dex.token0 = tokenZero > tokenOne ? tokenOne : tokenZero;
        dex.token1 = tokenOne > tokenZero ? tokenOne : tokenZero;
        dex.token0Wei = dex.token0 == address(NATIVE_TOKEN_ADDRESS) ? 1e18 : 10 ** (ERC20(dex.token0).decimals());
        dex.token1Wei = dex.token1 == address(NATIVE_TOKEN_ADDRESS) ? 1e18 : 10 ** (ERC20(dex.token1).decimals());

        vm.startPrank(alice);
        bytes memory poolT1CreationCode =
            abi.encodeCall(poolT1DeploymentLogic.dexT1, (dex.token0, dex.token1, oracleSlots_));
        dex.dexColDebt = FluidDexT1(payable(dexFactory.deployDex(address(poolT1DeploymentLogic), poolT1CreationCode)));
        dex.dexCol = FluidDexT1(payable(dexFactory.deployDex(address(poolT1DeploymentLogic), poolT1CreationCode)));
        dex.dexDebt = FluidDexT1(payable(dexFactory.deployDex(address(poolT1DeploymentLogic), poolT1CreationCode)));
        vm.stopPrank();

        vm.label(address(dex.dexColDebt), _getDexPoolName(dex, DexType.SmartColAndDebt));
        vm.label(address(dex.dexCol), _getDexPoolName(dex, DexType.SmartCol));
        vm.label(address(dex.dexDebt), _getDexPoolName(dex, DexType.SmartDebt));
    }

    function _makeUserContract(address user, bool makeCode) internal {
        vm.etch(user, makeCode ? address(mockDexCallback).code : new bytes(0));
    }

    function _setUpDexParams(
        DexParams memory dex,
        uint256 centerPrice,
        uint256 token0ColAmt,
        uint256 token0DebtAmt,
        DexAdminStrcuts.InitializeVariables memory initializeParams_
    ) internal {
        if (dex.token0 != address(NATIVE_TOKEN_ADDRESS)) {
            _setApproval(IERC20(dex.token0), address(dex.dexCol), alice);
            _setApproval(IERC20(dex.token0), address(dex.dexCol), bob);

            _setApproval(IERC20(dex.token0), address(dex.dexColDebt), alice);
            _setApproval(IERC20(dex.token0), address(dex.dexColDebt), bob);

            _setApproval(IERC20(dex.token0), address(dex.dexDebt), alice);
            _setApproval(IERC20(dex.token0), address(dex.dexDebt), bob);
        }

        if (dex.token1 != address(NATIVE_TOKEN_ADDRESS)) {
            _setApproval(IERC20(dex.token1), address(dex.dexCol), alice);
            _setApproval(IERC20(dex.token1), address(dex.dexCol), bob);

            _setApproval(IERC20(dex.token1), address(dex.dexColDebt), alice);
            _setApproval(IERC20(dex.token1), address(dex.dexColDebt), bob);

            _setApproval(IERC20(dex.token1), address(dex.dexDebt), alice);
            _setApproval(IERC20(dex.token1), address(dex.dexDebt), bob);
        }

        // set default allowances for vault
        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token0), address(dex.dexCol), true
        );
        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token1), address(dex.dexCol), true
        );

        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token0), address(dex.dexColDebt), true
        );
        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token1), address(dex.dexColDebt), true
        );

        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token0), address(dex.dexDebt), true
        );
        _setUserAllowancesDefaultWithModeWithHighLimit(
            address(liquidity), address(admin), address(dex.token1), address(dex.dexDebt), true
        );

        // Updating admin related things to setup dex
        DexAdminStrcuts.InitializeVariables memory initialize_ = DexAdminStrcuts.InitializeVariables({
            smartCol: false,
            token0ColAmt: 0,
            smartDebt: false,
            token0DebtAmt: 0,
            centerPrice: centerPrice,
            fee: initializeParams_.fee == 0 ? 0 : initializeParams_.fee,
            // fee: 500,
            revenueCut: 0,
            upperPercent: initializeParams_.upperPercent == 0 ? 10 * 1e4 : initializeParams_.upperPercent, // 1% = 1e4
            lowerPercent: initializeParams_.lowerPercent == 0 ? 10 * 1e4 : initializeParams_.lowerPercent, // 1% = 1e4
            upperShiftThreshold: initializeParams_.upperShiftThreshold == 0
                ? 5 * 1e4
                : initializeParams_.upperShiftThreshold, // 1% = 1e4
            lowerShiftThreshold: initializeParams_.lowerShiftThreshold == 0
                ? 5 * 1e4
                : initializeParams_.lowerShiftThreshold,
            thresholdShiftTime: initializeParams_.thresholdShiftTime == 0 ? 1 days : initializeParams_.thresholdShiftTime,
            centerPriceAddress: 0,
            hookAddress: 0,
            maxCenterPrice: centerPrice * 120 / 100,
            minCenterPrice: centerPrice * 80 / 100
        });

        bool isSameRange_ = initializeParams_.upperPercent == initializeParams_.lowerPercent;

        _makeUserContract(alice, true);
        _makeUserContract(bob, true);
        {
            // Smart Col
            initialize_.smartCol = true;
            initialize_.token0ColAmt = token0ColAmt;
            initialize_.smartDebt = false;
            initialize_.token0DebtAmt = 0;

            uint256 ethValue_ = _getSmartDebtOrColEthAmount(dex, dex.dexCol, token0ColAmt, centerPrice);
            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexCol)).initialize{value: ethValue_}(initialize_);

            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexCol)).toggleOracleActivation(true);

            _setDexUserAllowancesDefault(address(dex.dexCol), address(admin), alice);
            _setDexUserAllowancesDefault(address(dex.dexCol), address(admin), bob);
        }

        {
            // Smart Debt
            initialize_.smartCol = false;
            initialize_.token0ColAmt = 0;
            initialize_.smartDebt = true;
            initialize_.token0DebtAmt = token0DebtAmt;

            uint256 ethValue_ = _getSmartDebtOrColEthAmount(dex, dex.dexDebt, token0DebtAmt, centerPrice);

            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexDebt)).initialize{value: ethValue_}(initialize_);

            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexDebt)).toggleOracleActivation(true);

            _setDexUserAllowancesDefault(address(dex.dexDebt), address(admin), alice);
            _setDexUserAllowancesDefault(address(dex.dexDebt), address(admin), bob);
        }

        {
            // Smart Col And Debt
            initialize_.smartCol = true;
            initialize_.token0ColAmt = token0ColAmt;
            initialize_.smartDebt = true;
            initialize_.token0DebtAmt = token0DebtAmt;

            uint256 ethValue_ =
                _getSmartDebtOrColEthAmount(dex, dex.dexColDebt, token0ColAmt + token0DebtAmt, centerPrice);

            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexColDebt)).initialize{value: ethValue_}(initialize_);

            vm.prank(alice);
            FluidDexT1Admin(address(dex.dexColDebt)).toggleOracleActivation(true);

            _setDexUserAllowancesDefault(address(dex.dexColDebt), address(admin), alice);
            _setDexUserAllowancesDefault(address(dex.dexColDebt), address(admin), bob);

            if (!isSameRange_) {
                vm.prank(alice);
                dex.dexColDebt.deposit(10 * dex.token0Wei, 10 * dex.token1Wei, 0, false);
                validatePricesOfPoolAfterSwap((dex.dexColDebt), "");
            }
        }

        _makeUserContract(alice, false);
        _makeUserContract(bob, false);
    }

    function _getSmartDebtOrColEthAmount(
        DexParams memory dexPool_,
        FluidDexT1 dex_,
        uint256 token0Amount_,
        uint256 centerPrice_
    ) internal returns (uint256 ethValue_) {
        if (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS)) {
            ethValue_ = token0Amount_;
        } else if (dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            if (centerPrice_ == 0) {
                centerPrice_ = getCenterPrice(dex_);
            }
            ethValue_ = centerPrice_ * _convertNormalToAdjusted(token0Amount_, dexPool_.token0Wei) / 1e27;
            ethValue_ = _convertAdjustedToNormal(ethValue_, dexPool_.token1Wei);
        }
    }

    function _setDexUserAllowancesDefault(address dex, address admin, address user) internal {
        // Add supply config
        DexAdminStrcuts.UserSupplyConfig[] memory userSupplyConfigs_ = new DexAdminStrcuts.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = DexAdminStrcuts.UserSupplyConfig({
            user: user,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT * 100
        });

        vm.prank(admin);
        FluidDexT1Admin(dex).updateUserSupplyConfigs(userSupplyConfigs_);

        // Add borrow config
        DexAdminStrcuts.UserBorrowConfig[] memory userBorrowConfigs_ = new DexAdminStrcuts.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = DexAdminStrcuts.UserBorrowConfig({
            user: user,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
            maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING * 100
        });

        vm.prank(admin);
        FluidDexT1Admin(dex).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function getUserSupplyShare(FluidDexT1 dex, address user) internal view returns (uint256 share) {
        uint256 userSupplyData = dex.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(3, user));

        userSupplyData = (userSupplyData >> 1) & X64;
        share = (userSupplyData >> DEFAULT_EXPONENT_SIZE) << (userSupplyData & DEFAULT_EXPONENT_MASK);
    }

    function getDexType(FluidDexT1 dex) internal view returns (uint256) {
        uint256 dexVariables2_ = dex.readFromStorage(bytes32(uint256(1)));
        return dexVariables2_ & 3;
    }

    function getTotalSupplyShares(FluidDexT1 dex) internal view returns (uint256 totalShares) {
        totalShares = dex.readFromStorage(bytes32(uint256(2))) & X128;
        return totalShares;
    }

    function getUserBorrowShare(FluidDexT1 dex, address user) internal view returns (uint256 share) {
        uint256 userBorrowData = dex.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(5, user));

        userBorrowData = (userBorrowData >> 1) & X64;
        share = (userBorrowData >> DEFAULT_EXPONENT_SIZE) << (userBorrowData & DEFAULT_EXPONENT_MASK);
    }

    function getTotalBorrowShares(FluidDexT1 dex) internal view returns (uint256 totalShares_) {
        totalShares_ = dex.readFromStorage(bytes32(uint256(4))) & X128;
        return totalShares_;
    }

    function getCenterPrice(FluidDexT1 dex) internal view returns (uint256 centerPrice_) {
        uint256 dexVariables_ = dex.readFromStorage(0);
        centerPrice_ = (dexVariables_ >> 81) & X40;

        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
    }

    function getCurrentPrice(FluidDexT1 dex) internal view returns (uint256 centerPrice_) {
        uint256 dexVariables_ = dex.readFromStorage(0);
        centerPrice_ = (dexVariables_ >> 41) & X40;

        centerPrice_ = (centerPrice_ >> DEFAULT_EXPONENT_SIZE) << (centerPrice_ & DEFAULT_EXPONENT_MASK);
    }

    struct DexVariablesData {
        uint256 isEntrancy;
        uint256 lastToLastPrice;
        uint256 lastPrice;
        uint256 centerPrice;
        uint256 lastTimestamp;
        uint256 lastTimestampDifBetweenLastToLastPrice;
        uint256 oracleSlot;
        uint256 oracleMap;
    }

    function _getDexVariablesData(FluidDexT1 dex) internal view returns (DexVariablesData memory d_) {
        uint256 dexVariables_ = dex.readFromStorage(0);

        d_ = DexVariablesData({
            isEntrancy: (dexVariables_) & 1,
            lastToLastPrice: (dexVariables_ >> 1) & X40,
            lastPrice: (dexVariables_ >> 41) & X40,
            centerPrice: (dexVariables_ >> 81) & X40,
            lastTimestamp: (dexVariables_ >> 121) & X33,
            lastTimestampDifBetweenLastToLastPrice: (dexVariables_ >> 154) & X22,
            oracleSlot: (dexVariables_ >> 176) & X3,
            oracleMap: (dexVariables_ >> 179) & X16
        });

        d_.lastToLastPrice =
            (d_.lastToLastPrice >> DEFAULT_EXPONENT_SIZE) << (d_.lastToLastPrice & DEFAULT_EXPONENT_MASK);
        d_.lastPrice = (d_.lastPrice >> DEFAULT_EXPONENT_SIZE) << (d_.lastPrice & DEFAULT_EXPONENT_MASK);
        d_.centerPrice = (d_.centerPrice >> DEFAULT_EXPONENT_SIZE) << (d_.centerPrice & DEFAULT_EXPONENT_MASK);
    }

    struct DexVariables2Data {
        bool isSmartColEnabled;
        bool isSmartDebtEnabled;
        uint256 fee;
        uint256 revenueCut;
        bool isPercentChangeActive;
        uint256 upperPercent;
        uint256 lowerPercent;
        bool isThresholdPercentActive;
        uint256 upperShiftPercent;
        uint256 lowerShiftPercent;
        uint256 shiftTime;
        uint256 centerPriceAddress;
        uint256 hookDeploymentNonce;
        uint256 minCenterPrice;
        uint256 maxCenterPrice;
        uint256 utilizationLimitToken0;
        uint256 utilizationLimitToken1;
        bool isCenterPriceShiftActive;
        bool pauseSwap;
    }

    function _getDexVariables2Data(FluidDexT1 dex) internal view returns (DexVariables2Data memory d2_) {
        uint256 dexVariables2_ = dex.readFromStorage(bytes32(uint256(1)));

        d2_ = DexVariables2Data({
            isSmartColEnabled: ((dexVariables2_) & 1) == 1,
            isSmartDebtEnabled: ((dexVariables2_) & 2) == 1,
            fee: (dexVariables2_ >> 2) & X17,
            revenueCut: (dexVariables2_ >> 19) & X7,
            isPercentChangeActive: ((dexVariables2_ >> 26) & 1) == 1,
            upperPercent: (dexVariables2_ >> 27) & X20,
            lowerPercent: (dexVariables2_ >> 47) & X20,
            isThresholdPercentActive: ((dexVariables2_ >> 67) & 1) == 1,
            upperShiftPercent: ((dexVariables2_ >> 68) & X10) * 1e3,
            lowerShiftPercent: ((dexVariables2_ >> 78) & X10) * 1e3,
            shiftTime: (dexVariables2_ >> 88) & X24,
            centerPriceAddress: (dexVariables2_ >> 112) & X30,
            hookDeploymentNonce: (dexVariables2_ >> 142) & X30,
            minCenterPrice: (dexVariables2_ >> 172) & X28,
            maxCenterPrice: (dexVariables2_ >> 200) & X28,
            utilizationLimitToken0: (dexVariables2_ >> 228) & X10,
            utilizationLimitToken1: (dexVariables2_ >> 238) & X10,
            isCenterPriceShiftActive: ((dexVariables2_ >> 248) & 1) == 1,
            pauseSwap: ((dexVariables2_ >> 255) & 1) == 1
        });

        d2_.minCenterPrice =
            (d2_.minCenterPrice >> DEFAULT_EXPONENT_SIZE) << (d2_.minCenterPrice & DEFAULT_EXPONENT_MASK);
        d2_.maxCenterPrice =
            (d2_.maxCenterPrice >> DEFAULT_EXPONENT_SIZE) << (d2_.maxCenterPrice & DEFAULT_EXPONENT_MASK);
    }

    struct DexRangeShiftData {
        uint256 oldUpperShift;
        uint256 oldLowerShift;
        uint256 shiftTime;
        uint256 timestampOfShiftStart;
    }

    function _getDexRangeShiftData(FluidDexT1 dex) internal view returns (DexRangeShiftData memory rs_) {
        uint256 rangeShift_ = dex.readFromStorage(bytes32(uint256(7)));

        rs_ = DexRangeShiftData({
            oldUpperShift: (rangeShift_) & X20,
            oldLowerShift: (rangeShift_ >> 20) & X20,
            shiftTime: (rangeShift_ >> 40) & X20,
            timestampOfShiftStart: (rangeShift_ >> 60) & X33
        });
    }

    struct DexThresholdShiftData {
        uint256 oldUpperShift;
        uint256 oldLowerShift;
        uint256 shiftTime;
        uint256 timestampOfShiftStart;
        uint256 oldThresholdTimestamp;
    }

    function _getDexThresholdShiftData(FluidDexT1 dex) internal view returns (DexThresholdShiftData memory ts_) {
        uint256 thresholdShift_ = (dex.readFromStorage(bytes32(uint256(7)))) >> 128;

        ts_ = DexThresholdShiftData({
            oldUpperShift: ((thresholdShift_) & X10) * 1e3,
            oldLowerShift: ((thresholdShift_ >> 20) & X10) * 1e3,
            shiftTime: (thresholdShift_ >> 40) & X20,
            timestampOfShiftStart: (thresholdShift_ >> 60) & X33,
            oldThresholdTimestamp: (thresholdShift_ >> 93) & X24
        });
    }

    struct DexCenterPriceShiftData {
        uint256 timestampOfShiftStart;
        uint256 percentShift;
        uint256 timeToShiftPercent;
    }

    function _getDexCenterPriceShiftData(FluidDexT1 dex) internal view returns (DexCenterPriceShiftData memory cps_) {
        uint256 thresholdShift_ = dex.readFromStorage(bytes32(uint256(8)));

        cps_ = DexCenterPriceShiftData({
            timestampOfShiftStart: (thresholdShift_) & X33,
            percentShift: (thresholdShift_ >> 33) & X20,
            timeToShiftPercent: (thresholdShift_ >> 53) & X20
        });
    }

    struct DexUserSupplyData {
        bool isUserAllowed;
        uint256 userShares;
        uint256 previousUserLimit;
        uint256 lastTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseLimit;
    }

    function _getDexSupplyData(FluidDexT1 dex, address user_) internal view returns (DexUserSupplyData memory us_) {
        uint256 userSupplyData_ = dex.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(3, user_));

        us_ = DexUserSupplyData({
            isUserAllowed: ((userSupplyData_) & 1) == 1,
            userShares: (userSupplyData_ >> 1) & X64,
            previousUserLimit: (userSupplyData_ >> 65) & X64,
            lastTimestamp: (userSupplyData_ >> 129) & X33,
            expandPercent: (userSupplyData_ >> 162) & X14,
            expandDuration: (userSupplyData_ >> 176) & X24,
            baseLimit: (userSupplyData_ >> 200) & X18
        });

        us_.userShares = (us_.userShares >> DEFAULT_EXPONENT_SIZE) << (us_.userShares & DEFAULT_EXPONENT_MASK);
        us_.previousUserLimit =
            (us_.previousUserLimit >> DEFAULT_EXPONENT_SIZE) << (us_.previousUserLimit & DEFAULT_EXPONENT_MASK);
        us_.baseLimit = (us_.baseLimit >> DEFAULT_EXPONENT_SIZE) << (us_.baseLimit & DEFAULT_EXPONENT_MASK);
    }

    struct DexUserBorrowData {
        bool isUserAllowed;
        uint256 userShares;
        uint256 previousUserLimit;
        uint256 lastTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseLimit;
        uint256 maxLimit;
    }

    function _getDexBorrowData(FluidDexT1 dex, address user_) internal view returns (DexUserBorrowData memory ub_) {
        uint256 userBorrowData_ = dex.readFromStorage(LiquiditySlotsLink.calculateMappingStorageSlot(5, user_));

        ub_ = DexUserBorrowData({
            isUserAllowed: ((userBorrowData_) & 1) == 1,
            userShares: (userBorrowData_ >> 1) & X64,
            previousUserLimit: (userBorrowData_ >> 65) & X64,
            lastTimestamp: (userBorrowData_ >> 129) & X33,
            expandPercent: (userBorrowData_ >> 162) & X14,
            expandDuration: (userBorrowData_ >> 176) & X24,
            baseLimit: (userBorrowData_ >> 200) & X18,
            maxLimit: (userBorrowData_ >> 218) & X18
        });

        ub_.userShares = (ub_.userShares >> DEFAULT_EXPONENT_SIZE) << (ub_.userShares & DEFAULT_EXPONENT_MASK);
        ub_.previousUserLimit =
            (ub_.previousUserLimit >> DEFAULT_EXPONENT_SIZE) << (ub_.previousUserLimit & DEFAULT_EXPONENT_MASK);
        ub_.baseLimit = (ub_.baseLimit >> DEFAULT_EXPONENT_SIZE) << (ub_.baseLimit & DEFAULT_EXPONENT_MASK);
        ub_.maxLimit = (ub_.maxLimit >> DEFAULT_EXPONENT_SIZE) << (ub_.maxLimit & DEFAULT_EXPONENT_MASK);
    }

    struct OracleMapData {
        uint256 timeDiff;
        uint256 changePriceSign;
        uint256 changeInPrice;
        uint256 changeInPriceWithMax5Percent;
    }

    function _calculateMappingStorageSlotForUint256(uint256 slot_, uint256 key_) internal pure returns (bytes32) {
        return keccak256(abi.encode(key_, slot_));
    }

    struct OracleSlotConfig {
        uint256 totalSlots;
        uint256 totalMaps;
        uint256 totalCycle;
    }

    function _getOracleMapData(FluidDexT1 dex, uint256 oracleMap_, uint256 oracleSlot_)
        internal
        returns (OracleMapData memory data_, OracleSlotConfig memory slotConfig)
    {
        uint256 oracleMapData_ = dex.readFromStorage(_calculateMappingStorageSlotForUint256(6, oracleMap_));

        uint256 shift_ = 32 * (oracleSlot_);

        bool isVeryFirstSlot_ = (oracleMap_ == 0 && oracleSlot_ == 7);

        if ((oracleMapData_ >> (shift_)) & X32 == 0 && !(isVeryFirstSlot_)) {
            revert("shouldn't come here");
        }

        if (
            (oracleMapData_ >> (shift_)) & X9 == 0
                && (isVeryFirstSlot_ || ((oracleMapData_ >> (shift_ + 9)) & X22 != 0))
        ) {
            slotConfig.totalSlots = 2;
            uint256 changePriceSign_ = (oracleMapData_ >> (shift_ + 9)) & 1;
            uint256 changeInPrice_ = ((oracleMapData_ >> (shift_ + 10)) & X22);
            if (oracleSlot_ > 0) {
                slotConfig.totalMaps = 1;
                uint256 timeDiff_ = (oracleMapData_ >> (shift_ - 32 + 9)) & X22;
                data_ = OracleMapData({
                    timeDiff: timeDiff_,
                    changePriceSign: changePriceSign_,
                    changeInPrice: changeInPrice_ * 5e16 / X22,
                    changeInPriceWithMax5Percent: changeInPrice_
                });
            } else {
                slotConfig.totalMaps = 2;

                uint256 oracleNextMapData_ = dex.readFromStorage(
                    _calculateMappingStorageSlotForUint256(6, (oracleMap_ + 1) % dex.constantsView().oracleMapping)
                );

                uint256 timeDiff_ = (oracleNextMapData_ >> ((7 * 32) + 9)) & X22;
                data_ = OracleMapData({
                    timeDiff: timeDiff_,
                    changePriceSign: changePriceSign_,
                    changeInPrice: changeInPrice_ * 5e16 / X22,
                    changeInPriceWithMax5Percent: changeInPrice_
                });
            }
        } else {
            slotConfig.totalSlots = 1;
            data_ = OracleMapData({
                timeDiff: (oracleMapData_ >> (shift_)) & X9,
                changePriceSign: (oracleMapData_ >> (shift_ + 9)) & 1,
                changeInPrice: ((oracleMapData_ >> (shift_ + 10)) & X22) * 5e16 / X22,
                changeInPriceWithMax5Percent: (oracleMapData_ >> (shift_ + 10)) & X22
            });
        }

        if ((slotConfig.totalSlots == 1 && oracleSlot_ == 0) || (slotConfig.totalSlots == 2 && oracleSlot_ <= 1)) {
            if (((oracleMap_ + 1) % dex.constantsView().oracleMapping) != oracleMap_ + 1) {
                slotConfig.totalCycle = 1;
            }
        }
    }

    function _getOracleAllSlotsData(FluidDexT1 dex) internal returns (OracleMapData[] memory data_) {
        uint256 oracleSlot_ = _getDexVariablesData(dex).oracleSlot;
        uint256 oracleMap_ = _getDexVariablesData(dex).oracleMap;

        uint256 totalOracleSlots_ = (oracleMap_ * 8) + (7 - oracleSlot_);

        uint256 k = 0;
        OracleMapData[] memory dataTemp_ = new OracleMapData[](totalOracleSlots_);

        uint256 j = 8;
        for (uint256 i = 0; i <= oracleMap_; i++) {
            uint256 oracleMapData_ = dex.readFromStorage(_calculateMappingStorageSlotForUint256(6, i));

            for (j; j > 0; j--) {
                uint256 shift_ = 32 * (j - 1);
                bool isVeryFirstSlot_ = (i == 0 && j == 8);

                if ((oracleMapData_ >> (shift_)) & X32 == 0 && !(isVeryFirstSlot_)) {
                    break;
                }

                OracleSlotConfig memory c_;

                (dataTemp_[k++], c_) = _getOracleMapData(dex, i, j - 1);

                if (c_.totalSlots == 2) {
                    if (c_.totalMaps == 1) {
                        j--;
                    } else if (c_.totalMaps == 2) {
                        j = 7;
                        break;
                    } else {}
                }
            }

            if (j == 0) j = 8;
        }

        data_ = new OracleMapData[](k);

        for (uint256 i = 0; i < k; i++) {
            data_[i] = dataTemp_[i];
        }
    }

    function validateAfterTest(FluidDexT1 dex) internal view {
        uint256 dexVariables_ = dex.readFromStorage(0);
        assertEq(dexVariables_ & 1, 0, "validateAfterTest: dex pool didn't uninitialize re-entrancy");
    }

    function validatePricesOfPoolAfterSwap(FluidDexT1 dex, string memory assertMessage_) internal {
        if (getDexType(dex) != 3) return;

        // Decode the sliced bytes into the specified struct
        DexStrcuts.PricesAndExchangePrice memory pex_ = _getPricesAndExchangePrices(dex);
        FluidDexT1.CollateralReserves memory c_ = dex.getCollateralReserves(
            pex_.geometricMean,
            pex_.upperRange,
            pex_.lowerRange,
            pex_.supplyToken0ExchangePrice,
            pex_.supplyToken1ExchangePrice
        );
        FluidDexT1.DebtReserves memory d_ = dex.getDebtReserves(
            pex_.geometricMean,
            pex_.upperRange,
            pex_.lowerRange,
            pex_.borrowToken0ExchangePrice,
            pex_.borrowToken1ExchangePrice
        );

        uint256 collPrice_ = c_.token1ImaginaryReserves * 1e12 / c_.token0ImaginaryReserves;
        uint256 debtPrice_ = d_.token1ImaginaryReserves * 1e12 / d_.token0ImaginaryReserves;

        assertApproxEqAbs(
            collPrice_,
            debtPrice_,
            1000,
            string(abi.encodePacked(assertMessage_, " col price and debt price is not same after swap"))
        );
    }

    error FluidTest_Error(uint256);

    struct DepositPerfectColLiquidityParams {
        DexParams dexPools;
        uint256 shareAmount;
    }

    struct StateData {
        uint256 userToken0Balance;
        uint256 userToken1Balance;
        uint256 liquidityToken0Balance;
        uint256 liquidityToken1Balance;
        uint256 liquidityToken0SupplyReserve;
        uint256 liquidityToken1SupplyReserve;
        uint256 liquidityToken0BorrowReserve;
        uint256 liquidityToken1BorrowReserve;
        uint256 totalSupplyShares;
        uint256 totalBorrowShares;
        uint256 userSupplyShares;
        uint256 userBorrowShares;
    }

    function _getTokenBalance(address token_, address user_) internal returns (uint256) {
        return token_ == address(NATIVE_TOKEN_ADDRESS) ? user_.balance : IERC20(token_).balanceOf(user_);
    }

    function _getDexType(DexParams memory dexPool_, DexType dexType_, bool skipValidation)
        internal
        returns (FluidDexT1 dex_)
    {
        if (dexType_ == DexType.SmartColAndDebt) {
            dex_ = dexPool_.dexColDebt;
            if (!skipValidation) assertEq(getDexType(dex_), 3, "Dex Smart Col and Debt not enabled");
        } else if (dexType_ == DexType.SmartCol) {
            dex_ = dexPool_.dexCol;
            if (!skipValidation) assertEq(getDexType(dex_), 1, "Dex Smart Col not enabled");
        } else if (dexType_ == DexType.SmartDebt) {
            dex_ = dexPool_.dexDebt;
            if (!skipValidation) assertEq(getDexType(dex_), 2, "Dex Smart Debt not enabled");
        } else {
            revert("no dex type");
        }
    }

    struct DexState {
        DexVariablesData d;
        DexVariables2Data d2;
        DexRangeShiftData rs;
        DexThresholdShiftData ts;
        DexCenterPriceShiftData cps;
    }

    function getDexState(DexParams memory dexPool_, FluidDexT1 dex_) internal returns (DexState memory ds_) {
        ds_.d = _getDexVariablesData(dex_);
        ds_.d2 = _getDexVariables2Data(dex_);
        ds_.rs = _getDexRangeShiftData(dex_);
        ds_.ts = _getDexThresholdShiftData(dex_);
        ds_.cps = _getDexCenterPriceShiftData(dex_);
    }

    function getState(DexParams memory dexPool_, FluidDexT1 dex_, address user_) internal returns (StateData memory) {
        (FluidLiquidityResolver.UserSupplyData memory userSupplyDataToken0_,) =
            resolver.getUserSupplyData(address(dex_), dexPool_.token0);
        (FluidLiquidityResolver.UserSupplyData memory userSupplyDataToken1_,) =
            resolver.getUserSupplyData(address(dex_), dexPool_.token1);
        (FluidLiquidityResolver.UserBorrowData memory userBorrowDataToken0_,) =
            resolver.getUserBorrowData(address(dex_), dexPool_.token0);
        (FluidLiquidityResolver.UserBorrowData memory userBorrowDataToken1_,) =
            resolver.getUserBorrowData(address(dex_), dexPool_.token1);

        StateData memory s_ = StateData({
            userToken0Balance: _getTokenBalance(dexPool_.token0, user_),
            userToken1Balance: _getTokenBalance(dexPool_.token1, user_),
            liquidityToken0Balance: _getTokenBalance(dexPool_.token0, address(liquidity)),
            liquidityToken1Balance: _getTokenBalance(dexPool_.token1, address(liquidity)),
            liquidityToken0SupplyReserve: userSupplyDataToken0_.supply,
            liquidityToken1SupplyReserve: userSupplyDataToken1_.supply,
            liquidityToken0BorrowReserve: userBorrowDataToken0_.borrow,
            liquidityToken1BorrowReserve: userBorrowDataToken1_.borrow,
            totalSupplyShares: getTotalSupplyShares(dex_),
            totalBorrowShares: getTotalBorrowShares(dex_),
            userSupplyShares: getUserSupplyShare(dex_, user_),
            userBorrowShares: getUserBorrowShare(dex_, user_)
        });

        return s_;
    }

    function _getPricesAndExchangePrices(FluidDexT1 dex_)
        internal
        returns (DexStrcuts.PricesAndExchangePrice memory pex_)
    {
        (bool status_, bytes memory returnData_) =
            address(dex_).call(abi.encodeWithSelector(FluidDexT1.getPricesAndExchangePrices.selector));

        require(!status_, "getPricesAndExchangePrices didn't fail");

        bytes memory tempBytes;

        assembly {
            // Allocate memory for the output bytes array
            tempBytes := mload(0x40)

            // Calculate the length of the sliced bytes array, excluding the first 4 bytes (function selector)
            let length := sub(mload(returnData_), 4)

            // Set the length of the output bytes array
            mstore(tempBytes, length)

            // Calculate the start position of the input bytes array in memory
            let start := add(returnData_, 0x24) // 0x20 for the length prefix + 4 for the selector

            // Copy the sliced portion to the output bytes array
            for { let i := 0 } lt(i, length) { i := add(i, 0x20) } {
                mstore(add(tempBytes, add(0x20, i)), mload(add(start, i)))
            }

            // Update the free memory pointer
            mstore(0x40, add(add(tempBytes, 0x20), length))
        }

        // Decode the sliced bytes into the specified struct
        pex_ = abi.decode(tempBytes, (DexStrcuts.PricesAndExchangePrice));
    }

    function _getDexPoolName(DexParams memory dexPool_, DexType dexType_) internal returns (string memory s_) {
        s_ = string(abi.encodePacked(dexPool_.poolName, ":::"));
        if (dexType_ == DexType.SmartColAndDebt) {
            s_ = string(abi.encodePacked(s_, "ColDeb::"));
        } else if (dexType_ == DexType.SmartCol) {
            s_ = string(abi.encodePacked(s_, "Col::"));
        } else if (dexType_ == DexType.SmartDebt) {
            s_ = string(abi.encodePacked(s_, "Debt::"));
        }
    }

    function _convertNormalToAdjusted(uint256 amount_, uint256 weiAmount_) internal returns (uint256 adjustedAmt_) {
        if (weiAmount_ == 1e12) {
            adjustedAmt_ = amount_;
        } else if (weiAmount_ > 1e12) {
            adjustedAmt_ = amount_ / (weiAmount_ / 1e12);
        } else {
            adjustedAmt_ = amount_ * (1e12 / weiAmount_);
        }
        return adjustedAmt_;
    }

    function _convertAdjustedToNormal(uint256 adjustedAmt_, uint256 weiAmount_)
        internal
        returns (uint256 convertedAmount_)
    {
        if (weiAmount_ == 1e12) {
            convertedAmount_ = adjustedAmt_;
        } else if (weiAmount_ > 1e12) {
            convertedAmount_ = adjustedAmt_ * (weiAmount_ / 1e12);
        } else {
            convertedAmount_ = adjustedAmt_ / (1e12 / weiAmount_);
        }
        return convertedAmount_;
    }

    function _convertNormalToAdjustedToNormal(uint256 amount_, uint256 weiAmount_) internal returns (uint256) {
        uint256 adjustedAmount_ = _convertNormalToAdjusted(amount_, weiAmount_);
        return _convertAdjustedToNormal(adjustedAmount_, weiAmount_);
    }

    function _convertNormalToBNToNormalLimit(uint256 limit_) internal view returns (uint256) {
        uint256 temp_ = BigMathMinified.toBigNumber(
            limit_, SMALL_COEFFICIENT_SIZE, DEFAULT_COEFFICIENT_SIZE, BigMathMinified.ROUND_DOWN
        );
        return (temp_ >> DEFAULT_COEFFICIENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
    }

    function _comparePrecision(
        uint256 num1_,
        uint256 num2_,
        uint256 tokenWei_,
        uint256 additionalPrecision_,
        string memory assertMessage_
    ) internal pure {
        if (num1_ == num2_) return;
        uint256 weiDelta_ = 5 + additionalPrecision_;
        num1_ = num1_ - 1;

        if (tokenWei_ < 1e8) {
            assertApproxEqAbs(num1_, num2_, weiDelta_, assertMessage_);
        } else {
            uint256 num1TotalDigits_ = _numDigits(num1_);
            uint256 num1Digits_ = _numDigits(num1_ / tokenWei_);

            if (num1Digits_ > 0) {
                uint256 factor_ = 10 ** (num1TotalDigits_ - num1Digits_ - 8);

                assertApproxEqAbs(num1_ / factor_, num2_ / factor_, weiDelta_, assertMessage_);
            } else {
                if (num1TotalDigits_ > 8) {
                    uint256 factor_ = 10 ** (num1TotalDigits_ - 8);
                    assertApproxEqAbs(num1_ / factor_, num2_ / factor_, weiDelta_, assertMessage_);
                } else {
                    revert(string(abi.encodePacked(assertMessage_, "it shouldn't come here")));
                }
            }
        }
    }

    function _comparePrecision(
        int256 num1_,
        int256 num2_,
        uint256 tokenWei_,
        uint256 additionalPrecision_,
        string memory assertMessage_
    ) internal pure {
        if (num1_ >= 0 && num2_ >= 0) {
            _comparePrecision(uint256(num1_), uint256(num2_), tokenWei_, additionalPrecision_, assertMessage_);
        } else if (num1_ < 0 && num2_ < 0) {
            _comparePrecision(uint256(-num1_), uint256(-num2_), tokenWei_, additionalPrecision_, assertMessage_);
        } else {
            revert("_comparePrecision + and - numbers");
        }
    }

    function _numDigits(uint256 num) public pure returns (uint256) {
        uint256 digits = 0;
        while (num != 0) {
            num /= 10;
            digits++;
        }
        return digits;
    }

    function _validatePerfectAmounts(
        DexParams memory dexPool_,
        bool isSupply,
        uint256 token0Amount_,
        uint256 token1Amount_,
        uint256 shareAmount_,
        StateData memory s_,
        string memory assertMessage_
    ) internal {
        _comparePrecision(
            token0Amount_,
            _convertNormalToAdjustedToNormal(
                isSupply ? s_.liquidityToken0SupplyReserve : s_.liquidityToken0BorrowReserve, dexPool_.token0Wei
            ) * shareAmount_ / (isSupply ? s_.totalSupplyShares : s_.totalBorrowShares),
            dexPool_.token0Wei,
            0,
            string(abi.encodePacked(assertMessage_, "_validatePerfectAmounts: token0Amount is not expected"))
        );

        _comparePrecision(
            token1Amount_,
            _convertNormalToAdjustedToNormal(
                isSupply ? s_.liquidityToken1SupplyReserve : s_.liquidityToken1BorrowReserve, dexPool_.token1Wei
            ) * shareAmount_ / (isSupply ? s_.totalSupplyShares : s_.totalBorrowShares),
            dexPool_.token1Wei,
            0,
            string(abi.encodePacked(assertMessage_, "_validatePerfectAmounts: token1Amount is not expected"))
        );
    }

    function _testDepositPerfectColLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        DexType dexType_
    ) internal returns (uint256 token0Amount_, uint256 token1Amount_) {
        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testDepositPerfectColLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_)
            )
        );

        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));

        PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
        string[] memory inputs = new string[](13);
        inputs[0] = "node";
        inputs[1] = "dexMath/userOperations/validate.js";
        inputs[2] = "5";
        inputs[5] = _uintToString(
            uint256(
                dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token0).decimals()
            )
        );
        inputs[6] = _uintToString(
            uint256(
                dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token1).decimals()
            )
        );
        inputs[7] = "1";
        inputs[8] = _uintToString(preState_.totalSupplyShares);
        inputs[9] = _uintToString(poolState.collateralReserves.token0RealReserves);
        inputs[10] = _uintToString(poolState.collateralReserves.token1RealReserves);
        inputs[11] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
        inputs[12] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

        vm.prank(address(user_));

        uint256 ethValue_ = 0;
        if (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) || dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            ethValue_ = user_.balance;
        }
        (token0Amount_, token1Amount_) =
            dex_.depositPerfect{value: ethValue_}(shareAmount_, type(uint256).max, type(uint256).max, false);

        {
            inputs[3] = _uintToString(token0Amount_);
            inputs[4] = _uintToString(0);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
            uint256 percentDiff = (shareAmount_ > JsOutput)
                ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                : (JsOutput - shareAmount_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        {
            inputs[3] = _uintToString(0);
            inputs[4] = _uintToString(token1Amount_);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
            uint256 percentDiff = (shareAmount_ > JsOutput)
                ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                : (JsOutput - shareAmount_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        _validatePerfectAmounts(dexPool_, true, token0Amount_, token1Amount_, shareAmount_, preState_, assertMessage_);
        StateData memory postState_ = getState(dexPool_, dex_, address(user_));
        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken0Balance - postState_.userToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken1Balance - postState_.userToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            postState_.totalSupplyShares - preState_.totalSupplyShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.totalBorrowShares - preState_.totalBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userSupplyShares - preState_.userSupplyShares,
            shareAmount_,
            262144,
            string(abi.encodePacked(assertMessage_, "user supply share is not expected"))
        );
        assertApproxEqAbs(
            postState_.userBorrowShares - preState_.userBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow share is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testWithdrawPerfectColLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 token0AmountWithdraw_, uint256 token1AmountWithdraw_) {
        _makeUserContract(user_, true);
        _makeUserContract(bob, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
        string[] memory inputs = new string[](13);
        inputs[0] = "node";
        inputs[1] = "dexMath/userOperations/validate.js";
        inputs[2] = "6";
        inputs[5] = _uintToString(
            uint256(
                dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token0).decimals()
            )
        );
        inputs[6] = _uintToString(
            uint256(
                dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token1).decimals()
            )
        );
        inputs[7] = "1";
        inputs[8] = _uintToString(preState_.totalSupplyShares);
        inputs[9] = _uintToString(poolState.collateralReserves.token0RealReserves);
        inputs[10] = _uintToString(poolState.collateralReserves.token1RealReserves);
        inputs[11] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
        inputs[12] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testWithdrawPerfectColLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_)
            )
        );

        if (revertReason_.length > 0) vm.expectRevert(revertReason_);
        vm.prank(address(user_));
        (token0AmountWithdraw_, token1AmountWithdraw_) = dex_.withdrawPerfect(shareAmount_, 0, 0, address(0));

        if (revertReason_.length == 0) {
            {
                inputs[3] = _uintToString(token0AmountWithdraw_);
                inputs[4] = _uintToString(0);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                if (token0AmountWithdraw_ == 0) {
                    assert(JsOutput == 0);
                } else {
                    assert(percentDiff <= 1);
                }
            }
            {
                inputs[3] = _uintToString(0);
                inputs[4] = _uintToString(token1AmountWithdraw_);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                if (token1AmountWithdraw_ == 0) {
                    assert(JsOutput == 0);
                } else {
                    assert(percentDiff <= 1);
                }
            }

            {
                string[] memory inputsAdjusted = new string[](12);
                inputsAdjusted[0] = "node";
                inputsAdjusted[1] = "dexMath/userOperations/validate.js";
                inputsAdjusted[2] = "11";
                inputsAdjusted[3] = _uintToString(shareAmount_);
                inputsAdjusted[4] = _uintToString(
                    uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                );
                inputsAdjusted[5] = _uintToString(
                    uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
                );
                inputsAdjusted[6] = "1";
                inputsAdjusted[7] = _uintToString(preState_.totalSupplyShares);
                inputsAdjusted[8] = _uintToString(poolState.collateralReserves.token0RealReserves);
                inputsAdjusted[9] = _uintToString(poolState.collateralReserves.token1RealReserves);
                inputsAdjusted[10] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
                inputsAdjusted[11] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

                bytes memory response = vm.ffi(inputsAdjusted);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (token0AmountWithdraw_ > JsOutput)
                    ? (token0AmountWithdraw_ - JsOutput) * 10000 / token0AmountWithdraw_
                    : (JsOutput - token0AmountWithdraw_) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }
            {
                string[] memory inputsAdjusted = new string[](12);
                inputsAdjusted[0] = "node";
                inputsAdjusted[1] = "dexMath/userOperations/validate.js";
                inputsAdjusted[2] = "12";
                inputsAdjusted[3] = _uintToString(shareAmount_);
                inputsAdjusted[4] = _uintToString(
                    uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                );
                inputsAdjusted[5] = _uintToString(
                    uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
                );
                inputsAdjusted[6] = "1";
                inputsAdjusted[7] = _uintToString(preState_.totalSupplyShares);
                inputsAdjusted[8] = _uintToString(poolState.collateralReserves.token0RealReserves);
                inputsAdjusted[9] = _uintToString(poolState.collateralReserves.token1RealReserves);
                inputsAdjusted[10] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
                inputsAdjusted[11] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

                bytes memory response = vm.ffi(inputsAdjusted);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (token1AmountWithdraw_ > JsOutput)
                    ? (token1AmountWithdraw_ - JsOutput) * 10000 / token1AmountWithdraw_
                    : (JsOutput - token1AmountWithdraw_) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }
        }

        if (revertReason_.length > 0) return (token0AmountWithdraw_, token1AmountWithdraw_);

        _validatePerfectAmounts(
            dexPool_, true, token0AmountWithdraw_, token1AmountWithdraw_, shareAmount_, preState_, assertMessage_
        );

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));
        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
            token0AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
            token1AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken0Balance - preState_.userToken0Balance,
            token0AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken1Balance - preState_.userToken1Balance,
            token1AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            shareAmount_,
            262144,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testWithdrawPerfectInOne(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        bool withdrawInToken0,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 token0AmountWithdraw_, uint256 token1AmountWithdraw_) {
        _makeUserContract(user_, true);
        _makeUserContract(bob, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);
        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](13);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "9";
            inputs[3] = _uintToString(shareAmount_);
            inputs[4] = _uintToString(withdrawInToken0 ? 0 : 1);
            inputs[5] = _uintToString(
                withdrawInToken0
                    ? uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                    : uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
            );
            inputs[6] = "1";
            inputs[7] = _uintToString(poolState.fee);
            inputs[8] = _uintToString(preState_.totalSupplyShares);
            inputs[9] = _uintToString(poolState.collateralReserves.token0RealReserves);
            inputs[10] = _uintToString(poolState.collateralReserves.token1RealReserves);
            inputs[11] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
            inputs[12] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }
        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testWithdrawPerfectInOne::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_)
            )
        );

        if (revertReason_.length > 0) vm.expectRevert(revertReason_);
        vm.prank(address(user_));
        uint256 withdrawAmt_ =
            dex_.withdrawPerfectInOneToken(shareAmount_, withdrawInToken0 ? 1 : 0, withdrawInToken0 ? 0 : 1, address(0));
        if (revertReason_.length == 0) {
            uint256 percentDiff = (withdrawAmt_ > JsOutput)
                ? (withdrawAmt_ - JsOutput) * 10000 / withdrawAmt_
                : (JsOutput - withdrawAmt_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }
        if (revertReason_.length > 0) return (token0AmountWithdraw_, token1AmountWithdraw_);

        (token0AmountWithdraw_, token1AmountWithdraw_) =
            withdrawInToken0 ? (withdrawAmt_, uint256(0)) : (uint256(0), withdrawAmt_);

        // TODO: adjust the case
        // _validatePerfectAmounts(dexPool_, true, token0AmountWithdraw_, token1AmountWithdraw_, shareAmount_, preState_, assertMessage_);

        // Validate Liquidity and user balances of token0 and token1
        StateData memory postState_ = getState(dexPool_, dex_, address(user_));
        assertApproxEqAbs(
            preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
            token0AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
            token1AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken0Balance - preState_.userToken0Balance,
            token0AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken1Balance - preState_.userToken1Balance,
            token1AmountWithdraw_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            shareAmount_,
            262144,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testBorrowPerfectDebtLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 token0Amount_, uint256 token1Amount_) {
        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);
        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));

        PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
        string[] memory inputs = new string[](15);
        inputs[0] = "node";
        inputs[1] = "dexMath/userOperations/validate.js";
        inputs[2] = "7";
        inputs[5] = _uintToString(
            uint256(
                dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token0).decimals()
            )
        );
        inputs[6] = _uintToString(
            uint256(
                dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token1).decimals()
            )
        );
        inputs[7] = "1";
        inputs[8] = _uintToString(preState_.totalBorrowShares);
        inputs[9] = _uintToString(poolState.debtReserves.token0Debt);
        inputs[10] = _uintToString(poolState.debtReserves.token1Debt);
        inputs[11] = _uintToString(poolState.debtReserves.token0RealReserves);
        inputs[12] = _uintToString(poolState.debtReserves.token1RealReserves);
        inputs[13] = _uintToString(poolState.debtReserves.token0ImaginaryReserves);
        inputs[14] = _uintToString(poolState.debtReserves.token1ImaginaryReserves);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testBorrowPerfectDebtLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_),
                " "
            )
        );

        vm.prank(address(user_));
        if (revertReason_.length > 0) vm.expectRevert(revertReason_);
        (token0Amount_, token1Amount_) =
            dex_.borrowPerfect(shareAmount_, type(uint256).min, type(uint256).min, address(0));

        if (revertReason_.length == 0) {
            {
                inputs[3] = _uintToString(token0Amount_);
                inputs[4] = _uintToString(0);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                if (token0Amount_ == 0) {
                    assert(JsOutput == 0);
                } else {
                    assert(percentDiff <= 1);
                }
            }

            {
                inputs[3] = _uintToString(0);
                inputs[4] = _uintToString(token1Amount_);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                if (token1Amount_ == 0) {
                    assert(JsOutput == 0);
                } else {
                    assert(percentDiff <= 1);
                }
            }
        }

        if (revertReason_.length > 0) return (token0Amount_, token1Amount_);

        _validatePerfectAmounts(dexPool_, false, token0Amount_, token1Amount_, shareAmount_, preState_, assertMessage_);
        // Validate Liquidity and user balances of token0 and token1

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));
        assertApproxEqAbs(
            preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken0Balance - preState_.userToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken1Balance - preState_.userToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            postState_.totalSupplyShares - preState_.totalSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userSupplyShares - preState_.userSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.totalBorrowShares - preState_.totalBorrowShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userBorrowShares - preState_.userBorrowShares,
            shareAmount_,
            262144,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testPaybackPerfectDebtLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        DexType dexType_
    ) internal returns (uint256 token0AmountPayback, uint256 token1AmountPayback) {
        _makeUserContract(user_, true);
        _makeUserContract(bob, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));

        PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testPaybackPerfectDebtLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_)
            )
        );
        uint256 ethValue_ = 0;
        if (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) || dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS)) {
            ethValue_ = user_.balance;
        }

        vm.prank(address(user_));
        (token0AmountPayback, token1AmountPayback) =
            dex_.paybackPerfect{value: ethValue_}(shareAmount_, type(uint256).max, type(uint256).max, false);


        {        
            string[] memory inputs = new string[](15);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "8";
            inputs[5] = _uintToString(
                uint256(
                    dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token0).decimals()
                )
            );
            inputs[6] = _uintToString(
                uint256(
                    dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE ? 18 : ERC20(dexPool_.token1).decimals()
                )
            );
            inputs[7] = "1";
            inputs[8] = _uintToString(preState_.totalBorrowShares);
            inputs[9] = _uintToString(poolState.debtReserves.token0Debt);
            inputs[10] = _uintToString(poolState.debtReserves.token1Debt);
            inputs[11] = _uintToString(poolState.debtReserves.token0RealReserves);
            inputs[12] = _uintToString(poolState.debtReserves.token1RealReserves);
            inputs[13] = _uintToString(poolState.debtReserves.token0ImaginaryReserves);
            inputs[14] = _uintToString(poolState.debtReserves.token1ImaginaryReserves);

            {
                inputs[3] = _uintToString(token0AmountPayback);
                inputs[4] = _uintToString(0);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }

            {
                inputs[3] = _uintToString(0);
                inputs[4] = _uintToString(token1AmountPayback);

                bytes memory response = vm.ffi(inputs);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (shareAmount_ > JsOutput)
                    ? (shareAmount_ - JsOutput) * 10000 / shareAmount_
                    : (JsOutput - shareAmount_) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }

            {
                string[] memory inputsAdjusted = new string[](14);
                inputsAdjusted[0] = "node";
                inputsAdjusted[1] = "dexMath/userOperations/validate.js";
                inputsAdjusted[2] = "13";
                inputsAdjusted[3] = _uintToString(shareAmount_);
                inputsAdjusted[4] = _uintToString(
                    uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                );
                inputsAdjusted[5] = _uintToString(
                    uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
                );
                inputsAdjusted[6] = "1";
                inputsAdjusted[7] = _uintToString(preState_.totalBorrowShares);
                inputsAdjusted[8] = _uintToString(poolState.debtReserves.token0Debt);
                inputsAdjusted[9] = _uintToString(poolState.debtReserves.token1Debt);
                inputsAdjusted[10] = _uintToString(poolState.collateralReserves.token0RealReserves);
                inputsAdjusted[11] = _uintToString(poolState.collateralReserves.token1RealReserves);
                inputsAdjusted[12] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
                inputsAdjusted[13] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

                bytes memory response = vm.ffi(inputsAdjusted);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (token0AmountPayback > JsOutput)
                    ? (token0AmountPayback - JsOutput) * 10000 / token0AmountPayback
                    : (JsOutput - token0AmountPayback) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }
            {
                string[] memory inputsAdjusted = new string[](14);
                inputsAdjusted[0] = "node";
                inputsAdjusted[1] = "dexMath/userOperations/validate.js";
                inputsAdjusted[2] = "14";
                inputsAdjusted[3] = _uintToString(shareAmount_);
                inputsAdjusted[4] = _uintToString(
                    uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                );
                inputsAdjusted[5] = _uintToString(
                    uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
                );
                inputsAdjusted[6] = "1";
                inputsAdjusted[7] = _uintToString(preState_.totalBorrowShares);
                inputsAdjusted[8] = _uintToString(poolState.debtReserves.token0Debt);
                inputsAdjusted[9] = _uintToString(poolState.debtReserves.token1Debt);
                inputsAdjusted[10] = _uintToString(poolState.collateralReserves.token0RealReserves);
                inputsAdjusted[11] = _uintToString(poolState.collateralReserves.token1RealReserves);
                inputsAdjusted[12] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
                inputsAdjusted[13] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

                bytes memory response = vm.ffi(inputsAdjusted);
                JsOutput = _bytesToDecimal(response);
                uint256 percentDiff = (token1AmountPayback > JsOutput)
                    ? (token1AmountPayback - JsOutput) * 10000 / token1AmountPayback
                    : (JsOutput - token1AmountPayback) * 10000 / JsOutput;
                assert(percentDiff <= 1);
            }
        }

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        _validatePerfectAmounts(
            dexPool_, false, token0AmountPayback, token1AmountPayback, shareAmount_, preState_, assertMessage_
        );
        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
            token0AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
            token1AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken0Balance - postState_.userToken0Balance,
            token0AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken1Balance - postState_.userToken1Balance,
            token1AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            shareAmount_,
            262144,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testPaybackPerfectInOneToken(
        DexParams memory dexPool_,
        address user_,
        uint256 shareAmount_,
        bool paybackInToken0_,
        DexType dexType_
    ) internal returns (uint256 token0AmountPayback, uint256 token1AmountPayback) {
        _makeUserContract(user_, true);
        _makeUserContract(bob, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](15);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "10";
            inputs[3] = _uintToString(shareAmount_);
            inputs[4] = _uintToString(paybackInToken0_ ? 0 : 1);
            inputs[5] = _uintToString(
                paybackInToken0_
                    ? uint256(
                        dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token0).decimals()
                    )
                    : uint256(
                        dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                            ? 18
                            : ERC20(dexPool_.token1).decimals()
                    )
            );
            inputs[6] = "1";
            inputs[7] = _uintToString(poolState.fee);
            inputs[8] = _uintToString(preState_.totalBorrowShares);
            inputs[9] = _uintToString(poolState.debtReserves.token0Debt);
            inputs[10] = _uintToString(poolState.debtReserves.token1Debt);
            inputs[11] = _uintToString(poolState.debtReserves.token0RealReserves);
            inputs[12] = _uintToString(poolState.debtReserves.token1RealReserves);
            inputs[13] = _uintToString(poolState.debtReserves.token0ImaginaryReserves);
            inputs[14] = _uintToString(poolState.debtReserves.token1ImaginaryReserves);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testPaybackPerfectDebtLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(shareAmount_)
            )
        );

        uint256 ethValue_ = 0;
        if (
            (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) && paybackInToken0_)
                || (dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS) && !paybackInToken0_)
        ) {
            ethValue_ = user_.balance;
        }

        vm.prank(address(user_));
        uint256 paybackAmt_ = dex_.paybackPerfectInOneToken{value: ethValue_}(
            shareAmount_, paybackInToken0_ ? type(uint128).max : 0, paybackInToken0_ ? 0 : type(uint128).max, false
        );

        {
            uint256 percentDiff = (paybackAmt_ > JsOutput)
                ? (paybackAmt_ - JsOutput) * 10000 / paybackAmt_
                : (JsOutput - paybackAmt_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        (token0AmountPayback, token1AmountPayback) =
            paybackInToken0_ ? (paybackAmt_, uint256(0)) : (uint256(0), paybackAmt_);

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        // TODO: adjust the case
        // _validatePerfectAmounts(dexPool_, false, token0AmountPayback, token1AmountPayback, shareAmount_, preState_, assertMessage_);

        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
            token0AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
            token1AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken0Balance - postState_.userToken0Balance,
            token0AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken1Balance - postState_.userToken1Balance,
            token1AmountPayback,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            shareAmount_,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _getSwapEthAmount(DexParams memory dexPool_, bool swap0to1_, address user_, uint256 amountIn_)
        internal
        returns (uint256 ethValue_)
    {
        if (
            (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) && swap0to1_)
                || (dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS) && !swap0to1_)
        ) {
            if (amountIn_ == 0) {
                ethValue_ = user_.balance;
            } else {
                ethValue_ = amountIn_;
            }
        } else {
            ethValue_ = 0;
        }
    }

    struct SwapData {
        FluidDexT1 dex;
        string assertMessage;
        StateData preState;
        StateData postState;
        uint256 weiDiff;
    }

    function _testSwapExactIn(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool swap0to1_,
        DexType dexType_,
        bool skipDepositOrBorrow,
        bool skipDexValidate,
        bool skipPriceValidate
    ) internal returns (uint256 amountOut_) {
        _makeUserContract(user_, true);
        SwapData memory d_;
        d_.dex = _getDexType(dexPool_, dexType_, skipDexValidate);

        if (dexType_ == DexType.SmartColAndDebt) {
            // Deposit liquidity for swap, 100k
            if (!skipDepositOrBorrow) _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        } else if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            if (!skipDepositOrBorrow) {
                _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
            }
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            if (!skipDepositOrBorrow) _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        d_.assertMessage = string(
            abi.encodePacked(
                "_testSwapExactIn::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                " ",
                swap0to1_ ? "0to1" : "1to0"
            )
        );

        d_.preState = getState(dexPool_, d_.dex, address(alice));
        {
            skip(1);
            vm.prank(address(user_));
            amountOut_ = d_.dex.swapIn{value: _getSwapEthAmount(dexPool_, swap0to1_, user_, amountIn_)}(
                swap0to1_, amountIn_, 0, address(user_)
            );
        }

        {
            d_.postState = getState(dexPool_, d_.dex, address(user_));
            d_.weiDiff = 1;
            if (swap0to1_) {
                assertApproxEqAbs(
                    d_.postState.liquidityToken0Balance - d_.preState.liquidityToken0Balance,
                    amountIn_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "liquidity balance token0 is not expected"))
                );
                assertApproxEqAbs(
                    d_.preState.liquidityToken1Balance - d_.postState.liquidityToken1Balance,
                    amountOut_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "liquidity balance token1 is not expected"))
                );
                assertApproxEqAbs(
                    d_.preState.userToken0Balance - d_.postState.userToken0Balance,
                    amountIn_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "user balance token0 is not expected"))
                );
                assertApproxEqAbs(
                    d_.postState.userToken1Balance - d_.preState.userToken1Balance,
                    amountOut_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "user balance token1 is not expected"))
                );
            } else {
                assertApproxEqAbs(
                    d_.postState.liquidityToken1Balance - d_.preState.liquidityToken1Balance,
                    amountIn_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "liquidity balance token1 is not expected"))
                );
                assertApproxEqAbs(
                    d_.preState.liquidityToken0Balance - d_.postState.liquidityToken0Balance,
                    amountOut_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "liquidity balance token0 is not expected"))
                );
                assertApproxEqAbs(
                    d_.preState.userToken1Balance - d_.postState.userToken1Balance,
                    amountIn_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "user balance token1 is not expected"))
                );
                assertApproxEqAbs(
                    d_.postState.userToken0Balance - d_.preState.userToken0Balance,
                    amountOut_,
                    d_.weiDiff,
                    string(abi.encodePacked(d_.assertMessage, "user balance token0 is not expected"))
                );
            }
        }

        validateAfterTest(d_.dex);
        if (!skipPriceValidate) validatePricesOfPoolAfterSwap(d_.dex, d_.assertMessage);
    }

    function _testSwapExactOut(
        DexParams memory dexPool_,
        address user_,
        uint256 amountOut_,
        bool swap0to1_,
        DexType dexType_,
        bool skipDepositOrBorrow,
        bool skipDexValidate
    ) internal returns (uint256 amountIn_) {
        _makeUserContract(user_, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, skipDexValidate);

        if (dexType_ == DexType.SmartColAndDebt) {
            // Deposit liquidity for swap, 100k
            if (!skipDepositOrBorrow) _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        } else if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            if (!skipDepositOrBorrow) {
                _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
            }
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            if (!skipDepositOrBorrow) _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testSwapExactIn::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountOut_),
                " ",
                swap0to1_ ? "0to1" : "1to0"
            )
        );

        StateData memory preState_ = getState(dexPool_, dex_, address(alice));

        vm.prank(address(user_));
        amountIn_ = dex_.swapOut{value: _getSwapEthAmount(dexPool_, swap0to1_, user_, type(uint128).max)}(
            swap0to1_, amountOut_, type(uint128).max, address(user_)
        );

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        uint256 weiDiff_ = 1;
        if (swap0to1_) {
            assertApproxEqAbs(
                postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
                amountIn_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
            );
            assertApproxEqAbs(
                preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
                amountOut_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
            );
            assertApproxEqAbs(
                preState_.userToken0Balance - postState_.userToken0Balance,
                amountIn_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
            );
            assertApproxEqAbs(
                postState_.userToken1Balance - preState_.userToken1Balance,
                amountOut_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
            );
        } else {
            assertApproxEqAbs(
                postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
                amountIn_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
            );
            assertApproxEqAbs(
                preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
                amountOut_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
            );
            assertApproxEqAbs(
                preState_.userToken1Balance - postState_.userToken1Balance,
                amountIn_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
            );
            assertApproxEqAbs(
                postState_.userToken0Balance - preState_.userToken0Balance,
                amountOut_,
                weiDiff_,
                string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
            );
        }

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testDepositColLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_
    ) internal returns (uint256 share_) {
        return _testDepositColLiquidityInWei(
            dexPool_, user_, token0Amount_ * dexPool_.token0Wei, token1Amount_ * dexPool_.token1Wei, dexType_
        );
    }

    function _testDepositColLiquidityInWei(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testDepositColLiquidityInWei::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(token0Amount_),
                "-",
                LibString.toString(token1Amount_)
            )
        );
        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](14);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "1";
            inputs[3] = _uintToString(token0Amount_);
            inputs[4] = _uintToString(token1Amount_);
            inputs[5] = _uintToString(
                uint256(
                    dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token0).decimals()
                )
            );
            inputs[6] = _uintToString(
                uint256(
                    dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token1).decimals()
                )
            );
            inputs[7] = "1";
            inputs[8] = _uintToString(poolState.fee);
            inputs[9] = _uintToString(preState_.totalSupplyShares);
            inputs[10] = _uintToString(poolState.collateralReserves.token0RealReserves);
            inputs[11] = _uintToString(poolState.collateralReserves.token1RealReserves);
            inputs[12] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
            inputs[13] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }
        vm.prank(address(user_));
        if (preState_.liquidityToken1SupplyReserve == 0 || preState_.liquidityToken0SupplyReserve == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__TokenReservesTooLow)
            );
        }
        uint256 ethValue_ = 0;
        if (
            (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) && token0Amount_ > 0)
                || (dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS) && token1Amount_ > 0)
        ) {
            ethValue_ = user_.balance;
        }

        (share_) = dex_.deposit{value: ethValue_}(token0Amount_, token1Amount_, type(uint256).min, false);
        uint256 percentDiff =
            (share_ > JsOutput) ? (share_ - JsOutput) * 10000 / share_ : (JsOutput - share_) * 10000 / JsOutput;
        assert(percentDiff <= 1);
        StateData memory postState_ = getState(dexPool_, dex_, address(user_));
        if (preState_.liquidityToken1SupplyReserve == 0 || preState_.liquidityToken0SupplyReserve == 0) {
            return share_;
        }

        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken0Balance - postState_.userToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken1Balance - postState_.userToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        uint256 shareDelta_ = 262144;
        assertApproxEqAbs(
            postState_.totalSupplyShares - preState_.totalSupplyShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.totalBorrowShares - preState_.totalBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userSupplyShares - preState_.userSupplyShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userBorrowShares - preState_.userBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testWithdrawColLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 token0AmountInWei_ = token0Amount_ * dexPool_.token0Wei;
        uint256 token1AmountInWei_ = token1Amount_ * dexPool_.token1Wei;

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            IFluidDexT1.PricesAndExchangePrice memory pex = dexResolver.getDexPricesAndExchangePrices(address(dex_));
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](17);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "2";
            inputs[3] = _uintToString(token0AmountInWei_);
            inputs[4] = _uintToString(token1AmountInWei_);
            inputs[5] = _uintToString(
                uint256(
                    dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token0).decimals()
                )
            );
            inputs[6] = _uintToString(
                uint256(
                    dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token1).decimals()
                )
            );
            inputs[7] = "1";
            inputs[8] = _uintToString(poolState.fee);
            inputs[9] = _uintToString(preState_.totalSupplyShares);
            inputs[10] = _uintToString(poolState.collateralReserves.token0RealReserves);
            inputs[11] = _uintToString(poolState.collateralReserves.token1RealReserves);
            inputs[12] = _uintToString(poolState.collateralReserves.token0ImaginaryReserves);
            inputs[13] = _uintToString(poolState.collateralReserves.token1ImaginaryReserves);
            inputs[14] = _uintToString(pex.geometricMean);
            inputs[15] = _uintToString(pex.upperRange);
            inputs[16] = _uintToString(pex.lowerRange);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }
        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testWithdrawColLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(token0Amount_),
                "-",
                LibString.toString(token1Amount_)
            )
        );

        if (revertReason_.length > 0) vm.expectRevert(revertReason_);
        vm.prank(address(user_));
        (share_) = dex_.withdraw(token0AmountInWei_, token1AmountInWei_, type(uint256).max, address(0));
        if (revertReason_.length == 0) {
            uint256 percentDiff =
                (share_ > JsOutput) ? (share_ - JsOutput) * 10000 / share_ : (JsOutput - share_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        if (revertReason_.length > 0) return (share_);

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
            token0AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
            token1AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken0Balance - preState_.userToken0Balance,
            token0AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken1Balance - preState_.userToken1Balance,
            token1AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        uint256 shareDelta_ = 262144;
        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testBorrowDebtLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 share_) {
        return _testBorrowDebtLiquidityInWei(
            dexPool_,
            user_,
            token0Amount_ * dexPool_.token0Wei,
            token1Amount_ * dexPool_.token1Wei,
            dexType_,
            revertReason_
        );
    }

    function _testBorrowDebtLiquidityInWei(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_,
        bytes memory revertReason_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            IFluidDexT1.PricesAndExchangePrice memory pex = dexResolver.getDexPricesAndExchangePrices(address(dex_));
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](19);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "3";
            inputs[3] = _uintToString(token0Amount_);
            inputs[4] = _uintToString(token1Amount_);
            inputs[5] = _uintToString(
                uint256(
                    dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token0).decimals()
                )
            );
            inputs[6] = _uintToString(
                uint256(
                    dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token1).decimals()
                )
            );
            inputs[7] = "1";
            inputs[8] = _uintToString(poolState.fee);
            inputs[9] = _uintToString(preState_.totalBorrowShares);
            inputs[10] = _uintToString(poolState.debtReserves.token0Debt);
            inputs[11] = _uintToString(poolState.debtReserves.token1Debt);
            inputs[12] = _uintToString(poolState.debtReserves.token0RealReserves);
            inputs[13] = _uintToString(poolState.debtReserves.token1RealReserves);
            inputs[14] = _uintToString(poolState.debtReserves.token0ImaginaryReserves);
            inputs[15] = _uintToString(poolState.debtReserves.token1ImaginaryReserves);
            inputs[16] = _uintToString(pex.geometricMean);
            inputs[17] = _uintToString(pex.upperRange);
            inputs[18] = _uintToString(pex.lowerRange);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testBorrowDebtLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(token0Amount_),
                "-",
                LibString.toString(token1Amount_)
            )
        );

        if (revertReason_.length > 0) vm.expectRevert(revertReason_);
        vm.prank(address(user_));
        (share_) = dex_.borrow(token0Amount_, token1Amount_, type(uint256).max, address(0));
        if (revertReason_.length == 0) {
            uint256 percentDiff =
                (share_ > JsOutput) ? (share_ - JsOutput) * 10000 / share_ : (JsOutput - share_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        if (revertReason_.length > 0) return (share_);

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        // Validate Liquidity and user balances of token0 and token1
        assertApproxEqAbs(
            preState_.liquidityToken0Balance - postState_.liquidityToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.liquidityToken1Balance - postState_.liquidityToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken0Balance - preState_.userToken0Balance,
            token0Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.userToken1Balance - preState_.userToken1Balance,
            token1Amount_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        uint256 shareDelta_ = 262144;
        assertApproxEqAbs(
            postState_.totalSupplyShares - preState_.totalSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.totalBorrowShares - preState_.totalBorrowShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userSupplyShares - preState_.userSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            postState_.userBorrowShares - preState_.userBorrowShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testPaybackDebtLiquidity(
        DexParams memory dexPool_,
        address user_,
        uint256 token0Amount_,
        uint256 token1Amount_,
        DexType dexType_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        vm.prank(address(user_));
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        uint256 token0AmountInWei_ = token0Amount_ * dexPool_.token0Wei;
        uint256 token1AmountInWei_ = token1Amount_ * dexPool_.token1Wei;

        uint256 JsOutput = 0;
        StateData memory preState_ = getState(dexPool_, dex_, address(user_));
        {
            PoolStructs.PoolWithReserves memory poolState = dexResolver.getPoolReservesAdjusted(address(dex_));
            string[] memory inputs = new string[](16);
            inputs[0] = "node";
            inputs[1] = "dexMath/userOperations/validate.js";
            inputs[2] = "4";
            inputs[3] = _uintToString(token0AmountInWei_);
            inputs[4] = _uintToString(token1AmountInWei_);
            inputs[5] = _uintToString(
                uint256(
                    dexPool_.token0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token0).decimals()
                )
            );
            inputs[6] = _uintToString(
                uint256(
                    dexPool_.token1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
                        ? 18
                        : ERC20(dexPool_.token1).decimals()
                )
            );
            inputs[7] = "4";
            inputs[8] = _uintToString(poolState.fee);
            inputs[9] = _uintToString(preState_.totalBorrowShares);
            inputs[10] = _uintToString(poolState.debtReserves.token0Debt);
            inputs[11] = _uintToString(poolState.debtReserves.token1Debt);
            inputs[12] = _uintToString(poolState.debtReserves.token0RealReserves);
            inputs[13] = _uintToString(poolState.debtReserves.token1RealReserves);
            inputs[14] = _uintToString(poolState.debtReserves.token0ImaginaryReserves);
            inputs[15] = _uintToString(poolState.debtReserves.token1ImaginaryReserves);

            bytes memory response = vm.ffi(inputs);
            JsOutput = _bytesToDecimal(response);
        }
        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testPaybackDebtLiquidity::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(token0Amount_),
                "-",
                LibString.toString(token1Amount_)
            )
        );

        uint256 ethValue_ = 0;
        if (
            (dexPool_.token0 == address(NATIVE_TOKEN_ADDRESS) && token0Amount_ > 0)
                || (dexPool_.token1 == address(NATIVE_TOKEN_ADDRESS) && token1Amount_ > 0)
        ) {
            ethValue_ = user_.balance;
        }

        vm.prank(address(user_));
        (share_) = dex_.payback{value: ethValue_}(token0AmountInWei_, token1AmountInWei_, type(uint256).min, false);
        {
            uint256 percentDiff =
                (share_ > JsOutput) ? (share_ - JsOutput) * 10000 / share_ : (JsOutput - share_) * 10000 / JsOutput;
            assert(percentDiff <= 1);
        }

        StateData memory postState_ = getState(dexPool_, dex_, address(user_));

        assertApproxEqAbs(
            postState_.liquidityToken0Balance - preState_.liquidityToken0Balance,
            token0AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token0 is not expected"))
        );
        assertApproxEqAbs(
            postState_.liquidityToken1Balance - preState_.liquidityToken1Balance,
            token1AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "liquidity balance token1 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken0Balance - postState_.userToken0Balance,
            token0AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token0 is not expected"))
        );
        assertApproxEqAbs(
            preState_.userToken1Balance - postState_.userToken1Balance,
            token1AmountInWei_,
            0,
            string(abi.encodePacked(assertMessage_, "user balance token1 is not expected"))
        );

        uint256 shareDelta_ = 262144;
        assertApproxEqAbs(
            preState_.totalSupplyShares - postState_.totalSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "total supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.totalBorrowShares - postState_.totalBorrowShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "total borrow shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userSupplyShares - postState_.userSupplyShares,
            0,
            0,
            string(abi.encodePacked(assertMessage_, "user supply shares is not expected"))
        );
        assertApproxEqAbs(
            preState_.userBorrowShares - postState_.userBorrowShares,
            share_,
            shareDelta_,
            string(abi.encodePacked(assertMessage_, "user borrow shares is not expected"))
        );

        validateAfterTest(dex_);
        validatePricesOfPoolAfterSwap(dex_, assertMessage_);
    }

    function _testSwapExactInBackAndForth(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool startSwap0To1,
        DexType dexType_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        if (dexType_ == DexType.SmartColAndDebt) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testSwapExactInBackAndForth::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                " ",
                startSwap0To1 ? "0to1" : "1to0"
            )
        );

        uint256 amountOut_ = _testSwapExactIn(dexPool_, user_, amountIn_, startSwap0To1, dexType_, true, false, false);
        uint256 amountInBack_ =
            _testSwapExactIn(dexPool_, user_, amountOut_, !startSwap0To1, dexType_, true, false, false);

        assertGe(
            amountIn_ * 10001 / 10000,
            amountInBack_,
            string(abi.encodePacked(assertMessage_, "amountIn_ is less than amountInBack_"))
        );

        // TODO: adjust percision
        if (dexType_ == DexType.SmartColAndDebt) {
            assertApproxEqRel(
                amountIn_,
                amountInBack_,
                2 * 1e16,
                string(abi.encodePacked(assertMessage_, "amountInBack_ is very less than amountIn_"))
            );
        } else {
            // TODO: convert to abs value
            assertApproxEqRel(
                amountIn_,
                amountInBack_,
                0.0000005 * 1e18,
                string(abi.encodePacked(assertMessage_, "amountInBack_ is very less than amountIn_"))
            );
        }
    }

    // Admin Module Helpers
    function _testUpdateRangePercents(
        DexParams memory dexPool_,
        address admin_,
        uint256 upperPercent_,
        uint256 lowerPercent_,
        uint256 shiftTime_,
        DexType dexType_
    ) internal {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateRangePercents::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(upperPercent_),
                "-",
                LibString.toString(lowerPercent_),
                "-",
                LibString.toString(shiftTime_)
            )
        );

        DexState memory preDs_ = getDexState(dexPool_, dex_);
        vm.prank(address(admin_));
        FluidDexT1Admin(address(dex_)).updateRangePercents(upperPercent_, lowerPercent_, shiftTime_);
        DexState memory postDs_ = getDexState(dexPool_, dex_);

        assertEq(
            shiftTime_ > 0,
            postDs_.d2.isPercentChangeActive,
            string(abi.encodePacked(assertMessage_, "isPercentChangeActive not match"))
        );
        assertEq(
            upperPercent_, postDs_.d2.upperPercent, string(abi.encodePacked(assertMessage_, "upperPercent not match"))
        );
        assertEq(
            lowerPercent_, postDs_.d2.lowerPercent, string(abi.encodePacked(assertMessage_, "lowerPercent not match"))
        );

        if (shiftTime_ > 0) {
            assertEq(
                preDs_.d2.upperPercent,
                postDs_.rs.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldUpperShift doesn't match"))
            );
            assertEq(
                preDs_.d2.lowerPercent,
                postDs_.rs.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldLowerShift doesn't match"))
            );
            assertEq(
                shiftTime_,
                postDs_.rs.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: shiftTime doesn't match"))
            );
            assertEq(
                block.timestamp,
                postDs_.rs.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: timestampOfShiftStart doesn't match"))
            );
        }

        // Dex Variables
        {
            assertEq(preDs_.d.isEntrancy, postDs_.d.isEntrancy, string(abi.encodePacked(assertMessage_, "isEntrancy")));
            assertEq(
                preDs_.d.lastToLastPrice,
                postDs_.d.lastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
            );
            assertEq(preDs_.d.lastPrice, postDs_.d.lastPrice, string(abi.encodePacked(assertMessage_, "lastPrice")));
            assertEq(
                preDs_.d.centerPrice, postDs_.d.centerPrice, string(abi.encodePacked(assertMessage_, "centerPrice"))
            );
            assertEq(
                preDs_.d.lastTimestamp,
                postDs_.d.lastTimestamp,
                string(abi.encodePacked(assertMessage_, "lastTimestamp"))
            );
            assertEq(
                preDs_.d.lastTimestampDifBetweenLastToLastPrice,
                postDs_.d.lastTimestampDifBetweenLastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastTimestampDifBetweenLastToLastPrice"))
            );
            assertEq(preDs_.d.oracleSlot, postDs_.d.oracleSlot, string(abi.encodePacked(assertMessage_, "oracleSlot")));
            assertEq(preDs_.d.oracleMap, postDs_.d.oracleMap, string(abi.encodePacked(assertMessage_, "oracleMap")));
        }

        // Dex Variables 2
        {
            assertEq(
                preDs_.d2.isSmartColEnabled,
                postDs_.d2.isSmartColEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartColEnabled"))
            );
            assertEq(
                preDs_.d2.isSmartDebtEnabled,
                postDs_.d2.isSmartDebtEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartDebtEnabled"))
            );
            assertEq(preDs_.d2.fee, postDs_.d2.fee, string(abi.encodePacked(assertMessage_, "fee")));
            assertEq(
                preDs_.d2.revenueCut, postDs_.d2.revenueCut, string(abi.encodePacked(assertMessage_, "revenueCut"))
            );

            // assertEq(preDs_.d2.isPercentChangeActive, postDs_.d2.isPercentChangeActive, string(abi.encodePacked(assertMessage_, "isPercentChangeActive")));
            // assertEq(preDs_.d2.upperPercent, postDs_.d2.upperPercent, string(abi.encodePacked(assertMessage_, "upperPercent")));
            // assertEq(preDs_.d2.lowerPercent, postDs_.d2.lowerPercent, string(abi.encodePacked(assertMessage_, "lowerPercent")));

            assertEq(
                preDs_.d2.isThresholdPercentActive,
                postDs_.d2.isThresholdPercentActive,
                string(abi.encodePacked(assertMessage_, "isThresholdPercentActive"))
            );
            assertEq(
                preDs_.d2.upperShiftPercent,
                postDs_.d2.upperShiftPercent,
                string(abi.encodePacked(assertMessage_, "upperShiftPercent"))
            );
            assertEq(
                preDs_.d2.lowerShiftPercent,
                postDs_.d2.lowerShiftPercent,
                string(abi.encodePacked(assertMessage_, "lowerShiftPercent"))
            );
            assertEq(preDs_.d2.shiftTime, postDs_.d2.shiftTime, string(abi.encodePacked(assertMessage_, "shiftTime")));
            assertEq(
                preDs_.d2.centerPriceAddress,
                postDs_.d2.centerPriceAddress,
                string(abi.encodePacked(assertMessage_, "centerPriceAddress"))
            );
            assertEq(
                preDs_.d2.hookDeploymentNonce,
                postDs_.d2.hookDeploymentNonce,
                string(abi.encodePacked(assertMessage_, "hookDeploymentNonce"))
            );
            assertEq(
                preDs_.d2.minCenterPrice,
                postDs_.d2.minCenterPrice,
                string(abi.encodePacked(assertMessage_, "minCenterPrice"))
            );
            assertEq(
                preDs_.d2.maxCenterPrice,
                postDs_.d2.maxCenterPrice,
                string(abi.encodePacked(assertMessage_, "maxCenterPrice"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken0,
                postDs_.d2.utilizationLimitToken0,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken0"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken1,
                postDs_.d2.utilizationLimitToken1,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken1"))
            );
            assertEq(
                preDs_.d2.isCenterPriceShiftActive,
                postDs_.d2.isCenterPriceShiftActive,
                string(abi.encodePacked(assertMessage_, "isCenterPriceShiftActive"))
            );
            assertEq(preDs_.d2.pauseSwap, postDs_.d2.pauseSwap, string(abi.encodePacked(assertMessage_, "pauseSwap")));
        }

        // Range Shift
        {
            // assertEq(preDs_.rs.oldUpperShift, postDs_.rs.oldUpperShift, string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldUpperShift")));
            // assertEq(preDs_.rs.oldLowerShift, postDs_.rs.oldLowerShift, string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldLowerShift")));
            // assertEq(preDs_.rs.shiftTime, postDs_.rs.shiftTime, string(abi.encodePacked(assertMessage_, "DexRangeShiftData: shiftTime")));
            // assertEq(preDs_.rs.timestampOfShiftStart, postDs_.rs.timestampOfShiftStart, string(abi.encodePacked(assertMessage_, "DexRangeShiftData: timestampOfShiftStart")));
        }

        // Threshold Shift
        {
            assertEq(
                preDs_.ts.oldUpperShift,
                postDs_.ts.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.ts.oldLowerShift,
                postDs_.ts.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.ts.shiftTime,
                postDs_.ts.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: shiftTime"))
            );
            assertEq(
                preDs_.ts.timestampOfShiftStart,
                postDs_.ts.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.ts.oldThresholdTimestamp,
                postDs_.ts.oldThresholdTimestamp,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldThresholdTimestamp"))
            );
        }

        // Center Price shift
        {
            assertEq(
                preDs_.cps.timestampOfShiftStart,
                postDs_.cps.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.cps.percentShift,
                postDs_.cps.percentShift,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift"))
            );
            assertEq(
                preDs_.cps.timeToShiftPercent,
                postDs_.cps.timeToShiftPercent,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent"))
            );
        }
    }

    function _testUpdateThresholdPercent(
        DexParams memory dexPool_,
        address admin_,
        uint256 upperThresholdPercent_,
        uint256 lowerThresholdPercent_,
        uint256 thresholdTime_,
        uint256 shiftTime_,
        DexType dexType_
    ) internal {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateThresholdPercent::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(upperThresholdPercent_),
                "-",
                LibString.toString(lowerThresholdPercent_),
                "-",
                LibString.toString(shiftTime_)
            )
        );

        DexState memory preDs_ = getDexState(dexPool_, dex_);
        vm.prank(address(admin_));
        FluidDexT1Admin(address(dex_)).updateThresholdPercent(
            upperThresholdPercent_, lowerThresholdPercent_, thresholdTime_, shiftTime_
        );
        DexState memory postDs_ = getDexState(dexPool_, dex_);

        assertEq(
            shiftTime_ > 0,
            postDs_.d2.isThresholdPercentActive,
            string(abi.encodePacked(assertMessage_, "isThresholdPercentActive not match"))
        );
        assertEq(
            upperThresholdPercent_,
            postDs_.d2.upperShiftPercent,
            string(abi.encodePacked(assertMessage_, "upperThresholdPercent_ not match"))
        );
        assertEq(
            lowerThresholdPercent_,
            postDs_.d2.lowerShiftPercent,
            string(abi.encodePacked(assertMessage_, "lowerThresholdPercent_ not match"))
        );
        assertEq(thresholdTime_, postDs_.d2.shiftTime, string(abi.encodePacked(assertMessage_, "shiftTime not match")));

        if (shiftTime_ > 0) {
            assertEq(
                preDs_.d2.upperShiftPercent,
                postDs_.ts.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.d2.lowerShiftPercent,
                postDs_.ts.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldLowerShift"))
            );
            assertEq(
                shiftTime_,
                postDs_.ts.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: shiftTime"))
            );
            assertEq(
                block.timestamp,
                postDs_.ts.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.d2.shiftTime,
                postDs_.ts.oldThresholdTimestamp,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldThresholdTimestamp"))
            );
        }

        // Dex Variables
        {
            assertEq(preDs_.d.isEntrancy, postDs_.d.isEntrancy, string(abi.encodePacked(assertMessage_, "isEntrancy")));
            assertEq(
                preDs_.d.lastToLastPrice,
                postDs_.d.lastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
            );
            assertEq(preDs_.d.lastPrice, postDs_.d.lastPrice, string(abi.encodePacked(assertMessage_, "lastPrice")));
            assertEq(
                preDs_.d.centerPrice, postDs_.d.centerPrice, string(abi.encodePacked(assertMessage_, "centerPrice"))
            );
            assertEq(
                preDs_.d.lastTimestamp,
                postDs_.d.lastTimestamp,
                string(abi.encodePacked(assertMessage_, "lastTimestamp"))
            );
            assertEq(
                preDs_.d.lastTimestampDifBetweenLastToLastPrice,
                postDs_.d.lastTimestampDifBetweenLastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastTimestampDifBetweenLastToLastPrice"))
            );
            assertEq(preDs_.d.oracleSlot, postDs_.d.oracleSlot, string(abi.encodePacked(assertMessage_, "oracleSlot")));
            assertEq(preDs_.d.oracleMap, postDs_.d.oracleMap, string(abi.encodePacked(assertMessage_, "oracleMap")));
        }

        // Dex Variables 2
        {
            assertEq(
                preDs_.d2.isSmartColEnabled,
                postDs_.d2.isSmartColEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartColEnabled"))
            );
            assertEq(
                preDs_.d2.isSmartDebtEnabled,
                postDs_.d2.isSmartDebtEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartDebtEnabled"))
            );
            assertEq(preDs_.d2.fee, postDs_.d2.fee, string(abi.encodePacked(assertMessage_, "fee")));
            assertEq(
                preDs_.d2.revenueCut, postDs_.d2.revenueCut, string(abi.encodePacked(assertMessage_, "revenueCut"))
            );
            assertEq(
                preDs_.d2.isPercentChangeActive,
                postDs_.d2.isPercentChangeActive,
                string(abi.encodePacked(assertMessage_, "isPercentChangeActive"))
            );
            assertEq(
                preDs_.d2.upperPercent,
                postDs_.d2.upperPercent,
                string(abi.encodePacked(assertMessage_, "upperPercent"))
            );
            assertEq(
                preDs_.d2.lowerPercent,
                postDs_.d2.lowerPercent,
                string(abi.encodePacked(assertMessage_, "lowerPercent"))
            );

            // assertEq(preDs_.d2.isThresholdPercentActive, postDs_.d2.isThresholdPercentActive, string(abi.encodePacked(assertMessage_, "isThresholdPercentActive")));
            // assertEq(preDs_.d2.upperShiftPercent, postDs_.d2.upperShiftPercent, string(abi.encodePacked(assertMessage_, "upperShiftPercent")));
            // assertEq(preDs_.d2.lowerShiftPercent, postDs_.d2.lowerShiftPercent, string(abi.encodePacked(assertMessage_, "lowerShiftPercent")));
            // assertEq(preDs_.d2.shiftTime, postDs_.d2.shiftTime, string(abi.encodePacked(assertMessage_, "shiftTime")));

            assertEq(
                preDs_.d2.centerPriceAddress,
                postDs_.d2.centerPriceAddress,
                string(abi.encodePacked(assertMessage_, "centerPriceAddress"))
            );
            assertEq(
                preDs_.d2.hookDeploymentNonce,
                postDs_.d2.hookDeploymentNonce,
                string(abi.encodePacked(assertMessage_, "hookDeploymentNonce"))
            );
            assertEq(
                preDs_.d2.minCenterPrice,
                postDs_.d2.minCenterPrice,
                string(abi.encodePacked(assertMessage_, "minCenterPrice"))
            );
            assertEq(
                preDs_.d2.maxCenterPrice,
                postDs_.d2.maxCenterPrice,
                string(abi.encodePacked(assertMessage_, "maxCenterPrice"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken0,
                postDs_.d2.utilizationLimitToken0,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken0"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken1,
                postDs_.d2.utilizationLimitToken1,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken1"))
            );
            assertEq(
                preDs_.d2.isCenterPriceShiftActive,
                postDs_.d2.isCenterPriceShiftActive,
                string(abi.encodePacked(assertMessage_, "isCenterPriceShiftActive"))
            );
            assertEq(preDs_.d2.pauseSwap, postDs_.d2.pauseSwap, string(abi.encodePacked(assertMessage_, "pauseSwap")));
        }

        // Range Shift
        {
            assertEq(
                preDs_.rs.oldUpperShift,
                postDs_.rs.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.rs.oldLowerShift,
                postDs_.rs.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.rs.shiftTime,
                postDs_.rs.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: shiftTime"))
            );
            assertEq(
                preDs_.rs.timestampOfShiftStart,
                postDs_.rs.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: timestampOfShiftStart"))
            );
        }

        // Threshold Shift
        {
            // assertEq(preDs_.ts.oldUpperShift, postDs_.ts.oldUpperShift, string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldUpperShift")));
            // assertEq(preDs_.ts.oldLowerShift, postDs_.ts.oldLowerShift, string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldLowerShift")));
            // assertEq(preDs_.ts.shiftTime, postDs_.ts.shiftTime, string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: shiftTime")));
            // assertEq(preDs_.ts.timestampOfShiftStart, postDs_.ts.timestampOfShiftStart, string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: timestampOfShiftStart")));
            // assertEq(preDs_.ts.oldThresholdTimestamp, postDs_.ts.oldThresholdTimestamp, string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldThresholdTimestamp")));
        }

        // Center Price shift
        {
            assertEq(
                preDs_.cps.timestampOfShiftStart,
                postDs_.cps.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.cps.percentShift,
                postDs_.cps.percentShift,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift"))
            );
            assertEq(
                preDs_.cps.timeToShiftPercent,
                postDs_.cps.timeToShiftPercent,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent"))
            );
        }
    }

    function _testUpdateCenterPriceAddress(
        DexParams memory dexPool_,
        address admin_,
        uint256 centerPriceAddress_,
        uint256 percent_,
        uint256 time_,
        DexType dexType_
    ) internal {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateCenterPriceAddress::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(centerPriceAddress_),
                "-",
                LibString.toString(percent_),
                "-",
                LibString.toString(time_)
            )
        );

        DexState memory preDs_ = getDexState(dexPool_, dex_);
        vm.prank(address(admin_));
        FluidDexT1Admin(address(dex_)).updateCenterPriceAddress(centerPriceAddress_, percent_, time_);
        DexState memory postDs_ = getDexState(dexPool_, dex_);

        assertEq(
            centerPriceAddress_,
            postDs_.d2.centerPriceAddress,
            string(abi.encodePacked(assertMessage_, "centerPriceAddress"))
        );
        assertEq(
            centerPriceAddress_ > 0,
            postDs_.d2.isCenterPriceShiftActive,
            string(abi.encodePacked(assertMessage_, "isCenterPriceShiftActive"))
        );

        if (centerPriceAddress_ > 0) {
            assertEq(
                block.timestamp,
                postDs_.cps.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart"))
            );
            assertEq(
                percent_,
                postDs_.cps.percentShift,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift"))
            );
            assertEq(
                time_,
                postDs_.cps.timeToShiftPercent,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent"))
            );
        } else {
            assertEq(
                0,
                postDs_.cps.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart"))
            );
            assertEq(
                0,
                postDs_.cps.percentShift,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift"))
            );
            assertEq(
                0,
                postDs_.cps.timeToShiftPercent,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent"))
            );
        }

        // Dex Variables
        {
            assertEq(preDs_.d.isEntrancy, postDs_.d.isEntrancy, string(abi.encodePacked(assertMessage_, "isEntrancy")));
            assertEq(
                preDs_.d.lastToLastPrice,
                postDs_.d.lastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
            );
            assertEq(preDs_.d.lastPrice, postDs_.d.lastPrice, string(abi.encodePacked(assertMessage_, "lastPrice")));
            assertEq(
                preDs_.d.centerPrice, postDs_.d.centerPrice, string(abi.encodePacked(assertMessage_, "centerPrice"))
            );
            assertEq(
                preDs_.d.lastTimestamp,
                postDs_.d.lastTimestamp,
                string(abi.encodePacked(assertMessage_, "lastTimestamp"))
            );
            assertEq(
                preDs_.d.lastTimestampDifBetweenLastToLastPrice,
                postDs_.d.lastTimestampDifBetweenLastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastTimestampDifBetweenLastToLastPrice"))
            );
            assertEq(preDs_.d.oracleSlot, postDs_.d.oracleSlot, string(abi.encodePacked(assertMessage_, "oracleSlot")));
            assertEq(preDs_.d.oracleMap, postDs_.d.oracleMap, string(abi.encodePacked(assertMessage_, "oracleMap")));
        }

        // Dex Variables 2
        {
            assertEq(
                preDs_.d2.isSmartColEnabled,
                postDs_.d2.isSmartColEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartColEnabled"))
            );
            assertEq(
                preDs_.d2.isSmartDebtEnabled,
                postDs_.d2.isSmartDebtEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartDebtEnabled"))
            );
            assertEq(preDs_.d2.fee, postDs_.d2.fee, string(abi.encodePacked(assertMessage_, "fee")));
            assertEq(
                preDs_.d2.revenueCut, postDs_.d2.revenueCut, string(abi.encodePacked(assertMessage_, "revenueCut"))
            );
            assertEq(
                preDs_.d2.isPercentChangeActive,
                postDs_.d2.isPercentChangeActive,
                string(abi.encodePacked(assertMessage_, "isPercentChangeActive"))
            );
            assertEq(
                preDs_.d2.upperPercent,
                postDs_.d2.upperPercent,
                string(abi.encodePacked(assertMessage_, "upperPercent"))
            );
            assertEq(
                preDs_.d2.lowerPercent,
                postDs_.d2.lowerPercent,
                string(abi.encodePacked(assertMessage_, "lowerPercent"))
            );
            assertEq(
                preDs_.d2.isThresholdPercentActive,
                postDs_.d2.isThresholdPercentActive,
                string(abi.encodePacked(assertMessage_, "isThresholdPercentActive"))
            );
            assertEq(
                preDs_.d2.upperShiftPercent,
                postDs_.d2.upperShiftPercent,
                string(abi.encodePacked(assertMessage_, "upperShiftPercent"))
            );
            assertEq(
                preDs_.d2.lowerShiftPercent,
                postDs_.d2.lowerShiftPercent,
                string(abi.encodePacked(assertMessage_, "lowerShiftPercent"))
            );
            assertEq(preDs_.d2.shiftTime, postDs_.d2.shiftTime, string(abi.encodePacked(assertMessage_, "shiftTime")));

            // assertEq(preDs_.d2.centerPriceAddress, postDs_.d2.centerPriceAddress, string(abi.encodePacked(assertMessage_, "centerPriceAddress")));
            // assertEq(preDs_.d2.isCenterPriceShiftActive, postDs_.d2.isCenterPriceShiftActive, string(abi.encodePacked(assertMessage_, "isCenterPriceShiftActive")));

            assertEq(
                preDs_.d2.hookDeploymentNonce,
                postDs_.d2.hookDeploymentNonce,
                string(abi.encodePacked(assertMessage_, "hookDeploymentNonce"))
            );
            assertEq(
                preDs_.d2.minCenterPrice,
                postDs_.d2.minCenterPrice,
                string(abi.encodePacked(assertMessage_, "minCenterPrice"))
            );
            assertEq(
                preDs_.d2.maxCenterPrice,
                postDs_.d2.maxCenterPrice,
                string(abi.encodePacked(assertMessage_, "maxCenterPrice"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken0,
                postDs_.d2.utilizationLimitToken0,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken0"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken1,
                postDs_.d2.utilizationLimitToken1,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken1"))
            );
            assertEq(preDs_.d2.pauseSwap, postDs_.d2.pauseSwap, string(abi.encodePacked(assertMessage_, "pauseSwap")));
        }

        // Range Shift
        {
            assertEq(
                preDs_.rs.oldUpperShift,
                postDs_.rs.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.rs.oldLowerShift,
                postDs_.rs.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.rs.shiftTime,
                postDs_.rs.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: shiftTime"))
            );
            assertEq(
                preDs_.rs.timestampOfShiftStart,
                postDs_.rs.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: timestampOfShiftStart"))
            );
        }

        // Threshold Shift
        {
            assertEq(
                preDs_.ts.oldUpperShift,
                postDs_.ts.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.ts.oldLowerShift,
                postDs_.ts.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.ts.shiftTime,
                postDs_.ts.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: shiftTime"))
            );
            assertEq(
                preDs_.ts.timestampOfShiftStart,
                postDs_.ts.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.ts.oldThresholdTimestamp,
                postDs_.ts.oldThresholdTimestamp,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldThresholdTimestamp"))
            );
        }

        // Center Price shift
        {
            // assertEq(preDs_.cps.timestampOfShiftStart, postDs_.cps.timestampOfShiftStart, string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart")));
            // assertEq(preDs_.cps.percentShift, postDs_.cps.percentShift, string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift")));
            // assertEq(preDs_.cps.timeToShiftPercent, postDs_.cps.timeToShiftPercent, string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent")));
        }
    }

    function _testUpdateHookAddress(DexParams memory dexPool_, address admin_, uint256 hookAddress_, DexType dexType_)
        internal
    {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateHookAddress::", _getDexPoolName(dexPool_, dexType_), ":", LibString.toString(hookAddress_)
            )
        );

        DexState memory preDs_ = getDexState(dexPool_, dex_);
        vm.prank(address(admin_));
        FluidDexT1Admin(address(dex_)).updateHookAddress(hookAddress_);
        DexState memory postDs_ = getDexState(dexPool_, dex_);

        assertEq(
            hookAddress_,
            postDs_.d2.hookDeploymentNonce,
            string(abi.encodePacked(assertMessage_, "hookDeploymentNonce"))
        );

        // Dex Variables
        {
            assertEq(preDs_.d.isEntrancy, postDs_.d.isEntrancy, string(abi.encodePacked(assertMessage_, "isEntrancy")));
            assertEq(
                preDs_.d.lastToLastPrice,
                postDs_.d.lastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
            );
            assertEq(preDs_.d.lastPrice, postDs_.d.lastPrice, string(abi.encodePacked(assertMessage_, "lastPrice")));
            assertEq(
                preDs_.d.centerPrice, postDs_.d.centerPrice, string(abi.encodePacked(assertMessage_, "centerPrice"))
            );
            assertEq(
                preDs_.d.lastTimestamp,
                postDs_.d.lastTimestamp,
                string(abi.encodePacked(assertMessage_, "lastTimestamp"))
            );
            assertEq(
                preDs_.d.lastTimestampDifBetweenLastToLastPrice,
                postDs_.d.lastTimestampDifBetweenLastToLastPrice,
                string(abi.encodePacked(assertMessage_, "lastTimestampDifBetweenLastToLastPrice"))
            );
            assertEq(preDs_.d.oracleSlot, postDs_.d.oracleSlot, string(abi.encodePacked(assertMessage_, "oracleSlot")));
            assertEq(preDs_.d.oracleMap, postDs_.d.oracleMap, string(abi.encodePacked(assertMessage_, "oracleMap")));
        }

        // Dex Variables 2
        {
            assertEq(
                preDs_.d2.isSmartColEnabled,
                postDs_.d2.isSmartColEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartColEnabled"))
            );
            assertEq(
                preDs_.d2.isSmartDebtEnabled,
                postDs_.d2.isSmartDebtEnabled,
                string(abi.encodePacked(assertMessage_, "isSmartDebtEnabled"))
            );
            assertEq(preDs_.d2.fee, postDs_.d2.fee, string(abi.encodePacked(assertMessage_, "fee")));
            assertEq(
                preDs_.d2.revenueCut, postDs_.d2.revenueCut, string(abi.encodePacked(assertMessage_, "revenueCut"))
            );
            assertEq(
                preDs_.d2.isPercentChangeActive,
                postDs_.d2.isPercentChangeActive,
                string(abi.encodePacked(assertMessage_, "isPercentChangeActive"))
            );
            assertEq(
                preDs_.d2.upperPercent,
                postDs_.d2.upperPercent,
                string(abi.encodePacked(assertMessage_, "upperPercent"))
            );
            assertEq(
                preDs_.d2.lowerPercent,
                postDs_.d2.lowerPercent,
                string(abi.encodePacked(assertMessage_, "lowerPercent"))
            );
            assertEq(
                preDs_.d2.isThresholdPercentActive,
                postDs_.d2.isThresholdPercentActive,
                string(abi.encodePacked(assertMessage_, "isThresholdPercentActive"))
            );
            assertEq(
                preDs_.d2.upperShiftPercent,
                postDs_.d2.upperShiftPercent,
                string(abi.encodePacked(assertMessage_, "upperShiftPercent"))
            );
            assertEq(
                preDs_.d2.lowerShiftPercent,
                postDs_.d2.lowerShiftPercent,
                string(abi.encodePacked(assertMessage_, "lowerShiftPercent"))
            );
            assertEq(preDs_.d2.shiftTime, postDs_.d2.shiftTime, string(abi.encodePacked(assertMessage_, "shiftTime")));
            assertEq(
                preDs_.d2.centerPriceAddress,
                postDs_.d2.centerPriceAddress,
                string(abi.encodePacked(assertMessage_, "centerPriceAddress"))
            );
            assertEq(
                preDs_.d2.isCenterPriceShiftActive,
                postDs_.d2.isCenterPriceShiftActive,
                string(abi.encodePacked(assertMessage_, "isCenterPriceShiftActive"))
            );

            // assertEq(preDs_.d2.hookDeploymentNonce, postDs_.d2.hookDeploymentNonce, string(abi.encodePacked(assertMessage_, "hookDeploymentNonce")));

            assertEq(
                preDs_.d2.minCenterPrice,
                postDs_.d2.minCenterPrice,
                string(abi.encodePacked(assertMessage_, "minCenterPrice"))
            );
            assertEq(
                preDs_.d2.maxCenterPrice,
                postDs_.d2.maxCenterPrice,
                string(abi.encodePacked(assertMessage_, "maxCenterPrice"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken0,
                postDs_.d2.utilizationLimitToken0,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken0"))
            );
            assertEq(
                preDs_.d2.utilizationLimitToken1,
                postDs_.d2.utilizationLimitToken1,
                string(abi.encodePacked(assertMessage_, "utilizationLimitToken1"))
            );
            assertEq(preDs_.d2.pauseSwap, postDs_.d2.pauseSwap, string(abi.encodePacked(assertMessage_, "pauseSwap")));
        }

        // Range Shift
        {
            assertEq(
                preDs_.rs.oldUpperShift,
                postDs_.rs.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.rs.oldLowerShift,
                postDs_.rs.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.rs.shiftTime,
                postDs_.rs.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: shiftTime"))
            );
            assertEq(
                preDs_.rs.timestampOfShiftStart,
                postDs_.rs.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexRangeShiftData: timestampOfShiftStart"))
            );
        }

        // Threshold Shift
        {
            assertEq(
                preDs_.ts.oldUpperShift,
                postDs_.ts.oldUpperShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldUpperShift"))
            );
            assertEq(
                preDs_.ts.oldLowerShift,
                postDs_.ts.oldLowerShift,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldLowerShift"))
            );
            assertEq(
                preDs_.ts.shiftTime,
                postDs_.ts.shiftTime,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: shiftTime"))
            );
            assertEq(
                preDs_.ts.timestampOfShiftStart,
                postDs_.ts.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.ts.oldThresholdTimestamp,
                postDs_.ts.oldThresholdTimestamp,
                string(abi.encodePacked(assertMessage_, "DexThresholdShiftData: oldThresholdTimestamp"))
            );
        }

        // Center Price shift
        {
            assertEq(
                preDs_.cps.timestampOfShiftStart,
                postDs_.cps.timestampOfShiftStart,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timestampOfShiftStart"))
            );
            assertEq(
                preDs_.cps.percentShift,
                postDs_.cps.percentShift,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: percentShift"))
            );
            assertEq(
                preDs_.cps.timeToShiftPercent,
                postDs_.cps.timeToShiftPercent,
                string(abi.encodePacked(assertMessage_, "DexCenterPriceShiftData: timeToShiftPercent"))
            );
        }
    }

    function _testUpdateUserSupplyConfig(
        DexParams memory dexPool_,
        address admin_,
        address user_,
        uint256 expandPercent_,
        uint256 expandDuration_,
        uint256 withdrawLimit_,
        DexType dexType_
    ) internal {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ =
            string(abi.encodePacked("_testUpdateUserSupplyConfig::", _getDexPoolName(dexPool_, dexType_), ":"));

        // Add supply config
        DexAdminStrcuts.UserSupplyConfig[] memory userSupplyConfigs_ = new DexAdminStrcuts.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = DexAdminStrcuts.UserSupplyConfig({
            user: user_,
            expandPercent: expandPercent_,
            expandDuration: expandDuration_,
            baseWithdrawalLimit: withdrawLimit_
        });

        if (dexPool_.token0 != address(NATIVE_TOKEN_ADDRESS)) {
            TestERC20(address(dexPool_.token0)).mint(user_, 1e50 ether);
            _setApproval(IERC20(dexPool_.token0), address(dex_), user_);
        } else {
            vm.deal(user_, 1e50 ether);
        }
        if (dexPool_.token1 != address(NATIVE_TOKEN_ADDRESS)) {
            TestERC20(address(dexPool_.token1)).mint(user_, 1e50 ether);
            _setApproval(IERC20(dexPool_.token1), address(dex_), user_);
        } else {
            vm.deal(user_, 1e50 ether);
        }

        DexUserSupplyData memory preState_ = _getDexSupplyData(dex_, user_);
        assertEq(
            preState_.isUserAllowed,
            false,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: !isUserAllowed"))
        );

        _makeUserContract(user_, true);
        vm.prank(admin_);
        FluidDexT1Admin(address(dex_)).updateUserSupplyConfigs(userSupplyConfigs_);

        DexUserSupplyData memory postState_ = _getDexSupplyData(dex_, user_);

        assertEq(
            postState_.isUserAllowed, true, string(abi.encodePacked(assertMessage_, "DexUserSupplyData: isUserAllowed"))
        );
        assertEq(
            preState_.userShares,
            postState_.userShares,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: userShares"))
        );
        assertEq(
            preState_.previousUserLimit,
            postState_.previousUserLimit,
            string(abi.encodePacked(assertMessage_, "previousUserLimit: shiftTime"))
        );
        assertEq(
            preState_.lastTimestamp,
            postState_.lastTimestamp,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: lastTimestamp"))
        );
        assertEq(
            expandPercent_,
            postState_.expandPercent,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: expandPercent"))
        );
        assertEq(
            expandDuration_,
            postState_.expandDuration,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: expandDuration"))
        );
        assertEq(
            _convertNormalToBNToNormalLimit(withdrawLimit_),
            postState_.baseLimit,
            string(abi.encodePacked(assertMessage_, "DexUserSupplyData: baseLimit"))
        );
    }

    function _testUpdateUserBorrowConfig(
        DexParams memory dexPool_,
        address admin_,
        address user_,
        uint256 expandPercent_,
        uint256 expandDuration_,
        uint256 baseBorrowLimit_,
        uint256 maxBorrowLimit_,
        DexType dexType_
    ) internal {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ =
            string(abi.encodePacked("_testUpdateUserBorrowConfig::", _getDexPoolName(dexPool_, dexType_), ":"));

        // Add Borrow config
        DexAdminStrcuts.UserBorrowConfig[] memory userBorrowConfigs_ = new DexAdminStrcuts.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = DexAdminStrcuts.UserBorrowConfig({
            user: user_,
            expandPercent: expandPercent_,
            expandDuration: expandDuration_,
            baseDebtCeiling: baseBorrowLimit_,
            maxDebtCeiling: maxBorrowLimit_
        });

        DexUserBorrowData memory preState_ = _getDexBorrowData(dex_, user_);
        assertEq(
            preState_.isUserAllowed,
            false,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: !isUserAllowed"))
        );

        _makeUserContract(user_, true);
        vm.prank(admin_);
        FluidDexT1Admin(address(dex_)).updateUserBorrowConfigs(userBorrowConfigs_);

        DexUserBorrowData memory postState_ = _getDexBorrowData(dex_, user_);

        assertEq(
            postState_.isUserAllowed, true, string(abi.encodePacked(assertMessage_, "DexUserBorrowData: isUserAllowed"))
        );
        assertEq(
            preState_.userShares,
            postState_.userShares,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: userShares"))
        );
        assertEq(
            preState_.previousUserLimit,
            postState_.previousUserLimit,
            string(abi.encodePacked(assertMessage_, "previousUserLimit: shiftTime"))
        );
        assertEq(
            preState_.lastTimestamp,
            postState_.lastTimestamp,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: lastTimestamp"))
        );
        assertEq(
            expandPercent_,
            postState_.expandPercent,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: expandPercent"))
        );
        assertEq(
            expandDuration_,
            postState_.expandDuration,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: expandDuration"))
        );

        assertEq(
            _convertNormalToBNToNormalLimit(baseBorrowLimit_),
            postState_.baseLimit,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: baseLimit"))
        );
        assertEq(
            _convertNormalToBNToNormalLimit(maxBorrowLimit_),
            postState_.maxLimit,
            string(abi.encodePacked(assertMessage_, "DexUserBorrowData: maxLimit"))
        );
    }

    function _testSwapExactInForthEnablePoolSwapBack(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool startSwap0To1,
        DexType dexType_
    ) internal returns (uint256 share_) {
        _makeUserContract(user_, true);
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testSwapExactInForthEnablePoolSwapBack::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                " ",
                startSwap0To1 ? "0to1" : "1to0"
            )
        );

        uint256 amountOut_ = _testSwapExactIn(dexPool_, user_, amountIn_, startSwap0To1, dexType_, true, false, false);
        if (dexType_ == DexType.SmartDebt) {
            uint256 ethValue_ = _getSmartDebtOrColEthAmount(dexPool_, dex_, 1e4 * dexPool_.token0Wei, 0);
            vm.prank(alice);
            FluidDexT1Admin(address(dex_)).turnOnSmartCol{value: ethValue_}(1e4 * dexPool_.token0Wei);
        } else if (dexType_ == DexType.SmartCol) {
            uint256 ethValue_ = _getSmartDebtOrColEthAmount(dexPool_, dex_, 1e4 * dexPool_.token0Wei, 0);
            vm.prank(alice);
            FluidDexT1Admin(address(dex_)).turnOnSmartDebt(1e4 * dexPool_.token0Wei);
        }

        vm.recordLogs();
        uint256 amountInBack_ =
            _testSwapExactIn(dexPool_, user_, amountOut_, !startSwap0To1, dexType_, true, true, false);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory l_ = entries[i];
            if (l_.emitter != address(liquidity)) continue;
            if (l_.topics[0] != FluidLiquidityUserModuleEvents.LogOperate.selector) continue;
            if (address(uint160(uint256(l_.topics[2]))) != (startSwap0To1 ? dexPool_.token1 : dexPool_.token0)) {
                continue;
            }
            if (dexType_ == DexType.SmartDebt) {
                (, int256 borrowAmount_,,,,) = abi.decode(l_.data, (int256, int256, address, address, uint256, uint256));
                assertLt(borrowAmount_, 0, string(abi.encodePacked(assertMessage_, "borrowAmount_ is not deposit")));
            } else if (dexType_ == DexType.SmartCol) {
                (int256 depositAmount_,,,,,) = abi.decode(l_.data, (int256, int256, address, address, uint256, uint256));
                assertGt(depositAmount_, 0, string(abi.encodePacked(assertMessage_, "depositAmount_ is not deposit")));
            }
        }

        assertGe(
            amountIn_ * 1001 / 1000,
            amountInBack_,
            string(abi.encodePacked(assertMessage_, "amountIn_ is less than amountInBack_"))
        );

        // TODO @thrilok precison delta was 20 reduced by more 20 wei, DAI_USDC_LESS_THAN_ONE 67
        _comparePrecision(
            amountIn_,
            amountInBack_,
            (startSwap0To1 ? dexPool_.token0Wei : dexPool_.token1Wei),
            100,
            string(abi.encodePacked(assertMessage_, "amountInBack_ is very less than amountIn_"))
        );
    }

    struct OracleLoopData {
        int256 changeInPriceBeforeSwap;
        int256 changeInPriceBeforeSwapWithMax5Percent;
        int256 changeInPriceAfterSwap;
        int256 changeInPriceAfterSwapWithMax5Percent;
        DexVariablesData dexVariablesBeforeSwap;
        DexVariablesData dexVariablesAfterSwap;
        OracleMapData oracleMapData;
        OracleSlotConfig oracleSlotConfig;
    }

    struct OracleData {
        DexVariablesData dexVariables;
        uint256 lastPrice;
        uint256 lastToLastPrice;
        uint256 totalSlots;
        uint256 totalCycle;
        OracleMapData[] overallOracleMapDataAfterEachSwap;
        OracleMapData[] overallOracleMapDataAtEnd;
    }

    function _testUpdateOracleWithTimes(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool swap0To1,
        uint256[250] memory timesToSkip_,
        DexType dexType_
    ) public {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateOracleWithTimes::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                "-",
                swap0To1 ? "0to1" : "1to0"
            )
        );

        skip(1);

        OracleData memory d_;

        d_.dexVariables = _getDexVariablesData(dex_);
        d_.lastPrice = d_.dexVariables.lastPrice;
        d_.lastToLastPrice = d_.dexVariables.lastToLastPrice;

        uint256 casesToRun_ = timesToSkip_.length;

        d_.overallOracleMapDataAfterEachSwap = new OracleMapData[](casesToRun_);
        uint256 q_;

        for (uint256 i = 0; i < casesToRun_; i++) {
            skip(timesToSkip_[i]);

            OracleLoopData memory v_;
            {
                v_.changeInPriceBeforeSwap =
                    int256(ORACLE_PRECISION) - int256((d_.lastToLastPrice * ORACLE_PRECISION) / d_.lastPrice);
                v_.changeInPriceBeforeSwapWithMax5Percent = v_.changeInPriceBeforeSwap * int256(X22) / int256(5e16);

                v_.dexVariablesBeforeSwap = _getDexVariablesData(dex_);

                _testSwapExactIn(dexPool_, user_, amountIn_, swap0To1, dexType_, true, false, true);

                v_.dexVariablesAfterSwap = _getDexVariablesData(dex_);

                assertApproxEqAbs(
                    d_.lastPrice,
                    v_.dexVariablesAfterSwap.lastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
                );
                d_.lastToLastPrice = d_.lastPrice;
                d_.lastPrice = v_.dexVariablesAfterSwap.lastPrice;

                (v_.oracleMapData, v_.oracleSlotConfig) =
                    _getOracleMapData(dex_, v_.dexVariablesBeforeSwap.oracleMap, v_.dexVariablesBeforeSwap.oracleSlot);
                d_.totalSlots += v_.oracleSlotConfig.totalSlots;
                d_.totalCycle += v_.oracleSlotConfig.totalCycle;

                v_.changeInPriceAfterSwapWithMax5Percent = v_.oracleMapData.changePriceSign == 1
                    ? int256(v_.oracleMapData.changeInPriceWithMax5Percent)
                    : -int256(v_.oracleMapData.changeInPriceWithMax5Percent);
                assertApproxEqAbs(
                    v_.changeInPriceBeforeSwapWithMax5Percent,
                    v_.changeInPriceAfterSwapWithMax5Percent,
                    0,
                    string(abi.encodePacked(assertMessage_, "changeInPriceWithMax5Percent"))
                );
                assertApproxEqAbs(
                    v_.oracleMapData.timeDiff,
                    v_.dexVariablesBeforeSwap.lastTimestampDifBetweenLastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "timeDiff"))
                );
            }

            d_.overallOracleMapDataAfterEachSwap[q_++] = v_.oracleMapData;
        }

        {
            assertApproxEqAbs(
                d_.totalSlots,
                (_getDexVariablesData(dex_).oracleMap * 8) + (7 - _getDexVariablesData(dex_).oracleSlot),
                0,
                string(abi.encodePacked(assertMessage_, "no of slots didn't match"))
            );
            d_.overallOracleMapDataAtEnd = _getOracleAllSlotsData(dex_);
            assertApproxEqAbs(
                d_.overallOracleMapDataAtEnd.length,
                casesToRun_,
                0,
                string(abi.encodePacked(assertMessage_, "no of cases didn't match"))
            );

            for (uint256 i = 0; i < d_.overallOracleMapDataAtEnd.length; i++) {
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].changeInPriceWithMax5Percent,
                    d_.overallOracleMapDataAfterEachSwap[i].changeInPriceWithMax5Percent,
                    0,
                    string(abi.encodePacked(assertMessage_, "changeInPriceWithMax5Percent Overall"))
                );
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].timeDiff,
                    d_.overallOracleMapDataAfterEachSwap[i].timeDiff,
                    0,
                    string(abi.encodePacked(assertMessage_, "timeDiff Overall"))
                );
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].changePriceSign,
                    d_.overallOracleMapDataAfterEachSwap[i].changePriceSign,
                    0,
                    string(abi.encodePacked(assertMessage_, "changePriceSign Overall"))
                );
            }
        }
    }

    function _testUpdateOracle(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool swap0To1,
        uint256 timeToSkip_,
        uint256 casesToRun_,
        uint256 startTimeToSkip,
        DexType dexType_
    ) public {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateOracle::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                "-",
                swap0To1 ? "0to1" : "1to0",
                "-",
                LibString.toString(timeToSkip_),
                "-",
                LibString.toString(startTimeToSkip),
                "-",
                LibString.toString(casesToRun_),
                " "
            )
        );

        skip(1);

        OracleData memory d_;

        d_.dexVariables = _getDexVariablesData(dex_);
        d_.lastPrice = d_.dexVariables.lastPrice;
        d_.lastToLastPrice = d_.dexVariables.lastToLastPrice;

        d_.overallOracleMapDataAfterEachSwap = new OracleMapData[](casesToRun_);
        uint256 q_;

        for (uint256 i = 0; i < casesToRun_; i++) {
            skip(i == 0 ? startTimeToSkip : timeToSkip_);

            OracleLoopData memory v_;
            {
                v_.changeInPriceBeforeSwap =
                    int256(ORACLE_PRECISION) - int256((d_.lastToLastPrice * ORACLE_PRECISION) / d_.lastPrice);
                v_.changeInPriceBeforeSwapWithMax5Percent = v_.changeInPriceBeforeSwap * int256(X22) / int256(5e16);

                v_.dexVariablesBeforeSwap = _getDexVariablesData(dex_);

                _testSwapExactIn(dexPool_, user_, amountIn_, swap0To1, dexType_, true, false, true);

                v_.dexVariablesAfterSwap = _getDexVariablesData(dex_);

                assertApproxEqAbs(
                    d_.lastPrice,
                    v_.dexVariablesAfterSwap.lastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
                );
                d_.lastToLastPrice = d_.lastPrice;
                d_.lastPrice = v_.dexVariablesAfterSwap.lastPrice;
                (v_.oracleMapData, v_.oracleSlotConfig) =
                    _getOracleMapData(dex_, v_.dexVariablesBeforeSwap.oracleMap, v_.dexVariablesBeforeSwap.oracleSlot);
                d_.totalSlots += v_.oracleSlotConfig.totalSlots;
                d_.totalCycle += v_.oracleSlotConfig.totalCycle;

                v_.changeInPriceAfterSwapWithMax5Percent = v_.oracleMapData.changePriceSign == 1
                    ? int256(v_.oracleMapData.changeInPriceWithMax5Percent)
                    : -int256(v_.oracleMapData.changeInPriceWithMax5Percent);
                assertApproxEqAbs(
                    v_.changeInPriceBeforeSwapWithMax5Percent,
                    v_.changeInPriceAfterSwapWithMax5Percent,
                    0,
                    string(abi.encodePacked(assertMessage_, "changeInPriceWithMax5Percent"))
                );
                assertApproxEqAbs(
                    v_.oracleMapData.timeDiff,
                    v_.dexVariablesBeforeSwap.lastTimestampDifBetweenLastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "timeDiff"))
                );
            }

            d_.overallOracleMapDataAfterEachSwap[q_++] = v_.oracleMapData;
        }

        {
            assertApproxEqAbs(
                d_.totalSlots,
                (_getDexVariablesData(dex_).oracleMap * 8) + (7 - _getDexVariablesData(dex_).oracleSlot),
                0,
                string(abi.encodePacked(assertMessage_, "no of slots didn't match"))
            );
            d_.overallOracleMapDataAtEnd = _getOracleAllSlotsData(dex_);
            assertApproxEqAbs(
                d_.overallOracleMapDataAtEnd.length,
                casesToRun_,
                0,
                string(abi.encodePacked(assertMessage_, "no of cases didn't match"))
            );

            for (uint256 i = 0; i < d_.overallOracleMapDataAtEnd.length; i++) {
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].changeInPriceWithMax5Percent,
                    d_.overallOracleMapDataAfterEachSwap[i].changeInPriceWithMax5Percent,
                    0,
                    string(abi.encodePacked(assertMessage_, "changeInPriceWithMax5Percent Overall"))
                );
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].timeDiff,
                    d_.overallOracleMapDataAfterEachSwap[i].timeDiff,
                    0,
                    string(abi.encodePacked(assertMessage_, "timeDiff Overall"))
                );
                assertApproxEqAbs(
                    d_.overallOracleMapDataAtEnd[i].changePriceSign,
                    d_.overallOracleMapDataAfterEachSwap[i].changePriceSign,
                    0,
                    string(abi.encodePacked(assertMessage_, "changePriceSign Overall"))
                );
            }
        }
    }

    function _testUpdateOracleOverLimit(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool swap0To1,
        uint256 timeToSkip_,
        uint256 casesToRun_,
        uint256 startTimeToSkip,
        DexType dexType_
    ) public {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        if (dexType_ == DexType.SmartDebt) {
            // Borrow liquidity for swap, 10k
            _testBorrowPerfectDebtLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_, new bytes(0));
        } else if (dexType_ == DexType.SmartCol) {
            // Deposit liquidity for swap, 100k
            _testDepositPerfectColLiquidity(dexPool_, bob, 1e4 * 1e18, dexType_);
        }

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testUpdateOracleOverLimit::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                "-",
                swap0To1 ? "0to1" : "1to0",
                "-",
                LibString.toString(timeToSkip_),
                "-",
                LibString.toString(startTimeToSkip),
                "-",
                LibString.toString(casesToRun_),
                " "
            )
        );

        skip(1);

        OracleData memory d_;

        d_.dexVariables = _getDexVariablesData(dex_);
        d_.lastPrice = d_.dexVariables.lastPrice;
        d_.lastToLastPrice = d_.dexVariables.lastToLastPrice;

        d_.overallOracleMapDataAfterEachSwap = new OracleMapData[](casesToRun_);
        uint256 q_;

        for (uint256 i = 0; i < casesToRun_; i++) {
            skip(i == 0 ? startTimeToSkip : timeToSkip_);

            OracleLoopData memory v_;
            {
                v_.changeInPriceBeforeSwap =
                    int256(ORACLE_PRECISION) - int256((d_.lastToLastPrice * ORACLE_PRECISION) / d_.lastPrice);
                v_.changeInPriceBeforeSwapWithMax5Percent = v_.changeInPriceBeforeSwap * int256(X22) / int256(5e16);

                v_.dexVariablesBeforeSwap = _getDexVariablesData(dex_);

                _testSwapExactIn(dexPool_, user_, amountIn_, swap0To1, dexType_, true, false, true);

                v_.dexVariablesAfterSwap = _getDexVariablesData(dex_);

                assertApproxEqAbs(
                    d_.lastPrice,
                    v_.dexVariablesAfterSwap.lastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "lastToLastPrice"))
                );
                d_.lastToLastPrice = d_.lastPrice;
                d_.lastPrice = v_.dexVariablesAfterSwap.lastPrice;
                (v_.oracleMapData, v_.oracleSlotConfig) =
                    _getOracleMapData(dex_, v_.dexVariablesBeforeSwap.oracleMap, v_.dexVariablesBeforeSwap.oracleSlot);
                d_.totalSlots += v_.oracleSlotConfig.totalSlots;
                d_.totalCycle += v_.oracleSlotConfig.totalCycle;

                v_.changeInPriceAfterSwapWithMax5Percent = v_.oracleMapData.changePriceSign == 1
                    ? int256(v_.oracleMapData.changeInPriceWithMax5Percent)
                    : -int256(v_.oracleMapData.changeInPriceWithMax5Percent);
                assertApproxEqAbs(
                    v_.changeInPriceBeforeSwapWithMax5Percent,
                    v_.changeInPriceAfterSwapWithMax5Percent,
                    0,
                    string(abi.encodePacked(assertMessage_, "changeInPriceWithMax5Percent"))
                );
                assertApproxEqAbs(
                    v_.oracleMapData.timeDiff,
                    v_.dexVariablesBeforeSwap.lastTimestampDifBetweenLastToLastPrice,
                    0,
                    string(abi.encodePacked(assertMessage_, "timeDiff"))
                );
            }

            d_.overallOracleMapDataAfterEachSwap[q_++] = v_.oracleMapData;
        }

        d_.dexVariables = _getDexVariablesData(dex_);
        {
            uint256 totalSlots_ = (d_.totalCycle * dex_.constantsView().oracleMapping * 8)
                + (d_.dexVariables.oracleMap * 8) + (7 - d_.dexVariables.oracleSlot);
            assertApproxEqAbs(
                d_.totalSlots, totalSlots_, 0, string(abi.encodePacked(assertMessage_, "no of slots didn't match"))
            );
            d_.overallOracleMapDataAtEnd = _getOracleAllSlotsData(dex_);
        }

        // TODO: validate slots
    }

    struct ValidateThresholdShift {
        uint256[] timeShifts;
        uint256 totalShiftTime;
        uint256 snapshotId;
        DexStrcuts.PricesAndExchangePrice prePex;
        DexVariables2Data dexVariables2;
        DexVariablesData dexVariables;
        uint256 centerPrice;
        uint256 upperRange;
        uint256 lowerRange;
        uint256 upperThreshold;
        uint256 lowerThreshold;
        uint256 shiftingTime;
    }

    struct RangeParams {
        uint256 centerPrice;
        uint256 lastPrice;
        uint256 upperRange;
        uint256 lowerRange;
        uint256 upperThreshold;
        uint256 lowerThreshold;
    }

    function _calculateRange(FluidDexT1 dex_) internal returns (RangeParams memory r_) {
        DexVariablesData memory dexVariables_ = _getDexVariablesData(dex_);
        DexVariables2Data memory dexVariables2_ = _getDexVariables2Data(dex_);

        r_.centerPrice = dexVariables_.centerPrice;
        r_.lastPrice = dexVariables_.lastPrice;
        r_.upperRange = (r_.centerPrice * 1e6) / (1e6 - dexVariables2_.upperPercent);
        r_.lowerRange = (r_.centerPrice * (1e6 - dexVariables2_.lowerPercent)) / 1e6;
        r_.upperThreshold =
            (r_.centerPrice + (r_.upperRange - r_.centerPrice) * (1e3 - dexVariables2_.upperShiftPercent / 1e3) / 1e3);
        r_.lowerThreshold =
            (r_.centerPrice - (r_.centerPrice - r_.lowerRange) * (1e3 - dexVariables2_.lowerShiftPercent / 1e3) / 1e3);
    }

    function _validateThresholdShift(
        FluidDexT1 dex_,
        uint256[] memory timeShiftInPercentage_,
        bool completeShift_,
        string memory assertMessage_
    ) internal {
        ValidateThresholdShift memory v_;
        if (timeShiftInPercentage_.length == 0) {
            v_.timeShifts = new uint256[](6);

            v_.timeShifts[0] = 10 * 1e4;
            v_.timeShifts[1] = 25 * 1e4;
            v_.timeShifts[2] = 50 * 1e4;
            v_.timeShifts[3] = 75 * 1e4;
            v_.timeShifts[4] = 100 * 1e4;
            v_.timeShifts[5] = 150 * 1e4;
        } else {
            v_.timeShifts = timeShiftInPercentage_;
        }

        v_.snapshotId = vm.snapshot();

        v_.prePex = _getPricesAndExchangePrices(dex_);
        v_.dexVariables = _getDexVariablesData(dex_);
        v_.dexVariables2 = _getDexVariables2Data(dex_);

        v_.centerPrice = v_.dexVariables.centerPrice;

        v_.totalShiftTime = block.timestamp - v_.dexVariables.lastTimestamp;

        v_.upperRange = (v_.centerPrice * 1e6) / (1e6 - v_.dexVariables2.upperPercent);
        v_.lowerRange = (v_.centerPrice * (1e6 - v_.dexVariables2.lowerPercent)) / 1e6;
        v_.upperThreshold =
            (v_.centerPrice + (v_.upperRange - v_.centerPrice) * (1e3 - v_.dexVariables2.upperShiftPercent / 1e3) / 1e3);
        v_.lowerThreshold =
            (v_.centerPrice - (v_.centerPrice - v_.lowerRange) * (1e3 - v_.dexVariables2.lowerShiftPercent / 1e3) / 1e3);
        v_.shiftingTime = v_.dexVariables2.shiftTime;

        if ((v_.upperThreshold > v_.dexVariables.lastPrice && v_.dexVariables.lastPrice > v_.lowerThreshold)) {
            console.log("no shift needed", v_.upperThreshold, v_.dexVariables.lastPrice, v_.lowerThreshold);
            return;
        }

        for (uint256 i = 0; i < v_.timeShifts.length; i++) {
            uint256 timeToShift_ = (v_.shiftingTime * v_.timeShifts[i] / 1e6) - v_.totalShiftTime;

            v_.totalShiftTime += timeToShift_;
            skip(timeToShift_);

            DexStrcuts.PricesAndExchangePrice memory postPex_ = _getPricesAndExchangePrices(dex_);

            uint256 timeShiftDone = v_.totalShiftTime * 1e4 / v_.shiftingTime;

            uint256 changeCenterPrice_;
            if (v_.dexVariables.lastPrice > v_.upperThreshold) {
                if (v_.totalShiftTime >= v_.shiftingTime) {
                    changeCenterPrice_ = v_.upperRange;
                } else {
                    changeCenterPrice_ =
                        v_.centerPrice + ((v_.upperRange - v_.centerPrice) * v_.totalShiftTime / v_.shiftingTime);
                }
            } else {
                if (v_.totalShiftTime >= v_.shiftingTime) {
                    changeCenterPrice_ = v_.lowerRange;
                } else {
                    changeCenterPrice_ = v_.centerPrice - ((v_.centerPrice - v_.lowerRange) * timeShiftDone / 1e4);
                }
            }

            _comparePrecision(
                postPex_.centerPrice,
                changeCenterPrice_,
                1e18,
                0,
                string(
                    abi.encodePacked(assertMessage_, "_validateThresholdShift -", LibString.toString(v_.timeShifts[i]))
                )
            );
            // TODO: validate range
        }

        if (!completeShift_) {
            vm.revertTo(v_.snapshotId);
        }
    }

    function _testThresholdShift(
        DexParams memory dexPool_,
        address user_,
        uint256 amountIn_,
        bool swap0To1,
        uint256[] memory timeShiftInPercentage_,
        DexType dexType_
    ) public {
        FluidDexT1 dex_ = _getDexType(dexPool_, dexType_, false);

        string memory assertMessage_ = string(
            abi.encodePacked(
                "_testThresholdShift::",
                _getDexPoolName(dexPool_, dexType_),
                ":",
                LibString.toString(amountIn_),
                "-",
                swap0To1 ? "0to1" : "1to0",
                " "
            )
        );

        RangeParams memory r_ = _calculateRange(dex_);
        while ((r_.upperThreshold > r_.lastPrice && r_.lastPrice > r_.lowerThreshold)) {
            _testSwapExactIn(dexPool_, user_, amountIn_ * 10, swap0To1, dexType_, true, false, true);
            skip(1);
            r_ = _calculateRange(dex_);
        }

        _validateThresholdShift(dex_, timeShiftInPercentage_, false, assertMessage_);
    }

    struct OraclePriceData {
        DexVariablesData dexVariables;
        OracleMapData[] oracleMapData;
        DexStrcuts.Oracle[] twaps;
        uint256 currentPrice;
        uint256 aggTwap1By0;
        uint256 aggTwap0By1;
        uint256 totalTwapTimeCal;
    }

    function _validateTwap(FluidDexT1 dex_, uint256[] memory secondsAgo_, string memory assertMessage_) internal {
        OraclePriceData memory p_;
        (p_.twaps, p_.currentPrice) = dex_.oraclePrice(secondsAgo_);

        p_.oracleMapData = _getOracleAllSlotsData(dex_);
        p_.dexVariables = _getDexVariablesData(dex_);

        for (uint256 j = 0; j < p_.twaps.length; j++) {
            p_.totalTwapTimeCal = block.timestamp - p_.dexVariables.lastTimestamp;
            DexStrcuts.Oracle memory twap_ = p_.twaps[j];
            uint256 twapTime_ = secondsAgo_[j];
            if (j == 0) {
                p_.aggTwap1By0 = twap_.twap1by0;
                p_.aggTwap0By1 = twap_.twap0by1;
            } else {
                p_.aggTwap1By0 = (
                    (p_.aggTwap1By0 * secondsAgo_[j - 1]) + (twap_.twap1by0 * (secondsAgo_[j] - secondsAgo_[j - 1]))
                ) / twapTime_;
                p_.aggTwap0By1 = (
                    (p_.aggTwap0By1 * secondsAgo_[j - 1]) + (twap_.twap0by1 * (secondsAgo_[j] - secondsAgo_[j - 1]))
                ) / twapTime_;
            }

            uint256 twap1by0_ = 0;
            uint256 twap0by1_ = 0;

            uint256 price_ = p_.dexVariables.lastToLastPrice;

            if (p_.totalTwapTimeCal >= twapTime_ && j == 0) {
                price_ = p_.dexVariables.lastPrice;
                twap1by0_ += price_ * twapTime_;
                twap0by1_ += (1e54 / price_) * twapTime_;
            } else {
                // last updated time to current time price.
                twap1by0_ += price_ * p_.totalTwapTimeCal;
                twap0by1_ += (1e54 / price_) * p_.totalTwapTimeCal;

                if (p_.totalTwapTimeCal + p_.dexVariables.lastTimestampDifBetweenLastToLastPrice >= twapTime_) {
                    uint256 twapTimeDiff_ = twapTime_ - p_.totalTwapTimeCal;
                    twap1by0_ += price_ * twapTimeDiff_;
                    twap0by1_ += (1e54 / price_) * twapTimeDiff_;
                    p_.totalTwapTimeCal += twapTimeDiff_;
                } else {
                    twap1by0_ += price_ * p_.dexVariables.lastTimestampDifBetweenLastToLastPrice;
                    twap0by1_ += (1e54 / price_) * p_.dexVariables.lastTimestampDifBetweenLastToLastPrice;
                    p_.totalTwapTimeCal += p_.dexVariables.lastTimestampDifBetweenLastToLastPrice;

                    for (uint256 k = p_.oracleMapData.length - 1; k >= 0; k--) {
                        if (p_.oracleMapData[k].changePriceSign == 1) {
                            price_ = price_ - (price_ * p_.oracleMapData[k].changeInPrice / 1e18);
                        } else {
                            price_ = price_ + (price_ * p_.oracleMapData[k].changeInPrice / 1e18);
                        }

                        if (twapTime_ >= p_.oracleMapData[k].timeDiff + p_.totalTwapTimeCal) {
                            twap1by0_ += price_ * p_.oracleMapData[k].timeDiff;
                            twap0by1_ += (1e54 / price_) * p_.oracleMapData[k].timeDiff;
                            p_.totalTwapTimeCal += p_.oracleMapData[k].timeDiff;
                        } else {
                            uint256 twapTimeDiff_ = twapTime_ - p_.totalTwapTimeCal;
                            twap1by0_ += price_ * twapTimeDiff_;
                            twap0by1_ += (1e54 / price_) * twapTimeDiff_;

                            p_.totalTwapTimeCal += twapTimeDiff_;
                            break;
                        }
                    }
                }
            }
            twap1by0_ = twap1by0_ / twapTime_;
            twap0by1_ = twap0by1_ / twapTime_;

            {
                assertApproxEqAbs(
                    twap1by0_, p_.aggTwap1By0, 1, string(abi.encodePacked(assertMessage_, "twap_.twap1by0"))
                );
                assertApproxEqAbs(
                    twap0by1_, p_.aggTwap0By1, 1, string(abi.encodePacked(assertMessage_, "twap_.twap0by1"))
                );
            }
        }
    }

    function _bytesToDecimal(bytes memory input) public pure returns (uint256 result) {
        for (uint256 i = 0; i < input.length - 1; i++) {
            // Convert byte to its ASCII value
            uint8 asciiValue = uint8(input[i]);

            // Check if the ASCII value represents a digit (0-9)
            if (asciiValue < 48 || asciiValue > 57) {
                revert("Invalid digit: not a numeric ASCII character");
            }

            // Convert ASCII digit to its numeric value
            uint8 digit = asciiValue - 48;

            // Build the number by multiplying previous result by 10 and adding new digit
            result = result * 10 + digit;
        }
    }

    function _uintToString(uint256 _value) internal pure returns (string memory) {
        // Special case for zero
        if (_value == 0) {
            return "0";
        }

        // Calculate the number of digits
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        // Create a bytes array to store the string
        bytes memory buffer = new bytes(digits);

        // Convert each digit to character, working backwards
        while (_value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }

        return string(buffer);
    }
}

contract PoolT1Admin is PoolT1BaseTest {
    function testAdmin_UpdateRangePercents() public {
        uint256 lowerPercent_ = 20 * 1e4;
        uint256 upperPercent_ = 20 * 1e4;
        uint256[3] memory shiftTimes_ = [uint256(0), uint256(1 hours), uint256(1 days)];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < shiftTimes_.length; k++) {
                    _testUpdateRangePercents(
                        pools[i], admin, upperPercent_, lowerPercent_, shiftTimes_[k], poolTypes_[j]
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testAdmin_UpdateThresholdPercent() public {
        uint256 lowerPercent_ = 20 * 1e4;
        uint256 upperPercent_ = 20 * 1e4;
        uint256[3] memory shiftTimes_ = [uint256(0), uint256(1 hours), uint256(1 days)];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < shiftTimes_.length; k++) {
                    _testUpdateThresholdPercent(
                        pools[i], admin, upperPercent_, lowerPercent_, 1 days, shiftTimes_[k], poolTypes_[j]
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testAdmin_UpdateCenterPriceAddress() public {
        vm.prank(bob);
        contractDeployerFactory.deployContract(type(MockDexCenterPrice).creationCode);
        uint256 percent_ = 3 * 1e4;
        uint256[2] memory centerPriceAddressNonces_ = [contractDeployerFactory.totalContracts(), 0];
        uint256[3] memory times_ = [uint256(1), uint256(1 hours), uint256(1 days)];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < times_.length; k++) {
                    for (uint256 l = 0; l < centerPriceAddressNonces_.length; l++) {
                        _testUpdateCenterPriceAddress(
                            pools[i], admin, centerPriceAddressNonces_[l], percent_, times_[k], poolTypes_[j]
                        );
                        vm.revertTo(snapshotId_);
                    }
                }
            }
        }
    }

    function testAdmin_UpdateHookAddress() public {
        vm.prank(bob);
        contractDeployerFactory.deployContract(type(MockDexCenterPrice).creationCode);
        uint256[2] memory centerPriceAddressNonces_ = [contractDeployerFactory.totalContracts(), 0];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 l = 0; l < centerPriceAddressNonces_.length; l++) {
                    _testUpdateHookAddress(pools[i], admin, centerPriceAddressNonces_[l], poolTypes_[j]);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testAdmin_UpdateUserSupplyConfig() public {
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        address payable eve = payable(makeAddr("eve"));
        vm.label(eve, "eve");

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 l = 0; l < 2; l++) {
                    _testUpdateUserSupplyConfig(
                        pools[i],
                        admin,
                        eve,
                        DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
                        DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
                        100 * 1e18,
                        poolTypes_[j]
                    );

                    _testDepositPerfectColLiquidity(pools[i], eve, 200 * 1e18, poolTypes_[j]);
                    uint256 snapshotId2_ = vm.snapshot();

                    {
                        // withdrawPerfectColLiquidity
                        _testWithdrawPerfectColLiquidity(pools[i], eve, 10 * 1e18, poolTypes_[j], new bytes(0));
                        _testWithdrawPerfectColLiquidity(
                            pools[i],
                            eve,
                            40 * 1e18,
                            poolTypes_[j],
                            abi.encodeWithSelector(
                                FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__WithdrawLimitReached
                            )
                        );
                        vm.revertTo(snapshotId2_);
                    }

                    // {
                    //     // withdrawColLiquidity
                    //     (uint256 token0Amount_, uint256 token1Amount_) =
                    //         _testWithdrawPerfectColLiquidity(pools[i], eve, 10 * 1e18, poolTypes_[j], new bytes(0));

                    //     _testWithdrawColLiquidity(
                    //         pools[i],
                    //         eve,
                    //         token0Amount_ * 5 / pools[i].token0Wei,
                    //         token1Amount_ * 4 / pools[i].token1Wei,
                    //         poolTypes_[j],
                    //         abi.encodeWithSelector(
                    //             FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__WithdrawLimitReached
                    //         )
                    //     );
                    //     vm.revertTo(snapshotId2_);
                    // }

                    // {
                    //     // withdrawPerfectInOne
                    //     (uint256 token0Amount_, uint256 token1Amount_) =
                    //         _testWithdrawPerfectColLiquidity(pools[i], eve, 10 * 1e18, poolTypes_[j], new bytes(0));

                    //     _testWithdrawPerfectInOne(
                    //         pools[i],
                    //         eve,
                    //         40 * 1e18,
                    //         true,
                    //         poolTypes_[j],
                    //         abi.encodeWithSelector(
                    //             FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__WithdrawLimitReached
                    //         )
                    //     );
                    //     vm.revertTo(snapshotId2_);
                    // }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testAdmin_UpdateUserBorrowConfig() public {
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();

        address payable eve = payable(makeAddr("eve"));
        vm.label(eve, "eve");

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 l = 0; l < 2; l++) {
                    _testUpdateUserBorrowConfig(
                        pools[i],
                        admin,
                        eve,
                        DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
                        DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
                        100 * 1e18,
                        200 * 1e18,
                        poolTypes_[j]
                    );

                    uint256 snapshotId2_ = vm.snapshot();

                    {
                        // withdrawPerfectColLiquidity
                        _testBorrowPerfectDebtLiquidity(pools[i], eve, 10 * 1e18, poolTypes_[j], new bytes(0));
                        _testBorrowPerfectDebtLiquidity(
                            pools[i],
                            eve,
                            250 * 1e18,
                            poolTypes_[j],
                            abi.encodeWithSelector(
                                FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__DebtLimitReached
                            )
                        );
                        vm.revertTo(snapshotId2_);
                    }

                    {
                        // withdrawColLiquidity
                        (uint256 token0Amount_, uint256 token1Amount_) =
                            _testBorrowPerfectDebtLiquidity(pools[i], eve, 50 * 1e18, poolTypes_[j], new bytes(0));

                        _testBorrowDebtLiquidity(
                            pools[i],
                            eve,
                            token0Amount_ * 5 / pools[i].token0Wei,
                            token1Amount_ * 4 / pools[i].token1Wei,
                            poolTypes_[j],
                            abi.encodeWithSelector(
                                FluidDexErrors.FluidDexError.selector, FluidDexTypes.DexT1__DebtLimitReached
                            )
                        );
                        vm.revertTo(snapshotId2_);
                    }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }
}

contract PoolT1Base is PoolT1BaseTest {
    // DepositPerfectColLiquidity //
    function testDexT1_DepositPerfectColLiquidity() public {
        uint256 sharesAmount_ = 1e2 * 1e18;
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testDepositPerfectColLiquidity(pools[i], alice, sharesAmount_, poolTypes_[j]);
            }
        }
    }

    function testDexT1_WithdrawPerfectColLiquidity() public {
        uint256 sharesAmount_ = 1e3 * 1e18;
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                DexParams memory dexPool_ = pools[i];
                string memory assertMessage_ = string(
                    abi.encodePacked(
                        "testDexT1_WithdrawPerfectColLiquidity::",
                        _getDexPoolName(dexPool_, poolTypes_[j]),
                        ":",
                        LibString.toString(sharesAmount_)
                    )
                );

                // Deposit Dust liquidity
                _testDepositPerfectColLiquidity(dexPool_, bob, 1 * 1e18, poolTypes_[j]);

                (uint256 token0AmountDeposit_, uint256 token1AmountDeposit_) =
                    _testDepositPerfectColLiquidity(dexPool_, alice, sharesAmount_, poolTypes_[j]);

                (uint256 token0AmountWithdraw_, uint256 token1AmountWithdraw_) =
                    _testWithdrawPerfectColLiquidity(dexPool_, alice, sharesAmount_, poolTypes_[j], new bytes(0));

                assertGt(
                    token0AmountDeposit_,
                    token0AmountWithdraw_,
                    string(abi.encodePacked(assertMessage_, "token0AmountDeposit_ < token0AmountWithdraw_"))
                );
                _comparePrecision(
                    token0AmountDeposit_,
                    token0AmountWithdraw_,
                    pools[i].token0Wei,
                    0,
                    string(abi.encodePacked(assertMessage_, "token0AmountPayback != token0AmountWithdraw_"))
                );

                assertGt(
                    token1AmountDeposit_,
                    token1AmountWithdraw_,
                    string(abi.encodePacked(assertMessage_, "token1AmountDeposit_ < token1AmountWithdraw_"))
                );
                _comparePrecision(
                    token1AmountDeposit_,
                    token1AmountWithdraw_,
                    pools[i].token1Wei,
                    0,
                    string(abi.encodePacked(assertMessage_, "token1AmountPayback != token1AmountWithdraw_"))
                );
            }
        }
    }

    function testDexT1_BorrowPerfectDebtLiquidity() public {
        uint256 sharesAmount_ = 1e3 * 1e18;
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testBorrowPerfectDebtLiquidity(pools[i], alice, sharesAmount_, poolTypes_[j], new bytes(0));
            }
        }
    }

    function testDexT1_PaybackPerfectDebtLiquidity() public {
        uint256 sharesAmount_ = 1e3 * 1e18;
        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                string memory assertMessage_ = string(
                    abi.encodePacked(
                        "testDexT1_PaybackPerfectDebtLiquidity::",
                        _getDexPoolName(pools[i], poolTypes_[j]),
                        ":",
                        LibString.toString(sharesAmount_)
                    )
                );

                // Borrow Dust liquidity
                _testBorrowPerfectDebtLiquidity(pools[i], bob, 1 * 1e18, poolTypes_[j], new bytes(0));

                (uint256 token0AmountBorrow_, uint256 token1AmountBorrow_) =
                    _testBorrowPerfectDebtLiquidity(pools[i], alice, sharesAmount_, poolTypes_[j], new bytes(0));

                (uint256 token0AmountPayback, uint256 token1AmountPayback) =
                    _testPaybackPerfectDebtLiquidity(pools[i], alice, sharesAmount_, poolTypes_[j]);

                assertLt(
                    token0AmountBorrow_,
                    token0AmountPayback,
                    string(abi.encodePacked(assertMessage_, "token0AmountBorrow_ < token0AmountPayback"))
                );
                _comparePrecision(
                    token0AmountPayback,
                    token0AmountBorrow_,
                    pools[i].token0Wei,
                    0,
                    string(abi.encodePacked(assertMessage_, "token0AmountPayback != token0AmountBorrow_"))
                );

                assertLt(
                    token1AmountBorrow_,
                    token1AmountPayback,
                    string(abi.encodePacked(assertMessage_, "token1AmountBorrow_ < token1AmountPayback"))
                );
                _comparePrecision(
                    token1AmountPayback,
                    token1AmountBorrow_,
                    pools[i].token1Wei,
                    0,
                    string(abi.encodePacked(assertMessage_, "token1AmountPayback != token1AmountBorrow_"))
                );
            }
        }
    }

    function testDexT1_SwapExactInOneDirection() public {
        uint256 sharesAmount_ = 1e2;
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];
        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    bool swap0to1_ = k == 0;
                    uint256 amountIn_ = sharesAmount_ * (swap0to1_ ? pools[i].token0Wei : pools[i].token1Wei);
                    _testSwapExactIn(pools[i], alice, amountIn_, swap0to1_, poolTypes_[j], false, false, false);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_SwapExactOutOneDirection() public {
        uint256 sharesAmount_ = 1e2;
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];
        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    bool swap0to1_ = k == 0;
                    uint256 amountOut_ = sharesAmount_ * (!swap0to1_ ? pools[i].token0Wei : pools[i].token1Wei);
                    _testSwapExactOut(pools[i], alice, amountOut_, swap0to1_, poolTypes_[j], false, false);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_SwapBackAndForth() public {
        uint256 sharesAmount_ = 1e3;
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];
        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    bool swap0to1_ = k == 0;
                    uint256 amountIn_ = sharesAmount_ * (swap0to1_ ? pools[i].token0Wei : pools[i].token1Wei);

                    _testSwapExactInBackAndForth(pools[i], alice, amountIn_, swap0to1_, poolTypes_[j]);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    struct TokenAmountParams {
        uint256 token0Amount;
        uint256 token1Amount;
    }

    function testDexT1_DepositColLiquidity_() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](4);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        a_[2] = TokenAmountParams({token0Amount: 2 * 1e4, token1Amount: 1 * 1e4});

        a_[3] = TokenAmountParams({token0Amount: 1 * 1e4, token1Amount: 2 * 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    _testDepositColLiquidity(pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j]);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_DepositColLiquidityInTwoHalfs() public {
        uint256 shareAmount_ = 1 * 1e3 * 1e18;

        DexType[1] memory poolTypes_ = [DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                string memory assertMessage_ = string(
                    abi.encodePacked(
                        "testDexT1_DepositColLiquidityInTwoHalfs::",
                        _getDexPoolName(pools[i], poolTypes_[j]),
                        ":",
                        LibString.toString(shareAmount_)
                    )
                );
                (uint256 token0Amount_, uint256 token1Amount_) =
                    _testDepositPerfectColLiquidity(pools[i], alice, shareAmount_, poolTypes_[j]);
                uint256 share0_ = _testDepositColLiquidityInWei(pools[i], alice, token0Amount_, 0, poolTypes_[j]);
                uint256 share1_ = _testDepositColLiquidityInWei(pools[i], alice, 0, token1Amount_, poolTypes_[j]);

                // TODO: @thrilok USDT_USDC:::Col, difference 11. Increasing by 10 wei: 99999999999, 99999999988
                assertGt(
                    shareAmount_,
                    share0_ + share1_,
                    string(abi.encodePacked(assertMessage_, "shareAmount_ < share0_ + share1_"))
                );
                _comparePrecision(
                    shareAmount_,
                    share0_ + share1_,
                    1e18,
                    10,
                    string(abi.encodePacked(assertMessage_, "shareAmount_ != share0_ + share1_"))
                );
                vm.revertTo(snapshotId_);
            }
        }
    }

    function testDexT1_WithdrawColLiquidity() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](4);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        a_[2] = TokenAmountParams({token0Amount: 2 * 1e4, token1Amount: 1 * 1e4});

        a_[3] = TokenAmountParams({token0Amount: 1 * 1e4, token1Amount: 2 * 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_WithdrawColLiquidity::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);

                    _testDepositColLiquidity(pools[i], alice, 10, 20, poolTypes_[j]);
                    uint256 depositShares_ =
                        _testDepositColLiquidity(pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j]);

                    uint256 withdrawShares_ = _testWithdrawColLiquidity(
                        pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j], new bytes(0)
                    );

                    assertLe(
                        depositShares_,
                        withdrawShares_,
                        string(abi.encodePacked(assertMessage_, "depositShares_ are more than withdrawShares_"))
                    );

                    // TODO @thrilok wei difference is max 10 * 1e18 for colDebt and 200 wei difference for non colDebt pools
                    if (poolTypes_[j] == DexType.SmartColAndDebt) {
                        assertApproxEqAbs(
                            depositShares_,
                            withdrawShares_,
                            type(uint64).max,
                            string(abi.encodePacked(assertMessage_, "depositShares_ != withdrawShares_"))
                        );
                    } else {
                        _comparePrecision(
                            depositShares_,
                            withdrawShares_,
                            1e18,
                            200,
                            string(abi.encodePacked(assertMessage_, "depositShares_ != withdrawShares_"))
                        );
                    }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_WithdrawColLiquidityInTwoTxs() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](2);
        a_[0] = TokenAmountParams({token0Amount: 2 * 1e3, token1Amount: 1 * 1e3});

        a_[1] = TokenAmountParams({token0Amount: 1 * 1e3, token1Amount: 2 * 1e3});

        DexType[1] memory poolTypes_ = [DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_WithdrawColLiquidityInTwoTxs::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);

                    _testDepositPerfectColLiquidity(pools[i], alice, 10 * 1e18, poolTypes_[j]);
                    uint256 depositShares_ =
                        _testDepositColLiquidity(pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j]);

                    uint256 withdrawShares0_ =
                        _testWithdrawColLiquidity(pools[i], alice, a_[k].token0Amount, 0, poolTypes_[j], new bytes(0));
                    uint256 withdrawShares1_ =
                        _testWithdrawColLiquidity(pools[i], alice, 0, a_[k].token1Amount, poolTypes_[j], new bytes(0));

                    assertLe(
                        depositShares_,
                        withdrawShares0_ + withdrawShares1_,
                        string(abi.encodePacked(assertMessage_, "depositShares_ are more than withdrawShares_"))
                    );

                    // TODO @thrilok: kept reduced precision to by 2 more decimals.
                    _comparePrecision(
                        depositShares_,
                        withdrawShares0_ + withdrawShares1_,
                        1e18 * 100,
                        0,
                        string(abi.encodePacked(assertMessage_, "depositShares_ != withdrawShares_"))
                    );

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_BorrowDebtLiquidity() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](4);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        a_[2] = TokenAmountParams({token0Amount: 2 * 1e4, token1Amount: 1 * 1e4});

        a_[3] = TokenAmountParams({token0Amount: 1 * 1e4, token1Amount: 2 * 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    _testBorrowDebtLiquidity(
                        pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j], new bytes(0)
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_PaybackDebtLiquidity() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](4);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        a_[2] = TokenAmountParams({token0Amount: 2 * 1e4, token1Amount: 1 * 1e4});

        a_[3] = TokenAmountParams({token0Amount: 1 * 1e4, token1Amount: 2 * 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_PaybackDebtLiquidity::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Borrow intial liquidity from bob
                    _testBorrowPerfectDebtLiquidity(pools[i], bob, 1e4 * 1e18, poolTypes_[j], new bytes(0));

                    _testBorrowDebtLiquidity(pools[i], alice, 10, 20, poolTypes_[j], new bytes(0));
                    uint256 borrowShares_ = _testBorrowDebtLiquidity(
                        pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j], new bytes(0)
                    );

                    uint256 paybackShares_ = _testPaybackDebtLiquidity(
                        pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j]
                    );

                    assertGt(
                        borrowShares_,
                        paybackShares_,
                        string(abi.encodePacked(assertMessage_, "borrowShares_ are more than paybackShares_"))
                    );

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    struct TokenAmountParamsDouble {
        TokenAmountParams txOne;
        TokenAmountParams txTwo;
    }

    struct TwoTxsParamsWithPercent {
        uint256 shares;
        uint256 txOneAmount0Percentage;
        uint256 txOneAmount1Percentage;
        uint256 txTwoAmount0Percentage;
        uint256 txTwoAmount1Percentage;
    }

    function testDexT1_DepositInTwoTxsAndWithdrawPerfect() public {
        TwoTxsParamsWithPercent[] memory a_ = new TwoTxsParamsWithPercent[](4);
        a_[0] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 100,
            txOneAmount1Percentage: 0,
            txTwoAmount0Percentage: 0,
            txTwoAmount1Percentage: 100
        });

        a_[1] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 0,
            txOneAmount1Percentage: 100,
            txTwoAmount0Percentage: 100,
            txTwoAmount1Percentage: 0
        });

        a_[2] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 100,
            txOneAmount1Percentage: 50,
            txTwoAmount0Percentage: 50,
            txTwoAmount1Percentage: 100
        });

        a_[3] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 50,
            txOneAmount1Percentage: 100,
            txTwoAmount0Percentage: 100,
            txTwoAmount1Percentage: 50
        });

        DexType[1] memory poolTypes_ = [DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    TokenAmountParamsDouble memory b_;
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_DepositInTwoTxsAndWithdrawPerfect::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].txOneAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txOneAmount1Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount1Percentage),
                            "-"
                        )
                    );
                    {
                        // Deposit intial liquidity from bob
                        _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);
                        _testDepositPerfectColLiquidity(pools[i], alice, 10 * 1e18, poolTypes_[j]);

                        (uint256 tokenDeposit0_, uint256 tokenDeposit1_) =
                            _testDepositPerfectColLiquidity(pools[i], alice, a_[k].shares, poolTypes_[j]);
                        b_ = TokenAmountParamsDouble({
                            txOne: TokenAmountParams({
                                token0Amount: tokenDeposit0_ * a_[k].txOneAmount0Percentage / 100,
                                token1Amount: tokenDeposit1_ * a_[k].txOneAmount1Percentage / 100
                            }),
                            txTwo: TokenAmountParams({
                                token0Amount: tokenDeposit0_ * a_[k].txTwoAmount0Percentage / 100,
                                token1Amount: tokenDeposit1_ * a_[k].txTwoAmount1Percentage / 100
                            })
                        });
                    }

                    uint256 depositShares0_ = _testDepositColLiquidityInWei(
                        pools[i], alice, b_.txOne.token0Amount, b_.txOne.token1Amount, poolTypes_[j]
                    );
                    uint256 depositShares1_ = _testDepositColLiquidityInWei(
                        pools[i], alice, b_.txTwo.token0Amount, b_.txTwo.token1Amount, poolTypes_[j]
                    );
                    (uint256 tokenWithdraw0_, uint256 tokenWithdraw1_) = _testWithdrawPerfectColLiquidity(
                        pools[i], alice, (depositShares0_ + depositShares1_), poolTypes_[j], new bytes(0)
                    );

                    assertGt(
                        (b_.txOne.token0Amount + b_.txTwo.token0Amount),
                        tokenWithdraw0_,
                        "token0Amount < tokenWithdraw0_"
                    );
                    assertGt(
                        (b_.txOne.token1Amount + b_.txTwo.token1Amount),
                        tokenWithdraw1_,
                        "token1Amount < tokenWithdraw1_"
                    );
                    // TODO @thrilok precision was off by 52, increasing wei difference to 100.
                    // DAI_USDC:::Col:::100-50-50-100 token0Amount != tokenWithdraw0_: 150000000000 !~= 149999999948 (max delta: 5, real delta: 55)
                    // DAI_USDC_MORE_THAN_ONE:::Col:::100-50-50-100-token0Amount != tokenWithdraw0_: 150000000000 !~= 149999999942 (max delta: 55, real delta: 58)
                    _comparePrecision(
                        (b_.txOne.token0Amount + b_.txTwo.token0Amount),
                        tokenWithdraw0_,
                        pools[i].token0Wei,
                        100,
                        string(abi.encodePacked(assertMessage_, "token0Amount != tokenWithdraw0_"))
                    );
                    _comparePrecision(
                        (b_.txOne.token1Amount + b_.txTwo.token1Amount),
                        tokenWithdraw1_,
                        pools[i].token1Wei,
                        100,
                        string(abi.encodePacked(assertMessage_, "token1Amount != tokenWithdraw1_"))
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_DepositTwoTxsAndWithdrawTwoTxs() public {
        TwoTxsParamsWithPercent[] memory a_ = new TwoTxsParamsWithPercent[](2);
        a_[0] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 100,
            txOneAmount1Percentage: 0,
            txTwoAmount0Percentage: 0,
            txTwoAmount1Percentage: 100
        });

        a_[1] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 0,
            txOneAmount1Percentage: 100,
            txTwoAmount0Percentage: 100,
            txTwoAmount1Percentage: 0
        });

        DexType[1] memory poolTypes_ = [DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        // TODO: @thrilok @samyak, there is a more withdraw amount at the end. Reason: USDC has 6 decimals and this gets better as liquidity in the pool of USDC increases.
        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    TokenAmountParamsDouble memory b_;
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_DepositTwoTxsAndWithdrawTwoTxs::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].txOneAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txOneAmount1Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount1Percentage),
                            "-"
                        )
                    );

                    {
                        // Deposit intial liquidity from bob
                        _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);
                        _testDepositPerfectColLiquidity(pools[i], alice, 100 * 1e18, poolTypes_[j]);

                        (uint256 tokenDeposit0_, uint256 tokenDeposit1_) =
                            _testDepositPerfectColLiquidity(pools[i], alice, a_[k].shares, poolTypes_[j]);
                        b_ = TokenAmountParamsDouble({
                            txOne: TokenAmountParams({
                                token0Amount: tokenDeposit0_ * a_[k].txOneAmount0Percentage / 100,
                                token1Amount: tokenDeposit1_ * a_[k].txOneAmount1Percentage / 100
                            }),
                            txTwo: TokenAmountParams({
                                token0Amount: tokenDeposit0_ * a_[k].txTwoAmount0Percentage / 100,
                                token1Amount: tokenDeposit1_ * a_[k].txTwoAmount1Percentage / 100
                            })
                        });
                    }

                    uint256 depositShares0_ = _testDepositColLiquidityInWei(
                        pools[i], alice, b_.txOne.token0Amount, b_.txOne.token1Amount, poolTypes_[j]
                    );
                    uint256 depositShares1_ = _testDepositColLiquidityInWei(
                        pools[i], alice, b_.txTwo.token0Amount, b_.txTwo.token1Amount, poolTypes_[j]
                    );

                    assertGt(
                        a_[k].shares,
                        depositShares0_ + depositShares1_,
                        string(abi.encodePacked(assertMessage_, "depositShares0_ + depositShares1_ > a_[k].shares"))
                    );
                    TokenAmountParamsDouble memory withdraw_;

                    (withdraw_.txTwo.token0Amount, withdraw_.txTwo.token1Amount) = _testWithdrawPerfectInOne(
                        pools[i], alice, depositShares1_, b_.txTwo.token0Amount != 0, poolTypes_[j], new bytes(0)
                    );
                    if (b_.txTwo.token0Amount != 0) {
                        assertGt(
                            (b_.txTwo.token0Amount),
                            withdraw_.txTwo.token0Amount,
                            string(
                                abi.encodePacked(assertMessage_, " txTwo token0Amount < withdraw_.txTwo.token0Amount")
                            )
                        );
                        _comparePrecision(
                            (b_.txTwo.token0Amount),
                            withdraw_.txTwo.token0Amount,
                            pools[i].token0Wei,
                            0,
                            string(
                                abi.encodePacked(assertMessage_, "txTwo token0Amount != withdraw_.txTwo.token0Amount")
                            )
                        );
                    } else {
                        assertGt(
                            (b_.txTwo.token1Amount),
                            withdraw_.txTwo.token1Amount,
                            string(
                                abi.encodePacked(assertMessage_, " txTwo token1Amount < withdraw_.txTwo.token1Amount")
                            )
                        );
                        _comparePrecision(
                            (b_.txTwo.token1Amount),
                            withdraw_.txTwo.token1Amount,
                            pools[i].token1Wei,
                            0,
                            string(
                                abi.encodePacked(assertMessage_, "txTwo token1Amount != withdraw_.txTwo.token1Amount")
                            )
                        );
                    }

                    (withdraw_.txOne.token0Amount, withdraw_.txOne.token1Amount) = _testWithdrawPerfectInOne(
                        pools[i], alice, depositShares0_, b_.txOne.token0Amount != 0, poolTypes_[j], new bytes(0)
                    );

                    // TODO @thrilok adjust it properly
                    // if (b_.txOne.token0Amount != 0) {
                    //     assertGt((b_.txOne.token0Amount), withdraw_.txOne.token0Amount, string(abi.encodePacked(assertMessage_, " txOne token0Amount < withdraw_.txOne.token0Amount")));
                    //     _comparePrecision(
                    //         ( b_.txOne.token0Amount),
                    //         withdraw_.txOne.token0Amount,
                    //         pools[i].token0Wei,
                    //         0,
                    //         string(abi.encodePacked(assertMessage_, "txOne token0Amount != withdraw_.txOne.token0Amount"))
                    //     );
                    // } else {
                    //     assertGt((b_.txOne.token1Amount), withdraw_.txOne.token1Amount, string(abi.encodePacked(assertMessage_, " txOne token1Amount < withdraw_.txOne.token1Amount")));
                    //     _comparePrecision(
                    //         (b_.txOne.token1Amount),
                    //         withdraw_.txOne.token1Amount,
                    //         pools[i].token1Wei,
                    //         0,
                    //         string(abi.encodePacked(assertMessage_, "txOne token1Amount != withdraw_.txOne.token1Amount"))
                    //     );
                    // }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_BorrowInTwoTxsAndPaybackPerfect() public {
        // TODO @thrilok borrow is was than payback, this is expected.
        TwoTxsParamsWithPercent[] memory a_ = new TwoTxsParamsWithPercent[](4);
        a_[0] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 100,
            txOneAmount1Percentage: 0,
            txTwoAmount0Percentage: 0,
            txTwoAmount1Percentage: 100
        });

        a_[1] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 0,
            txOneAmount1Percentage: 100,
            txTwoAmount0Percentage: 100,
            txTwoAmount1Percentage: 0
        });

        a_[2] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 100,
            txOneAmount1Percentage: 50,
            txTwoAmount0Percentage: 50,
            txTwoAmount1Percentage: 100
        });

        a_[3] = TwoTxsParamsWithPercent({
            shares: 1000 * 1e18,
            txOneAmount0Percentage: 50,
            txOneAmount1Percentage: 100,
            txTwoAmount0Percentage: 100,
            txTwoAmount1Percentage: 50
        });

        DexType[1] memory poolTypes_ = [DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    TokenAmountParamsDouble memory b_;
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_BorrowInTwoTxsAndPaybackPerfect::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].txOneAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txOneAmount1Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount0Percentage),
                            "-",
                            LibString.toString(a_[k].txTwoAmount1Percentage),
                            "-"
                        )
                    );
                    {
                        // Deposit intial liquidity from bob
                        _testBorrowPerfectDebtLiquidity(pools[i], bob, 1e4 * 1e18, poolTypes_[j], new bytes(0));
                        _testBorrowPerfectDebtLiquidity(pools[i], alice, 10 * 1e18, poolTypes_[j], new bytes(0));

                        (uint256 tokenBorrow0_, uint256 tokenBorrow1_) =
                            _testBorrowPerfectDebtLiquidity(pools[i], alice, a_[k].shares, poolTypes_[j], new bytes(0));
                        b_ = TokenAmountParamsDouble({
                            txOne: TokenAmountParams({
                                token0Amount: tokenBorrow0_ * a_[k].txOneAmount0Percentage / 100,
                                token1Amount: tokenBorrow1_ * a_[k].txOneAmount1Percentage / 100
                            }),
                            txTwo: TokenAmountParams({
                                token0Amount: tokenBorrow0_ * a_[k].txTwoAmount0Percentage / 100,
                                token1Amount: tokenBorrow1_ * a_[k].txTwoAmount1Percentage / 100
                            })
                        });
                    }

                    uint256 borrowShares0_ = _testBorrowDebtLiquidityInWei(
                        pools[i], alice, b_.txOne.token0Amount, b_.txOne.token1Amount, poolTypes_[j], new bytes(0)
                    );
                    uint256 borrowShares1_ = _testBorrowDebtLiquidityInWei(
                        pools[i], alice, b_.txTwo.token0Amount, b_.txTwo.token1Amount, poolTypes_[j], new bytes(0)
                    );

                    // TODO: testDexT1_BorrowInTwoTxsAndPaybackPerfect::DAI_SUSDE:::Debt:::0-100-100-0-borrowShares0_ + borrowShares1_ > a_[k].shares: 1000000000000000000000 <= 1000000000000000380710
                    // assertGt(a_[k].shares * (a_[k].txOneAmount0Percentage + a_[k].txOneAmount1Percentage) / 100, borrowShares0_ + borrowShares1_, string(abi.encodePacked(assertMessage_, "borrowShares0_ + borrowShares1_ > a_[k].shares")));

                    (uint256 tokenPayback0_, uint256 tokenPayback1_) = _testPaybackPerfectDebtLiquidity(
                        pools[i], alice, (borrowShares0_ + borrowShares1_), poolTypes_[j]
                    );

                    // assertLt((b_.txOne.token0Amount + b_.txTwo.token0Amount), tokenPayback0_, string(abi.encodePacked(assertMessage_, "token0Amount > tokenPayback0_")));
                    // assertLt((b_.txOne.token1Amount + b_.txTwo.token1Amount), tokenPayback1_, string(abi.encodePacked(assertMessage_, "token1Amount > tokenPayback1_")));
                    _comparePrecision(
                        (b_.txOne.token0Amount + b_.txTwo.token0Amount),
                        tokenPayback0_,
                        pools[i].token0Wei,
                        50,
                        string(abi.encodePacked(assertMessage_, "token0Amount != tokenPayback0_"))
                    );
                    _comparePrecision(
                        (b_.txOne.token1Amount + b_.txTwo.token1Amount),
                        tokenPayback1_,
                        pools[i].token1Wei,
                        50,
                        string(abi.encodePacked(assertMessage_, "token1Amount != tokenPayback1_"))
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_WithdrawPerfectInOneTokenWithDepositPerfect() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](2);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_WithdrawPerfectInOneToken::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);

                    _testDepositPerfectColLiquidity(pools[i], alice, 1e4 * 1e18, poolTypes_[j]);

                    _testWithdrawPerfectInOne(pools[i], alice, 1e4 * 1e18, k == 0, poolTypes_[j], new bytes(0));

                    // TODO: adjust the asserts cases

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_WithdrawPerfectInOneTokenWithDepositOne() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](2);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        DexType[1] memory poolTypes_ = [DexType.SmartCol];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_WithdrawPerfectInOneTokenWithDepositOne::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testDepositPerfectColLiquidity(pools[i], bob, 1e5 * 1e18, poolTypes_[j]);
                    _testDepositPerfectColLiquidity(pools[i], alice, 10 * 1e18, poolTypes_[j]);

                    uint256 share_ =
                        _testDepositColLiquidity(pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j]);

                    (uint256 withdrawToken0_, uint256 withdrawToken1_) = _testWithdrawPerfectInOne(
                        pools[i], alice, share_, a_[k].token0Amount != 0, poolTypes_[j], new bytes(0)
                    );

                    if (a_[k].token0Amount != 0) {
                        assertGt(
                            a_[k].token0Amount * pools[i].token0Wei,
                            withdrawToken0_,
                            string(abi.encodePacked(assertMessage_, "token0Amount > withdrawToken0_"))
                        );
                    }
                    if (a_[k].token1Amount != 0) {
                        assertGt(
                            a_[k].token1Amount * pools[i].token1Wei,
                            withdrawToken1_,
                            string(abi.encodePacked(assertMessage_, "token1Amount > withdrawToken1_"))
                        );
                    }

                    if (a_[k].token0Amount != 0) {
                        _comparePrecision(
                            a_[k].token0Amount * pools[i].token0Wei,
                            withdrawToken0_,
                            pools[i].token0Wei,
                            0,
                            string(abi.encodePacked(assertMessage_, "token0Amount != withdrawToken0_"))
                        );
                    }
                    if (a_[k].token1Amount != 0) {
                        _comparePrecision(
                            a_[k].token1Amount * pools[i].token1Wei,
                            withdrawToken1_,
                            pools[i].token1Wei,
                            0,
                            string(abi.encodePacked(assertMessage_, "token1Amount != withdrawToken1_"))
                        );
                    }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_PaybackPerfectInOneTokenBorrowPerfect() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](2);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        DexType[2] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_PaybackPerfectInOneToken::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testBorrowPerfectDebtLiquidity(pools[i], bob, 1e4 * 1e18, poolTypes_[j], new bytes(0));

                    (uint256 token0AmountBorrow_, uint256 token1AmountBorrow_) =
                        _testBorrowPerfectDebtLiquidity(pools[i], alice, 1e3 * 1e18, poolTypes_[j], new bytes(0));

                    (uint256 token0AmountPayback_, uint256 token1AmountPayback_) =
                        _testPaybackPerfectInOneToken(pools[i], alice, 1e3 * 1e18, k == 0, poolTypes_[j]);

                    // TODO: adjust assert cases

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_PaybackPerfectInOneTokenBorrowOne() public {
        TokenAmountParams[] memory a_ = new TokenAmountParams[](2);
        a_[0] = TokenAmountParams({token0Amount: 1e4, token1Amount: 0});

        a_[1] = TokenAmountParams({token0Amount: 0, token1Amount: 1e4});

        DexType[1] memory poolTypes_ = [DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        uint256 snapshotId_ = vm.snapshot();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < a_.length; k++) {
                    string memory assertMessage_ = string(
                        abi.encodePacked(
                            "testDexT1_PaybackPerfectInOneTokenBorrowOne::",
                            _getDexPoolName(pools[i], poolTypes_[j]),
                            ":",
                            LibString.toString(a_[k].token0Amount),
                            "-",
                            LibString.toString(a_[k].token1Amount)
                        )
                    );

                    // Deposit intial liquidity from bob
                    _testBorrowPerfectDebtLiquidity(pools[i], bob, 1e4 * 1e18, poolTypes_[j], new bytes(0));

                    (uint256 shares_) = _testBorrowDebtLiquidity(
                        pools[i], alice, a_[k].token0Amount, a_[k].token1Amount, poolTypes_[j], new bytes(0)
                    );

                    (uint256 token0AmountPayback_, uint256 token1AmountPayback_) =
                        _testPaybackPerfectInOneToken(pools[i], alice, shares_, a_[k].token0Amount != 0, poolTypes_[j]);

                    // TODO: @samyak precision is higher but need to more
                    // if (a_[k].token0Amount != 0) {
                    //     assertLt(a_[k].token0Amount * pools[i].token0Wei, token0AmountPayback_, string(abi.encodePacked(assertMessage_, "token0Amount > token0AmountPayback_")));
                    //     _comparePrecision(a_[k].token0Amount * pools[i].token0Wei, token0AmountPayback_, pools[i].token0Wei, 0, string(abi.encodePacked(assertMessage_, "token0Amount != token0AmountPayback_")));
                    // }

                    // if (a_[k].token1Amount != 0) {
                    //     assertLt(a_[k].token1Amount * pools[i].token1Wei, token1AmountPayback_, string(abi.encodePacked(assertMessage_, "token1Amount > token1AmountPayback_")));
                    //     _comparePrecision(a_[k].token1Amount * pools[i].token1Wei, token1AmountPayback_, pools[i].token1Wei, 0, string(abi.encodePacked(assertMessage_, "token1Amount != token1AmountPayback_")));
                    // }

                    vm.revertTo(snapshotId_);
                }
            }
        }
    }

    function testDexT1_SwapForthEnablePoolSwapBack() public {
        vm.skip(true);
        uint256 sharesAmount_ = 1000;
        DexType[2] memory poolTypes_ = [DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];
        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    bool swap0to1_ = k == 0;
                    uint256 amountIn_ = sharesAmount_ * (swap0to1_ ? pools[i].token0Wei : pools[i].token1Wei);
                    _testSwapExactInForthEnablePoolSwapBack(pools[i], alice, amountIn_, swap0to1_, poolTypes_[j]);
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }
}

contract PoolT1Oracle is PoolT1BaseTest {
    // Oracles //

    struct OracleDataS {
        uint256 time;
        uint256 price;
    }

    function testDexT1_OraclePriceCaseOne() public {
        DexType[1] memory poolTypes_ = [DexType.SmartColAndDebt];
        DexParams[1] memory pools = [DAI_USDC];

        vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                string memory assertMessage_ =
                    string(abi.encodePacked("_testOraclePrice::", _getDexPoolName(pools[i], poolTypes_[j]), ":", " "));

                uint256 totalTime_ = block.timestamp;
                _testUpdateOracle(pools[i], alice, 100 * pools[i].token0Wei, true, 10, 25, 10, poolTypes_[j]);

                totalTime_ = block.timestamp - totalTime_;

                for (uint256 k = 0; k < totalTime_ % 13; k++) {
                    uint256[] memory secondsAgo_ = new uint256[](k + 1);
                    for (uint256 l = 0; l < k + 1; l++) {
                        secondsAgo_[l] = 13 * (l + 1);
                    }

                    _validateTwap(_getDexType(pools[i], poolTypes_[j], false), secondsAgo_, assertMessage_);
                }

                skip(50);

                for (uint256 k = 0; k < (totalTime_ % 13) - 3; k++) {
                    uint256[] memory secondsAgo_ = new uint256[](k + 1);
                    for (uint256 l = 0; l < k + 1; l++) {
                        secondsAgo_[l] = 13 * (l + 1);
                    }

                    _validateTwap(_getDexType(pools[i], poolTypes_[j], false), secondsAgo_, assertMessage_);
                }
            }
        }
    }

    function testDexT1_UpdateOracleCaseOne() public {
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracle(pools[i], alice, 100 * pools[i].token0Wei, true, 10, 25, 10, poolTypes_[j]);
            }
        }
    }

    function testDexT1_UpdateOracleCaseTwo() public {
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];

        vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracle(pools[i], alice, 100 * pools[i].token0Wei, true, 601, 25, 601, poolTypes_[j]);
            }
        }
    }

    function testDexT1_UpdateOracleCaseThree() public {
        DexParams[10] memory pools = [
            DAI_USDC,
            USDT_USDC,
            DAI_SUSDE,
            USDT_SUSDE,
            DAI_USDC_WITH_LESS_THAN_ONE,
            DAI_USDC_WITH_MORE_THAN_ONE,
            USDC_ETH,
            DAI_USDC_WITH_80_20,
            DAI_USDC_WITH_50_5,
            DAI_USDC_WITH_10_1
        ];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];

        vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracle(pools[i], alice, 100 * pools[i].token0Wei, true, 601, 25, 10, poolTypes_[j]);
            }
        }
    }

    function testDexT1_UpdateOracleCaseFour() public {
        DexParams[1] memory pools = [DAI_USDC_WITH_LESS_ORACLE];
        DexType[1] memory poolTypes_ = [DexType.SmartColAndDebt];
        uint256 snapshotId_ = vm.snapshot();

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracleOverLimit(pools[i], alice, 100 * pools[i].token0Wei, true, 10, 150, 10, poolTypes_[j]);
                vm.revertTo(snapshotId_);
            }
        }

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracleOverLimit(
                    pools[i], alice, 100 * pools[i].token0Wei, true, 601, 150, 601, poolTypes_[j]
                );

                vm.revertTo(snapshotId_);
            }
        }

        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracleOverLimit(pools[i], alice, 100 * pools[i].token0Wei, true, 601, 150, 10, poolTypes_[j]);
            }
            vm.revertTo(snapshotId_);
        }
    }

    function testDexT1_UpdateOracleWithTimes() public {
        uint256[250] memory times_ = [
            uint256(1914706),
            uint256(2126517),
            uint256(1080588),
            uint256(3339778),
            uint256(3524166),
            uint256(746203),
            uint256(1094671),
            uint256(4182004),
            uint256(1594565),
            uint256(1937978),
            uint256(2696768),
            uint256(1543254),
            uint256(653003),
            uint256(3417180),
            uint256(2756766),
            uint256(3414311),
            uint256(4039049),
            uint256(1684430),
            uint256(4145736),
            uint256(1326451),
            uint256(2034953),
            uint256(51172),
            uint256(1268060),
            uint256(1743949),
            uint256(3459068),
            uint256(3124833),
            uint256(566309),
            uint256(3882476),
            uint256(3155612),
            uint256(2613733),
            uint256(1139690),
            uint256(2043388),
            uint256(229531),
            uint256(1068482),
            uint256(932262),
            uint256(2018110),
            uint256(2102803),
            uint256(3536180),
            uint256(2555217),
            uint256(2929084),
            uint256(3241633),
            uint256(3730809),
            uint256(822908),
            uint256(881910),
            uint256(3829849),
            uint256(4183406),
            uint256(788376),
            uint256(556816),
            uint256(3967281),
            uint256(3995677),
            uint256(461),
            uint256(416),
            uint256(319),
            uint256(44),
            uint256(73),
            uint256(264),
            uint256(462),
            uint256(221),
            uint256(322),
            uint256(89),
            uint256(498),
            uint256(183),
            uint256(481),
            uint256(368),
            uint256(400),
            uint256(476),
            uint256(114),
            uint256(126),
            uint256(76),
            uint256(347),
            uint256(131),
            uint256(103),
            uint256(256),
            uint256(296),
            uint256(484),
            uint256(368),
            uint256(52),
            uint256(137),
            uint256(94),
            uint256(153),
            uint256(463),
            uint256(401),
            uint256(176),
            uint256(138),
            uint256(261),
            uint256(219),
            uint256(45),
            uint256(496),
            uint256(194),
            uint256(121),
            uint256(9),
            uint256(487),
            uint256(182),
            uint256(4),
            uint256(82),
            uint256(92),
            uint256(185),
            uint256(309),
            uint256(475),
            uint256(498),
            uint256(336),
            uint256(495),
            uint256(3),
            uint256(137),
            uint256(441),
            uint256(143),
            uint256(395),
            uint256(426),
            uint256(182),
            uint256(122),
            uint256(501),
            uint256(450),
            uint256(227),
            uint256(83),
            uint256(70),
            uint256(25),
            uint256(143),
            uint256(223),
            uint256(251),
            uint256(85),
            uint256(199),
            uint256(92),
            uint256(262),
            uint256(402),
            uint256(439),
            uint256(505),
            uint256(89),
            uint256(257),
            uint256(440),
            uint256(510),
            uint256(161),
            uint256(167),
            uint256(402),
            uint256(46),
            uint256(411),
            uint256(305),
            uint256(399),
            uint256(411),
            uint256(141),
            uint256(273),
            uint256(174),
            uint256(190),
            uint256(470),
            uint256(2),
            uint256(264),
            uint256(176),
            uint256(298),
            uint256(473),
            uint256(101),
            uint256(115),
            uint256(382),
            uint256(431),
            uint256(65),
            uint256(243),
            uint256(9),
            uint256(221),
            uint256(428),
            uint256(350),
            uint256(180),
            uint256(228),
            uint256(194),
            uint256(156),
            uint256(97),
            uint256(493),
            uint256(9),
            uint256(111),
            uint256(315),
            uint256(287),
            uint256(249),
            uint256(188),
            uint256(136),
            uint256(296),
            uint256(91),
            uint256(269),
            uint256(91),
            uint256(2444281),
            uint256(1094285),
            uint256(2476384),
            uint256(2793588),
            uint256(3148257),
            uint256(1650301),
            uint256(2504633),
            uint256(145636),
            uint256(633371),
            uint256(2635847),
            uint256(1210751),
            uint256(1618747),
            uint256(915431),
            uint256(3171099),
            uint256(2934331),
            uint256(1540218),
            uint256(1832743),
            uint256(3125126),
            uint256(3627778),
            uint256(1611852),
            uint256(3906648),
            uint256(3425441),
            uint256(1313561),
            uint256(3261146),
            uint256(3113910),
            uint256(2445699),
            uint256(2000373),
            uint256(1197462),
            uint256(1421472),
            uint256(3456046),
            uint256(511),
            uint256(305),
            uint256(285),
            uint256(924971),
            uint256(216301),
            uint256(1466699),
            uint256(2624208),
            uint256(4055841),
            uint256(2650004),
            uint256(2856893),
            uint256(2031359),
            uint256(3658675),
            uint256(4076071),
            uint256(3962944),
            uint256(3669561),
            uint256(564985),
            uint256(577738),
            uint256(2473934),
            uint256(2126325),
            uint256(2696079),
            uint256(1936867),
            uint256(2537110),
            uint256(2632054),
            uint256(2448137),
            uint256(3544353),
            uint256(2124564),
            uint256(3741951),
            uint256(834251),
            uint256(4112510),
            uint256(3200780),
            uint256(1908994),
            uint256(2424569),
            uint256(268613),
            uint256(2481216),
            uint256(2130646),
            uint256(1243972),
            uint256(1683109),
            uint256(1138484),
            uint256(250377),
            uint256(3172629),
            uint256(3267467),
            uint256(3225130),
            uint256(1255809),
            uint256(2406667),
            uint256(946462)
        ];
        DexParams[1] memory pools = [DAI_USDC];
        DexType[3] memory poolTypes_ = [DexType.SmartColAndDebt, DexType.SmartCol, DexType.SmartDebt];

        vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                _testUpdateOracleWithTimes(pools[i], alice, 50 * pools[i].token0Wei, true, times_, poolTypes_[j]);
            }
        }
    }
}

contract PoolT1RangeTest is PoolT1BaseTest {
    function testDexT1_ThresholdShift() public {
        DexParams[4] memory pools =
            [DAI_USDC_WITH_LESS_THRESHOLD, DAI_USDC_WITH_80_20, DAI_USDC_WITH_50_5, DAI_USDC_WITH_10_1];
        DexType[1] memory poolTypes_ = [DexType.SmartColAndDebt /*, DexType.SmartCol, DexType.SmartDebt*/ ];
        uint256[] memory timeShifts_ = new uint256[](5);
        timeShifts_[0] = 10 * 1e4;
        timeShifts_[1] = 25 * 1e4;
        timeShifts_[2] = 50 * 1e4;
        timeShifts_[3] = 75 * 1e4;
        timeShifts_[4] = 100 * 1e4;

        uint256 snapshotId_ = vm.snapshot();

        // vm.pauseGasMetering();
        for (uint256 i = 0; i < pools.length; i++) {
            for (uint256 j = 0; j < poolTypes_.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    _testThresholdShift(
                        pools[i],
                        alice,
                        50 * (k == 0 ? pools[i].token0Wei : pools[i].token1Wei),
                        k == 0,
                        timeShifts_,
                        poolTypes_[j]
                    );
                    vm.revertTo(snapshotId_);
                }
            }
        }
    }
}
