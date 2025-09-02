//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { BigMathMinified } from "contracts/libraries/bigMathMinified.sol";
import { FluidLimitsAuth } from "contracts/config/limitsAuth/main.sol";
import { Error } from "contracts/config/error.sol";
import { ErrorTypes } from "contracts/config/errorTypes.sol";
import { IFluidLiquidity } from "contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "contracts/liquidity/adminModule/structs.sol";
import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";

/// To test run:  forge test -vvv --match-path test/foundry/config/limitsAuth.t.sol
contract LimitsAuthTest is LiquidityBaseTest {
    using BigMathMinified for uint256;

    address public immutable TEAM_MULTISIG_MAINNET = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address public immutable TEAM_MULTISIG_MAINNET2 = 0x1e2e1aeD876f67Fe4Fd54090FD7B8F57Ce234219;
    FluidLimitsAuth handler;
    address internal multisig = TEAM_MULTISIG_MAINNET;

    IFluidLiquidity liquidityProxy;

    function setUp() public virtual override {
        super.setUp();
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19876269);

        liquidityProxy = IFluidLiquidity(address(liquidity));

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
            baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
            maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING
        });
        vm.prank(admin);
        liquidityProxy.updateUserBorrowConfigs(userBorrowConfigs_);

        _deployNewHandler();
    }

    function test_deploy_revertOnInvalidParams() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        new FluidLimitsAuth(address(0));
    }

    function _deployNewHandler() internal {
        handler = new FluidLimitsAuth(address(liquidityProxy));

        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(admin);
        liquidityProxy.updateAuths(updateAuthsParams);
    }
}

contract LimitsAuthSetWithdrawBaseLimitTest is LimitsAuthTest {
    using BigMathMinified for uint256;

    function test_revertIfNotMultisig() public {
        address user = makeAddr("user");
        uint256 baseLimit = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        handler.setUserWithdrawLimit(user, address(USDC), baseLimit, false);

        // expect revert unauthorized for setUserWithdrawLimit
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        handler.setWithdrawalLimit(user, address(USDC), 1000);
    }

    function test_revertIfUserNotDefinedYet() public {
        address user = makeAddr("user");
        uint256 baseLimit = 1000 ether;

        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__UserNotDefinedYet)
        );
        handler.setUserWithdrawLimit(user, address(USDC), baseLimit, false);
    }

    function test_revertIfBaseLimit0() public {
        address user = makeAddr("user");
        uint256 baseLimit = 0;

        vm.prank(TEAM_MULTISIG_MAINNET2);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        handler.setUserWithdrawLimit(user, address(USDC), baseLimit, false);
    }

    function test_NOTRevertIfExceedAllowedPercentageChangeFlagTrue() public {
        // First set up a user with initial config
        _supply(mockProtocol, address(USDC), alice, 1000 ether);

        uint256 newBaseLimit = DEFAULT_BASE_WITHDRAWAL_LIMIT + (DEFAULT_BASE_WITHDRAWAL_LIMIT * 25) / 100; // This is more than 25% increase

        vm.prank(multisig);
        handler.setUserWithdrawLimit(address(mockProtocol), address(USDC), newBaseLimit, true);
    }

    function test_RevertIfExceedAllowedPercentageChange() public {
        // First set up a user with initial config
        _supply(mockProtocol, address(USDC), alice, 1000 ether);

        uint256 newBaseLimit = DEFAULT_BASE_WITHDRAWAL_LIMIT + (DEFAULT_BASE_WITHDRAWAL_LIMIT * 25) / 100; // This is more than 25% increase

        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange
            )
        );
        handler.setUserWithdrawLimit(address(mockProtocol), address(USDC), newBaseLimit, false);
    }

    function _setUserWithdrawLimit(uint256 percentIncrease_, bool revertIfCoolDownPending_) internal {
        // First set up a user with initial config
        _supply(mockProtocol, address(USDC), alice, 1000 ether);

        AdminModuleStructs.UserSupplyConfig memory oldConfig = handler.getUserSupplyConfig(
            address(mockProtocol),
            address(USDC)
        );

        uint256 newBaseLimit = oldConfig.baseWithdrawalLimit +
            ((oldConfig.baseWithdrawalLimit * percentIncrease_) / 100); // 10% increase

        vm.prank(multisig);

        if (revertIfCoolDownPending_) {
            vm.expectRevert(
                abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
            );
        }

        handler.setUserWithdrawLimit(address(mockProtocol), address(USDC), newBaseLimit, false);

        AdminModuleStructs.UserSupplyConfig memory config = handler.getUserSupplyConfig(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(config.expandPercent, oldConfig.expandPercent);
        assertEq(config.expandDuration, oldConfig.expandDuration);

        if (revertIfCoolDownPending_) {
            assertEq(config.baseWithdrawalLimit, oldConfig.baseWithdrawalLimit);
        } else {
            newBaseLimit = newBaseLimit.toBigNumber(
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            );
            newBaseLimit = BigMathMinified.fromBigNumber(newBaseLimit, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            assertEq(config.baseWithdrawalLimit, newBaseLimit);
        }
    }

    function test_setUserWithdrawLimit() public {
        _setUserWithdrawLimit(10, false);
    }

    function test_NOTRevertIfSetUserWithdrawLimitWithinCooldown() public {
        _setUserWithdrawLimit(10, false);

        vm.warp(block.timestamp + 1 days);

        _setUserWithdrawLimit(5, false);
    }

    function test_setUserWithdrawLimitAfterCooldown() public {
        _setUserWithdrawLimit(10, false);

        vm.warp(block.timestamp + 4 days + 1);

        _setUserWithdrawLimit(5, false);
    }

    function test_setUserWithdrawLimitKeepOldValues() public {
        _setUserWithdrawLimit(0, false);
    }
}

contract LimitsAuthSetBorrowLimitsTest is LimitsAuthTest {
    using BigMathMinified for uint256;

    function test_revertIfNotMultisig() public {
        address user = makeAddr("user");
        uint256 baseLimit = 1000 ether;
        uint256 maxLimit = 2000 ether;
        uint256 expandPercentage = 1000; // 10%
        uint256 expandDuration = 1 days;

        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__Unauthorized));
        handler.setUserBorrowLimits(user, address(USDC), baseLimit, maxLimit);
    }

    function test_revertIfUserNotDefinedYet() public {
        address user = makeAddr("user");
        uint256 baseLimit = 1000 ether;
        uint256 maxLimit = 2000 ether;
        uint256 expandPercentage = 1000; // 10%
        uint256 expandDuration = 1 days;

        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__UserNotDefinedYet)
        );
        handler.setUserBorrowLimits(user, address(USDC), baseLimit, maxLimit);
    }

    function test_revertIfBothLimits0() public {
        address user = makeAddr("user");
        uint256 baseLimit = 0;
        uint256 maxLimit = 0;

        vm.prank(multisig);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__InvalidParams));
        handler.setUserBorrowLimits(user, address(USDC), baseLimit, maxLimit);
    }

    function test_revertIfExceedAllowedPercentageChange() public {
        // First set up a user with initial borrow config
        _supply(mockProtocol, address(USDC), alice, 1000 ether);

        uint256 currentBaseLimit = handler.getUserBorrowConfig(address(mockProtocol), address(USDC)).baseDebtCeiling;
        uint256 newBaseLimit = currentBaseLimit + ((currentBaseLimit * 25) / 100); // 25% increase

        vm.prank(multisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidConfigError.selector,
                ErrorTypes.LimitsAuth__ExceedAllowedPercentageChange
            )
        );
        handler.setUserBorrowLimits(address(mockProtocol), address(USDC), newBaseLimit, 0);
    }

    function _setUserBorrowLimits(uint256 percentIncrease_, bool revertIfCoolDownPending_) internal {
        // First set up a user with initial borrow config
        _supply(mockProtocol, address(USDC), alice, 1000 ether);

        AdminModuleStructs.UserBorrowConfig memory oldConfig = handler.getUserBorrowConfig(
            address(mockProtocol),
            address(USDC)
        );

        uint256 currentBaseLimit = oldConfig.baseDebtCeiling;
        uint256 currentMaxLimit = oldConfig.maxDebtCeiling;

        uint256 newBaseLimit = currentBaseLimit + ((currentBaseLimit * percentIncrease_) / 100); // 15% increase
        uint256 newMaxLimit = currentMaxLimit + ((currentMaxLimit * percentIncrease_) / 100); // 15% increase

        vm.prank(multisig);

        if (revertIfCoolDownPending_) {
            vm.expectRevert(
                abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LimitsAuth__CoolDownPending)
            );
        }

        handler.setUserBorrowLimits(address(mockProtocol), address(USDC), newBaseLimit, newMaxLimit);

        AdminModuleStructs.UserBorrowConfig memory config = handler.getUserBorrowConfig(
            address(mockProtocol),
            address(USDC)
        );

        assertEq(config.expandPercent, oldConfig.expandPercent);
        assertEq(config.expandDuration, oldConfig.expandDuration);

        if (revertIfCoolDownPending_) {
            assertEq(config.baseDebtCeiling, oldConfig.baseDebtCeiling);
            assertEq(config.maxDebtCeiling, oldConfig.maxDebtCeiling);
        } else {
            newBaseLimit = newBaseLimit.toBigNumber(
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            );
            newBaseLimit = BigMathMinified.fromBigNumber(newBaseLimit, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            newMaxLimit = newMaxLimit.toBigNumber(
                SMALL_COEFFICIENT_SIZE,
                DEFAULT_EXPONENT_SIZE,
                BigMathMinified.ROUND_DOWN
            );
            newMaxLimit = BigMathMinified.fromBigNumber(newMaxLimit, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);

            assertEq(config.baseDebtCeiling, newBaseLimit);
            assertEq(config.maxDebtCeiling, newMaxLimit);
        }
    }

    function test_setUserBorrowLimits() public {
        _setUserBorrowLimits(15, false);
    }

    function test_revertIfSetUserBorrowConfigWithinCooldown() public {
        _setUserBorrowLimits(15, false);

        vm.warp(block.timestamp + 1 days);

        _setUserBorrowLimits(5, true);
    }

    function test_setUserBorrowLimitsAfterCooldown() public {
        _setUserBorrowLimits(15, false);

        vm.warp(block.timestamp + 4 days + 1);

        _setUserBorrowLimits(5, false);
    }

    function test_setUserBorrowLimitsKeepOldValues() public {
        _setUserBorrowLimits(0, false);
    }
}
