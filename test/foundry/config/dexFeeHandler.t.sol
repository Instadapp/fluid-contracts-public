// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "contracts/config/dexFeeHandler/main.sol";
import "contracts/protocols/dex/interfaces/iDexT1.sol";
import "contracts/reserve/interfaces/iReserveContract.sol";
import "contracts/libraries/dexSlotsLink.sol";
import "contracts/libraries/dexCalcs.sol";
import "contracts/libraries/bigMathMinified.sol";

import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

interface IFluidDexFactory {
    function setDexAuth(address dex_, address dexAuth_, bool allowed_) external;
}

// To test run:
// forge test -vvv --match-path test/foundry/config/dexFeeHandler.t.sol
contract FluidDexFeeHandlerTest is Test {
    FluidDexFeeHandler public fluidDexFeeHandler;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC");

    address constant DEPLOYER_CONTRACT = 0x4EC7b668BAF70d4A4b0FC7941a7708A07b6d45Be;
    address internal constant TIMELOCK = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;
    address internal constant REBALANCER_MAINNET = 0xb287f8A01a9538656c72Fa6aE1EE0117A187Be0C;
    address constant RESERVE_CONTRACT_MAINNET_ADDRESS = 0x264786EF916af64a1DB19F513F24a3681734ce92;
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);

    IFluidDexFactory internal constant DEX_FACTORY_MAINNET =
        IFluidDexFactory(0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085);

    address public constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7; // id 1
    address public constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B; // id 2

    uint256 immutable MIN_FEE;
    uint256 immutable MAX_FEE;
    uint256 immutable MIN_DEVIATION;
    uint256 immutable MAX_DEVIATION;
    address public immutable TEAM_MULTISIG_MAINNET;

    constructor() {
        TEAM_MULTISIG_MAINNET = makeAddr("TEAM_MULTISIG_MAINNET");
    }
}

// To test run:
// forge test -vvv --match-path test/foundry/config/dexFeeHandler.t.sol --match-contract FluidDexFeeHandlerTest_usdc_usdt
contract FluidDexFeeHandlerTest_usdc_usdt is FluidDexFeeHandlerTest {
    constructor() {
        MIN_FEE = 30;
        MAX_FEE = 100;
        MIN_DEVIATION = 2e23;
        MAX_DEVIATION = 1e24;
    }

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21680552);
        _deployNewHandler();
    }

    function _deployNewHandler() internal {
        fluidDexFeeHandler = new FluidDexFeeHandler(
            MIN_FEE,
            MAX_FEE,
            MIN_DEVIATION,
            MAX_DEVIATION,
            DEX_USDC_USDT,
            DEPLOYER_CONTRACT,
            IFluidReserveContract(RESERVE_CONTRACT_MAINNET_ADDRESS),
            false
        );

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(fluidDexFeeHandler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
        vm.stopPrank();

        vm.startPrank(TIMELOCK);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_USDC_USDT, address(fluidDexFeeHandler), true);
        vm.stopPrank();
    }

    function test_RebalanceFeeAndRevenueCut() public {
        vm.startPrank(REBALANCER_MAINNET);
        vm.deal(REBALANCER_MAINNET, 1 ether);

        uint256 currentRevenueCut_ = fluidDexFeeHandler.getDexRevenueCut();
        console.log("currentRevenueCut_", currentRevenueCut_);

        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        fluidDexFeeHandler.rebalance();

        uint256 newRevenueCut_ = fluidDexFeeHandler.getDexRevenueCut();

        assertEq(newRevenueCut_, currentRevenueCut_);

        vm.stopPrank();

        uint256 newFee = fluidDexFeeHandler.currentConfig();
        emit log_named_uint("New fee from Dex", newFee);

        assertEq(newFee, 33);
    }

    function test_DynamicFee() public {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        // Absolute deviation from 1.0
        uint256 deviation = lastStoredPriceOfPool_ > 1e27
            ? lastStoredPriceOfPool_ - 1e27
            : 1e27 - lastStoredPriceOfPool_;

        deviation = deviation * 2;

        uint256 newFee_ = fluidDexFeeHandler.dynamicFeeFromDeviation(deviation);
        emit log_named_uint("New fee from Dex", newFee_);

        assertEq(newFee_, 66); // not change in this block
    }

    function test_DynamicFeeMultiPrices() public {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        for (uint256 i = 1; i < 1000; i++) {
            // Absolute deviation from 1.0
            uint256 deviation = lastStoredPriceOfPool_ > 1e27
                ? lastStoredPriceOfPool_ - 1e27
                : 1e27 - lastStoredPriceOfPool_;

            deviation = (deviation * i) / 100;
            uint256 newFee_ = fluidDexFeeHandler.dynamicFeeFromDeviation(deviation);
            console.log("Deviation:", deviation, "New fee from Dex:", newFee_);
        }
    }
}

// To test run:
// forge test -vvv --match-path test/foundry/config/dexFeeHandler.t.sol --match-contract FluidDexFeeHandlerTest_wsteth_eth
contract FluidDexFeeHandlerTest_wsteth_eth is FluidDexFeeHandlerTest {
    constructor() {
        MIN_FEE = 10;
        MAX_FEE = 100;
        MIN_DEVIATION = 2e23; // 0.02% depeg
        MAX_DEVIATION = 5e23; // 0.05% depeg
    }

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 21600552);
        _deployNewHandler();
    }

    function _deployNewHandler() internal {
        fluidDexFeeHandler = new FluidDexFeeHandler(
            MIN_FEE,
            MAX_FEE,
            MIN_DEVIATION,
            MAX_DEVIATION,
            DEX_WSTETH_ETH,
            DEPLOYER_CONTRACT,
            IFluidReserveContract(RESERVE_CONTRACT_MAINNET_ADDRESS),
            true
        );

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(fluidDexFeeHandler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
        vm.stopPrank();

        vm.startPrank(TIMELOCK);
        DEX_FACTORY_MAINNET.setDexAuth(DEX_WSTETH_ETH, address(fluidDexFeeHandler), true);
        vm.stopPrank();
    }

    function test_RebalanceFeeAndRevenueCut() public {
        vm.startPrank(REBALANCER_MAINNET);
        vm.deal(REBALANCER_MAINNET, 1 ether);

        uint256 currentRevenueCut_ = fluidDexFeeHandler.getDexRevenueCut();
        console.log("currentRevenueCut_", currentRevenueCut_);

        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        fluidDexFeeHandler.rebalance();

        uint256 newRevenueCut_ = fluidDexFeeHandler.getDexRevenueCut();

        assertEq(newRevenueCut_, currentRevenueCut_);

        vm.stopPrank();

        uint256 newFee = fluidDexFeeHandler.currentConfig();
        emit log_named_uint("New fee from Dex", newFee);

        assertEq(newFee, 20);
    }

    function test_DynamicFee() public {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        uint deviationFromPrice_ = fluidDexFeeHandler.getDeviationFromPrice(lastStoredPriceOfPool_);
        console.log("% Depeg from center price", (deviationFromPrice_ * 1e6) / 1e27);

        uint256 newFee_ = fluidDexFeeHandler.dynamicFeeFromPrice(lastStoredPriceOfPool_);
        emit log_named_uint("New fee from Dex", newFee_);

        assertEq(newFee_, 20);
    }

    function test_DynamicFeeMultiPrices() public {
        (
            uint256 lastToLastStoredPrice_,
            uint256 lastStoredPriceOfPool_,
            uint256 lastInteractionTimeStamp_
        ) = fluidDexFeeHandler.getDexVariables();

        emit log_named_uint("Last to last stored price", lastToLastStoredPrice_);
        emit log_named_uint("Last stored price of pool", lastStoredPriceOfPool_);
        emit log_named_uint("Last interaction time stamp", lastInteractionTimeStamp_);

        uint deviationFromPrice_ = fluidDexFeeHandler.getDeviationFromPrice(lastStoredPriceOfPool_);
        console.log("% Depeg from center price", (deviationFromPrice_ * 1e6) / 1e27);

        uint256 newFee_ = fluidDexFeeHandler.dynamicFeeFromDeviation(deviationFromPrice_);
        console.log("New fee from Dex", newFee_);

        for (uint256 i = 500; i < 10000; i++) {
            uint256 deviation = (deviationFromPrice_ * i) / 1000;
            uint256 newFee_ = fluidDexFeeHandler.dynamicFeeFromDeviation(deviation);
            if (newFee_ != 100 && newFee_ != 20) {
                console.log("depeg from center price:", deviation, "New fee from Dex:", newFee_);
            }
        }
    }
}
