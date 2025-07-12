//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultRewards } from "../../../../contracts/protocols/vault/rewards/main.sol";
import { Events } from "../../../../contracts/protocols/vault/rewards/events.sol";

import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";

import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { FluidLendingFactory } from "../../../../contracts/protocols/lending/lendingFactory/main.sol";

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFluidReserveContract } from "../../../../contracts/reserve/interfaces/iReserveContract.sol";
import { FluidReserveContract } from "../../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../../contracts/reserve/proxy.sol";

import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { TestERC20 } from "../../testERC20.sol";
import { TestERC20Dec6 } from "../../testERC20Dec6.sol";

import { VaultFactoryBaseTest } from "../factory/vaultFactory.t.sol";

contract VaultRewardsTest is VaultFactoryBaseTest, Events {
    FluidVaultT1 vaultOne;
    MockOracle oracleOne;

    TestERC20Dec6 supplyToken;
    TestERC20 borrowToken;

    IFluidLiquidity liquidityProxy;

    FluidReserveContract reserveContractImpl;
    FluidReserveContract reserveContract; //proxy

    uint256 RATE_PRECISION = 10000;
    uint256 rewardsMagnifierAtZero = 2 * RATE_PRECISION;
    uint256 rewardsMagnifier1AtTVL = 1 * RATE_PRECISION;
    uint256 startingTVL = 0;

    FluidVaultRewards vaultRewards;

    uint256 vaultRewardsDuration = 365 days;
    uint256 vaultRewardsStartTime;
    uint256 vaultRewardsEndTime;

    address owner = address(0x123F);
    address rebalancer = address(0x678A);
    address authUser = address(0x987B);
    address governance = address(0x654C);

    address[] rebalancers;
    address[] auths;

    address vaultAuthContractAuthorizedUser = address(0x123D);

    function setUp() public virtual override {
        super.setUp();

        rebalancers = new address[](1);
        rebalancers[0] = owner;

        auths = new address[](1);
        auths[0] = authUser;

        liquidityProxy = IFluidLiquidity(address(liquidity));

        supplyToken = TestERC20Dec6(address(USDC));
        borrowToken = TestERC20(address(DAI));

        vaultOne = FluidVaultT1(_deployVaultTokens(address(supplyToken), address(borrowToken)));

        // set default allowances for vault
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultOne));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultOne));

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(supplyToken), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(borrowToken), address(mockProtocol));

        _supply(mockProtocol, address(supplyToken), alice, 1e6 * 1e6);
        _supply(mockProtocol, address(borrowToken), alice, 1e6 * 1e18);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(USDC, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), alice);

        reserveContractImpl = new FluidReserveContract();
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        reserveContract.initialize(auths, rebalancers, owner);
        // reserve contract proxy admin is 'admin'
        // reserve contract owner is 'owner'
        vm.prank(authUser);
        reserveContract.updateRebalancer(rebalancer, true);

        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(supplyToken),
            governance
        );

        // revert if not initiator
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__NotTheInitiator)
        );
        vm.prank(admin);
        vaultRewards.start();

        // reverts before started
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__RewardsNotStartedOrEnded)
        );
        vaultRewards.calculateMagnifier();

        // start rewards
        vm.warp(block.timestamp + 100);
        vaultRewardsStartTime = block.timestamp;
        vaultRewardsEndTime = block.timestamp + vaultRewardsDuration;
        vm.prank(alice);
        vaultRewards.start();

        assertEq(uint256(vaultRewards.startTime()), vaultRewardsStartTime);
        assertEq(uint256(vaultRewards.endTime()), vaultRewardsEndTime);

        // revert if already started
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AlreadyStarted)
        );
        vm.prank(alice);
        vaultRewards.start();

        vm.warp(block.timestamp + 1);

        vm.prank(admin);
        vaultFactory.setVaultAuth(address(vaultOne), address(vaultRewards), true);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(DAI, address(vaultOne), alice);

        oracleOne = MockOracle(_setDefaultVaultSettings(address(vaultOne)));

        _setOracleOnePrice(1e39);

        // updating the user borrow and supply configs so that we can change the borrow rate during testing
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(this),
            token: address(supplyToken),
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 1_000_000 ether,
            maxDebtCeiling: 10_000_000 ether
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(this),
            token: address(supplyToken),
            mode: 1, // with interest
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT
        });
        vm.prank(admin);
        liquidityProxy.updateUserSupplyConfigs(userSupplyConfigs_);

        borrowToken.mint(address(this), 1e6 * 1e18);
        supplyToken.mint(address(this), 1e6 * 1e6);
    }

    // ################### HELPERS #####################

    function _deployVaultTokens(address supplyToken_, address borrowToken_) internal returns (address vault_) {
        vm.prank(alice);

        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (supplyToken_, borrowToken_));
        vault_ = address(FluidVaultT1(vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode)));
    }

    function _setDefaultVaultSettings(address vault_) internal returns (address oracle_) {
        FluidVaultT1Admin vaultAdmin_ = FluidVaultT1Admin(vault_);
        vm.prank(alice);
        vaultAdmin_.updateCoreSettings(
            10000, // supplyFactor_ => 100%
            10000, // borrowFactor_ => 100%
            8000, // collateralFactor_ => 80%
            8100, // liquidationThreshold_ => 81%
            9000, // liquidationMaxLimit_ => 90%
            500, // withdrawGap_ => 5%
            0, // liquidationPenalty_ => 0%
            0 // borrowFee_ => 0.01%
        );

        oracle_ = address(new MockOracle());
        vm.prank(alice);
        vaultAdmin_.updateOracle(address(oracle_));

        vm.prank(alice);
        vaultAdmin_.updateRebalancer(address(alice));
    }

    function _setOracleOnePrice(uint price) internal {
        oracleOne.setPrice(price);
    }

    // ################### TESTS #####################

    function test_contructor_RevertIfReserveContractAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AddressZero));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(0)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_contructor_RevertIfVaultAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AddressZero));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(0)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_contructor_RevertIfInitiatorAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AddressZero));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            address(0), // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_contructor_RevertIfLiquidityAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AddressZero));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(0)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_contructor_RevertIfCollateralTokenAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__AddressZero));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(0),
            governance
        );
    }

    function test_contructor_RevertIfRewardsAmountZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__InvalidParams));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            0, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_contructor_RevertIfDurationZero() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__InvalidParams));
        vaultRewards = new FluidVaultRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            0,
            alice, // start initiator
            address(supplyToken),
            governance
        );
    }

    function test_calculateMagnifier_AfterEndTime() public {
        vm.warp(vaultRewardsEndTime + 1);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();
        assertEq(calculatedMagnifier, RATE_PRECISION);
    }

    function test_rebalance_RevertIfNoRebalancer() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__Unauthorized));
        vm.prank(alice);
        vaultRewards.rebalance();
    }

    function test_rebalance_RevertIfMagnifierNotChanged() public {
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 ether,
            1 ether,
            alice
        );

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, 10000);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();

        vm.prank(rebalancer);
        vaultRewards.rebalance();

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, calculatedMagnifier);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultRewards.rebalance();
    }

    function test_rebalance_OnePointFiveMagnifier() public {
        // rewardsAmount = 2 ether
        // so if currentTVL is 4 ether, rate magnifier would have to be 1.5
        int256 tvlForOnePointFive = 4 ether;

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            tvlForOnePointFive,
            0,
            alice
        );
        vm.warp(block.timestamp + vaultRewardsStartTime);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();

        uint256 expectedMagnifier = (15 * RATE_PRECISION) / 10; // 1.5 * RATE_PRECISION;
        assertEq(calculatedMagnifier, expectedMagnifier);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, 10000);

        vm.expectEmit(true, true, true, false);
        emit LogUpdateMagnifier(address(vaultOne), expectedMagnifier);
        vm.prank(rebalancer);
        vaultRewards.rebalance();

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, expectedMagnifier);
    }

    function test_rebalance_OnePointTwentyFiveMagnifier() public {
        // rewardsAmount = 2 ether
        // so if currentTVL is 8 ether, rate magnifier would have to be 1.25
        int256 tvlForOnePointTwentyFive = 8 ether;

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            tvlForOnePointTwentyFive,
            0,
            alice
        );
        vm.warp(block.timestamp + vaultRewardsStartTime);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();

        uint256 expectedMagnifier = (125 * RATE_PRECISION) / 100; // 1.25 * RATE_PRECISION;
        assertEq(calculatedMagnifier, expectedMagnifier);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, 10000);

        vm.expectEmit(true, true, true, false);
        emit LogUpdateMagnifier(address(vaultOne), expectedMagnifier);
        vm.prank(rebalancer);
        vaultRewards.rebalance();

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, expectedMagnifier);
    }

    function test_rebalanceAfterEndTime_NextRewardsNotQueued() public {
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 ether,
            1 ether,
            alice
        );
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, 10000);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();

        vm.prank(rebalancer);
        vaultRewards.rebalance();
        assertEq(vaultRewards.ended(), false);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, calculatedMagnifier);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultRewards.rebalance();

        vm.warp(block.timestamp + 365 days);
        assertEq(vaultRewards.nextDuration(), 0);
        assertEq(vaultRewards.nextRewardsAmount(), 0);
        vm.prank(rebalancer);
        vaultRewards.rebalance();
        assertEq(vaultRewards.ended(), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultRewards__RewardsNotStartedOrEnded
            )
        );
        vm.prank(rebalancer);
        vaultRewards.rebalance();
    }

    function test_rebalanceAfterEndTime_NextRewardsQueued() public {
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 ether,
            1 ether,
            alice
        );
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, 10000);
        (uint256 calculatedMagnifier, ) = vaultRewards.calculateMagnifier();

        vm.prank(rebalancer);
        vaultRewards.rebalance();
        assertEq(vaultRewards.ended(), false);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.supplyRateMagnifier, calculatedMagnifier);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultRewards.rebalance();

        // verifying the invalid params error
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__InvalidParams));
        vaultRewards.queueNextRewards(0, 365 days);

        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__InvalidParams));
        vaultRewards.queueNextRewards(2 ether, 0);

        // verifying the unauthorized error
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultRewards__NotTheGovernance)
        );
        vaultRewards.queueNextRewards(2 ether, 365 days);

        // setting next rewards
        vm.prank(governance);
        vaultRewards.queueNextRewards(2 ether, 365 days);

        vm.warp(block.timestamp + 365 days);
        assertEq(vaultRewards.nextDuration(), 365 days);
        assertEq(vaultRewards.nextRewardsAmount(), 2 ether);
        liquidityProxy.operate(
            vaultRewards.VAULT_COLLATERAL_TOKEN(),
            0 ether,
            10 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );
        vm.prank(rebalancer);
        vaultRewards.rebalance();
        assertEq(vaultRewards.ended(), false);
        assertEq(vaultRewards.nextDuration(), 0);
        assertEq(vaultRewards.nextRewardsAmount(), 0);

        assertEq(vaultRewards.ended(), false);
        assertEq(vaultRewards.duration(), 365 days);
        assertEq(vaultRewards.rewardsAmount(), 2 ether);
        assertEq(vaultRewards.rewardsAmountPerYear(), 2 ether);

        assertEq(vaultRewards.startTime(), uint96(block.timestamp));
        assertEq(vaultRewards.endTime(), uint96(block.timestamp + 365 days));
    }
}
