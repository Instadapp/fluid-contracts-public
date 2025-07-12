//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";

import { FluidLendingStakingRewards } from "../../../contracts/protocols/lending/stakingRewards/main.sol";
import { FluidStakingRewardsResolver } from "../../../contracts/periphery/resolvers/stakingRewards/main.sol";
import { FluidLendingFactory } from "../../../contracts/protocols/lending/lendingFactory/main.sol";
import { IFluidLendingFactory } from "../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLendingResolver } from "../../../contracts/periphery/resolvers/lending/main.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { fToken } from "../../../contracts/protocols/lending/fToken/main.sol";
import { IFToken } from "../../../contracts/protocols/lending/interfaces/iFToken.sol";
import { MockOracle } from "../../../contracts/mocks/mockOracle.sol";

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { fTokenBaseSetUp } from "./fToken.t.sol";

import { Structs } from "../../../contracts/periphery/resolvers/stakingRewards/structs.sol";
import { Structs as FluidLendingResolverStructs } from "../../../contracts/periphery/resolvers/lending/structs.sol";
import { IFluidLendingResolver } from "../../../contracts/periphery/resolvers/lending/iLendingResolver.sol";

import "forge-std/console2.sol";

abstract contract FluidLendingStakingRewardsBaseTest is fTokenBaseSetUp {
    FluidLendingStakingRewards internal stakingRewards;
    FluidStakingRewardsResolver internal stakingRewardsResolver;
    IFluidLendingResolver internal lendingResolver;

    address payable internal owner;
    IERC20 internal rewardsToken;
    IERC20 internal stakingToken;
    uint40 internal rewardsDuration;

    address michal = address(0x234D);

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    uint256 deploymentTimestamp;

    function setUp() public virtual override {
        // native underlying tests must run in fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(18827888);

        super.setUp();

        // setting up staking rewards contract

        owner = payable(makeAddr("owner"));
        rewardsToken = IERC20(address(new MockERC20("Mock INST", "INST")));
        vm.prank(admin);
        factory.setFTokenCreationCode("fTokenTest", type(fToken).creationCode);
        vm.prank(admin);
        stakingToken = IERC20(factory.createToken(address(USDC), "fTokenTest", false));
        rewardsDuration = 100 days;

        stakingRewards = new FluidLendingStakingRewards(owner, rewardsToken, stakingToken, rewardsDuration);
        deploymentTimestamp = block.timestamp;

        vm.prank(alice);
        IERC20(address(USDC)).approve(address(stakingToken), type(uint256).max);
        vm.prank(bob);
        IERC20(address(USDC)).approve(address(stakingToken), type(uint256).max);
        vm.prank(michal);
        IERC20(address(USDC)).approve(address(stakingToken), type(uint256).max);

        _setUserAllowancesDefault(address(liquidity), address(admin), address(USDC), address(stakingToken));

        vm.prank(alice);
        fToken(address(stakingToken)).deposit(6e18, alice);
        vm.prank(bob);
        fToken(address(stakingToken)).deposit(6e18, bob);
        MockERC20(address(USDC)).mint(michal, 6e18);
        vm.prank(michal);
        fToken(address(stakingToken)).deposit(6e18, michal);

        vm.prank(alice);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        vm.prank(michal);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        vm.prank(owner);
        stakingToken.approve(address(stakingRewards), type(uint256).max);

        // setting up staking rewards resolver contract
        FluidLiquidityResolver liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        lendingResolver = IFluidLendingResolver(
            address(
                new FluidLendingResolver(
                    IFluidLendingFactory(address(factory)),
                    IFluidLiquidityResolver(address(liquidityResolver))
                )
            )
        );
        stakingRewardsResolver = new FluidStakingRewardsResolver(address(lendingResolver));
    }

    function _createToken(
        FluidLendingFactory lendingFactory_,
        IERC20 asset_
    ) internal virtual override returns (IERC4626) {
        vm.prank(admin);
        factory.setFTokenCreationCode("fToken", type(fToken).creationCode);
        vm.prank(admin);
        return IERC4626(lendingFactory_.createToken(address(asset_), "fToken", false));
    }
}

contract FluidLendingStakingRewardsConstructorTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_constructor_InvalidOwnerAddress() public {
        vm.expectRevert("Invalid params");
        stakingRewards = new FluidLendingStakingRewards(address(0), rewardsToken, stakingToken, rewardsDuration);
    }

    function test_constructor_InvalidRewardTokenAddress() public {
        vm.expectRevert("Invalid params");
        stakingRewards = new FluidLendingStakingRewards(owner, IERC20(address(0)), stakingToken, rewardsDuration);
    }

    function test_constructor_InvalidStakingTokenAddress() public {
        vm.expectRevert("Invalid params");
        stakingRewards = new FluidLendingStakingRewards(owner, rewardsToken, IERC20(address(0)), rewardsDuration);
    }

    function test_constructor_InvalidRewardsDurationValue() public {
        vm.expectRevert("Invalid params");
        stakingRewards = new FluidLendingStakingRewards(owner, rewardsToken, stakingToken, 0);
    }

    function test_constructor() public {
        stakingRewards = new FluidLendingStakingRewards(owner, rewardsToken, stakingToken, rewardsDuration);
        assertEq(stakingRewards.owner(), owner);
        assertEq(address(stakingRewards.rewardsToken()), address(rewardsToken));
        assertEq(address(stakingRewards.stakingToken()), address(stakingToken));
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);
    }
}

interface IERC2612 is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract FluidLendingStakingRewardsStakeTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_stake_ZeroAmount() public {
        vm.expectRevert("Cannot stake 0");
        stakingRewards.stake(0);
    }

    function test_stake() public {
        // totalSupply changedd, balance of stake changedd, user stake balance, user underlying token balance change, rate changedd, event emitted, time variables changedd ,
        vm.warp(block.timestamp + 10 days);
        uint256 aliceStakingBalanceBefore = stakingToken.balanceOf(alice);

        uint256 amount = 1e18;

        vm.prank(alice);
        stakingRewards.stake(amount);

        uint256 aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, amount);
        assertEq(stakingRewards.totalSupply(), amount);
        assertEq(stakingRewards.balanceOf(alice), amount);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), 0);

        // second stake
        vm.warp(block.timestamp + 20 days);

        amount = 2e18;

        vm.prank(alice);
        stakingRewards.stake(amount);

        aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, 1e18 + 2e18);
        assertEq(stakingRewards.totalSupply(), 1e18 + 2e18);
        assertEq(stakingRewards.balanceOf(alice), 1e18 + 2e18);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), 0);

        vm.prank(owner);
        stakingRewards.notifyRewardAmount(1500);

        // third stake
        vm.warp(block.timestamp + 10 days);

        amount = 3e18;

        vm.prank(alice);
        stakingRewards.stake(amount);

        aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.totalSupply(), 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.balanceOf(alice), 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), block.timestamp);
    }

    function test_stakeWithPermit() public {
        // totalSupply changedd, balance of stake changedd, user stake balance, user underlying token balance change, rate changedd, event emitted, time variables changedd ,
        vm.warp(block.timestamp + 10 days);
        uint256 aliceStakingBalanceBefore = stakingToken.balanceOf(alice);

        uint256 amount = 1e18;

        uint256 deadline = block.timestamp + 10 minutes;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(stakingToken)),
                alice,
                address(stakingRewards),
                amount,
                0, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );

        vm.prank(alice);
        stakingRewards.stakeWithPermit(amount, deadline, v, r, s);

        uint256 aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, amount);
        assertEq(stakingRewards.totalSupply(), amount);
        assertEq(stakingRewards.balanceOf(alice), amount);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), 0);

        // second stake
        vm.warp(block.timestamp + 20 days);

        amount = 2e18;

        deadline = block.timestamp + 10 minutes;
        (v, r, s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(stakingToken)),
                alice,
                address(stakingRewards),
                amount,
                1, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );

        vm.prank(alice);
        stakingRewards.stakeWithPermit(amount, deadline, v, r, s);

        aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, 1e18 + 2e18);
        assertEq(stakingRewards.totalSupply(), 1e18 + 2e18);
        assertEq(stakingRewards.balanceOf(alice), 1e18 + 2e18);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), 0);

        vm.prank(owner);
        stakingRewards.notifyRewardAmount(1500);

        // third stake
        vm.warp(block.timestamp + 10 days);

        amount = 3e18;

        deadline = block.timestamp + 10 minutes;
        (v, r, s) = vm.sign(
            alicePrivateKey,
            _getPermitHash(
                IERC2612(address(stakingToken)),
                alice,
                address(stakingRewards),
                amount,
                2, // Nonce is always 0 because user is a fresh address.
                deadline
            )
        );

        vm.prank(alice);
        stakingRewards.stakeWithPermit(amount, deadline, v, r, s);

        aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertEq(aliceStakingBalanceBefore - aliceStakingBalanceAfter, 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.totalSupply(), 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.balanceOf(alice), 1e18 + 2e18 + 3e18);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.userRewardPerTokenPaid(alice), 0);
        assertEq(stakingRewards.lastUpdateTime(), block.timestamp);
    }

    function _getPermitHash(
        IERC2612 token,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) private view returns (bytes32 h) {
        bytes32 domainHash = token.DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainHash, structHash));
    }
}

contract FluidLendingStakingRewardsNotifyRewardAmountTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_notifyRewardAmount_RevertUnauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        stakingRewards.notifyRewardAmount(0);
    }

    function test_notifyRewardAmount_RevertWhenProvidedRewardIsTooHigh() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);
        vm.expectRevert("Provided reward too high");
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(2e18);
    }

    function test_notifyRewardAmount() public {
        uint256 currentTime = block.timestamp;
        uint256 newTime = block.timestamp + 1 days;
        vm.warp(newTime);
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        vm.prank(alice);
        stakingRewards.stake(1e18);

        vm.expectEmit(true, true, true, true);
        emit RewardAdded(1e18);
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(1e18);
        assertEq(stakingRewards.lastUpdateTime(), newTime);
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);
        // reward per token = (current timestamp - last timestamp) * rewards rate / total supply
        // reward per token = 86400 (1day) * 0 / 1e18
        assertEq(stakingRewards.rewardPerTokenStored(), 0);
    }

    function test_notifyRewardAmount_RevertWhenNextRewardsQueued() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.warp(block.timestamp + 20 days);

        // queue next rewards
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 60 days);

        vm.warp(block.timestamp + 20 days);

        // notify reward should revert now
        vm.expectRevert("Already queued next rewards");
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);
    }
}

contract FluidLendingStakingRewardsNotifyRewardAmountWithDurationTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_notifyRewardAmountWithDuration_RevertUnauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        stakingRewards.notifyRewardAmountWithDuration(0, 0);
    }

    function test_notifyRewardAmountWithDuration_RevertCurrentRewardsNotEnded() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.warp(block.timestamp + 20 days);

        vm.expectRevert("Previous duration not ended");
        vm.prank(owner);
        stakingRewards.notifyRewardAmountWithDuration(5e17, 60 days);
    }

    function test_notifyRewardAmountWithDuration_RevertNextRewardsQueued() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        // queue next rewards
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 60 days);

        vm.warp(block.timestamp + 120 days);

        // notify reward should revert now
        vm.expectRevert("Previous duration not ended");
        vm.prank(owner);
        stakingRewards.notifyRewardAmountWithDuration(5e17, 60 days);

        vm.warp(block.timestamp + 40 days + 1);
        // cross-check after duration passed it should not revert anymore
        vm.prank(owner);
        stakingRewards.notifyRewardAmountWithDuration(5e17, 60 days);
    }

    function test_notifyRewardAmountWithDuration_RevertNewDurationZero() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.warp(block.timestamp + 120 days);

        vm.expectRevert("Invalid params");
        vm.prank(owner);
        stakingRewards.notifyRewardAmountWithDuration(5e17, 0);
    }

    function test_notifyRewardAmountWithDuration() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // stake some tokens for alice
        vm.prank(alice);
        stakingRewards.stake(1e18);
        // stake some tokens for bob
        vm.prank(bob);
        stakingRewards.stake(6e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        assertEq(stakingRewards.periodFinish(), block.timestamp + rewardsDuration);
        // expected reward rate = 5e17 at 100 days
        // rewardRate = total reward amunt / reward distribution period = 5e17 / 100 days = 5e17 / 8640000 = 57870370370
        assertEq(stakingRewards.rewardRate(), 57870370370);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 5e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.earned(alice), 0);
        assertEq(stakingRewards.earned(bob), 0);

        vm.warp(block.timestamp + 10 days);
        assertEq(stakingRewards.rewardPerTokenStored(), 0); // nobody interacted yet
        stakingRewards.updateRewards(); // should bring rewards to stored
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 7142857142857142, 5e6); // 1/10 of below 71428571428571428

        vm.warp(stakingRewards.periodFinish() + 5 days);
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428571428571428, 5e6); // 5e17 * 1e18 / 7e18 = 71428571428571428
        assertApproxEqAbs(stakingRewards.earned(alice), 71428571428571428, 5e6); // should have earned 1/7. 5e17 / 7 = 71428571428571428
        assertApproxEqAbs(stakingRewards.earned(bob), 428571428571428568, 5e6); // should have earned 6/7 -> 71428571428571428 * 6 = 428571428571428568

        vm.prank(owner);
        stakingRewards.notifyRewardAmountWithDuration(4e17, 10 days);

        assertEq(stakingRewards.periodFinish(), block.timestamp + 10 days);
        // rewardRate = total reward amunt / reward distribution period = 4e17 / 10 days = 4e17 / 864000 = 462962962962
        assertEq(stakingRewards.rewardRate(), 462962962962);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 4e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428571428571428, 5e6); // no time passed yet
        assertApproxEqAbs(stakingRewards.earned(alice), 71428571428571428, 5e6); // no time passed yet
        assertApproxEqAbs(stakingRewards.earned(bob), 428571428571428568, 5e6); // no time passed yet

        vm.warp(stakingRewards.periodFinish() + 100);
        assertEq(stakingRewards.rewardRate(), 462962962962);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 4e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), stakingRewards.periodFinish());
        assertApproxEqAbs(stakingRewards.rewardPerToken(), (71428571428571428 + 57142857142857142), 5e6); // previous + 4e17 * 1e18 / 7e18 = previous + 57142857142857142
        assertApproxEqAbs(stakingRewards.earned(alice), (71428571428571428 + 57142857142857142), 5e6); // previous + 1/7 = 57142857142857142
        assertApproxEqAbs(stakingRewards.earned(bob), (428571428571428568 + 57142857142857142 * 6), 5e6); // previous + 6/7 = 57142857142857142 * 6
    }
}

contract FluidLendingStakingRewardsQueueNextRewardAmountTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_queueNextRewardAmount_RevertUnauthorized() public {
        vm.expectRevert("UNAUTHORIZED");
        stakingRewards.queueNextRewardAmount(5e17, 60 days);
    }

    function test_queueNextRewardAmount_RevertAlreadyQueued() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        // queue next rewards
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 60 days);

        vm.expectRevert("Already queued next rewards");
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 60 days);
    }

    function test_queueNextRewardAmount_RevertAlreadyEnded() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.warp(stakingRewards.periodFinish() + 1);

        vm.expectRevert("Previous duration already ended");
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 60 days);
    }

    function test_queueNextRewardAmount_RevertNextRewardZero() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.expectRevert("Invalid params");
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(0, 60 days);
    }

    function test_queueNextRewardAmount_RevertNextDurationZero() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        vm.expectRevert("Invalid params");
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, 0);
    }

    function test_queueNextRewardAmount() public {
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);

        // stake some tokens for alice
        vm.prank(alice);
        stakingRewards.stake(1e18);
        // stake some tokens for bob
        vm.prank(bob);
        stakingRewards.stake(6e18);

        // notify reward
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(5e17);

        assertEq(stakingRewards.periodFinish(), block.timestamp + rewardsDuration);
        // expected reward rate = 5e17 at 100 days
        // rewardRate = total reward amunt / reward distribution period = 5e17 / 100 days = 5e17 / 8640000 = 57870370370
        assertEq(stakingRewards.rewardRate(), 57870370370);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 5e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertEq(stakingRewards.rewardPerToken(), 0);
        assertEq(stakingRewards.earned(alice), 0);
        assertEq(stakingRewards.earned(bob), 0);
        assertEq(stakingRewards.nextPeriodFinish(), 0);
        assertEq(stakingRewards.nextRewardRate(), 0);
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);

        vm.warp(block.timestamp + 10 days);
        assertEq(stakingRewards.rewardPerTokenStored(), 0); // nobody interacted yet
        stakingRewards.updateRewards(); // should bring rewards to stored
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 7142857142857142, 5e6); // 1/10 of below at periodFinish
        assertEq(stakingRewards.earned(alice), 7142857142811428); // ~1/10 of below at periodFinish
        assertEq(stakingRewards.earned(bob), 42857142856868568); // ~1/10 of below at periodFinish

        // --------------------- queue next rewards ----------------------
        uint40 nextRewardsDuration_ = 60 days;
        vm.prank(owner);
        stakingRewards.queueNextRewardAmount(5e17, nextRewardsDuration_);

        assertEq(stakingRewards.nextRewards(), 5e17);
        assertEq(stakingRewards.nextRewardsDuration(), nextRewardsDuration_);

        assertEq(stakingRewards.periodFinish(), block.timestamp - 10 days + rewardsDuration);
        assertEq(stakingRewards.rewardRate(), 57870370370);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 5e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 7142857142857142, 5e6); // 1/10 of below at periodFinish
        assertEq(stakingRewards.earned(alice), 7142857142811428); // ~1/10 of below at periodFinish
        assertEq(stakingRewards.earned(bob), 42857142856868568); // ~1/10 of below at periodFinish
        assertEq(stakingRewards.nextPeriodFinish(), stakingRewards.periodFinish() + nextRewardsDuration_);
        // rewardRate = total reward amunt / reward distribution period = 5e17 / 60 days = 5e17 / 5184000 = 96450617283
        assertEq(stakingRewards.nextRewardRate(), 96450617283);
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);

        // --------------------- warp to full amount - 1 second (-1 * rewardRate) -------------------------------
        vm.warp(stakingRewards.periodFinish() - 1);
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428563161375661, 5e6); // (5e17 - 57870370370) * 1e18 / 7e18 = 71428563161375661
        assertApproxEqAbs(stakingRewards.earned(alice), 71428563161375661, 5e6); // should have earned 1/7. (5e17 - 57870370370) / 7 = 71428563161375661
        assertApproxEqAbs(stakingRewards.earned(bob), 428571378968253966, 5e6); // should have earned 6/7 -> 71428563161375661 * 6 = 428571378968253966

        // --------------------- unstake some tokens for bob ---------------------
        vm.warp(stakingRewards.periodFinish());
        vm.prank(bob);
        stakingRewards.withdraw(3e18); // new total for bob 3e18

        assertEq(stakingRewards.nextRewards(), 5e17);
        assertEq(stakingRewards.nextRewardsDuration(), nextRewardsDuration_);

        // --------------------- warp to half (30 days) in, with no write interaction happened ---------------------
        vm.warp(block.timestamp + 30 days);
        assertEq(stakingRewards.periodFinish(), block.timestamp + 30 days);

        assertEq(stakingRewards.rewardRate(), 96450617283); // must be queued next reward rate
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 5e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);

        // previous rewards at periodFinish when bob unstaked = 5e17 * 1e18 / 7e18 = 71428571428571428
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 71428571428571428, 5e6); // unchanged

        // previous rewards at periodFinish = 5e17 * 1e18 / 7e18 = 71428571428571428
        // next rewards at half time (30 days) passed = 5e17 * 1e18 / 4e18 / 2 = 62500000000000000
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428571428571428 + 62500000000000000, 5e6);

        assertApproxEqAbs(stakingRewards.earned(alice), 71428571428571428 + 62500000000000000, 5e6); // prev + 1/4 of half of next rewards
        assertApproxEqAbs(stakingRewards.earned(bob), 428571428571428568 + 62500000000000000 * 3, 5e6); // prev + 3/4 of half of next rewards

        // no storage write so next related view methods return next period data still
        assertEq(stakingRewards.nextPeriodFinish(), stakingRewards.periodFinish());
        // rewardRate = total reward amunt / reward distribution period = 5e17 / 60 days = 5e17 / 5184000 = 96450617283
        assertEq(stakingRewards.nextRewardRate(), 96450617283);
        assertEq(stakingRewards.rewardsDuration(), nextRewardsDuration_);
        assertEq(stakingRewards.nextRewards(), 5e17);
        assertEq(stakingRewards.nextRewardsDuration(), nextRewardsDuration_);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);

        stakingRewards.updateRewards(); // should bring rewards to stored, automatically transitioning to next rewards
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 71428571428571428 + 62500000000000000, 5e6); // rewardPerToken() 1 above
        // next rewards related vars should be updated
        assertEq(stakingRewards.nextRewardRate(), 0);
        assertEq(stakingRewards.nextRewards(), 0);
        assertEq(stakingRewards.nextRewardsDuration(), 0);
        assertEq(stakingRewards.nextPeriodFinish(), 0);

        // other view methods should still be the same
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428571428571428 + 62500000000000000, 5e6);
        assertEq(stakingRewards.periodFinish(), block.timestamp + 30 days);
        assertEq(stakingRewards.rewardsDuration(), nextRewardsDuration_);
        assertEq(stakingRewards.lastTimeRewardApplicable(), block.timestamp);

        // --------------------- warp to end ---------------------
        vm.warp(stakingRewards.periodFinish() + 100);
        assertEq(stakingRewards.rewardRate(), 96450617283);
        assertApproxEqAbs(stakingRewards.getRewardForDuration(), 5e17, 1e7);
        assertEq(stakingRewards.lastTimeRewardApplicable(), stakingRewards.periodFinish());
        assertApproxEqAbs(stakingRewards.rewardPerToken(), 71428571428571428 + 125000000000000000, 5e6); // previous + 125000000000000000
        assertApproxEqAbs(stakingRewards.earned(alice), 71428571428571428 + 125000000000000000, 5e6); // previous + 1/4
        assertApproxEqAbs(stakingRewards.earned(bob), 428571428571428568 + 125000000000000000 * 3, 7e6); // previous + 3/4

        assertEq(stakingRewards.nextRewardRate(), 0);
        assertEq(stakingRewards.nextRewards(), 0);
        assertEq(stakingRewards.nextRewardsDuration(), 0);
        assertEq(stakingRewards.nextPeriodFinish(), 0);

        stakingRewards.updateRewards(); // should bring rewards to stored, automatically transitioning to next rewards
        assertApproxEqAbs(stakingRewards.rewardPerTokenStored(), 71428571428571428 + 125000000000000000, 5e6); // rewardPerToken() 1 above
    }
}

contract FluidLendingStakingRewardsGeneralTest is FluidLendingStakingRewardsBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    // check when no tokens are sent but we update variables TODO
    function test_general() public {
        _assertFTokenStakingRewardsEntireData(
            0,
            0,
            0,
            0,
            0,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );

        uint256 lastNotifyTimestamp = block.timestamp;
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 1e18);
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(1e18);
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(1e18);

        // rewardRate = total reward amunt / reward distribution period = 1e18 / 100 days = 1e18 / 8640000 = 115740740740
        _assertFTokenStakingRewardsEntireData(
            0,
            uint256(115740740740 * uint256(rewardsDuration)),
            0,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            115740740740,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), 0, 0, 0, type(uint256).max);

        vm.prank(alice);
        stakingRewards.stake(1e18);

        assertEq(stakingRewards.lastUpdateTime(), block.timestamp);
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);
        // reward per token = (current timestamp - last timestamp) * rewards rate / total supply
        // reward per token =  0 / 1e18
        assertEq(stakingRewards.rewardPerTokenStored(), 0);

        vm.prank(bob);
        stakingRewards.stake(2e18);

        assertEq(stakingRewards.lastUpdateTime(), block.timestamp);
        assertEq(stakingRewards.rewardsDuration(), rewardsDuration);
        // reward per token = (current timestamp - last timestamp) * rewards rate / total supply
        // reward per token = 0 / 1e18
        assertEq(stakingRewards.rewardPerTokenStored(), 0);
        _assertFTokenStakingRewardsEntireData(
            0,
            uint256(115740740740 * uint256(rewardsDuration)),
            3e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            115740740740,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), 0, 1e18, 1e18, type(uint256).max);
        _assertUserRewardsData(bob, address(stakingToken), 0, 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(michal, address(stakingToken), 0, 0, 0, type(uint256).max);
        _assertAllUsersPositions();

        vm.warp(block.timestamp + 25 days); //25% of whole period

        // alice shares  = 33% (1e18 from reward token total supply 1e18)
        // rewards tokens = 1e18
        // 25% * 100 days = 25 days

        // alice reward tokens after 25% of whole period:
        // (alice stake) / (total supply) * notified reward * 25% (25% of reward duration)
        // 1e18 / 3e18 * 1e18 * 0.25 = 83333333333333333.3333333333333333333333333333333333333333333
        _exitAndAssertStAndRwrdTokenBalance(alice, 1e18, 83333333332800000);

        // rewardRate = 115740740740

        // reward per token = stored + (current timestamp - last timestamp) * rewards rate / total supply
        // reward per token = 83333333333333333 + 0 *  115740740740 / 1e18 = 83333333333333333
        _assertFTokenStakingRewardsEntireData(
            83333333332800000,
            uint256(115740740740 * uint256(rewardsDuration)),
            2e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            115740740740,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), stakingRewards.earned(alice), 0, 0, type(uint256).max);
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(michal, address(stakingToken), stakingRewards.earned(michal), 0, 0, type(uint256).max);
        _assertAllUsersPositions();

        vm.prank(michal);
        stakingRewards.stake(4e18);

        vm.warp(block.timestamp + 25 days); //next 25 days which is 50 days forward and its 50% of whole period

        // reward per token = 83333333333333333 + 25 days *  115740740740 / 1e18 = 83333333333333333
        // reward per token = 83333333333333333 + 2160000 *  115740740740 * 1e18 / 6e18 = 83333333333333333
        // reward per token = 83333333333333333 + 41666666666400000 = 124999999999733333
        _assertFTokenStakingRewardsEntireData(
            124999999999200000,
            uint256(115740740740 * uint256(rewardsDuration)),
            6e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            115740740740,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), stakingRewards.earned(alice), 0, 0, type(uint256).max);
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(
            michal,
            address(stakingToken),
            stakingRewards.earned(michal),
            4e18,
            4e18,
            type(uint256).max
        );
        _assertAllUsersPositions();

        // new total supply should be 2e18 (bob's) + 4e18 (michal's)
        // bob reward tokens after 50% of whole period:
        // (bob stake) / (total supply) * notified reward * 25% (25% of reward duration)
        // 2e18 / 3e18 * 1e18 * 0.25 = 166666666666666666
        // calculation of reward tokens amount between 25-50% of reward duration:
        // 2e18 / 6e18 * 1e18 * 0.25 = 83333333333333333
        _getRewardAndAssertStAndRwrdTokenBalance(bob, 0, 249999999998400000); // 83333333333333333 + 166666666666666666 = 249999999999999999

        vm.warp(block.timestamp + 20 days); //next 20 days which is 70 days forward and its 70% of whole period

        // reward per token = 124999999999200000 + 20 days *  115740740740 * 1e18 / 6e18
        // reward per token = 124999999999200000 + 1728000 *  115740740740 * 1e18 / 6e18 = 158333333332320000
        _assertFTokenStakingRewardsEntireData(
            158333333332320000,
            uint256(115740740740 * uint256(rewardsDuration)),
            6e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            115740740740,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), stakingRewards.earned(alice), 0, 0, type(uint256).max);
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(
            michal,
            address(stakingToken),
            stakingRewards.earned(michal),
            4e18,
            4e18,
            type(uint256).max
        );
        _assertAllUsersPositions();

        lastNotifyTimestamp = block.timestamp;
        MockERC20(address(rewardsToken)).mint(address(stakingRewards), 4e18);
        vm.prank(owner);
        stakingRewards.notifyRewardAmount(4e18); // add next rewards (it restarts rewards from that point on, over the same reward duration)

        // because 70% of previous time passed and before it was 1e18 of rewards so 30% of it remained which is 0.3e18 = 3e17
        // rewardRate = total reward amunt / reward distribution period = (4e18 + 3e17) / 100 days = (4e18 + 3e17) / 8640000 = 497685185185.185185185185185185185185185185185185185185185185 (~497685185184)

        vm.warp(block.timestamp + 10 days); //next 10 days which is 10 days forward and its 10% of new rewards duration

        // reward per token = 158333333332320000 + 10 days *  115740740740 * 1e18 / 6e18
        // reward per token = 158333333332320000 + 864000 *  497685185184 * 1e18 / 6e18 = 224999999998848000 (~229999999998816000)
        _assertFTokenStakingRewardsEntireData(
            229999999998816000,
            uint256(497685185184 * uint256(rewardsDuration)),
            6e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            497685185184,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(alice, address(stakingToken), stakingRewards.earned(alice), 0, 0, type(uint256).max);
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(
            michal,
            address(stakingToken),
            stakingRewards.earned(michal),
            4e18,
            4e18,
            type(uint256).max
        );
        _assertAllUsersPositions();

        vm.prank(alice);
        stakingRewards.stake(2e18);

        vm.warp(block.timestamp + 10 days); //next 10 days which is 20 days forward and its 20% of new rewards duration

        // reward per token = 229999999998816000 + 10 days *  115740740740 * 1e18 / 8e18
        // reward per token = 229999999998816000 + 864000 *  497685185184 * 1e18 / 8e18 = 283749999998688000 (~283749999998688000)
        _assertFTokenStakingRewardsEntireData(
            283749999998688000,
            uint256(497685185184 * uint256(rewardsDuration)),
            8e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            497685185184,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );
        _assertUserRewardsData(
            alice,
            address(stakingToken),
            stakingRewards.earned(alice),
            2e18,
            2e18,
            type(uint256).max
        );
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(
            michal,
            address(stakingToken),
            stakingRewards.earned(michal),
            4e18,
            4e18,
            type(uint256).max
        );
        _assertAllUsersPositions();

        // michal gets reward
        // (michal stake) / (total supply) * notified reward * time span
        // calculation of reward tokens amount between 25-50% of reward duration:
        // 4e18 / 6e18 * 1e18 * 0.25 = 166666666666666666
        // calculation of reward tokens amount between 50-70% of reward duration:
        // 4e18 / 6e18 * 1e18 * 0.20 = 133333333333333333
        // here there is new notify reward (4e18) and it restars reward duration
        // calculation of reward tokens amount between 0-10% of reward duration:
        // 4e18 / 6e18 * 43e17 * 0.10 = 286666666666666666
        // calculation of reward tokens amount between 10-20% of reward duration:
        // 4e18 / 8e18 * 43e17 * 0.10 = 215000000000000000

        // rwrd token balance = 166666666666666666 + 133333333333333333 + 286666666666666666 + 215000000000000000 = 801666666666666665
        _getRewardAndAssertStAndRwrdTokenBalance(michal, 0, 801666666663552000); // ~801666666666666665

        vm.warp(block.timestamp + 20 days); //next 20 days which is 110 days forward and its 110% of whole period bit rewards should be calculated to 100%

        // reward per token = 283749999998688000 + 20 days *  115740740740 * 1e18 / 8e18
        // reward per token = 283749999998688000 + 1728000 *  497685185184 * 1e18 / 8e18 = 391249999998432000 (~391249999998432000)
        _assertFTokenStakingRewardsEntireData(
            391249999998432000,
            uint256(497685185184 * uint256(rewardsDuration)),
            8e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            497685185184,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );

        // reward per token = 158333333332320000 + 20 days *  115740740740 * 1e18 / 6e18
        // reward per token = 158333333332320000 + 1728000 *  115740740740 * 1e18 / 6e18 = 191666666665440000
        // _assertFTokenStakingRewardsEntireData(191666666665440000, 115740740740 * rewardsDuration, 6e18, lastNotifyTimestamp + rewardsDuration, 115740740740, rewardsDuration,address(rewardsToken),address(stakingToken));

        // (michal stake) / (total supply) * notified reward * time span
        // calculation of reward tokens amount between 10-20% (where we calculate 90%-100%) of reward duration:
        // 4e18 / 8e18 * 43e17 * 0.20 = 430000000000000000
        _exitAndAssertStAndRwrdTokenBalance(michal, 4e18, 429999999998976000); // ~430000000000000000
        _assertUserRewardsData(
            alice,
            address(stakingToken),
            stakingRewards.earned(alice),
            2e18,
            2e18,
            type(uint256).max
        );
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 2e18, 2e18, type(uint256).max);
        _assertUserRewardsData(michal, address(stakingToken), stakingRewards.earned(michal), 0, 0, type(uint256).max);
        _assertAllUsersPositions();

        vm.warp(block.timestamp + 80 days); //next 80 days which passes whole period. Rewards should be calculated to 100% thats why we take only 60 days to have 100% of reward duration
        // bob exits
        // reward per token = 391249999998432000 + 60 days *  115740740740 * 1e18 / 4e18
        // reward per token = 391249999998432000 + 5184000 *  497685185184 * 1e18 / 4e18 = 1036249999996896000 (~1036249999996896000)
        _assertFTokenStakingRewardsEntireData(
            1036249999996896000,
            uint256(497685185184 * uint256(rewardsDuration)),
            4e18,
            uint256(lastNotifyTimestamp) + uint256(rewardsDuration),
            497685185184,
            rewardsDuration,
            address(rewardsToken),
            address(stakingToken)
        );

        // calculation of reward tokens amount between 50-70% of first reward notification duration:
        // 2e18 / 6e18 * 1e18 * 0.20 = 66666666666666666
        // here there is new notify reward (4e18) and it restars reward duration
        // calculation of reward tokens amount between 0-10% of second reward notification duration:
        // 2e18 / 6e18 * 43e17 * 0.10 = 143333333333333333
        // calculation of reward tokens amount between 10-20% of second reward notification duration:
        // 2e18 / 8e18 * 43e17 * 0.10 = 107500000000000000
        // calculation of reward tokens amount between 20-40% of second reward notification duration:
        // 2e18 / 8e18 * 43e17 * 0.20 = 215000000000000000
        // michal's exit
        // calculation of reward tokens amount between 40-120% of second reward notification duration:
        // 2e18 / 4e18 * 43e17 * 0.60 = 1290000000000000000
        //70 days for first notified reward
        //120 days for second notified reward
        assertEq(block.timestamp, deploymentTimestamp + 190 days); // 2287499999999999998
        _exitAndAssertStAndRwrdTokenBalance(bob, 2e18, 1822499999995392000);

        _assertUserRewardsData(
            alice,
            address(stakingToken),
            stakingRewards.earned(alice),
            2e18,
            2e18,
            type(uint256).max
        );
        _assertUserRewardsData(bob, address(stakingToken), stakingRewards.earned(bob), 0, 0, type(uint256).max);
        _assertUserRewardsData(michal, address(stakingToken), stakingRewards.earned(michal), 0, 0, type(uint256).max);
        _assertAllUsersPositions();
    }

    function _exitAndAssertStAndRwrdTokenBalance(
        address user,
        uint stTokenBalanceChange,
        uint rwrdTokenBalanceChange
    ) internal {
        uint256 userStTokenBalanceBefore = stakingToken.balanceOf(user);
        uint256 userRwrdTokenBalanceBefore = rewardsToken.balanceOf(user);
        vm.prank(user);
        stakingRewards.exit();
        uint256 userStTokenBalanceAfter = stakingToken.balanceOf(user);
        uint256 userRwrdTokenBalanceAfter = rewardsToken.balanceOf(user);

        assertEq(userStTokenBalanceAfter - userStTokenBalanceBefore, stTokenBalanceChange);
        assertEq(userRwrdTokenBalanceAfter - userRwrdTokenBalanceBefore, rwrdTokenBalanceChange);
    }

    function _getRewardAndAssertStAndRwrdTokenBalance(
        address user,
        uint stTokenBalanceChange,
        uint rwrdTokenBalanceChange
    ) internal {
        uint256 userStTokenBalanceBefore = stakingToken.balanceOf(user);
        uint256 userRwrdTokenBalanceBefore = rewardsToken.balanceOf(user);
        vm.prank(user);
        stakingRewards.getReward();
        uint256 userStTokenBalanceAfter = stakingToken.balanceOf(user);
        uint256 userRwrdTokenBalanceAfter = rewardsToken.balanceOf(user);

        assertEq(userStTokenBalanceAfter - userStTokenBalanceBefore, stTokenBalanceChange);
        assertEq(userRwrdTokenBalanceAfter - userRwrdTokenBalanceBefore, rwrdTokenBalanceChange);
    }

    function _assertFTokenStakingRewardsEntireData(
        uint rewardPerToken,
        uint getRewardForDuration,
        uint totalSupply,
        uint periodFinish,
        uint rewardRate,
        uint rewardsDuration,
        address rewardsToken,
        address fToken
    ) internal {
        Structs.FTokenStakingRewardsDetails memory details = stakingRewardsResolver.getFTokenStakingRewardsEntireData(
            address(stakingRewards)
        );
        assertEq(details.rewardPerToken, rewardPerToken);
        assertEq(details.getRewardForDuration, getRewardForDuration);
        assertEq(details.totalSupply, totalSupply);
        assertEq(details.periodFinish, periodFinish);
        assertEq(details.rewardRate, rewardRate);
        assertEq(details.rewardsDuration, rewardsDuration);
        assertEq(details.rewardsToken, rewardsToken);
        assertEq(details.fToken, fToken);

        address[] memory rewards = new address[](1);
        rewards[0] = address(stakingRewards);
        Structs.FTokenStakingRewardsDetails[] memory detailss = stakingRewardsResolver
            .getFTokensStakingRewardsEntireData(rewards);
        assertEq(detailss[0].rewardPerToken, rewardPerToken);
        assertEq(detailss[0].getRewardForDuration, getRewardForDuration);
        assertEq(detailss[0].totalSupply, totalSupply);
        assertEq(detailss[0].periodFinish, periodFinish);
        assertEq(detailss[0].rewardRate, rewardRate);
        assertEq(detailss[0].rewardsDuration, rewardsDuration);
        assertEq(detailss[0].rewardsToken, rewardsToken);
        assertEq(detailss[0].fToken, fToken);
    }

    function _assertUserRewardsData(
        address user,
        address fToken,
        uint earned,
        uint fTokenShares,
        uint underlyingAssets,
        uint ftokenAllowance
    ) internal {
        FluidLendingResolverStructs.FTokenDetails memory fTokenDetails_ = lendingResolver.getFTokenDetails(
            IFToken(fToken)
        );

        // getUserRewardsData function
        Structs.UserRewardDetails memory userRewardDetails = stakingRewardsResolver.getUserRewardsData(
            user,
            address(stakingRewards),
            fTokenDetails_
        );
        assertEq(userRewardDetails.earned, earned);
        assertEq(userRewardDetails.fTokenShares, fTokenShares);
        assertEq(userRewardDetails.underlyingAssets, underlyingAssets);
        assertEq(userRewardDetails.ftokenAllowance, ftokenAllowance);

        // getUserAllRewardsData function
        address[] memory rewards = new address[](1);
        rewards[0] = address(stakingRewards);
        FluidLendingResolverStructs.FTokenDetails[]
            memory fTokensDetails_ = new FluidLendingResolverStructs.FTokenDetails[](1);
        fTokensDetails_[0] = fTokenDetails_;
        Structs.UserRewardDetails[] memory userRewardsDetails = stakingRewardsResolver.getUserAllRewardsData(
            user,
            rewards,
            fTokensDetails_
        );
        assertEq(userRewardsDetails[0].earned, earned);
        assertEq(userRewardsDetails[0].fTokenShares, fTokenShares);
        assertEq(userRewardsDetails[0].underlyingAssets, underlyingAssets);
        assertEq(userRewardsDetails[0].ftokenAllowance, ftokenAllowance);
    }

    function _assertAllUsersPositions() internal {
        _assertUserPositions(alice);
        _assertUserPositions(bob);
        _assertUserPositions(michal);
    }

    function _assertUserPositions(address user) internal {
        address[] memory rewards = new address[](1);
        rewards[0] = address(stakingRewards);
        FluidLendingResolverStructs.FTokenDetailsUserPosition[] memory usersEntireData = lendingResolver
            .getUserPositions(user);

        FluidStakingRewardsResolver.underlyingTokenToRewardsMap[]
            memory underlyingTokenToRewardMap_ = new FluidStakingRewardsResolver.underlyingTokenToRewardsMap[](1);
        underlyingTokenToRewardMap_[0] = FluidStakingRewardsResolver.underlyingTokenToRewardsMap({
            underlyingToken: address(USDC),
            rewardContract: address(stakingRewards)
        });
        FluidStakingRewardsResolver.UserFTokenRewardsEntireData[] memory userRewardsEntireData = stakingRewardsResolver
            .getUserPositions(user, underlyingTokenToRewardMap_);
        _compareFTokenDetails(userRewardsEntireData[0].fTokenDetails, usersEntireData[0].fTokenDetails);
        _compareUserPositions(userRewardsEntireData[0].userPosition, usersEntireData[0].userPosition);
        FluidStakingRewardsResolver.FTokenStakingRewardsDetails
            memory fTokenStakingRewardsDetails = stakingRewardsResolver.getFTokenStakingRewardsEntireData(
                address(stakingRewards)
            );
        _compareFTokenRewardsDetails(userRewardsEntireData[0].fTokenRewardsDetails, fTokenStakingRewardsDetails);
        _compareUserRewardData(
            userRewardsEntireData[0].userRewardsDetails,
            stakingRewardsResolver.getUserRewardsData(user, address(stakingRewards), usersEntireData[0].fTokenDetails)
        );
    }

    function _compareFTokenDetails(
        FluidLendingResolverStructs.FTokenDetails memory actualFTokenDetails,
        FluidLendingResolverStructs.FTokenDetails memory expectedFTokenDetails
    ) public {
        assertEq(actualFTokenDetails.tokenAddress, expectedFTokenDetails.tokenAddress);
        assertEq(actualFTokenDetails.eip2612Deposits, expectedFTokenDetails.eip2612Deposits);
        assertEq(actualFTokenDetails.isNativeUnderlying, expectedFTokenDetails.isNativeUnderlying);
        assertEq(actualFTokenDetails.name, expectedFTokenDetails.name);
        assertEq(actualFTokenDetails.symbol, expectedFTokenDetails.symbol);
        assertEq(actualFTokenDetails.decimals, expectedFTokenDetails.decimals);
        assertEq(actualFTokenDetails.asset, expectedFTokenDetails.asset);
        assertEq(actualFTokenDetails.totalAssets, expectedFTokenDetails.totalAssets);
        assertEq(actualFTokenDetails.totalSupply, expectedFTokenDetails.totalSupply);
        assertEq(actualFTokenDetails.convertToShares, expectedFTokenDetails.convertToShares);
        assertEq(actualFTokenDetails.convertToAssets, expectedFTokenDetails.convertToAssets);
        assertEq(actualFTokenDetails.rewardsRate, expectedFTokenDetails.rewardsRate);
        assertEq(actualFTokenDetails.supplyRate, expectedFTokenDetails.supplyRate);
        assertEq(actualFTokenDetails.rebalanceDifference, expectedFTokenDetails.rebalanceDifference);
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.modeWithInterest,
            expectedFTokenDetails.liquidityUserSupplyData.modeWithInterest
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.supply,
            expectedFTokenDetails.liquidityUserSupplyData.supply
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.withdrawalLimit,
            expectedFTokenDetails.liquidityUserSupplyData.withdrawalLimit
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.lastUpdateTimestamp,
            expectedFTokenDetails.liquidityUserSupplyData.lastUpdateTimestamp
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.expandPercent,
            expectedFTokenDetails.liquidityUserSupplyData.expandPercent
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.expandDuration,
            expectedFTokenDetails.liquidityUserSupplyData.expandDuration
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.baseWithdrawalLimit,
            expectedFTokenDetails.liquidityUserSupplyData.baseWithdrawalLimit
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.withdrawableUntilLimit,
            expectedFTokenDetails.liquidityUserSupplyData.withdrawableUntilLimit
        );
        assertEq(
            actualFTokenDetails.liquidityUserSupplyData.withdrawable,
            expectedFTokenDetails.liquidityUserSupplyData.withdrawable
        );
    }

    function _compareUserPositions(
        FluidLendingResolverStructs.UserPosition memory actualUserPosition,
        FluidLendingResolverStructs.UserPosition memory expectedUserPosition
    ) public {
        assertEq(actualUserPosition.fTokenShares, expectedUserPosition.fTokenShares);
        assertEq(actualUserPosition.underlyingAssets, expectedUserPosition.underlyingAssets);
        assertEq(actualUserPosition.underlyingBalance, expectedUserPosition.underlyingBalance);
        assertEq(actualUserPosition.allowance, expectedUserPosition.allowance);
    }

    function _compareFTokenRewardsDetails(
        FluidStakingRewardsResolver.FTokenStakingRewardsDetails memory actualFTokenRewardsDetails,
        FluidStakingRewardsResolver.FTokenStakingRewardsDetails memory expectedFTokenRewardsDetails
    ) public {
        assertEq(actualFTokenRewardsDetails.rewardPerToken, expectedFTokenRewardsDetails.rewardPerToken);
        assertEq(actualFTokenRewardsDetails.getRewardForDuration, expectedFTokenRewardsDetails.getRewardForDuration);
        assertEq(actualFTokenRewardsDetails.totalSupply, expectedFTokenRewardsDetails.totalSupply);
        assertEq(actualFTokenRewardsDetails.periodFinish, expectedFTokenRewardsDetails.periodFinish);
        assertEq(actualFTokenRewardsDetails.rewardRate, expectedFTokenRewardsDetails.rewardRate);
        assertEq(actualFTokenRewardsDetails.rewardsDuration, expectedFTokenRewardsDetails.rewardsDuration);
        assertEq(actualFTokenRewardsDetails.rewardsToken, expectedFTokenRewardsDetails.rewardsToken);
        assertEq(actualFTokenRewardsDetails.fToken, expectedFTokenRewardsDetails.fToken);
    }

    function _compareUserRewardData(
        FluidStakingRewardsResolver.UserRewardDetails memory actualUserRewardDetails,
        FluidStakingRewardsResolver.UserRewardDetails memory expectedUserRewardDetails
    ) public {
        assertEq(actualUserRewardDetails.earned, expectedUserRewardDetails.earned);
        assertEq(actualUserRewardDetails.fTokenShares, expectedUserRewardDetails.fTokenShares);
        assertEq(actualUserRewardDetails.underlyingAssets, expectedUserRewardDetails.underlyingAssets);
        assertEq(actualUserRewardDetails.ftokenAllowance, expectedUserRewardDetails.ftokenAllowance);
    }
}
