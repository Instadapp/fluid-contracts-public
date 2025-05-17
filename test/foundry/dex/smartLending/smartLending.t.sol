//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibString } from "solmate/src/utils/LibString.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";
import { LiquiditySlotsLink } from "../../../../contracts/libraries/liquiditySlotsLink.sol";
import { BigMathMinified } from "../../../../contracts/libraries/bigMathMinified.sol";

import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";

import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexStructs } from "../../../../contracts/protocols/dex/poolT1/coreModule/structs.sol";
import { Structs as DexAdminStructs } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { FluidContractFactory } from "../../../../contracts/deployer/main.sol";

import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";

import { MockDexCenterPrice } from "../../../../contracts/mocks/mockDexCenterPrice.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { FluidLiquidityUserModule } from "../../../../contracts/liquidity/userModule/main.sol";

import { FluidSmartLendingFactory } from "contracts/protocols/dex/smartLending/factory/main.sol";
import { FluidSmartLending, Events } from "contracts/protocols/dex/smartLending/main.sol";

contract SmartLendingTest is Test, Events {
    FluidSmartLendingFactory public smartLendingFactory;
    FluidSmartLending public smartLendingWSTETH_ETH;
    FluidSmartLending public smartLendingUSDC_USDT;

    address public constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7; // id 1
    address public constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B; // id 2

    address public constant DEX_FACTORY = 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085;

    address public constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");
    address deployer = makeAddr("deployer");

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21638485);

        smartLendingFactory = new FluidSmartLendingFactory(DEX_FACTORY, LIQUIDITY, GOVERNANCE);
        vm.prank(GOVERNANCE);
        smartLendingFactory.updateDeployer(deployer, true);

        vm.prank(GOVERNANCE);
        smartLendingFactory.setSmartLendingCreationCode(type(FluidSmartLending).creationCode);

        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH = FluidSmartLending(payable(smartLendingFactory.deploy(1)));

        vm.prank(GOVERNANCE);
        smartLendingUSDC_USDT = FluidSmartLending(payable(smartLendingFactory.deploy(2)));

        DexAdminStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new DexAdminStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = DexAdminStructs.UserSupplyConfig({
            user: address(smartLendingWSTETH_ETH),
            expandPercent: 2000,
            expandDuration: 43200,
            baseWithdrawalLimit: 1e25
        });

        vm.prank(GOVERNANCE);
        FluidDexT1Admin(DEX_WSTETH_ETH).updateUserSupplyConfigs(userSupplyConfigs_);

        deal(alice, 1e25);
        deal(WSTETH, alice, 1e25);
        vm.prank(alice);
        IERC20(WSTETH).approve(address(smartLendingWSTETH_ETH), type(uint256).max);

        deal(bob, 1e25);
        deal(WSTETH, bob, 1e25);
        vm.prank(bob);
        IERC20(WSTETH).approve(address(smartLendingWSTETH_ETH), type(uint256).max);
    }

    function test_deploy() public {
        // Check smartLendingWSTETH_ETH
        assertEq(smartLendingWSTETH_ETH.name(), "Fluid Smart Lending 1");
        assertEq(smartLendingWSTETH_ETH.symbol(), "fSL1");
        assertEq(smartLendingWSTETH_ETH.LIQUIDITY(), LIQUIDITY);
        assertEq(address(smartLendingWSTETH_ETH.DEX_FACTORY()), DEX_FACTORY);
        assertEq(address(smartLendingWSTETH_ETH.SMART_LENDING_FACTORY()), address(smartLendingFactory));
        assertEq(address(smartLendingWSTETH_ETH.DEX()), DEX_WSTETH_ETH);
        assertEq(smartLendingWSTETH_ETH.IS_NATIVE_PAIR(), true);
        assertEq(smartLendingWSTETH_ETH.TOKEN0(), WSTETH);
        assertEq(smartLendingWSTETH_ETH.TOKEN1(), NATIVE_TOKEN);

        // Check smartLendingUSDC_USDT
        assertEq(smartLendingUSDC_USDT.name(), "Fluid Smart Lending 2");
        assertEq(smartLendingUSDC_USDT.symbol(), "fSL2");
        assertEq(smartLendingUSDC_USDT.LIQUIDITY(), LIQUIDITY);
        assertEq(address(smartLendingUSDC_USDT.DEX_FACTORY()), DEX_FACTORY);
        assertEq(address(smartLendingUSDC_USDT.SMART_LENDING_FACTORY()), address(smartLendingFactory));
        assertEq(address(smartLendingUSDC_USDT.DEX()), DEX_USDC_USDT);
        assertEq(smartLendingUSDC_USDT.IS_NATIVE_PAIR(), false);
        assertEq(smartLendingUSDC_USDT.TOKEN0(), USDC);
        assertEq(smartLendingUSDC_USDT.TOKEN1(), USDT);
    }

    function test_setRebalancer() public {
        address newRebalancer = address(0x123);

        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__Unauthorized
            )
        );
        vm.prank(alice);
        smartLendingWSTETH_ETH.setRebalancer(newRebalancer);

        // Expect revert if zero address is provided
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__ZeroAddress
            )
        );
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setRebalancer(address(0));

        // Expect emit event when called by authorized user
        vm.expectEmit(true, true, true, true);
        emit LogRebalancerSet(newRebalancer);
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setRebalancer(newRebalancer);

        // Check if rebalancer is set correctly
        assertEq(smartLendingWSTETH_ETH.rebalancer(), newRebalancer);

        // callable by auth
        vm.prank(GOVERNANCE);
        smartLendingFactory.updateSmartLendingAuth(address(smartLendingWSTETH_ETH), alice, true);
        vm.prank(alice);
        smartLendingWSTETH_ETH.setRebalancer(address(1));
    }

    function test_setFeeOrReward() public {
        int256 newFeeOrReward = 1e4; // 1%
        int256 outOfRangeFeeOrReward = 1e7; // 1000%
        int256 negativeFeeOrReward = -1e4; // -1%
        int256 outOfRangeNegativeFeeOrReward = -1e7; // -1000%

        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__Unauthorized
            )
        );
        vm.prank(alice);
        smartLendingWSTETH_ETH.setFeeOrReward(newFeeOrReward);

        // Expect revert if fee or reward is out of range
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__OutOfRange
            )
        );
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(outOfRangeFeeOrReward);

        // Expect revert if negative fee or reward is out of range
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__OutOfRange
            )
        );
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(outOfRangeNegativeFeeOrReward);

        // Expect emit event when called by authorized user with valid fee or reward
        vm.expectEmit(true, true, true, true);
        emit LogFeeOrRewardSet(newFeeOrReward);
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(newFeeOrReward);

        // Check if fee or reward is set correctly
        assertEq(smartLendingWSTETH_ETH.feeOrReward(), newFeeOrReward);

        // Expect emit event when called by authorized user with valid negative fee or reward
        vm.expectEmit(true, true, true, true);
        emit LogFeeOrRewardSet(negativeFeeOrReward);
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(negativeFeeOrReward);

        // Check if negative fee or reward is set correctly
        assertEq(smartLendingWSTETH_ETH.feeOrReward(), negativeFeeOrReward);

        // callable by auth
        vm.prank(GOVERNANCE);
        smartLendingFactory.updateSmartLendingAuth(address(smartLendingWSTETH_ETH), alice, true);
        vm.prank(alice);
        smartLendingWSTETH_ETH.setFeeOrReward(1);
    }

    function test_deposit() public {
        uint256 balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        uint256 initialETH = payable(alice).balance;
        vm.assertEq(balance, 0);
        vm.prank(alice);
        uint256 depositAmount = 1e18;
        (uint256 lendingShares, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: depositAmount }(
            0,
            depositAmount,
            1,
            address(0)
        );

        balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(lendingShares, balance);
        assertEq(lendingShares, poolShares - 1); // same because exchange price is 1, except for safe rounding

        assertEq(payable(alice).balance, initialETH - depositAmount);

        vm.prank(alice);
        depositAmount = 1e18;
        (lendingShares, poolShares) = smartLendingWSTETH_ETH.deposit{ value: depositAmount }(
            depositAmount,
            depositAmount,
            1,
            address(0)
        );

        assertEq(0, smartLendingWSTETH_ETH.balanceOf(address(bob)));
        // deposit to bob
        vm.prank(alice);
        (lendingShares, poolShares) = smartLendingWSTETH_ETH.deposit{ value: depositAmount }(
            depositAmount,
            depositAmount,
            1,
            bob
        );
        balance = smartLendingWSTETH_ETH.balanceOf(address(bob));
        assertEq(lendingShares, balance);
    }

    function test_depositRevertsIfMsgValueDoesNotMatch() public {
        uint256 token0Amt = 1e18;
        uint256 token1Amt = 1e18;
        uint256 minSharesAmt = 1;

        // Expect revert if msg.value does not match the required value
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__InvalidMsgValue
            )
        );
        vm.prank(alice);
        smartLendingWSTETH_ETH.deposit{ value: token0Amt + 1 }(token0Amt, token1Amt, minSharesAmt, address(0));

        // Expect revert if msg.value does not match the required value
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__InvalidMsgValue
            )
        );
        vm.prank(alice);
        smartLendingWSTETH_ETH.deposit{ value: token1Amt - 1 }(token0Amt, token1Amt, minSharesAmt, address(0));
    }

    function test_depositPerfect() public {
        uint256 balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        uint256 initialETH = payable(alice).balance;
        vm.assertEq(balance, 0);
        vm.prank(alice);
        uint256 depositAmount = 1e18;
        (uint256 amount, uint256 token0Amt, uint256 token1Amt) = smartLendingWSTETH_ETH.depositPerfect{
            value: depositAmount
        }(1e14, 1e17, 1e17, address(0));

        balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(balance, 1e14);
        assertEq(token0Amt, 169445760000001);
        assertEq(token1Amt, 20327000001);

        assertEq(payable(alice).balance, 9999999999999979672999999); // some excess eth was sent back

        assertEq(0, smartLendingWSTETH_ETH.balanceOf(address(bob)));
        vm.prank(alice);
        // deposit to bob
        smartLendingWSTETH_ETH.depositPerfect{ value: depositAmount }(1e14, 1e17, 1e17, bob);
        assertEq(1e14, smartLendingWSTETH_ETH.balanceOf(address(bob)));
    }

    function test_withdraw() public {
        uint256 balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        vm.prank(alice);
        (uint256 lendingShares, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: 1e18 }(
            0,
            1e18,
            1,
            address(0)
        );

        balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(lendingShares, balance);

        vm.prank(alice);
        (uint256 amountBurnt, uint256 poolSharesWithdrawn) = smartLendingWSTETH_ETH.withdraw(
            0,
            1e17,
            balance,
            address(alice)
        );

        uint256 newBalance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(newBalance, balance - amountBurnt);
    }

    function test_withdrawPerfect() public {
        // bob dust position
        vm.prank(bob);
        (uint256 lendingTokens, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: 1e17 }(
            1e17,
            1e17,
            1,
            address(0)
        );

        uint256 balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        vm.prank(alice);
        (lendingTokens, poolShares) = smartLendingWSTETH_ETH.deposit{ value: 1e19 }(1e19, 1e19, 1, address(0));

        balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(lendingTokens, balance);

        vm.prank(alice);
        (uint256 amountBurnt, uint256 token0Withdrawn, uint256 token1Withdrawn) = smartLendingWSTETH_ETH
            .withdrawPerfect(balance / 2, 1, 1, address(alice));

        vm.prank(alice);
        (amountBurnt, token0Withdrawn, token1Withdrawn) = smartLendingWSTETH_ETH.withdrawPerfect(
            type(uint).max,
            1e14,
            1e14,
            address(alice)
        );

        uint256 newBalance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(newBalance, 0);
    }

    function test_withdrawPerfectInOneToken() public {
        // bob dust position
        vm.prank(bob);
        (uint256 lendingTokens, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: 1e17 }(
            1e17,
            1e17,
            1,
            address(0)
        );

        uint256 balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        vm.prank(alice);
        (lendingTokens, poolShares) = smartLendingWSTETH_ETH.deposit{ value: 1e19 }(1e19, 1e19, 1, address(0));

        balance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertEq(lendingTokens, balance);

        uint256 WSTETHbalanceBefore = IERC20(WSTETH).balanceOf(address(alice));

        vm.prank(alice);
        (uint256 amountBurnt, uint256 token0Withdrawn, uint256 token1Withdrawn) = smartLendingWSTETH_ETH
            .withdrawPerfect(balance / 2, 1, 0, address(alice));

        assertEq(token0Withdrawn, 9199486812384692999);
        assertEq(IERC20(WSTETH).balanceOf(address(alice)), WSTETHbalanceBefore + 9199486812384692999);
        assertEq(token1Withdrawn, 0);

        uint256 newBalance = smartLendingWSTETH_ETH.balanceOf(address(alice));
        assertApproxEqAbs(newBalance, balance / 2, 1);
    }

    function test_exchangePrice() public {
        int256 positiveFeeOrReward = 1e4; // 1%
        int256 negativeFeeOrReward = -1e4; // -1%

        uint184 exchangePrice = smartLendingWSTETH_ETH.exchangePrice();
        assertEq(exchangePrice, 1e18);

        // Set positive fee or reward
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(positiveFeeOrReward);

        vm.prank(alice);
        uint256 depositAmount = 1e18;
        (uint256 lendingShares, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: depositAmount }(
            0,
            depositAmount,
            1,
            address(0)
        );

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);

        // check getter method
        (uint256 updatedExchangePrice_, bool rewardsActive_) = smartLendingWSTETH_ETH.getUpdateExchangePrice();
        assertTrue(rewardsActive_);
        assertEq(updatedExchangePrice_, 1000027397260273972);

        // Trigger updateExchangePrice by calling a method with the modifier
        vm.prank(alice);
        smartLendingWSTETH_ETH.updateExchangePrice();

        // Check if exchange price increased
        assertGt(smartLendingWSTETH_ETH.exchangePrice(), exchangePrice);
        exchangePrice = smartLendingWSTETH_ETH.exchangePrice();
        assertEq(exchangePrice, 1000027397260273972);
        assertEq(smartLendingWSTETH_ETH.lastTimestamp(), block.timestamp);

        // Simulate time passing
        vm.warp(block.timestamp + 1 days);

        // Set negative fee or reward
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(negativeFeeOrReward);

        // Check if exchange price increased until update config call
        assertGt(smartLendingWSTETH_ETH.exchangePrice(), exchangePrice);
        exchangePrice = smartLendingWSTETH_ETH.exchangePrice();
        assertEq(exchangePrice, 1000054795271157815);
        assertEq(smartLendingWSTETH_ETH.lastTimestamp(), block.timestamp);

        // Simulate more time passing
        vm.warp(block.timestamp + 1 days);

        // Trigger updateExchangePrice by calling a method with the modifier
        vm.prank(alice);
        smartLendingWSTETH_ETH.updateExchangePrice();

        // Check if exchange price decreased
        assertLt(smartLendingWSTETH_ETH.exchangePrice(), exchangePrice);
        exchangePrice = smartLendingWSTETH_ETH.exchangePrice();
        assertEq(exchangePrice, 1000027396509643537);
        assertEq(smartLendingWSTETH_ETH.lastTimestamp(), block.timestamp);
    }

    function test_spell() public {
        address target = address(0x456);
        bytes memory data = abi.encodeWithSignature("someFunction()");

        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__Unauthorized
            )
        );
        vm.prank(alice);
        smartLendingWSTETH_ETH.spell(target, data);

        // Expect successful call when called by governance
        vm.prank(GOVERNANCE);
        bytes memory response = smartLendingWSTETH_ETH.spell(target, data);
        // Add any necessary assertions to check the response if needed
    }

    function test_dexCallbackRevertsIfNotCalledByDex() public {
        // Prepare data for dexCallback
        bytes memory data = abi.encodeWithSignature("dexCallback()");

        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__Unauthorized
            )
        );
        vm.prank(alice);
        (bool success, ) = address(smartLendingWSTETH_ETH).call(data);
        assertFalse(success);
    }

    function test_rebalance() public {
        vm.prank(alice);
        uint256 depositAmount = 1e18;
        (uint256 lendingShares, uint256 poolShares) = smartLendingWSTETH_ETH.deposit{ value: depositAmount }(
            0,
            depositAmount,
            1,
            address(0)
        );

        int256 positiveReward = 1e4; // 1%
        int256 negativeFee = -1e4; // -1%

        assertApproxEqAbs(smartLendingWSTETH_ETH.rebalanceDiff(), 0, 1);

        // Set positive reward
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(positiveReward);

        // Simulate time passing
        vm.warp(block.timestamp + 100 days);

        // trigger update exchange price
        smartLendingWSTETH_ETH.updateExchangePrice();

        assertApproxEqAbs(smartLendingWSTETH_ETH.rebalanceDiff(), -1358169636065775, 1);

        // trigger rebalance, rewards to be rebalanced
        vm.prank(alice);
        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__InvalidRebalancer
            )
        );
        smartLendingWSTETH_ETH.rebalance{ value: 1 }(1, 1);

        // make alice rebalancer
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setRebalancer(alice);

        vm.prank(alice);
        // Expect revert if called by unauthorized user
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingError.selector,
                FluidDexTypes.SmartLending__InvalidMsgValue
            )
        );
        smartLendingWSTETH_ETH.rebalance{ value: 0 }(1, 1);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(1358169636065775, 2302407545000001, 413065000001, false);
        smartLendingWSTETH_ETH.rebalance{ value: 1e18 }(1e18, 1e18);

        assertApproxEqAbs(smartLendingWSTETH_ETH.rebalanceDiff(), 0, 10);

        assertEq(payable(alice).balance, 9999998999999586934999999); // some excess eth was sent back

        // Set negative fee ---------------------------------------------------
        vm.prank(GOVERNANCE);
        smartLendingWSTETH_ETH.setFeeOrReward(negativeFee);

        // Simulate time passing
        vm.warp(block.timestamp + 100 days);

        // trigger update exchange price
        smartLendingWSTETH_ETH.updateExchangePrice();

        assertApproxEqAbs(smartLendingWSTETH_ETH.rebalanceDiff(), 1361890648767320, 1);

        // trigger rebalance, fees to be collected
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit LogRebalance(1361890648767320, 2309880068999999, 416295999999, true);
        smartLendingWSTETH_ETH.rebalance(1, 1);

        assertApproxEqAbs(smartLendingWSTETH_ETH.rebalanceDiff(), 0, 10);
    }
}
