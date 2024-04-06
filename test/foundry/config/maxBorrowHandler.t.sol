//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidMaxBorrowConfigHandler, Events } from "../../../contracts/config/maxBorrowHandler/main.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { FluidReserveContract } from "../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../contracts/reserve/proxy.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";

abstract contract FluidMaxBorrowConfigHandlerBaseTest is LiquidityUserModuleBaseTest, Events {
    uint256 constant EXPAND_PERCENT_UNTIL_CHECKPOINT = 25 * 1e2;

    uint256 constant TVL_CHECKPOINT = 20 ether;

    uint256 constant EXPAND_DURATION = 2 days;
    uint256 constant BASE_LIMIT = 7.5 ether;
    uint256 constant MAX_LIMIT = 200 ether;
    uint256 immutable BASE_LIMIT_AFTER_BIGMATH;
    uint256 immutable MAX_LIMIT_AFTER_BIGMATH;

    FluidReserveContract reserveContractImpl;
    FluidReserveContract reserveContract; //proxy
    FluidMaxBorrowConfigHandler configHandler;
    FluidLiquidityResolver liquidityResolver;

    constructor() {
        BASE_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                BASE_LIMIT,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
        MAX_LIMIT_AFTER_BIGMATH = BigMathMinified.fromBigNumber(
            BigMathMinified.toBigNumber(
                MAX_LIMIT,
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            ),
            DEFAULT_EXPONENT_SIZE,
            DEFAULT_EXPONENT_MASK
        );
    }

    function _getInterestMode() internal pure virtual returns (uint8);

    function setUp() public virtual override {
        super.setUp();

        // set up limits at liquidity
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT,
            expandDuration: EXPAND_DURATION,
            baseDebtCeiling: BASE_LIMIT,
            maxDebtCeiling: MAX_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: BASE_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // deploy reserve contract
        reserveContractImpl = new FluidReserveContract(IFluidLiquidity(address(liquidity)));
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        address[] memory authsRebalancers = new address[](1);
        authsRebalancers[0] = alice;
        reserveContract.initialize(authsRebalancers, authsRebalancers, admin);
        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));

        configHandler = new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(mockProtocol),
            address(USDC),
            7000, // max utilization 70%
            100 // min update diff 1%
        );

        // make configHandler an auth at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(configHandler), true);
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);
    }
}

abstract contract FluidMaxBorrowConfigHandlerTests is FluidMaxBorrowConfigHandlerBaseTest {
    function test_rebalance_RevertWhenUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__Unauthorized)
        );
        vm.prank(bob);
        configHandler.rebalance();
    }

    function test_rebalance() public {
        // check max borrow limit
        _assertMaxBorrowLimit(MAX_LIMIT_AFTER_BIGMATH);

        _supply(mockProtocol, address(USDC), alice, 3 ether);
        _borrow(mockProtocol, address(USDC), alice, 3 ether);

        assertEq(configHandler.calcMaxDebtCeiling(), BASE_LIMIT_AFTER_BIGMATH);
        assertEq(configHandler.currentMaxDebtCeiling(), 199743650673136238592);
        assertEq(configHandler.configPercentDiff(), 9624); // diff of 7493989779944505344 to 199743650673136238592 -> 96.24%

        // trigger rebalance
        vm.expectEmit(true, true, true, true);
        emit LogUpdateBorrowMaxDebtCeiling(3 ether, MAX_LIMIT_AFTER_BIGMATH, BASE_LIMIT_AFTER_BIGMATH);
        vm.prank(alice);
        configHandler.rebalance();

        // check max borrow limit
        _assertMaxBorrowLimit(BASE_LIMIT_AFTER_BIGMATH);

        assertEq(configHandler.calcMaxDebtCeiling(), BASE_LIMIT_AFTER_BIGMATH);
        assertEq(configHandler.configPercentDiff(), 0);
        assertEq(configHandler.currentMaxDebtCeiling(), BASE_LIMIT_AFTER_BIGMATH);

        // trigger rebalance, should revert no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();

        // small supply, change target max debt ceiling but not enough to cause a 1% diff -> should still revert.
        // so need to supply so much that 70% of it is slightly bigger than BASE_LIMIT_AFTER_BIGMATH.
        // 7.5 ether / 0.7 = 10.72 ether. 3 already supplied so 7.72 ether.
        _supply(mockProtocol, address(USDC), alice, 7.8 ether);

        assertEq(configHandler.currentMaxDebtCeiling(), BASE_LIMIT_AFTER_BIGMATH);
        assertEq(configHandler.calcMaxDebtCeiling(), 7560000000000000000);
        assertEq(configHandler.configPercentDiff(), 88); // new one would be 0.88% more. too little diff

        // trigger rebalance, should revert no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();

        // case when base debt ceiling is smaller than calculated max debt ceiling
        _supply(mockProtocol, address(USDC), alice, TVL_CHECKPOINT - 7.8 ether);

        assertEq(configHandler.calcMaxDebtCeiling(), 16.1 ether); // 70% of 20 + 3 ether -> 16.1 ether
        assertEq(configHandler.currentMaxDebtCeiling(), BASE_LIMIT_AFTER_BIGMATH);
        assertEq(configHandler.configPercentDiff(), 11483); // diff of 7493989779944505344 to 16100000000000000000 -> 114.83%

        vm.expectEmit(true, true, true, true);
        emit LogUpdateBorrowMaxDebtCeiling(
            TVL_CHECKPOINT + 3 ether,
            BASE_LIMIT_AFTER_BIGMATH,
            ((TVL_CHECKPOINT + 3 ether) * 70) / 100 // * 70% because of max utilization
        );

        vm.prank(alice);
        configHandler.rebalance();

        assertEq(configHandler.calcMaxDebtCeiling(), 16.1 ether); // 70% of 20 + 3 ether -> 16.1 ether
        assertEq(configHandler.currentMaxDebtCeiling(), 16086857868967411712); // rounded down by BigMath
        assertEq(configHandler.configPercentDiff(), 8); // rounding diff
    }

    function _assertMaxBorrowLimit(uint256 maxBorrowLimit) internal {
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userBorrowData.maxBorrowLimit, maxBorrowLimit);
    }
}

contract MaxBorrowConfigHandlerTestsWithInterest is FluidMaxBorrowConfigHandlerTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 1;
    }
}

contract MaxBorrowConfigHandlerTestsInterestFree is FluidMaxBorrowConfigHandlerTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 0;
    }
}

contract MaxBorrowConfigHandlerTestsConstructor is FluidMaxBorrowConfigHandlerBaseTest {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 1;
    }

    function test_constructor_RevertIfReserveContractZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__AddressZero)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(0)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(mockProtocol),
            address(USDC),
            7000, // max utilization 70%
            100 // min update diff 1%
        );
    }
    function test_constructor_RevertIfLiquidityZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__AddressZero)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(0)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(mockProtocol),
            address(USDC),
            7000, // max utilization 70%
            100 // min update diff 1%
        );
    }
    function test_constructor_RevertIfLiquidityResolverZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__AddressZero)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(0)),
            address(mockProtocol),
            address(USDC),
            7000, // max utilization 70%
            100 // min update diff 1%
        );
    }
    function test_constructor_RevertIfProtocolZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__AddressZero)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(0),
            address(USDC),
            7000, // max utilization 70%
            100 // min update diff 1%
        );
    }
    function test_constructor_RevertIfMaxUtilizationMoreThan100Percent() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__InvalidParams)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(mockProtocol),
            address(USDC),
            10001,
            100 // min update diff 1%
        );
    }
    function test_constructor_RevertIfMinUpdateDiffZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.MaxBorrowConfigHandler__InvalidParams)
        );
        new FluidMaxBorrowConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidLiquidityResolver(address(liquidityResolver)),
            address(mockProtocol),
            address(USDC),
            7000, // max utilization 70%
            0 // min update diff 0
        );
    }
}
