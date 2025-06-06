//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidWithdrawLimitAuth } from "../../../contracts/config/withdrawLimitAuth/main.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { TestERC20Dec6 } from "../testERC20Dec6.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";

contract testContract {
    constructor(
        address mockProtocol,
        address mockProtocolInterestFree,
        address mockProtocolWithInterest,
        TestERC20Dec6 USDC
    ) {
        USDC.approve(mockProtocol, type(uint256).max);
        USDC.approve(mockProtocolInterestFree, type(uint256).max);
        USDC.approve(mockProtocolWithInterest, type(uint256).max);
    }

    function liquidityCallback(address token_, uint256 amount_, bytes calldata data_) external {}
}

contract WithdrawLimitAuthTest is LiquidityBaseTest {
    // IFluidLiquidity internal constant liquidityProxy = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    IFluidLiquidityResolver liquidityResolver;
    IFluidLiquidity liquidityProxy;

    address internal constant rebalancer = 0x3BE5C671b20649DCA5D916b5698328D54BdAAf88;

    address internal multisig = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    // address bob = makeAddr("bob");

    FluidWithdrawLimitAuth handler;

    uint256 percentRateChangeAllowed = 5e4; // 15%
    uint256 hourlyChangeAllowed = 10e4;
    uint256 dailyChangeAllowed = 20e4;
    uint256 cooldown = 1 days;

    function setUp() public virtual override {
        super.setUp();
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19876268);

        liquidityProxy = IFluidLiquidity(address(liquidity));
        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(liquidityProxy)));

        _deployNewHandler();

        // testUser = address(new testContract(address(mockProtocol), address(mockProtocolInterestFree), address(mockProtocolWithInterest), USDC));

        vm.prank(alice);
        USDC.transfer(address(mockProtocol), 1e40);

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT
        });

        vm.prank(admin);
        liquidityProxy.updateUserSupplyConfigs(userSupplyConfigs_);

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: USDC.totalSupply(),
            maxDebtCeiling: 10 * USDC.totalSupply()
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);
    }

    function test_deploy_revertOnInvalidParams() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__InvalidParams)
        );
        new FluidWithdrawLimitAuth(RESERVE_CONTRACT, address(0), multisig);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__InvalidParams)
        );
        new FluidWithdrawLimitAuth(IFluidReserveContract(address(0)), address(liquidityProxy), multisig);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__InvalidParams)
        );
        new FluidWithdrawLimitAuth(RESERVE_CONTRACT, address(liquidityProxy), address(0));
    }

    function _deployNewHandler() internal {
        handler = new FluidWithdrawLimitAuth(RESERVE_CONTRACT, address(liquidityProxy), multisig);

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(admin);
        liquidityProxy.updateAuths(updateAuthsParams);
    }
}

contract FluidRebalanceWithdrawalLimit is WithdrawLimitAuthTest {
    function test_revertIfNotrebalancer() public {
        address user_ = makeAddr("user");

        uint256 newLimit_ = 1e26 - ((4 * 1e26) / 100);

        // revert if not called by rebalancer
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__Unauthorized)
        );
        handler.rebalanceWithdrawalLimit(user_, address(USDC), newLimit_);
    }

    function test_revertIfNoUserSupply() public {
        address user_ = makeAddr("user");

        uint256 newLimit_ = 1e26 - ((4 * 1e26) / 100);

        // revert if user has no supply
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__NoUserSupply)
        );
        handler.rebalanceWithdrawalLimit(user_, address(USDC), newLimit_);
    }

    function test_rebalanceWithdrawalLimitRevertIfBelowMinReachableLimit() public {
        _supply(mockProtocol, address(USDC), alice, 1000000 ether);

        (ResolverStructs.UserSupplyData memory data, ) = liquidityResolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        uint256 minReachableLimit_ = (data.withdrawalLimit * 95) / 100;

        uint256 newLimit_ = minReachableLimit_ - 0.1 ether;

        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.WithdrawLimitAuth__ExcessPercentageDifference
            )
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), newLimit_);
    }

    function test_rebalanceWithdrawalLimit() public {
        // seting up the initial values of supply and withdrawal limit
        // supply ~ 1e26, withdrawal limit ~ 96e24, minReachableLimit ~ 95e24
        _supply(mockProtocol, address(USDC), alice, 1100000 ether);

        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 1000000 ether);

        (ResolverStructs.UserSupplyData memory data, ) = liquidityResolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        uint256 minReachableLimit_ = (data.withdrawalLimit * 95) / 100;

        assertApproxEqAbs(data.withdrawalLimit, 1000000 ether, 1 ether);
        assertApproxEqAbs(data.supply, 1100000 ether, 1 ether);
        assertApproxEqAbs(minReachableLimit_, 950000 ether, 1 ether);

        vm.warp(block.timestamp + 2 days);

        // updating for the first time in the day and hour
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 990000 ether);

        (
            uint40 initialDailyTimestamp,
            uint40 initialHourlyTimestamp,
            uint8 rebalancesIn1Hour,
            uint8 rebalancesIn24Hours,
            uint160 leastDailyUserSupply
        ) = handler.userData(address(mockProtocol), address(USDC));

        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(data.withdrawalLimit, 990000 ether, 1 ether);

        assertEq(uint256(initialDailyTimestamp), block.timestamp);
        assertEq(uint256(initialHourlyTimestamp), block.timestamp);
        assertEq(uint256(rebalancesIn1Hour), 1);
        assertEq(uint256(rebalancesIn24Hours), 1);
        assertApproxEqAbs(uint256(leastDailyUserSupply), 990000 ether, 1 ether);

        minReachableLimit_ = (data.withdrawalLimit * 95) / 100 < leastDailyUserSupply
            ? (data.withdrawalLimit * 95) / 100
            : leastDailyUserSupply;

        assertApproxEqAbs(uint256(minReachableLimit_), 940500 ether, 1 ether);

        // error when we try to update the limit below the minReachableLimit
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.WithdrawLimitAuth__ExcessPercentageDifference
            )
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 940000 ether);

        // updating for the first time in the day and hour
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 980000 ether);

        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(data.withdrawalLimit, 980000 ether, 1 ether);

        (
            initialDailyTimestamp,
            initialHourlyTimestamp,
            rebalancesIn1Hour,
            rebalancesIn24Hours,
            leastDailyUserSupply
        ) = handler.userData(address(mockProtocol), address(USDC));

        assertEq(uint256(rebalancesIn1Hour), 2);
        assertEq(uint256(rebalancesIn24Hours), 2);
        assertApproxEqAbs(uint256(leastDailyUserSupply), 980000 ether, 1 ether);

        // error will occur if trying to update for the third time in an hour (below leastUserSupply and above minReachableLimit)
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__HourlyLimitReached)
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 970000 ether);

        // skipping 2 hours time
        vm.warp(block.timestamp + 2 hours);

        // updating for the third time in the day (in another hour)(above leastUserSupply and minReachableLimit)
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 970000 ether);

        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(data.withdrawalLimit, 970000 ether, 1 ether);

        (
            initialDailyTimestamp,
            initialHourlyTimestamp,
            rebalancesIn1Hour,
            rebalancesIn24Hours,
            leastDailyUserSupply
        ) = handler.userData(address(mockProtocol), address(USDC));

        assertEq(uint256(rebalancesIn1Hour), 1);
        assertEq(uint256(rebalancesIn24Hours), 3);
        assertApproxEqAbs(uint256(leastDailyUserSupply), 970000 ether, 1 ether);

        // doing two more updates in the new hour below leastDailySupply to update the rebalance count
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 960000 ether);
        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(data.withdrawalLimit, 960000 ether, 1 ether);

        // error will occur if trying to update for the fifth time in a day (if below leastUserSupply)
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.WithdrawLimitAuth__DailyLimitReached)
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 930000 ether);

        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));

        // any limit above the leastDailyUserSupply can be used
        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 970000 ether);
        (data, ) = liquidityResolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertApproxEqAbs(data.withdrawalLimit, 970000 ether, 1 ether);

        // minReachableLimit_ here is 95% of the current limit = 0.95*970000 = 921500
        // setting below reverts
        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.WithdrawLimitAuth__ExcessPercentageDifference
            )
        );
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 920000 ether);
    }

    function test_getUsersData() public {
        // seting up the initial values of supply and withdrawal limit
        // supply ~ 1e26, withdrawal limit ~ 96e24, minReachableLimit ~ 95e24
        _supply(mockProtocol, address(USDC), alice, 1100000 ether);

        vm.prank(rebalancer);
        handler.rebalanceWithdrawalLimit(address(mockProtocol), address(USDC), 1000000 ether);

        (ResolverStructs.UserSupplyData memory data, ) = liquidityResolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );

        address[] memory protocols = new address[](1);
        address[] memory tokens = new address[](1);

        protocols[0] = address(mockProtocol);
        tokens[0] = address(USDC);

        (uint256[] memory supplies, uint256[] memory withdrawalLimits) = handler.getUsersData(protocols, tokens);

        assertEq(data.withdrawalLimit, withdrawalLimits[0]);
        assertEq(data.supply, supplies[0]);
    }
}
