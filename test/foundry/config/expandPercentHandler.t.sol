//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { FluidExpandPercentConfigHandler, Events, Structs } from "../../../contracts/config/expandPercentHandler/main.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { FluidReserveContract } from "../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../contracts/reserve/proxy.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";

import "forge-std/console2.sol";

abstract contract FluidExpandPercentConfigHandlerTests is LiquidityUserModuleBaseTest, Events {
    uint256 constant EXPAND_PERCENT_UNTIL_CHECKPOINT1 = 25 * 1e2;
    uint256 constant EXPAND_PERCENT_UNTIL_CHECKPOINT2 = 20 * 1e2;
    uint256 constant EXPAND_PERCENT_UNTIL_CHECKPOINT3 = 15 * 1e2;
    uint256 constant EXPAND_PERCENT_ABOVE_CHECKPOINT3 = 10 * 1e2;

    uint256 constant TVL_CHECKPOINT1 = 20 ether;
    uint256 constant TVL_CHECKPOINT2 = 30 ether;
    uint256 constant TVL_CHECKPOINT3 = 40 ether;

    uint256 constant EXPAND_DURATION = 2 days;
    uint256 constant BASE_LIMIT = 7.5 ether;
    uint256 constant MAX_LIMIT = 200 ether;
    uint256 immutable BASE_LIMIT_AFTER_BIGMATH;
    uint256 immutable MAX_LIMIT_AFTER_BIGMATH;

    FluidReserveContract reserveContractImpl;
    FluidReserveContract reserveContract; //proxy
    FluidExpandPercentConfigHandler configHandler;

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

    function setUp() public virtual override {
        super.setUp();

        // set up limits at liquidity
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT1,
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
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: BASE_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // deploy reserve contract
        reserveContractImpl = new FluidReserveContract();
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        address[] memory authsRebalancers = new address[](1);
        authsRebalancers[0] = alice;
        reserveContract.initialize(authsRebalancers, authsRebalancers, admin);

        // prepare limit checkPointsConfig
        Structs.LimitCheckPoints memory checkPoints = Structs.LimitCheckPoints({
            tvlCheckPoint1: TVL_CHECKPOINT1,
            expandPercentUntilCheckPoint1: EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            tvlCheckPoint2: TVL_CHECKPOINT2,
            expandPercentUntilCheckPoint2: EXPAND_PERCENT_UNTIL_CHECKPOINT2,
            tvlCheckPoint3: TVL_CHECKPOINT3,
            expandPercentUntilCheckPoint3: EXPAND_PERCENT_UNTIL_CHECKPOINT3,
            expandPercentAboveCheckPoint3: EXPAND_PERCENT_ABOVE_CHECKPOINT3
        });

        // deploy configHandler
        configHandler = new FluidExpandPercentConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            address(mockProtocol),
            address(USDC),
            address(USDC),
            checkPoints,
            checkPoints
        );

        // make configHandler an auth at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(configHandler), true);
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);
    }

    function _getInterestMode() internal pure virtual returns (uint8);

    function test_rebalance_RevertWhenUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.ExpandPercentConfigHandler__Unauthorized)
        );
        vm.prank(bob);
        configHandler.rebalance();
    }

    function test_rebalance() public {
        // check expandPercent withdrawal limit when until base limit
        // check expandPercent borrow limit when until base limit
        _assertExpandPercentAndLimits(EXPAND_PERCENT_UNTIL_CHECKPOINT1, EXPAND_PERCENT_UNTIL_CHECKPOINT1);

        _supply(mockProtocol, address(USDC), alice, 3 ether);
        _borrow(mockProtocol, address(USDC), alice, 3 ether);

        // trigger rebalance, should revert no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.ExpandPercentConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();

        // check expandPercent withdrawal limit when until checkpoint1
        // check expandPercent borrow limit when until checkpoint1
        _assertExpandPercentAndLimits(EXPAND_PERCENT_UNTIL_CHECKPOINT1, EXPAND_PERCENT_UNTIL_CHECKPOINT1);

        _supply(mockProtocol, address(USDC), alice, TVL_CHECKPOINT1);

        vm.expectEmit(true, true, true, true);
        emit LogUpdateWithdrawLimitExpansion(
            TVL_CHECKPOINT1 + 3 ether,
            EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            EXPAND_PERCENT_UNTIL_CHECKPOINT2
        );

        vm.prank(alice);
        configHandler.rebalance();

        // check expandPercent withdrawal limit when until checkpoint2
        _assertExpandPercentAndLimits(EXPAND_PERCENT_UNTIL_CHECKPOINT2, EXPAND_PERCENT_UNTIL_CHECKPOINT1);

        _supply(mockProtocol, address(USDC), alice, TVL_CHECKPOINT2 - TVL_CHECKPOINT1);
        _borrowSkippingLimits(TVL_CHECKPOINT1);

        vm.expectEmit(true, true, true, true);
        emit LogUpdateWithdrawLimitExpansion(
            TVL_CHECKPOINT2 + 3 ether,
            EXPAND_PERCENT_UNTIL_CHECKPOINT2,
            EXPAND_PERCENT_UNTIL_CHECKPOINT3
        );
        vm.expectEmit(true, true, true, true);
        emit LogUpdateBorrowLimitExpansion(
            23000000000000000512, // = TVL_CHECKPOINT1 + 3 ether after rounding up
            EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            EXPAND_PERCENT_UNTIL_CHECKPOINT2
        );
        vm.prank(alice);
        configHandler.rebalance();

        // check expandPercent withdrawal limit when until checkpoint3
        // check expandPercent borrow limit when until checkpoint2
        _assertExpandPercentAndLimits(EXPAND_PERCENT_UNTIL_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT2);

        _supply(mockProtocol, address(USDC), alice, TVL_CHECKPOINT3 - TVL_CHECKPOINT2);
        vm.prank(alice);
        configHandler.rebalance();
        // check expandPercent withdrawal limit when above checkpoint3
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT2);

        _supply(mockProtocol, address(USDC), alice, TVL_CHECKPOINT3); // total supply will be 83
        // trigger rebalance, should revert no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.ExpandPercentConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT2);

        _borrowSkippingLimits(TVL_CHECKPOINT2 - TVL_CHECKPOINT1);
        vm.prank(alice);
        configHandler.rebalance();
        // check expandPercent borrow limit when until checkpoint3
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT3);

        _borrowSkippingLimits(TVL_CHECKPOINT3 - TVL_CHECKPOINT2);
        vm.prank(alice);
        configHandler.rebalance();
        // check expandPercent borrow limit when above checkpoint3
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_ABOVE_CHECKPOINT3);

        _borrowSkippingLimits(5 ether); // total borrow will be 48
        // trigger rebalance, should revert no update needed
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.ExpandPercentConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_ABOVE_CHECKPOINT3);

        _payback(mockProtocol, address(USDC), alice, 25 ether); // total borrow will be 23
        vm.prank(alice);
        configHandler.rebalance();
        _assertExpandPercentAndLimits(EXPAND_PERCENT_ABOVE_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT2);

        _withdrawSkippingLimits(50 ether); // total supply will be 33
        vm.prank(alice);
        configHandler.rebalance();
        _assertExpandPercentAndLimits(EXPAND_PERCENT_UNTIL_CHECKPOINT3, EXPAND_PERCENT_UNTIL_CHECKPOINT2);
    }

    function _withdrawSkippingLimits(uint256 amount) internal {
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        // temporarily set base limit very high
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: MAX_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        _supply(mockProtocol, address(USDC), alice, 1 ether);
        _withdraw(mockProtocol, address(USDC), alice, 1 ether);
        _withdraw(mockProtocol, address(USDC), alice, amount);

        // reset base limit and expand percent
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: userSupplyData.expandPercent,
            expandDuration: EXPAND_DURATION,
            baseWithdrawalLimit: BASE_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);
    }

    function _borrowSkippingLimits(uint256 amount) internal {
        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );

        // temporarily set base limit very high
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: EXPAND_PERCENT_UNTIL_CHECKPOINT1,
            expandDuration: EXPAND_DURATION,
            baseDebtCeiling: MAX_LIMIT - 10 ether,
            maxDebtCeiling: MAX_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        _borrow(mockProtocol, address(USDC), alice, amount);

        // reset base limit and expand percent
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: _getInterestMode(),
            expandPercent: userBorrowData.expandPercent,
            expandDuration: EXPAND_DURATION,
            baseDebtCeiling: BASE_LIMIT,
            maxDebtCeiling: MAX_LIMIT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function _assertExpandPercentAndLimits(
        uint256 withdrawLimitExpandPecent,
        uint256 borrowLimitExpandPercent
    ) internal {
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.expandPercent, withdrawLimitExpandPecent);
        assertEq(userSupplyData.expandDuration, EXPAND_DURATION);
        assertEq(userSupplyData.baseWithdrawalLimit, BASE_LIMIT_AFTER_BIGMATH);

        (ResolverStructs.UserBorrowData memory userBorrowData, ) = resolver.getUserBorrowData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userBorrowData.expandPercent, borrowLimitExpandPercent);
        assertEq(userBorrowData.expandDuration, EXPAND_DURATION);
        assertEq(userBorrowData.baseBorrowLimit, BASE_LIMIT_AFTER_BIGMATH);
        assertEq(userBorrowData.maxBorrowLimit, MAX_LIMIT_AFTER_BIGMATH);
    }
}

contract FluidExpandPercentConfigHandlerTestsWithInterest is FluidExpandPercentConfigHandlerTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 1;
    }
}

contract FluidExpandPercentConfigHandlerTestsInterestFree is FluidExpandPercentConfigHandlerTests {
    function _getInterestMode() internal pure virtual override returns (uint8) {
        return 0;
    }
}
