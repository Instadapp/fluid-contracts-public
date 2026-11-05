//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { IFluidVaultT1 } from "../../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { FluidVaultRewards } from "../../../../contracts/protocols/vault/rewards/main.sol";
import { FluidVaultBorrowRewards } from "../../../../contracts/protocols/vault/borrowRewards/main.sol";
import { Events } from "../../../../contracts/protocols/vault/rewards/events.sol";

import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";

import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";
import { FluidLendingFactory } from "../../../../contracts/protocols/lending/lendingFactory/main.sol";

import { IFluidReserveContract } from "../../../../contracts/reserve/interfaces/iReserveContract.sol";
import { FluidReserveContract } from "../../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../../contracts/reserve/proxy.sol";

import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { TestERC20 } from "../../testERC20.sol";
import { TestERC20Dec6 } from "../../testERC20Dec6.sol";

import { VaultFactoryBaseTest } from "../factory/vaultFactory.t.sol";

contract VaultBorrowRewardsTest is VaultFactoryBaseTest, Events {
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
    FluidVaultBorrowRewards vaultBorrowRewards;

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

        _supply(address(liquidity), mockProtocol, address(supplyToken), alice, 1e6 * 1e6);
        _supply(address(liquidity), mockProtocol, address(borrowToken), alice, 1e6 * 1e18);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(USDC, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), alice);

        reserveContractImpl = new FluidReserveContract(address(0), address(0));
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        reserveContract.initialize(auths, rebalancers, owner);
        // reserve contract proxy admin is 'admin'
        // reserve contract owner is 'owner'
        vm.prank(authUser);
        reserveContract.updateRebalancer(rebalancer, true);

        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(borrowToken),
            governance
        );

        // revert if not initiator
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__NotTheInitiator)
        );
        vm.prank(admin);
        vaultBorrowRewards.start();

        // reverts before started
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__RewardsNotStartedOrEnded
            )
        );
        vaultBorrowRewards.calculateBorrowMagnifier();

        // start rewards
        vm.warp(block.timestamp + 100);
        vaultRewardsStartTime = block.timestamp;
        vaultRewardsEndTime = block.timestamp + vaultRewardsDuration;
        vm.prank(alice);
        vaultBorrowRewards.start();

        assertEq(uint256(vaultBorrowRewards.startTime()), vaultRewardsStartTime);
        assertEq(uint256(vaultBorrowRewards.endTime()), vaultRewardsEndTime);

        // revert if already started
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AlreadyStarted)
        );
        vm.prank(alice);
        vaultBorrowRewards.start();

        vm.warp(block.timestamp + 1);

        vm.prank(admin);
        vaultFactory.setVaultAuth(address(vaultOne), address(vaultBorrowRewards), true);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(DAI, address(vaultOne), alice);

        oracleOne = MockOracle(_setDefaultVaultSettings(address(vaultOne)));

        _setOracleOnePrice(1e39);

        // updating the user borrow and supply configs so that we can change the borrow rate during testing
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(this),
            token: address(borrowToken),
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
            token: address(borrowToken),
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
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AddressZero)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
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
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AddressZero)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(0)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(borrowToken),
            governance
        );
    }

    function test_contructor_RevertIfInitiatorAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AddressZero)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            address(0), // start initiator
            address(borrowToken),
            governance
        );
    }

    function test_contructor_RevertIfLiquidityAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AddressZero)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(0)),
            2 ether, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(borrowToken),
            governance
        );
    }

    function test_contructor_RevertIfCollateralTokenAddressZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__AddressZero)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
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
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__InvalidParams)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            0, // distributing rewards amount
            vaultRewardsDuration,
            alice, // start initiator
            address(borrowToken),
            governance
        );
    }

    function test_contructor_RevertIfDurationZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__InvalidParams)
        );
        vaultBorrowRewards = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether, // distributing rewards amount
            0,
            alice, // start initiator
            address(borrowToken),
            governance
        );
    }

    function test_calculateMagnifier_AfterEndTime() public {
        vm.warp(vaultRewardsEndTime + 1);
        (uint256 calculatedMagnifier, ) = vaultBorrowRewards.calculateBorrowMagnifier();
        assertEq(calculatedMagnifier, RATE_PRECISION);
    }

    function test_rebalance_RevertIfNoRebalancer() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__Unauthorized)
        );
        vm.prank(alice);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), false);
    }

    function test_rebalance_RevertIfMagnifierNotChanged() public {
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 ether,
            1 ether,
            alice
        );
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, 10000);

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        (uint256 calculatedMagnifier, ) = vaultBorrowRewards.calculateBorrowMagnifier();

        vm.prank(rebalancer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), false);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, calculatedMagnifier);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            1000 ether,
            100 ether,
            alice
        );

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
    }

    function test_rebalance_ZeroPointFiveMagnifier() public {
        // rewardsAmount = 2 ether
        int256 tvlForZeroPointFive = 99.9 ether;

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            1 ether,
            tvlForZeroPointFive,
            alice
        );

        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );
        (uint256 calculatedMagnifierWithNonZeroBorrowRate, ) = vaultBorrowRewards.calculateBorrowMagnifier();
        uint rewardsRate_ = (vaultBorrowRewards.rewardsAmountPerYear() * FOUR_DECIMALS) /
            vaultBorrowRewards.vaultBorrowTVL();

        uint256 expectedMagnifier = (RATE_PRECISION) / 2; // 5000;
        assertApproxEqAbs(calculatedMagnifierWithNonZeroBorrowRate, expectedMagnifier, 1);
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, 10000);

        vm.expectEmit(true, true, true, false);
        emit LogUpdateMagnifier(address(vaultOne), expectedMagnifier);
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, expectedMagnifier);
    }

    function test_rebalance_ZeroPointSeventyFiveMagnifier() public {
        int256 tvlForZeroPointSeventyFive = 199 ether;

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            1 ether,
            tvlForZeroPointSeventyFive,
            alice
        );
        vm.warp(block.timestamp + vaultRewardsStartTime);

        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );

        assertEq(400, vaultBorrowRewards.getBorrowRate());
        assertEq(199000025692492028053, vaultBorrowRewards.vaultBorrowTVL()); // borrow TVL reflects the ceil-rounded borrow exchange prices
        assertEq(2000000000000000000, vaultBorrowRewards.rewardsAmountPerYear());

        (uint256 calculatedMagnifierWithNonZeroBorrowRate, ) = vaultBorrowRewards.calculateBorrowMagnifier();
        uint rewardsRate_ = (vaultBorrowRewards.rewardsAmountPerYear() * FOUR_DECIMALS) /
            vaultBorrowRewards.vaultBorrowTVL();
        assertEq(100, rewardsRate_); // rewards rate is 1%
        // magnifier at those values should be 100% - 1/4 = 75%. So instead of paying 4%, borrowers will pay 3%
        // which matches the 1% rewards target rate

        uint256 expectedMagnifier = (3 * RATE_PRECISION) / 4; // 7500;
        assertApproxEqAbs(calculatedMagnifierWithNonZeroBorrowRate, expectedMagnifier, 1);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, 10000);

        vm.expectEmit(true, true, true, false);
        emit LogUpdateMagnifier(address(vaultOne), expectedMagnifier);
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, expectedMagnifier);
    }

    function test_rebalanceAfterEndTime_NextRewardsNotQueued() public {
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, 10000);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            1000 ether,
            100 ether,
            alice
        );

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        (uint256 calculatedMagnifier, ) = vaultBorrowRewards.calculateBorrowMagnifier();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), false);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, calculatedMagnifier);

        vm.warp(block.timestamp + 365 days);
        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );
        assertEq(vaultBorrowRewards.nextDuration(), 0);
        assertEq(vaultBorrowRewards.nextRewardsAmount(), 0);
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__RewardsNotStartedOrEnded
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
    }

    function test_rebalanceAfterEndTime_NextRewardsQueued() public {
        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, 10000);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            1000 ether,
            100 ether,
            alice
        );

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        (uint256 calculatedMagnifier, ) = vaultBorrowRewards.calculateBorrowMagnifier();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), false);

        assertEq(vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier, calculatedMagnifier);

        // verifying the invalid params error
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__InvalidParams)
        );
        vaultBorrowRewards.queueNextRewards(0, 365 days);

        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__InvalidParams)
        );
        vaultBorrowRewards.queueNextRewards(2 ether, 0);

        // verifying the unauthorized error
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.VaultBorrowRewards__NotTheGovernance)
        );
        vaultBorrowRewards.queueNextRewards(2 ether, 365 days);

        // setting next rewards
        vm.prank(governance);
        vaultBorrowRewards.queueNextRewards(2 ether, 365 days);

        vm.warp(block.timestamp + 365 days);
        assertEq(vaultBorrowRewards.nextDuration(), 365 days);
        assertEq(vaultBorrowRewards.nextRewardsAmount(), 2 ether);

        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.ended(), false);
        assertEq(vaultBorrowRewards.nextDuration(), 0);
        assertEq(vaultBorrowRewards.nextRewardsAmount(), 0);

        assertEq(vaultBorrowRewards.ended(), false);
        assertEq(vaultBorrowRewards.duration(), 365 days);
        assertEq(vaultBorrowRewards.rewardsAmount(), 2 ether);
        assertEq(vaultBorrowRewards.rewardsAmountPerYear(), 2 ether);

        assertEq(vaultBorrowRewards.startTime(), uint96(block.timestamp));
        assertEq(vaultBorrowRewards.endTime(), uint96(block.timestamp + 365 days));

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
    }

    /// @notice Transitioning to queued rewards must not be rolled back when the newly computed magnifier happens to
    /// equal the currently configured one. Before the fix, rebalance() reverted after having already written the
    /// next-period state, leaving the queued rewards stuck.
    function test_rebalance_DoesNotRevertWhenTransitionedMagnifierEqualsCurrent() public {
        // small borrow TVL relative to the rewards -> rewardsDelta exceeds FOUR_DECIMALS so the magnifier
        // clamps to 0. A clamped magnifier is stable across the period, so the next period computes the
        // very same value and the equality branch is hit deterministically.
        vm.prank(alice);
        vaultOne.operate(0, 1 ether, 40 ether, alice);

        vm.warp(block.timestamp + vaultRewardsStartTime);
        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );

        (uint256 magnifier_, ) = vaultBorrowRewards.calculateBorrowMagnifier();
        assertEq(magnifier_, 0, "precondition: magnifier clamps to 0");

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
        assertEq(vaultBorrowRewards.currentBorrowMagnifier(), 0, "precondition: vault magnifier now 0");

        // queue the next period, then let the current one end
        vm.prank(governance);
        vaultBorrowRewards.queueNextRewards(2 ether, 365 days);
        vm.warp(block.timestamp + 366 days);

        // this call transitions to the queued rewards and then computes a magnifier equal to the current one.
        // Pre-fix it reverted with NewMagnifierSameAsOldMagnifier, discarding the transition.
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        // the transition must have persisted
        assertEq(vaultBorrowRewards.nextRewardsAmount(), 0, "queued rewards must be consumed");
        assertEq(vaultBorrowRewards.nextDuration(), 0, "queued duration must be consumed");
        assertEq(vaultBorrowRewards.rewardsAmount(), 2 ether, "next period rewards must be active");
        assertEq(vaultBorrowRewards.duration(), 365 days, "next period duration must be active");
        assertEq(vaultBorrowRewards.ended(), false, "rewards must not be marked ended");
        assertEq(vaultBorrowRewards.startTime(), uint40(block.timestamp), "next period must start now");
        assertEq(vaultBorrowRewards.endTime(), uint40(block.timestamp + 365 days), "next period must end in a year");
    }

    /// @notice the plain "nothing changed" revert must still fire when no transition happened
    function test_rebalance_StillRevertsWhenNoTransitionAndMagnifierUnchanged() public {
        vm.prank(alice);
        vaultOne.operate(0, 1 ether, 40 ether, alice);
        vm.warp(block.timestamp + vaultRewardsStartTime);
        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );

        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();

        // no queued rewards, period still active, magnifier unchanged -> original revert must remain
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        vaultBorrowRewards.rebalance();
    }

    // ############ scheduled start must not activate early ############

    /// @dev fresh, unstarted rewards instance so `startAt` can schedule into the future
    function _freshBorrowRewards() internal returns (FluidVaultBorrowRewards rewards_) {
        rewards_ = new FluidVaultBorrowRewards(
            IFluidReserveContract(address(reserveContract)),
            IFluidVaultT1(address(vaultOne)),
            IFluidLiquidity(address(liquidity)),
            2 ether,
            vaultRewardsDuration,
            alice,
            address(borrowToken),
            governance
        );
        vm.prank(admin);
        vaultFactory.setVaultAuth(address(vaultOne), address(rewards_), true);
    }

    function test_calculateBorrowMagnifier_NeutralBeforeScheduledStart() public {
        FluidVaultBorrowRewards rewards_ = _freshBorrowRewards();

        vm.prank(alice);
        rewards_.startAt(block.timestamp + 7 days);

        (uint256 magnifier_, bool ended_) = rewards_.calculateBorrowMagnifier();
        assertEq(magnifier_, RATE_PRECISION, "magnifier must be neutral before the scheduled start");
        assertEq(ended_, false, "not ended, just not started yet");
    }

    function test_rebalance_DoesNotActivateBeforeScheduledStartBorrow() public {
        // real borrow TVL, so without the guard `calculateBorrowMagnifier` would return a live value and apply it early
        vm.prank(alice);
        vaultOne.operate(0, 1 ether, 99.9 ether, alice);
        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );

        FluidVaultBorrowRewards rewards_ = _freshBorrowRewards();

        vm.prank(alice);
        rewards_.startAt(block.timestamp + 7 days);

        uint256 magnifierBefore_ = vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier;

        // neutral magnifier equals the vault's current one, so the rebalance is a no-op rather than an early start
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        rewards_.rebalance();

        assertEq(
            vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier,
            magnifierBefore_,
            "borrow rewards activated before their scheduled start"
        );
    }

    function test_calculateBorrowMagnifier_ReturnsVaultMagnifierBeforeScheduledStart() public {
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(12_000);

        FluidVaultBorrowRewards rewards_ = _freshBorrowRewards();

        vm.prank(alice);
        rewards_.startAt(block.timestamp + 7 days);

        (uint256 magnifier_, bool ended_) = rewards_.calculateBorrowMagnifier();
        assertEq(
            magnifier_,
            12_000,
            "pre-start magnifier must track the vault's current one, not a hardcoded neutral value"
        );
        assertEq(ended_, false);
    }

    function test_rebalance_PreservesGovernanceMagnifierUntilScheduledStartArrivesBorrow() public {
        vm.prank(alice);
        vaultOne.operate(0, 1 ether, 99.9 ether, alice);
        liquidityProxy.operate(
            vaultBorrowRewards.VAULT_DEBT_TOKEN(),
            0,
            100 ether,
            address(alice),
            address(alice),
            abi.encode(address(alice))
        );

        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(12_000);

        FluidVaultBorrowRewards rewards_ = _freshBorrowRewards();

        uint256 startTime_ = block.timestamp + 7 days;
        vm.prank(alice);
        rewards_.startAt(startTime_);

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidVaultError.selector,
                ErrorTypes.VaultBorrowRewards__NewMagnifierSameAsOldMagnifier
            )
        );
        vm.prank(rebalancer);
        rewards_.rebalance();

        assertEq(
            vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier,
            12_000,
            "pre-start rebalance must not overwrite the governance-set magnifier"
        );

        vm.warp(startTime_);
        (uint256 computedMagnifier_, ) = rewards_.calculateBorrowMagnifier();
        assertTrue(computedMagnifier_ != 12_000);

        vm.prank(rebalancer);
        rewards_.rebalance();

        assertEq(
            vaultResolver.getVaultEntireData(address(vaultOne)).configs.borrowRateMagnifier,
            computedMagnifier_,
            "rebalance must apply the computed magnifier once the scheduled start arrives"
        );
    }
}
