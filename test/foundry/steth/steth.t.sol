//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../testERC20.sol";
import "../bytesLib.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";

import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { FluidStETHQueue } from "../../../contracts/protocols/steth/main.sol";
import { FluidStETHQueueProxy } from "../../../contracts/protocols/steth/proxy.sol";
import { IFluidStETHQueue } from "../../../contracts/protocols/steth/interfaces/iStETHQueue.sol";
import { FluidStETHResolver } from "../../../contracts/periphery/resolvers/steth/main.sol";
import { Structs as StETHQueueStructs } from "../../../contracts/protocols/steth/structs.sol";
import { ILidoWithdrawalQueue } from "../../../contracts/protocols/steth/interfaces/external/iLidoWithdrawalQueue.sol";

import { FluidLiquidityUserModule } from "../../../contracts/liquidity/userModule/main.sol";
import { FluidLiquidityAdminModule, AuthModule, GovernanceModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { FluidLiquidityProxy } from "../../../contracts/liquidity/proxy.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";

import { Events } from "../../../contracts/protocols/steth/events.sol";
import { Error } from "../../../contracts/protocols/steth/error.sol";
import { ErrorTypes } from "../../../contracts/protocols/steth/errorTypes.sol";

import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { IStETH } from "./iStETH.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { FluidStETHQueueExposed } from "./stethExposed.sol";

abstract contract StETHQueueBaseTest is LiquidityBaseTest, Events {
    FluidStETHQueue stETHQueueImpl;
    FluidStETHQueue stETHQueue; // proxy
    FluidLiquidityResolver liquidityResolver;

    IFluidLiquidity liquidityProxy;
    FluidStETHResolver stETHResolver;

    ILidoWithdrawalQueue constant LIDO_WITHDRAWAL_QUEUE =
        ILidoWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    IStETH constant STETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    uint16 constant MAX_LTV = 90 * 1e2; // 90%

    uint16 constant TOP_UP_FEE = 10 * 1e2; // 10%

    address constant LIDO_FINALIZER = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    uint256 constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    uint256 constant DEFAULT_ETH_SUPPLIED = 60_000 ether;

    error FluidStETHResolver__AddressZero();
    error FluidStETHResolver__NoClaimQueued();

    event Initialized(uint8 version);

    function setUp() public virtual override {
        // native underlying tests must run in fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(18827888);

        super.setUp();
        liquidityProxy = IFluidLiquidity(address(liquidity));

        // fund Liquidity with ETH for lending out
        // Add supply config for MockProtocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT
        });
        vm.prank(admin);
        liquidityProxy.updateUserSupplyConfigs(userSupplyConfigs_);

        vm.deal(alice, 1_000_000 ether);
        _supplyNative(mockProtocol, alice, DEFAULT_ETH_SUPPLIED);

        // deploy FluidStETHQueue contract
        stETHQueueImpl = new FluidStETHQueue(liquidityProxy, LIDO_WITHDRAWAL_QUEUE, IERC20(address(STETH)));
        stETHQueue = FluidStETHQueue(payable(new FluidStETHQueueProxy(address(stETHQueueImpl), new bytes(0))));

        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        stETHResolver = new FluidStETHResolver(
            IFluidStETHQueue(address(stETHQueue)),
            liquidityResolver,
            LIDO_WITHDRAWAL_QUEUE
        );

        // configure FluidStETHQueue as user to borrow at Liquidity
        // set very high limits so borrow limits can be ignored in this test (not focus of FluidStETHQueue tests)
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(stETHQueue),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        stETHQueue.initialize(admin);
        vm.prank(admin);
        stETHQueue.setAllowListActive(false);

        // configure maxLTV
        vm.prank(admin);
        stETHQueue.setMaxLTV(MAX_LTV);

        // fund alice with stETH
        vm.prank(0xd8d041705735cd770408AD31F883448851F2C39d);
        IERC20(address(STETH)).transfer(alice, 60_000 ether);
        // approve stETH from alice to stETHQueue
        vm.prank(alice);
        STETH.approve(address(stETHQueue), type(uint256).max);
    }
}

contract StETHQueueTestConstructor is StETHQueueBaseTest {
    function test_StETHQueue() public {
        (IFluidLiquidity liquidity, ILidoWithdrawalQueue lidoWithdrawalQueue, IERC20 steth) = stETHQueue
            .constantsView();

        assertEq(address(liquidity), address(liquidityProxy));
        assertEq(address(lidoWithdrawalQueue), address(LIDO_WITHDRAWAL_QUEUE));
        assertEq(address(steth), address(STETH));
        assertEq(stETHQueue.maxLTV(), MAX_LTV);
    }

    function test_initializerDisabledOnLogicContract() public {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        stETHQueue.initialize(admin);
    }

    function test_initialize() public {
        stETHQueueImpl = new FluidStETHQueueExposed(liquidityProxy, LIDO_WITHDRAWAL_QUEUE, IERC20(address(STETH)));
        FluidStETHQueueExposed stETHQueueExp = FluidStETHQueueExposed(
            payable(new FluidStETHQueueProxy(address(stETHQueueImpl), new bytes(0)))
        );

        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(stETHQueueExp));
        (ResolverStructs.UserBorrowData memory userBorrowData_, ) = resolver.getUserBorrowData(
            address(address(stETHQueueExp)),
            address(NATIVE_TOKEN_ADDRESS)
        );
        uint256 borrowBefore = userBorrowData_.borrow;

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(stETHQueueExp),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        vm.prank(admin);
        stETHQueueExp.initialize(admin);

        assertEq(stETHQueueExp.owner(), admin);
        assertEq(
            IERC20(address(STETH)).allowance(address(stETHQueueExp), address(LIDO_WITHDRAWAL_QUEUE)),
            type(uint256).max
        );
        assertEq(stETHQueueExp.allowListActive(), true);
        assertEq(stETHQueueExp.exposed_status(), 1);

        (userBorrowData_, ) = resolver.getUserBorrowData(
            address(address(stETHQueueExp)),
            address(NATIVE_TOKEN_ADDRESS)
        );
        uint256 borrowAfter = userBorrowData_.borrow;

        assertTrue(borrowAfter > borrowBefore);
    }

    function test_initialize_RevertWhenOwnerIsAddressZero() public {
        stETHQueueImpl = new FluidStETHQueue(liquidityProxy, LIDO_WITHDRAWAL_QUEUE, IERC20(address(STETH)));
        stETHQueue = FluidStETHQueue(payable(new FluidStETHQueueProxy(address(stETHQueueImpl), new bytes(0))));

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(stETHQueue),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        stETHQueue.initialize(address(0));
    }
}

contract StETHQueueTestAdmin is StETHQueueBaseTest {
    function test_setAuth() public {
        vm.prank(admin);
        stETHQueue.setAuth(alice, true);
    }

    function test_setAuth_LogSetAuth() public {
        vm.expectEmit(true, true, true, true);
        emit LogSetAuth(alice, true);
        vm.prank(admin);
        stETHQueue.setAuth(alice, true);
    }

    function test_setAuth_RevertOnlyOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.setAuth(address(alice), true);
    }

    function test_setAuth_RevertAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        vm.prank(admin);
        stETHQueue.setAuth(address(0), true);
    }

    function test_isAuth_Auth() public {
        bool isAuth = stETHQueue.isAuth(alice);
        assertEq(isAuth, false);
        vm.prank(admin);
        stETHQueue.setAuth(alice, true);
        isAuth = stETHQueue.isAuth(alice);
        assertEq(isAuth, true);
    }

    function test_isAuth_NotAuth() public {
        bool isAuth = stETHQueue.isAuth(alice);
        assertEq(isAuth, false);
        vm.prank(admin);
        stETHQueue.setAuth(alice, true);
        isAuth = stETHQueue.isAuth(alice);
        assertEq(isAuth, true);
        vm.prank(admin);
        stETHQueue.setAuth(alice, false);
        isAuth = stETHQueue.isAuth(alice);
        assertEq(isAuth, false);
    }

    function test_isAuth_Owner() public {
        bool isAuth = stETHQueue.isAuth(admin);
        assertEq(isAuth, true);
    }

    function test_setGuardian() public {
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
    }

    function test_setGuardian_LogSetGuardian() public {
        vm.expectEmit(true, true, true, true);
        emit LogSetGuardian(alice, true);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
    }

    function test_setGuardian_RevertOnlyOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.setGuardian(alice, true);
    }

    function test_setGuardian_RevertAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        vm.prank(admin);
        stETHQueue.setGuardian(address(0), true);
    }

    function test_isGuardian_Guardian() public {
        bool isGuardian = stETHQueue.isGuardian(alice);
        assertEq(isGuardian, false);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
        isGuardian = stETHQueue.isGuardian(alice);
        assertEq(isGuardian, true);
    }

    function test_isGuardian_NotGuardian() public {
        bool isGuardian = stETHQueue.isGuardian(alice);
        assertEq(isGuardian, false);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
        isGuardian = stETHQueue.isGuardian(alice);
        assertEq(isGuardian, true);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, false);
        isGuardian = stETHQueue.isGuardian(alice);
        assertEq(isGuardian, false);
    }

    function test_isGuardian_Owner() public {
        bool isGuardian = stETHQueue.isGuardian(admin);
        assertEq(isGuardian, true);
    }

    function test_setMaxLTV() public {
        vm.prank(admin);
        stETHQueue.setMaxLTV(123);

        assertEq(stETHQueue.maxLTV(), 123);
    }

    function test_setMaxLTV_LogSetMaxLTV() public {
        vm.expectEmit(true, true, true, true);
        emit LogSetMaxLTV(123);
        vm.prank(admin);
        stETHQueue.setMaxLTV(123);
    }

    function test_setMaxLTV_RevertMaxLTVZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__MaxLTVZero));
        vm.prank(admin);
        stETHQueue.setMaxLTV(0);
    }

    function test_setMaxLTV_RevertMaxLTVHundredPercent() public {
        vm.prank(admin);
        stETHQueue.setMaxLTV(9999);
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__MaxLTVAboveCap));
        vm.prank(admin);
        stETHQueue.setMaxLTV(10000);
    }

    function test_setMaxLTV_RevertUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__Unauthorized));
        vm.prank(alice);
        stETHQueue.setMaxLTV(1);
    }

    function test_setUserAllowed() public {
        vm.prank(admin);
        stETHQueue.setUserAllowed(alice, true);
        bool isUserAllowed = stETHQueue.isUserAllowed(alice);
        assertEq(isUserAllowed, true);
    }

    function test_setUserAllowed_RevertOnlyAuths() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__Unauthorized));
        vm.prank(alice);
        stETHQueue.setUserAllowed(alice, true);
    }

    function test_setUserAllowed_RevertAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        vm.prank(admin);
        stETHQueue.setUserAllowed(address(0), true);
    }

    function test_setUserAllowed_LogSetAllowed() public {
        vm.expectEmit(true, true, true, true);
        emit LogSetAllowed(alice, true);
        vm.prank(admin);
        stETHQueue.setUserAllowed(alice, true);
    }

    function test_setAllowListActive() public {
        vm.prank(admin);
        stETHQueue.setAllowListActive(true);
        bool allowListActive = stETHQueue.allowListActive();
        assertEq(allowListActive, true);

        vm.prank(admin);
        stETHQueue.setAllowListActive(false);
        allowListActive = stETHQueue.allowListActive();
        assertEq(allowListActive, false);
    }

    function test_setAllowListActive_RevertOnlyOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.setAllowListActive(false);
    }

    function test_setAllowListActive_LogSetAllowListActive() public {
        vm.expectEmit(true, true, true, true);
        emit LogSetAllowListActive(false);
        vm.prank(admin);
        stETHQueue.setAllowListActive(false);
    }

    function test_pause() public {
        assertEq(stETHQueue.isPaused(), false);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
        vm.prank(alice);
        stETHQueue.pause();
        assertEq(stETHQueue.isPaused(), true);
    }

    function test_pause_LogPaused() public {
        assertEq(stETHQueue.isPaused(), false);
        vm.prank(admin);
        stETHQueue.setGuardian(alice, true);
        vm.expectEmit(true, true, true, true);
        emit LogPaused();
        vm.prank(alice);
        stETHQueue.pause();
        assertEq(stETHQueue.isPaused(), true);
    }

    function test_pause_RevertOnlyGuardian() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__Unauthorized));
        vm.prank(alice);
        stETHQueue.pause();
    }

    function test_unpause() public {
        assertEq(stETHQueue.isPaused(), false);
        vm.prank(admin);
        stETHQueue.pause();
        assertEq(stETHQueue.isPaused(), true);
        vm.prank(admin);
        stETHQueue.unpause();
        assertEq(stETHQueue.isPaused(), false);
    }

    function test_unpause_LogUnpaused() public {
        vm.prank(admin);
        stETHQueue.pause();
        assertEq(stETHQueue.isPaused(), true);
        vm.expectEmit(true, true, true, true);
        emit LogUnpaused();
        vm.prank(admin);
        stETHQueue.unpause();
        assertEq(stETHQueue.isPaused(), false);
    }

    function test_unpause_RevertOnlyOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.unpause();
    }
}

contract StETHQueueTest is StETHQueueBaseTest {
    function test_liquidityCallback_RevertUnexpectedLiquidityCallback() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__UnexpectedLiquidityCallback)
        );
        stETHQueue.liquidityCallback(address(0), 0, new bytes(0));
    }

    function test_onERC721Received() public {
        vm.prank(address(LIDO_WITHDRAWAL_QUEUE));
        bytes4 res = stETHQueue.onERC721Received(address(0), address(0), 0, new bytes(0));
        assertEq(res, stETHQueue.onERC721Received.selector);
    }

    function test_onERC721Received_RevertInvalidERC721Transfer() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__InvalidERC721Transfer)
        );
        vm.prank(alice);
        stETHQueue.onERC721Received(address(0), address(0), 0, new bytes(0));
    }
}

contract StETHResolverTest is StETHQueueBaseTest {
    function test_isClaimable_True() public {
        uint256 totalPooledEther = STETH.getTotalPooledEther();
        uint256 totalShares = STETH.getTotalShares();
        uint256 defaultShareRate = (totalPooledEther * 10 ** 27) / totalShares; // in 1e27
        uint256 supplyAmount = 300 ether;

        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
        bool isClaimable = stETHResolver.isClaimable(alice, requestIdFrom);
        assertEq(isClaimable, false);

        vm.deal(LIDO_FINALIZER, 1_000_000 ether);
        vm.prank(LIDO_FINALIZER);
        LIDO_WITHDRAWAL_QUEUE.finalize{ value: supplyAmount }(requestIdFrom, defaultShareRate);

        isClaimable = stETHResolver.isClaimable(alice, requestIdFrom);
        assertEq(isClaimable, true);
    }

    function test_isClaimable_False() public {
        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
        bool isClaimable = stETHResolver.isClaimable(alice, requestIdFrom);
        assertEq(isClaimable, false);
    }

    function test_isClaimable_RevertNoClaimQueued() public {
        vm.expectRevert(abi.encodeWithSelector(FluidStETHResolver__NoClaimQueued.selector));
        stETHResolver.isClaimable(alice, 1);
    }
}

contract StETHQueueTestQueue is StETHQueueBaseTest {
    function test_queue_OneNFT() public {
        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);

        // assert claim is stored
        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, DEFAULT_BORROW_AMOUNT);
        assertNotEq(requestIdFrom, 0);
        assertEq(requestIdFrom, requestIdTo);
        assertEq(checkpoint, LIDO_WITHDRAWAL_QUEUE.getLastCheckpointIndex());

        // assert NFT is present with expected properties
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        assertEq(requestIds.length, 1);
        assertEq(requestIds[0], requestIdFrom);
        ILidoWithdrawalQueue.WithdrawalRequestStatus memory status = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        )[0];
        assertEq(status.amountOfStETH, DEFAULT_SUPPLY_AMOUNT);
        assertEq(status.isClaimed, false);
        assertEq(status.isFinalized, false);
        assertEq(status.owner, address(stETHQueue));
    }

    function test_queue_MultipleNFTs() public {
        uint256 borrowAmount = MAX_WITHDRAWAL_AMOUNT * 3;
        uint256 supplyAmount = MAX_WITHDRAWAL_AMOUNT * 5 + 300 ether;
        // should lead to 9 NFTS
        uint256 expectedNFTs = 6;

        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(
            borrowAmount, // borrow
            supplyAmount, // supply
            alice,
            alice
        );

        // assert claim is stored
        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, borrowAmount);
        assertNotEq(requestIdFrom, 0);
        assertNotEq(requestIdTo, 0);
        assertEq(requestIdTo - requestIdFrom + 1, expectedNFTs);
        assertEq(checkpoint, LIDO_WITHDRAWAL_QUEUE.getLastCheckpointIndex());

        // assert NFTs are present with expected properties
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        assertEq(requestIds.length, expectedNFTs);
        assertEq(requestIds[0], requestIdFrom);
        assertEq(requestIds[1], requestIdFrom + 1);
        assertEq(requestIds[2], requestIdFrom + 2);
        assertEq(requestIds[3], requestIdFrom + 3);
        assertEq(requestIds[4], requestIdFrom + 4);
        assertEq(requestIds[requestIds.length - 1], requestIdTo);
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );
        assertEq(statuses[0].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[1].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[2].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[3].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[4].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[5].amountOfStETH, supplyAmount % MAX_WITHDRAWAL_AMOUNT);
    }

    function test_queue_MultipleNFTs_LastAmountIsLessThanMinStETHWithdrawalAmount() public {
        uint256 borrowAmount = MAX_WITHDRAWAL_AMOUNT * 3;
        uint256 supplyAmount = MAX_WITHDRAWAL_AMOUNT * 5 + 1;
        // should lead to 6 NFTS
        uint256 expectedNFTs = 6;

        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(
            borrowAmount, // borrow
            supplyAmount, // supply
            alice,
            alice
        );

        // assert claim is stored
        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, borrowAmount);
        assertNotEq(requestIdFrom, 0);
        assertNotEq(requestIdTo, 0);
        assertEq(requestIdTo - requestIdFrom + 1, expectedNFTs);
        assertEq(checkpoint, LIDO_WITHDRAWAL_QUEUE.getLastCheckpointIndex());

        // assert NFTs are present with expected properties
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        assertEq(requestIds.length, expectedNFTs);
        assertEq(requestIds[0], requestIdFrom);
        assertEq(requestIds[1], requestIdFrom + 1);
        assertEq(requestIds[2], requestIdFrom + 2);
        assertEq(requestIds[3], requestIdFrom + 3);
        assertEq(requestIds[4], requestIdFrom + 4);
        assertEq(requestIds[requestIds.length - 1], requestIdTo);
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );
        assertEq(statuses[0].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[1].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[2].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[3].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
        // 100 is moved to the last request because of min steth amount
        assertEq(statuses[4].amountOfStETH, MAX_WITHDRAWAL_AMOUNT - 100);
        assertEq(statuses[5].amountOfStETH, 101);
    }

    function test_queue_LogQueue() public {
        vm.expectEmit(true, true, true, true);
        emit LogQueue(alice, 19121, DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice); // 19121 its request id that will be created
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }

    function test_queue_WhenUserNotAllowedButAllowListNotActive() public {
        vm.prank(admin);
        stETHQueue.setAllowListActive(false);
        vm.prank(admin);
        stETHQueue.setUserAllowed(alice, false);

        vm.expectEmit(true, true, true, true);
        emit LogQueue(alice, 19121, DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice); // 19121 its request id that will be created
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }

    function test_queue_RevertInputAmountZeroStETH() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__InputAmountZero));
        vm.prank(alice);
        stETHQueue.queue(0, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }

    function test_queue_RevertInputAmountZeroETH() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__InputAmountZero));
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, 0, alice, alice);
    }

    function test_queue_RevertAddressZeroBorrowTo() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, address(0), alice);
    }

    function test_queue_RevertAddressZeroClaimTo() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__AddressZero));
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, address(0));
    }

    function test_queue_RevertUserNotAllowed() public {
        vm.prank(admin);
        stETHQueue.setAllowListActive(true);
        vm.prank(admin);
        stETHQueue.setUserAllowed(alice, false);
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__Unauthorized));
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }

    function test_queue_RevertMaxLTV() public {
        vm.prank(admin);
        stETHQueue.setMaxLTV(1); // set minimal ltv
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__MaxLTV));
        vm.prank(alice);
        stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }

    function test_queue_RevertBorrowAmountRawRoundingZero() public {
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
        _supplyNative(mockProtocol, alice, DEFAULT_SUPPLY_AMOUNT);
        _borrowNative(mockProtocol, alice, DEFAULT_ETH_SUPPLIED);
        vm.warp(block.timestamp + PASS_1YEAR_TIME / 1000);
        vm.expectRevert(
            abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__BorrowAmountRawRoundingZero)
        );
        vm.prank(alice);
        stETHQueue.queue(1, DEFAULT_SUPPLY_AMOUNT, alice, alice);
    }
}

contract StETHQueueTestClaim is StETHQueueBaseTest {
    uint256 defaultShareRate;

    function setUp() public virtual override {
        super.setUp();

        uint256 totalPooledEther = STETH.getTotalPooledEther();
        uint256 totalShares = STETH.getTotalShares();

        defaultShareRate = (totalPooledEther * 10 ** 27) / totalShares; // in 1e27
    }

    function test_claim_OneNFT() public {
        uint256 initialLiquidityBalance = address(liquidityProxy).balance;
        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(DEFAULT_BORROW_AMOUNT, DEFAULT_SUPPLY_AMOUNT, alice, alice);

        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);

        // Finalize the withdrawal request and fill ETH for withdrawal
        vm.deal(LIDO_FINALIZER, 1_000_000 ether);
        vm.prank(LIDO_FINALIZER);
        LIDO_WITHDRAWAL_QUEUE.finalize{ value: DEFAULT_SUPPLY_AMOUNT }(requestIdTo, defaultShareRate);

        // check state of withdrawal request is finalized
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        ILidoWithdrawalQueue.WithdrawalRequestStatus memory status = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        )[0];
        assertEq(status.amountOfStETH, DEFAULT_SUPPLY_AMOUNT);
        assertEq(status.isClaimed, false);
        assertEq(status.isFinalized, true);
        assertEq(status.owner, address(stETHQueue));

        uint256 initialAliceBalance = alice.balance;

        // execute claim
        vm.prank(alice);
        (uint256 totalClaimedAmount, uint256 totalRepaidAmount) = stETHQueue.claim(alice, requestIdFrom);

        // assert expected amounts
        assertApproxEqAbs(totalClaimedAmount, DEFAULT_SUPPLY_AMOUNT, 2);
        assertEq(totalRepaidAmount, DEFAULT_BORROW_AMOUNT + 1); // rounded up

        // check that balance of liquidity is back to initial
        assertEq(address(liquidityProxy).balance, initialLiquidityBalance + 1); // rounded up
        // no NFTs should be held by StETHQueue anymore (burned)
        assertEq(LIDO_WITHDRAWAL_QUEUE.balanceOf(address(stETHQueue)), 0);
        // alice should have received difference of supply amount - borrow amount
        assertApproxEqAbs(alice.balance - initialAliceBalance, DEFAULT_SUPPLY_AMOUNT - DEFAULT_BORROW_AMOUNT, 2);
        // claim should be deleted at mapping
        (borrowAmountRaw, checkpoint, requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, 0);
        assertEq(checkpoint, 0);
        assertEq(requestIdTo, 0);
    }

    function testFuzz_claim_MultipleNFTs(uint256 nftsCount) public {
        vm.assume(nftsCount > 1);
        vm.assume(nftsCount < 60);

        uint256 initialLiquidityBalance = address(liquidityProxy).balance;

        uint256 supplyAmount = MAX_WITHDRAWAL_AMOUNT * nftsCount + 300 ether;
        uint256 borrowAmount = (supplyAmount * 80) / 100; // ltv 80%

        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(
            borrowAmount, // borrow
            supplyAmount, // supply
            alice,
            alice
        );

        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);

        // Finalize the withdrawal request and fill ETH for withdrawal
        vm.deal(LIDO_FINALIZER, 1_000_000 ether);
        vm.prank(LIDO_FINALIZER);
        LIDO_WITHDRAWAL_QUEUE.finalize{ value: supplyAmount }(requestIdTo, defaultShareRate);

        // check state of withdrawal request ids is finalized
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        );
        for (uint256 i; i < statuses.length - 1; i++) {
            assertEq(statuses[i].amountOfStETH, MAX_WITHDRAWAL_AMOUNT);
            assertEq(statuses[i].isClaimed, false);
            assertEq(statuses[i].isFinalized, true);
            assertEq(statuses[i].owner, address(stETHQueue));
        }
        assertEq(statuses[statuses.length - 1].amountOfStETH, supplyAmount % MAX_WITHDRAWAL_AMOUNT);
        assertEq(statuses[statuses.length - 1].isClaimed, false);
        assertEq(statuses[statuses.length - 1].isFinalized, true);
        assertEq(statuses[statuses.length - 1].owner, address(stETHQueue));

        uint256 initialAliceBalance = alice.balance;

        // execute claim
        vm.prank(alice);
        (uint256 totalClaimedAmount, uint256 totalRepaidAmount) = stETHQueue.claim(alice, requestIdFrom);

        // assert expected amounts
        assertApproxEqAbs(totalClaimedAmount, supplyAmount, requestIds.length * 2); // 2 delta per NFT
        assertEq(totalRepaidAmount, borrowAmount + 1); // rounded up

        // check that balance of liquidity is back to initial
        assertEq(address(liquidityProxy).balance, initialLiquidityBalance + 1); // rounded up
        // no NFTs should be held by StETHQueue anymore (burned)
        assertEq(LIDO_WITHDRAWAL_QUEUE.balanceOf(address(stETHQueue)), 0);
        // alice should have received difference of supply amount - borrow amount
        assertApproxEqAbs(alice.balance - initialAliceBalance, supplyAmount - borrowAmount, requestIds.length * 2); // 2 delta per NFT
        // claim should be deleted at mapping
        (borrowAmountRaw, checkpoint, requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, 0);
        assertEq(checkpoint, 0);
        assertEq(requestIdTo, 0);
    }

    function test_claim_WithYield() public {
        // reduce supplied amount for easier calculation of yield
        _withdrawNative(mockProtocol, alice, DEFAULT_ETH_SUPPLIED - 100 ether - 1e12); // only 100 eth supplied afterwards. 1e12 from dust borrow

        uint256 initialLiquidityBalance = address(liquidityProxy).balance;
        assertEq(initialLiquidityBalance, 100 ether);

        uint256 ethBorrowAmount = 80 ether; // 80% borrowed so yield is at default kink -> 10% APR
        uint256 stETHSupplyAmount = 200 ether;

        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(
            ethBorrowAmount, // borrow
            stETHSupplyAmount, // supply
            alice,
            alice
        );

        (uint128 borrowAmountRaw, uint48 checkpoint, uint40 requestIdTo) = stETHQueue.claims(alice, requestIdFrom);

        // warp for 1 year -> repay amount will be 88 ether after applying borrow rate
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // Finalize the withdrawal request and fill ETH for withdrawal
        vm.deal(LIDO_FINALIZER, 1_000_000 ether);
        vm.prank(LIDO_FINALIZER);
        LIDO_WITHDRAWAL_QUEUE.finalize{ value: stETHSupplyAmount }(requestIdTo, defaultShareRate);

        // check state of withdrawal request is finalized
        uint256[] memory requestIds = LIDO_WITHDRAWAL_QUEUE.getWithdrawalRequests(address(stETHQueue));
        ILidoWithdrawalQueue.WithdrawalRequestStatus memory status = LIDO_WITHDRAWAL_QUEUE.getWithdrawalStatus(
            requestIds
        )[0];
        assertEq(status.amountOfStETH, stETHSupplyAmount);
        assertEq(status.isClaimed, false);
        assertEq(status.isFinalized, true);
        assertEq(status.owner, address(stETHQueue));

        uint256 initialAliceBalance = alice.balance;

        // execute claim
        vm.prank(alice);
        (uint256 totalClaimedAmount, uint256 totalRepaidAmount) = stETHQueue.claim(alice, requestIdFrom);

        // yield is 10% borrow apr => should have increased by 10% of borrowAmount 80 ether -> by 8 ether
        uint256 yield = ((ethBorrowAmount / 100) * 10);

        // assert expected amounts
        assertApproxEqAbs(totalClaimedAmount, stETHSupplyAmount, 2);
        assertEq(totalRepaidAmount, ethBorrowAmount + yield + 1); // rounded up

        // check that balance of liquidity is back to initial + yield
        assertEq(address(liquidityProxy).balance, initialLiquidityBalance + yield + 1); // rounded up
        // no NFTs should be held by StETHQueue anymore (burned)
        assertEq(LIDO_WITHDRAWAL_QUEUE.balanceOf(address(stETHQueue)), 0);
        // alice should have received difference of supply amount - borrow amount - yield
        assertApproxEqAbs(alice.balance - initialAliceBalance, stETHSupplyAmount - ethBorrowAmount - yield, 2);
        // claim should be deleted at mapping
        (borrowAmountRaw, checkpoint, requestIdTo) = stETHQueue.claims(alice, requestIdFrom);
        assertEq(borrowAmountRaw, 0);
        assertEq(checkpoint, 0);
        assertEq(requestIdTo, 0);
    }

    function test_claim_LogClaim() public {
        uint256 ethBorrowAmount = 80 ether;
        uint256 stETHSupplyAmount = 200 ether;
        vm.prank(alice);
        uint256 requestIdFrom = stETHQueue.queue(
            ethBorrowAmount, // borrow
            stETHSupplyAmount, // supply
            alice,
            alice
        );

        // Finalize the withdrawal request and fill ETH for withdrawal
        vm.deal(LIDO_FINALIZER, 1_000_000 ether);
        vm.prank(LIDO_FINALIZER);
        LIDO_WITHDRAWAL_QUEUE.finalize{ value: stETHSupplyAmount }(requestIdFrom, defaultShareRate);

        assertEq(address(stETHQueue).balance, 1e12); // from dust
        uint256 expectedClaimedAmount = stETHSupplyAmount - 1;
        uint256 expectedRepayAmount = ethBorrowAmount + 1;
        vm.expectEmit(true, true, true, true);
        emit LogClaim(alice, requestIdFrom, expectedClaimedAmount, expectedRepayAmount);
        vm.prank(alice);
        stETHQueue.claim(alice, requestIdFrom);
    }

    function test_claim_RevertNoClaimQueued() public {
        vm.expectRevert(abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__NoClaimQueued));
        vm.prank(alice);
        stETHQueue.claim(alice, 1);
    }
}

contract StETHQueueTestOwnership is StETHQueueBaseTest {
    function test_renounceOwnership_RevertIfNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.renounceOwnership();
    }

    function test_renounceOwnership_RevertUnsupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.StETHQueueError.selector, ErrorTypes.StETH__RenounceOwnershipUnsupported)
        );
        vm.prank(admin);
        stETHQueue.renounceOwnership();
    }
}

contract StETHQueueTestUpgradable is StETHQueueBaseTest {
    function test_upgrade_RevertOnlyOwner() public {
        stETHQueueImpl = new FluidStETHQueue(liquidityProxy, LIDO_WITHDRAWAL_QUEUE, IERC20(address(STETH)));
        stETHQueue = FluidStETHQueue(payable(new FluidStETHQueueProxy(address(stETHQueueImpl), new bytes(0))));

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(stETHQueue),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        stETHQueue.initialize(admin);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        stETHQueue.upgradeTo(address(0xCAFE));
    }

    function test_upgrade() public {
        stETHQueueImpl = new FluidStETHQueue(liquidityProxy, LIDO_WITHDRAWAL_QUEUE, IERC20(address(STETH)));
        FluidStETHQueue newStETHQueueImpl = new FluidStETHQueue(
            liquidityProxy,
            LIDO_WITHDRAWAL_QUEUE,
            IERC20(address(STETH))
        );
        stETHQueue = FluidStETHQueue(payable(new FluidStETHQueueProxy(address(stETHQueueImpl), new bytes(0))));

        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(stETHQueue),
            token: NATIVE_TOKEN_ADDRESS,
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        stETHQueue.initialize(admin);
        vm.prank(admin);
        stETHQueue.upgradeTo(address(newStETHQueueImpl));
    }
}
