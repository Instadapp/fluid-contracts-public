//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { LiquidityBaseTest } from "./liquidityBaseTest.t.sol";

import { FluidLiquidityAdminModule, AuthModule, GovernanceModule, GuardianModule, AuthInternals } from "../../../contracts/liquidity/adminModule/main.sol";
import { Events as AdminModuleEvents } from "../../../contracts/liquidity/adminModule/events.sol";
import { CommonHelpers } from "../../../contracts/liquidity/common/helpers.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { ErrorTypes } from "../../../contracts/liquidity/errorTypes.sol";
import { Error } from "../../../contracts/liquidity/error.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";

import "forge-std/console.sol";

contract TestERC20_5Decimals is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function decimals() public view virtual override returns (uint8) {
        return 5;
    }
}
contract TestERC20_19Decimals is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function decimals() public view virtual override returns (uint8) {
        return 19;
    }
}

// tests todo: make sure exchangePricesAndConfig timestamp is set with config
// test calcRevenue of LiquidityCalcs

contract LiquidityAdminModuleBaseTest is LiquidityBaseTest, AdminModuleEvents {
    function setUp() public virtual override {
        super.setUp();
    }
}

contract LiquidityAdminModuleTokenConfigTest is LiquidityAdminModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_UpdateTokenConfigs() public {
        // Add a token configuration for USDC
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 8800 // 88%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        // Verify the token configuration was correctly set
        uint256 exchangePricesAndConfig_ = resolver.getExchangePricesAndConfig(address(USDC));
        uint256 fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        uint256 threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        uint256 configs2_ = resolver.getConfigs2(address(USDC));
        uint256 maxUtilization_ = configs2_ & X14;
        assertEq(tokenConfigs_[0].fee, fee_);
        assertEq(tokenConfigs_[0].threshold, threshold_);
        assertEq(tokenConfigs_[0].maxUtilization, maxUtilization_);
        // ensure uses configs 2 flag is set
        assertEq((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2) & 1, 1);

        ResolverStructs.OverallTokenData memory overallTokenData = resolver.getOverallTokenData(address(USDC));
        assertEq(tokenConfigs_[0].fee, overallTokenData.fee);
        assertEq(tokenConfigs_[0].threshold, overallTokenData.storageUpdateThreshold);
        assertEq(tokenConfigs_[0].maxUtilization, overallTokenData.maxUtilization);
    }

    function test_UpdateTokenConfigs_NotUsesConfigs2Flag() public {
        // uses configs2 flag is set to true tested in test_UpdateTokenConfigs
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100% -> should set flag to 0 (not used)
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        uint256 exchangePricesAndConfig_ = resolver.getExchangePricesAndConfig(address(USDC));
        // ensure uses configs 2 flag is set
        assertEq((exchangePricesAndConfig_ >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_USES_CONFIGS2) & 1, 0);
    }

    function test_UpdateTokenConfigs_revertIfMaxUtilizationAbove100() public {
        // - reverts if set max utilization > 100%
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__ValueOverflow__MAX_UTILIZATION
            )
        );

        // Add a token configuration for USDC
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 10001 // > 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);
    }

    function test_UpdateTokenConfigs_Multiple() public {
        // Add a token configuration for USDC and DAI
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](2);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 130 // 1.3%
        });
        tokenConfigs_[1] = AdminModuleStructs.TokenConfig({
            token: address(DAI),
            fee: 900, // 9%
            threshold: 200, // 2%
            maxUtilization: 8800 // 88%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        // Verify the token configuration was correctly set
        uint256 exchangePricesAndConfig_ = resolver.getExchangePricesAndConfig(address(USDC));
        uint256 fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        uint256 threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        uint256 configs2_ = resolver.getConfigs2(address(USDC));
        uint256 maxUtilization_ = configs2_ & X14;
        assertEq(tokenConfigs_[0].fee, fee_);
        assertEq(tokenConfigs_[0].threshold, threshold_);
        assertEq(tokenConfigs_[0].maxUtilization, maxUtilization_);

        exchangePricesAndConfig_ = resolver.getExchangePricesAndConfig(address(DAI));
        fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        configs2_ = resolver.getConfigs2(address(DAI));
        maxUtilization_ = configs2_ & X14;
        assertEq(tokenConfigs_[1].fee, fee_);
        assertEq(tokenConfigs_[1].threshold, threshold_);
        assertEq(tokenConfigs_[1].maxUtilization, maxUtilization_);
    }

    function test_UpdateTokenConfigs_ListedTokens() public {
        // tokens configured in setUP in base test should be in listed tokens
        address[] memory listedTokens_ = resolver.listedTokens();
        assertEq(listedTokens_[0], address(USDC));
        assertEq(listedTokens_[1], address(DAI));
        assertEq(listedTokens_[2], NATIVE_TOKEN_ADDRESS);
        assertEq(listedTokens_[3], address(USDT));
        assertEq(listedTokens_[4], address(SUSDE));
        assertEq(listedTokens_.length, 5);

        // adding more
        address addToken1 = address(new MockERC20("TestName1", "TestSymbol1"));
        address addToken2 = address(new MockERC20("TestName2", "TestSymbol2"));

        _setDefaultRateDataV1(address(liquidity), admin, addToken1);
        _setDefaultRateDataV1(address(liquidity), admin, addToken2);

        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](2);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: addToken1,
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[1] = AdminModuleStructs.TokenConfig({
            token: addToken2,
            fee: 900, // 9%
            threshold: 200, // 2%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        // verify
        listedTokens_ = resolver.listedTokens();
        assertEq(listedTokens_[0], address(USDC));
        assertEq(listedTokens_[1], address(DAI));
        assertEq(listedTokens_[2], NATIVE_TOKEN_ADDRESS);
        assertEq(listedTokens_[3], address(USDT));
        assertEq(listedTokens_[4], address(SUSDE));
        assertEq(listedTokens_[5], addToken1);
        assertEq(listedTokens_[6], addToken2);
        assertEq(listedTokens_.length, 7);
    }

    function test_UpdateTokenConfigs_LogUpdateTokenConfigs() public {
        // Add a token configuration for USDC
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 1000, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.expectEmit(false, false, false, false);
        emit LogUpdateTokenConfigs(tokenConfigs_);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);
    }
}

contract LiquidityAdminModuleUserWithdrawalLimitTest is LiquidityAdminModuleBaseTest {
    function setUp() public virtual override {
        super.setUp();

        _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
        _setDefaultTokenConfigs(address(liquidity), admin, address(USDC));

        // Add supply config for alice via mock protocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BORROW_AMOUNT
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // supply as alice to above base limit
        _supply(mockProtocol, address(USDC), alice, DEFAULT_SUPPLY_AMOUNT);

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, DEFAULT_SUPPLY_AMOUNT);
        assertEq(userSupplyData.withdrawalLimit, 0.8 ether); // max expanded
        assertEq(userSupplyData.withdrawable, 0.2 ether);

        // withdraw max, now withdrawable would be 0
        _withdraw(mockProtocol, address(USDC), alice, 0.2 ether);
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.withdrawable, 0 ether);
    }

    function test_updateUserWithdrawalLimit_Zero() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0 // setting to max expanded
        );

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.8 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.64 ether); // max expanded
        assertEq(userSupplyData.withdrawable, 0.16 ether);
    }

    function test_updateUserWithdrawalLimit_BelowMaxExpansion() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0.5 ether // setting to below max expanded
        );

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.8 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.64 ether); // max expanded
        assertEq(userSupplyData.withdrawable, 0.16 ether);
    }

    function test_updateUserWithdrawalLimit_MaxUint256() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            type(uint256).max
        );

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.8 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.8 ether);
        assertEq(userSupplyData.withdrawable, 0);
    }

    function test_updateUserWithdrawalLimit_AboveUserSupply() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0.9 ether
        );

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.8 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.8 ether);
        assertEq(userSupplyData.withdrawable, 0);
    }

    function test_updateUserWithdrawalLimit_GoesBelowBaseLimit() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0 // setting to max expanded
        );

        // withdraw 0.1 ether, now withdrawable would be 0.06
        _withdraw(mockProtocol, address(USDC), alice, 0.1 ether);
        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.7 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.64 ether);
        assertEq(userSupplyData.withdrawable, 0.06 ether);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0 // setting to max expanded
        );
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.7 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.56 ether);
        assertEq(userSupplyData.withdrawable, 0.14 ether);

        // withdraw max, now withdrawable would be 0
        _withdraw(mockProtocol, address(USDC), alice, 0.14 ether);
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.56 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.56 ether);
        assertEq(userSupplyData.withdrawable, 0);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0 // setting to max expanded, which goes below base limit
        );

        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.56 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.448 ether);
        assertEq(userSupplyData.withdrawable, 0.112 ether);

        // small withdrawal
        _withdraw(mockProtocol, address(USDC), alice, 0.01 ether);
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.55 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.448 ether);
        assertEq(userSupplyData.withdrawable, 0.102 ether);

        // withdrawal that brings below base limit
        _withdraw(mockProtocol, address(USDC), alice, 0.06 ether);
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.49 ether);
        assertEq(userSupplyData.withdrawalLimit, 0);
        assertEq(userSupplyData.withdrawable, 0.49 ether);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0 // user supply is below base limit so should stay 0
        );
        (userSupplyData, ) = resolver.getUserSupplyData(address(mockProtocol), address(USDC));
        assertEq(userSupplyData.supply, 0.49 ether);
        assertEq(userSupplyData.withdrawalLimit, 0);
        assertEq(userSupplyData.withdrawable, 0.49 ether);
    }

    function test_updateUserWithdrawalLimit_ValidInputLimit() public {
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            0.7 ether // setting to valid between user supply and max expansion
        );

        (ResolverStructs.UserSupplyData memory userSupplyData, ) = resolver.getUserSupplyData(
            address(mockProtocol),
            address(USDC)
        );
        assertEq(userSupplyData.supply, 0.8 ether);
        assertEq(userSupplyData.withdrawalLimit, 0.7 ether);
        assertEq(userSupplyData.withdrawable, 0.1 ether);
    }

    function test_updateUserWithdrawalLimit_LogUpdateUserWithdrawalLimit() public {
        vm.expectEmit(false, false, false, false);
        emit LogUpdateUserWithdrawalLimit(address(mockProtocol), address(USDC), 1e16);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            1e16
        );
    }

    function test_updateUserWithdrawalLimit_RevertOnlyAuths() public {
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyAuths));

        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            1e10
        );

        // set alice as auth, should not revert then anymore
        _setAsAuth(address(liquidity), admin, alice);
        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(USDC),
            1e10
        );
    }

    function test_updateUserWithdrawalLimit_RevertUserNotAContract() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__AddressNotAContract)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(address(alice), address(USDC), 1e10);
    }

    function test_updateUserWithdrawalLimit_RevertUserNotDefined() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotDefined)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(address(USDC), address(USDC), 1e10);
    }

    function test_updateUserWithdrawalLimit_RevertTokenNotAContractOrNative() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__AddressNotAContract)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserWithdrawalLimit(
            address(mockProtocol),
            address(alice),
            1e10
        );
    }
}

contract LiquidityAdminModuleUserSupplyConfigTest is LiquidityAdminModuleBaseTest {
    function testupdateUserSupplyConfigs() public {
        // expect no config
        uint256 userSupplyData_ = resolver.getUserSupply(address(mockProtocol), address(USDC));
        assertEq((userSupplyData_ >> 0) & 1, 0); // mode
        assertEq((userSupplyData_ >> 162) & X14, 0); // expandPercent
        assertEq((userSupplyData_ >> 176) & X24, 0); // expandDuration
        uint256 temp_ = (userSupplyData_ >> 200) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_, 0); // baseWithdrawalLimit

        // Add supply config for alice via mock protocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseWithdrawalLimit: 1000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // expect correct config
        userSupplyData_ = resolver.getUserSupply(address(mockProtocol), address(USDC));
        assertEq((userSupplyData_ >> 0) & 1, 1); // mode
        assertEq((userSupplyData_ >> 162) & X14, 5000); // expandPercent
        assertEq((userSupplyData_ >> 176) & X24, 60); // expandDuration
        temp_ = (userSupplyData_ >> 200) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_ / 1e18, 999); // baseWithdrawalLimit (rounded for bigNumber conversion)
    }

    function testUpdateUserSupplyConfigLog() public {
        // Add supply config for alice via mock protocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseWithdrawalLimit: 1000 ether
        });

        vm.expectEmit(false, false, false, false);
        emit LogUpdateUserSupplyConfigs(userSupplyConfigs_);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);
    }
}

contract LiquidityAdminModuleUserBorrowConfigTest is LiquidityAdminModuleBaseTest {
    function testupdateUserBorrowConfigs() public {
        // expect no config
        uint256 userBorrowData_ = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        assertEq((userBorrowData_ >> 0) & 1, 0); // mode
        assertEq((userBorrowData_ >> 162) & X14, 0); // expandPercent
        assertEq((userBorrowData_ >> 176) & X24, 0); // expandDuration
        uint256 temp_ = (userBorrowData_ >> 200) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_, 0); // baseBorrowLimit
        temp_ = (userBorrowData_ >> 218) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_, 0); // maxBorrowLimit

        // Add borrow config for alice via mock protocol
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseDebtCeiling: 1000 ether,
            maxDebtCeiling: 1000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // expect correct config
        userBorrowData_ = resolver.getUserBorrow(address(mockProtocol), address(USDC));
        assertEq((userBorrowData_ >> 0) & 1, 1); // mode
        assertEq((userBorrowData_ >> 162) & X14, 5000); // expandPercent
        assertEq((userBorrowData_ >> 176) & X24, 60); // expandDuration
        temp_ = (userBorrowData_ >> 200) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_ / 1e18, 999); // baseBorrowLimit (rounded for bigNumber conversion)
        temp_ = (userBorrowData_ >> 218) & X18;
        temp_ = (temp_ >> DEFAULT_EXPONENT_SIZE) << (temp_ & DEFAULT_EXPONENT_MASK);
        assertEq(temp_ / 1e18, 999); // maxBorrowLimit (rounded for bigNumber conversion)
    }

    function testUpdateUserBorrowConfigLog() public {
        // Add borrow config for alice via mock protocol
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseDebtCeiling: 1000 ether,
            maxDebtCeiling: 1000 ether
        });

        vm.expectEmit(false, false, false, false);
        emit LogUpdateUserBorrowConfigs(userBorrowConfigs_);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);
    }
}

contract LiquidityAdminModuleGovernanceModuleTest is LiquidityAdminModuleBaseTest {
    function testAdminUpdateAuths() public {
        // assert initial values
        assertEq(resolver.isAuth(alice), 0);
        assertEq(resolver.isAuth(bob), 0);
        assertEq(resolver.isAuth(admin), 0);

        // create params
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](3);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(admin, false);
        updateAuthsParams[1] = AdminModuleStructs.AddressBool(alice, true);
        updateAuthsParams[2] = AdminModuleStructs.AddressBool(bob, true);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // Verify the token configuration was correctly set
        assertEq(resolver.isAuth(alice), 1);
        assertEq(resolver.isAuth(bob), 1);
        assertEq(resolver.isAuth(admin), 0);

        // unset alice
        updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(alice, false);
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);
        // assert expected results
        assertEq(resolver.isAuth(alice), 0);
    }

    function testAdminEmitLogUpdateAuthsForUpdateAuths() public {
        // create params
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](3);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(admin, false);
        updateAuthsParams[1] = AdminModuleStructs.AddressBool(alice, true);
        updateAuthsParams[2] = AdminModuleStructs.AddressBool(bob, true);

        // set expected event
        vm.expectEmit(false, false, false, false);
        emit LogUpdateAuths(updateAuthsParams);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);
    }

    function testAdminUpdateAuthsUnauthorizedRevert() public {
        // create params
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(alice, true);

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );

        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);

        // test also auths should revert, only governance can call.
        // set alice as auth
        _setAsAuth(address(liquidity), admin, alice);
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );
        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateAuths(updateAuthsParams);
    }

    function testAdminUpdateGuardians() public {
        // assert initial values
        assertEq(resolver.isGuardian(alice), 0);
        assertEq(resolver.isGuardian(bob), 0);
        assertEq(resolver.isGuardian(admin), 0);

        // create params
        AdminModuleStructs.AddressBool[] memory updateGuardiansParams = new AdminModuleStructs.AddressBool[](3);
        updateGuardiansParams[0] = AdminModuleStructs.AddressBool(admin, false);
        updateGuardiansParams[1] = AdminModuleStructs.AddressBool(alice, true);
        updateGuardiansParams[2] = AdminModuleStructs.AddressBool(bob, true);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);

        // assert expected results
        assertEq(resolver.isGuardian(alice), 1);
        assertEq(resolver.isGuardian(bob), 1);
        assertEq(resolver.isGuardian(admin), 0);

        // unset alice
        updateGuardiansParams = new AdminModuleStructs.AddressBool[](1);
        updateGuardiansParams[0] = AdminModuleStructs.AddressBool(alice, false);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);

        // assert expected results
        assertEq(resolver.isGuardian(alice), 0);
    }

    function testAdminEmitLogUpdateGuardiansForUpdateGuardians() public {
        // create params
        AdminModuleStructs.AddressBool[] memory updateGuardiansParams = new AdminModuleStructs.AddressBool[](3);
        updateGuardiansParams[0] = AdminModuleStructs.AddressBool(admin, false);
        updateGuardiansParams[1] = AdminModuleStructs.AddressBool(alice, true);
        updateGuardiansParams[2] = AdminModuleStructs.AddressBool(bob, true);

        // set expected event
        vm.expectEmit(false, false, false, false);
        emit LogUpdateGuardians(updateGuardiansParams);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);
    }

    function testAdminUpdateGuardiansUnauthorizedRevert() public {
        // create params
        AdminModuleStructs.AddressBool[] memory updateGuardiansParams = new AdminModuleStructs.AddressBool[](1);
        updateGuardiansParams[0] = AdminModuleStructs.AddressBool(alice, true);

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );

        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);

        // test also auths should revert, only governance can call.
        // set alice as auth
        _setAsAuth(address(liquidity), admin, alice);
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );
        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);
    }

    function testAdminUpdateRevenueCollector() public {
        address revenueCollector = address(uint160(liquidity.readFromStorage(bytes32(0))));

        // assert initial values
        assertEq(revenueCollector, address(0));

        // execute set alice
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(alice);

        // assert expected results
        revenueCollector = address(uint160(liquidity.readFromStorage(bytes32(0))));
        assertEq(revenueCollector, alice);

        // set bob
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(bob);
        // assert expected results
        revenueCollector = address(uint160(liquidity.readFromStorage(bytes32(0))));
        assertEq(revenueCollector, bob);
    }

    function testAdminEmitLogUpdateRevenueCollectorForUpdateRevenueCollector() public {
        // set expected event
        vm.expectEmit(true, false, false, false);
        emit LogUpdateRevenueCollector(alice);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(alice);
    }

    function testAdminUpdateRevenueCollectorUnauthorizedRevert() public {
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );

        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(bob);

        // test also auths should revert, only governance can call.
        // set alice as auth
        _setAsAuth(address(liquidity), admin, alice);
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyGovernance)
        );
        // execute
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(bob);
    }
}

contract LiquidityAdminModuleUpdateRateDataV1sTest is LiquidityAdminModuleBaseTest {
    AdminModuleStructs.RateDataV1Params[] rateDataV1Params;

    function setUp() public virtual override {
        super.setUp();

        rateDataV1Params.push(
            AdminModuleStructs.RateDataV1Params(
                address(USDC),
                DEFAULT_KINK,
                DEFAULT_RATE_AT_ZERO,
                DEFAULT_RATE_AT_KINK,
                DEFAULT_RATE_AT_MAX
            )
        );
        rateDataV1Params.push(
            AdminModuleStructs.RateDataV1Params(
                address(DAI),
                4000, // kink at 40%
                0, // rate at 0 = 0
                2000, // rate at kink = 20%
                20000 // rate at max (100%) = 200%
            )
        );
    }

    function test_AdminUpdateRateDataV1s() public {
        // assert initial values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, DEFAULT_RATE_AT_ZERO); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, DEFAULT_KINK); // utilizationKink
        assertEq((rateData_ >> 36) & X16, DEFAULT_RATE_AT_KINK); // rateAtUtilizationKink
        assertEq((rateData_ >> 52) & X16, DEFAULT_RATE_AT_MAX); // rateAtUtilizationMax

        // same for DAI
        // assert initial values
        rateData_ = resolver.getRateConfig(address(DAI));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, DEFAULT_RATE_AT_ZERO); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, DEFAULT_KINK); // utilizationKink
        assertEq((rateData_ >> 36) & X16, DEFAULT_RATE_AT_KINK); // rateAtUtilizationKink
        assertEq((rateData_ >> 52) & X16, DEFAULT_RATE_AT_MAX); // rateAtUtilizationMax

        // execute
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // assert values
        rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, rateDataV1Params[0].rateAtUtilizationZero);
        assertEq((rateData_ >> 20) & X16, rateDataV1Params[0].kink);
        assertEq((rateData_ >> 36) & X16, rateDataV1Params[0].rateAtUtilizationKink);
        assertEq((rateData_ >> 52) & X16, rateDataV1Params[0].rateAtUtilizationMax);

        // same for DAI
        // assert values
        rateData_ = resolver.getRateConfig(address(DAI));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, rateDataV1Params[1].rateAtUtilizationZero);
        assertEq((rateData_ >> 20) & X16, rateDataV1Params[1].kink);
        assertEq((rateData_ >> 36) & X16, rateDataV1Params[1].rateAtUtilizationKink);
        assertEq((rateData_ >> 52) & X16, rateDataV1Params[1].rateAtUtilizationMax);
    }

    function testAdminEmitUpdateRateDataV1sForUpdateRateDataV1s() public {
        // set expected event
        vm.expectEmit(false, false, false, false);
        emit LogUpdateRateDataV1s(rateDataV1Params);

        // execute
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }

    function testAdminUpdateRateDataV1sUnauthorizedRevert() public {
        // set expected revert
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyAuths));

        // execute
        vm.prank(alice);
        AuthModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // set alice as auth, should not revert then anymore
        _setAsAuth(address(liquidity), admin, alice);
        // execute
        vm.prank(alice);
        AuthModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }

    function testAdminUpdateRateDataV1s_RevertIfTokenDecimalsInvalidRange() public {
        rateDataV1Params[0].token = address(new TestERC20_5Decimals("test", "test"));
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__TokenInvalidDecimalsRange
            )
        );
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        rateDataV1Params[0].token = address(new TestERC20_19Decimals("test", "test"));
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__TokenInvalidDecimalsRange
            )
        );
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }

    function testAdminUpdateRateDataV1sOverflowKinkRevert() public {
        rateDataV1Params[0].kink = 1e4 + 1; // above 100%;

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }

    function testAdminUpdateRateDataV1sOverflowRateAtZeroRevert() public {
        rateDataV1Params[0].rateAtUtilizationZero = X16 + 1; // above max vlaue;

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_ZERO
            )
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }

    function testAdminUpdateRateDataV1sRateAtZeroBiggerRateAtKink() public {
        rateDataV1Params[0].rateAtUtilizationZero = 1e4 + 1;
        rateDataV1Params[0].rateAtUtilizationKink = 1e4;

        // should not revert, declining rate between zero and kink is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, rateDataV1Params[0].rateAtUtilizationZero);
        assertEq((rateData_ >> 20) & X16, rateDataV1Params[0].kink);
        assertEq((rateData_ >> 36) & X16, rateDataV1Params[0].rateAtUtilizationKink);
        assertEq((rateData_ >> 52) & X16, rateDataV1Params[0].rateAtUtilizationMax);
    }

    function testAdminUpdateRateDataV1sRateAtZeroEqualRateAtKink() public {
        rateDataV1Params[0].rateAtUtilizationZero = 1e3;
        rateDataV1Params[0].rateAtUtilizationKink = 1e3;

        // should not revert, flat rate between zero and kink is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, rateDataV1Params[0].rateAtUtilizationZero);
        assertEq((rateData_ >> 20) & X16, rateDataV1Params[0].kink);
        assertEq((rateData_ >> 36) & X16, rateDataV1Params[0].rateAtUtilizationKink);
        assertEq((rateData_ >> 52) & X16, rateDataV1Params[0].rateAtUtilizationMax);
    }

    function testAdminUpdateRateDataV1sRateAtZeroEqualRateAtKink_BothZero() public {
        rateDataV1Params[0].rateAtUtilizationZero = 0;
        rateDataV1Params[0].rateAtUtilizationKink = 0;

        // should not revert, flat rate between zero and kink is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, rateDataV1Params[0].rateAtUtilizationZero);
        assertEq((rateData_ >> 20) & X16, rateDataV1Params[0].kink);
        assertEq((rateData_ >> 36) & X16, rateDataV1Params[0].rateAtUtilizationKink);
        assertEq((rateData_ >> 52) & X16, rateDataV1Params[0].rateAtUtilizationMax);
    }

    function testAdminUpdateRateDataV1sRateAtKinkBiggerRateAtMaxRevert() public {
        rateDataV1Params[0].rateAtUtilizationZero = 1e3;
        rateDataV1Params[0].rateAtUtilizationKink = 1e4 + 1;
        rateDataV1Params[0].rateAtUtilizationMax = 1e4;

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);
    }
}

contract LiquidityAdminModuleUpdateRateDataV2sTest is LiquidityAdminModuleBaseTest {
    AdminModuleStructs.RateDataV2Params[] rateDataV2Params;

    function setUp() public virtual override {
        super.setUp();

        rateDataV2Params.push(
            AdminModuleStructs.RateDataV2Params(
                address(USDC),
                6000, // kink1 at 60%
                8000, // kink2 at 80%
                400, // rate at 0 = 4%
                1000, // rate at kink1 = 10%
                4000, // rate at kink2 = 40%
                12000 // rate at max (100%) = 120%
            )
        );
        rateDataV2Params.push(
            AdminModuleStructs.RateDataV2Params(
                address(DAI),
                4000, // kink1 at 40%
                7000, // kink2 at 70%
                0, // rate at 0
                2000, // rate at kink1 = 20%
                8000, // rate at kink2 = 80%
                20000 // rate at max (100%) = 200%
            )
        );
    }

    function testAdminUpdateRateDataV2s() public {
        // assert initial values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, DEFAULT_RATE_AT_ZERO); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, DEFAULT_KINK); // utilizationKink
        assertEq((rateData_ >> 36) & X16, DEFAULT_RATE_AT_KINK); // rateAtUtilizationKink
        assertEq((rateData_ >> 52) & X16, DEFAULT_RATE_AT_MAX); // rateAtUtilizationMax

        // same for DAI
        // assert initial values
        rateData_ = resolver.getRateConfig(address(DAI));
        assertEq(rateData_ & 0xF, 1); // version
        assertEq((rateData_ >> 4) & X16, DEFAULT_RATE_AT_ZERO); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, DEFAULT_KINK); // utilizationKink
        assertEq((rateData_ >> 36) & X16, DEFAULT_RATE_AT_KINK); // rateAtUtilizationKink
        assertEq((rateData_ >> 52) & X16, DEFAULT_RATE_AT_MAX); // rateAtUtilizationMax

        // execute
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax

        // same for DAI
        rateData_ = resolver.getRateConfig(address(DAI));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[1].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[1].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[1].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[1].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[1].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[1].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminEmitUpdateRateDataV2sForUpdateRateDataV2s() public {
        // set expected event
        vm.expectEmit(false, false, false, false);
        emit LogUpdateRateDataV2s(rateDataV2Params);

        // execute
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2sUnauthorizedRevert() public {
        // set expected revert
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyAuths));

        // execute
        vm.prank(alice);
        AuthModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // set alice as auth, should not revert then anymore
        _setAsAuth(address(liquidity), admin, alice);
        // execute
        vm.prank(alice);
        AuthModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2s_RevertIfTokenDecimalsInvalidRange() public {
        rateDataV2Params[0].token = address(new TestERC20_5Decimals("test", "test"));
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__TokenInvalidDecimalsRange
            )
        );
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        rateDataV2Params[0].token = address(new TestERC20_19Decimals("test", "test"));
        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__TokenInvalidDecimalsRange
            )
        );
        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2sOverflowKink1Revert() public {
        rateDataV2Params[0].kink1 = 1e4 + 1; // above 100%

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2sOverflowKink2Revert() public {
        rateDataV2Params[0].kink2 = 1e4 + 1; // above 100%

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2sOverflowRateAtZeroRevert() public {
        rateDataV2Params[0].rateAtUtilizationZero = X16 + 1; // above max vlaue;

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidLiquidityError.selector,
                ErrorTypes.AdminModule__ValueOverflow__RATE_AT_UTIL_ZERO
            )
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }

    function testAdminUpdateRateDataV2sRateAtZeroBiggerRateAtKink1() public {
        rateDataV2Params[0].rateAtUtilizationZero = 1e4;
        rateDataV2Params[0].rateAtUtilizationKink1 = 1e3;

        // should not revert, declining rate between zero and kink1 is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminUpdateRateDataV2sRateAtZeroEqualRateAtKink1() public {
        rateDataV2Params[0].rateAtUtilizationZero = 1e3;
        rateDataV2Params[0].rateAtUtilizationKink1 = 1e3;

        // should not revert, flat rate between zero and kink1 is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminUpdateRateDataV2sRateAtKink1BiggerRateAtKink2() public {
        rateDataV2Params[0].rateAtUtilizationZero = 0;
        rateDataV2Params[0].rateAtUtilizationKink1 = 1e4;
        rateDataV2Params[0].rateAtUtilizationKink2 = 1e3;

        // should not revert, declining rate between kink1 and kink2 is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminUpdateRateDataV2sRateAtKink1EqualRateAtKink2() public {
        rateDataV2Params[0].rateAtUtilizationZero = 0;
        rateDataV2Params[0].rateAtUtilizationKink1 = 1e3;
        rateDataV2Params[0].rateAtUtilizationKink2 = 1e3;

        // should not revert, flat rate between kink1 and kink2 is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminUpdateRateDataV2sRateAtKink1EqualRateAtKink2_Zero() public {
        rateDataV2Params[0].rateAtUtilizationZero = 0;
        rateDataV2Params[0].rateAtUtilizationKink1 = 0;
        rateDataV2Params[0].rateAtUtilizationKink2 = 0;

        // should not revert, flat rate between kink1 and kink2 is allowed

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);

        // assert values
        uint256 rateData_ = resolver.getRateConfig(address(USDC));
        assertEq(rateData_ & 0xF, 2); // version
        assertEq((rateData_ >> 4) & X16, rateDataV2Params[0].rateAtUtilizationZero); // rateAtUtilizationZero
        assertEq((rateData_ >> 20) & X16, rateDataV2Params[0].kink1); // utilizationKink1
        assertEq((rateData_ >> 36) & X16, rateDataV2Params[0].rateAtUtilizationKink1); // rateAtUtilizationKink1
        assertEq((rateData_ >> 52) & X16, rateDataV2Params[0].kink2); // utilizationKink2
        assertEq((rateData_ >> 68) & X16, rateDataV2Params[0].rateAtUtilizationKink2); // rateAtUtilizationKink2
        assertEq((rateData_ >> 84) & X16, rateDataV2Params[0].rateAtUtilizationMax); // rateAtUtilizationMax
    }

    function testAdminUpdateRateDataV2sRateAtKink2BiggerRateAtMaxRevert() public {
        rateDataV2Params[0].rateAtUtilizationZero = 0;
        rateDataV2Params[0].rateAtUtilizationKink1 = 1e2;
        rateDataV2Params[0].rateAtUtilizationKink2 = 1e4;
        rateDataV2Params[0].rateAtUtilizationMax = 1e3;

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRateDataV2s(rateDataV2Params);
    }
}

contract LiquidityAdminModuleRevenueTest is LiquidityAdminModuleBaseTest {
    function setUp() public override {
        super.setUp();

        _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
        _setDefaultRateDataV1(address(liquidity), admin, address(DAI));

        _setDefaultTokenConfigs(address(liquidity), admin, address(USDC));
        _setDefaultTokenConfigs(address(liquidity), admin, address(DAI));

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), alice);
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), alice);
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), bob);
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), bob);

        // Add a token configuration for USDC and DAI
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](1);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            fee: 500, // 10%
            threshold: 100, // 1%
            maxUtilization: 1e4 // 100%
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        AdminModuleStructs.RateDataV1Params[] memory rateDataV1Params = new AdminModuleStructs.RateDataV1Params[](1);
        rateDataV1Params[0] = AdminModuleStructs.RateDataV1Params(
            address(USDC),
            DEFAULT_KINK,
            DEFAULT_RATE_AT_ZERO,
            DEFAULT_RATE_AT_KINK,
            DEFAULT_RATE_AT_MAX
        );
        vm.prank(admin);
        AuthModule(address(liquidity)).updateRateDataV1s(rateDataV1Params);

        // Add supply config for alice via mock protocol
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000, // 50%
            expandDuration: 60,
            baseWithdrawalLimit: 11000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // Add borrow config for bob via mock protocol
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: 1000, // 10%
            expandDuration: 10, // 10s
            baseDebtCeiling: 10000 ether,
            maxDebtCeiling: 10000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // set revenue collector address to be admin
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(admin);
    }
}

contract LiquidityAdminModuleCollectRevenueTest is LiquidityAdminModuleBaseTest {
    function setUp() public override {
        super.setUp();

        // set revenue collector address to be admin
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(admin);

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));

        // set default token fee
        _setDefaultTokenConfigs(address(liquidity), admin, address(USDC));

        // set base allowance for borrow for bob really high
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: 500000 ether,
            maxDebtCeiling: 5000000 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // set base withdrawal limit for withdraw for alice really high
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(mockProtocol),
            token: address(USDC),
            mode: 1,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: 5000000 ether
        });
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);
    }

    function testAdminCollectRevenueUnauthorizedRevert() public {
        // set expected revert
        vm.expectRevert(abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__OnlyAuths));

        // execute
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);

        // set alice as auth, should not revert then anymore
        _setAsAuth(address(liquidity), admin, alice);
        // execute
        vm.prank(alice);
        AuthModule(address(liquidity)).collectRevenue(tokens);
    }

    function test_AdminCollectRevenue() public {
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 0);
        assertEq(USDC.balanceOf(admin), 0);

        // to test collecting revenue we first need to generate revenue through supply / borrow
        // 1. supply as alice
        _supply(mockProtocol, address(USDC), alice, 10000 ether);

        // 2. borrow as bob
        _borrow(mockProtocol, address(USDC), bob, 8000 ether);

        // 3. simulate passing time (365 days)
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // 4. assert expected revenue
        // for new borrow exchange price:
        // annual borrow rate for default test data with default values see {TestHelpers},
        // at utilization 80% (exactly at kink) the yearly borrow rate is 10%
        // borrowers pay 10% of 8000 ether = 800 ether
        // the token fee is 5% of that: 800 ether * 0.05 = 40 ether

        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 40 ether);
        // uint256  revenueData_ = resolver.getRevenueCollectorData(address(USDC));

        // 5. collect revenue
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);

        // 6. assert results
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 0);
        // slight tolerance for BigMath Round Up at total borrow amount
        assertApproxEqAbs(USDC.balanceOf(admin), 40 ether, 1e6);
    }

    function test_AdminCollectRevenueNoSuppliers() public {
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 0);
        assertEq(USDC.balanceOf(admin), 0);

        // to test collecting revenue we first need to generate revenue through supply / borrow
        // 1. supply as alice
        _supply(mockProtocol, address(USDC), alice, 10000 ether);

        // 2. borrow as bob
        _borrow(mockProtocol, address(USDC), bob, 8000 ether);

        // 3. simulate passing time (365 days)
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // 4. pay back all as bob and withdraw all as alice
        // bob must pay back original amount + 10% borrow fee
        _payback(mockProtocol, address(USDC), bob, 8800 ether);
        // alice withdraws original amount + the 10% borrow fee amount of bob minus token fee that goes to Liquidity
        _withdraw(mockProtocol, address(USDC), alice, 10760 ether);

        // 5. assert expected revenue (40 ether)
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 40 ether);

        // 6. collect revenue
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);

        // 7. assert results
        // all of revenue should be withdrawn
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 0);
        assertEq(USDC.balanceOf(admin), 40 ether);
    }

    function test_AdminCollectRevenue_LogCollectRevenue() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);

        // set expected event
        vm.expectEmit(true, true, false, false);
        emit LogCollectRevenue(address(USDC), 0);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);

        // to test collecting revenue we first need to generate revenue through supply / borrow
        // 1. supply as alice
        _supply(mockProtocol, address(USDC), alice, 10000 ether);

        // 2. borrow as bob
        _borrow(mockProtocol, address(USDC), bob, 8000 ether);

        // 3. simulate passing time (365 days)
        vm.warp(block.timestamp + PASS_1YEAR_TIME);

        // 4. assert expected revenue (40 ether)
        // assertEq(ReadModule(address(liquidity)).revenue(address(USDC)), 40 ether);

        // 5. set expected event
        vm.expectEmit(true, true, false, false);
        // actual amount is a tiny bit off from 40 ether because of BigMath Round Up at total borrow amount
        emit LogCollectRevenue(address(USDC), 40000000000000144179);

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).collectRevenue(tokens);
    }
}

contract LiquidityAdminModuleUpdateUserClassesTest is LiquidityAdminModuleBaseTest {
    function test_AdminUpdateUserClasses() public {
        // user test addresses must be contracts. using USDC & DAI for simplicity

        // assert initial values
        assertEq(resolver.getUserClass(address(USDC)), 0);
        assertEq(resolver.getUserClass(address(DAI)), 0);

        AddressUint256[] memory usersClass_ = new AddressUint256[](2);
        usersClass_[0] = AddressUint256(address(USDC), 1);
        usersClass_[1] = AddressUint256(address(DAI), 1);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserClasses(usersClass_);

        // assert expected results
        assertEq(resolver.getUserClass(address(USDC)), 1);
        assertEq(resolver.getUserClass(address(DAI)), 1);
    }

    function test_AdminUpdateUserClasses_RevertClassNotExist() public {
        AddressUint256[] memory usersClass_ = new AddressUint256[](2);
        usersClass_[0] = AddressUint256(address(USDC), 1);
        usersClass_[1] = AddressUint256(address(DAI), 2); // invalid user class

        // set expected revert
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__InvalidParams)
        );
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserClasses(usersClass_);
    }
}

contract LiquidityAdminModuleChangeStatusTest is LiquidityAdminModuleBaseTest {
    function test_AdminChangeStatus() public {
        // assert initial values
        assertEq(resolver.getStatus(), 0);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).changeStatus(1);

        // assert expected results
        assertEq(resolver.getStatus(), 1);
    }

    function test_AdminChangeStatus_LogChangeStatus() public {
        // set expected event
        vm.expectEmit(true, false, false, false);
        emit LogChangeStatus(1);

        // execute
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).changeStatus(1);
    }
}

contract LiquidityAdminModulePauseUserTest is LiquidityAdminModuleBaseTest {
    function setUp() public override {
        super.setUp();

        // user test addresses must be contracts. using USDC & DAI for simplicity

        // Add supply config for bob (DAI)
        AdminModuleStructs.UserSupplyConfig[] memory userSupplyConfigs_ = new AdminModuleStructs.UserSupplyConfig[](1);
        userSupplyConfigs_[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(DAI),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseWithdrawalLimit: 1000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserSupplyConfigs(userSupplyConfigs_);

        // Add borrow config for bob (DAI)
        AdminModuleStructs.UserBorrowConfig[] memory userBorrowConfigs_ = new AdminModuleStructs.UserBorrowConfig[](1);
        userBorrowConfigs_[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(DAI),
            token: address(USDC),
            mode: 1,
            expandPercent: 5000,
            expandDuration: 60,
            baseDebtCeiling: 1000 ether,
            maxDebtCeiling: 1000 ether
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateUserBorrowConfigs(userBorrowConfigs_);

        // Make Alice a guardian
        AdminModuleStructs.AddressBool[] memory updateGuardiansParams = new AdminModuleStructs.AddressBool[](1);
        updateGuardiansParams[0] = AdminModuleStructs.AddressBool(alice, true);

        // add guardians
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateGuardians(updateGuardiansParams);
    }

    function test_GuardianPauseUser() public {
        uint256 userSupplyData_ = resolver.getUserSupply(address(DAI), address(USDC));
        assertEq((userSupplyData_ >> 255) & 1, 0); // paused flag bit

        uint256 userBorrowData_ = resolver.getUserBorrow(address(DAI), address(USDC));
        assertEq((userBorrowData_ >> 255) & 1, 0); // paused flag bit
        // tokens to pause
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        // pause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(DAI), tokens_, tokens_);

        // check it made paused flag bit 1
        userSupplyData_ = resolver.getUserSupply(address(DAI), address(USDC));
        assertEq((userSupplyData_ >> 255) & 1, 1); // paused flag bit

        userBorrowData_ = resolver.getUserBorrow(address(DAI), address(USDC));
        assertEq((userBorrowData_ >> 255) & 1, 1); // paused flag bit
    }

    function test_GuardianPauseUser_LogPauseUser() public {
        // tokens to pause
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        // set expected event
        vm.expectEmit(true, false, false, false);
        emit LogPauseUser(address(DAI), tokens_, tokens_);

        // pause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(DAI), tokens_, tokens_);
    }

    function test_GuardianPauseUser_RevertUserNotDefined() public {
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        address[] memory noTokens_ = new address[](0);

        // set expected revert on the borrow pause
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotDefined)
        );

        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(resolver), noTokens_, tokens_);

        // set expected revert on the supply pause
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidLiquidityError.selector, ErrorTypes.AdminModule__UserNotDefined)
        );

        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(resolver), tokens_, noTokens_);
    }

    function test_GuardianUnpauseUser() public {
        // tokens to pause
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        // pause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(DAI), tokens_, tokens_);

        // check it made paused flag bit 1
        uint256 userSupplyData_ = resolver.getUserSupply(address(DAI), address(USDC));
        assertEq((userSupplyData_ >> 255) & 1, 1); // paused flag bit

        uint256 userBorrowData_ = resolver.getUserBorrow(address(DAI), address(USDC));
        assertEq((userBorrowData_ >> 255) & 1, 1); // paused flag bit

        // unpause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).unpauseUser(address(DAI), tokens_, tokens_);

        // check it made paused flag bit 0
        userSupplyData_ = resolver.getUserSupply(address(DAI), address(USDC));
        assertEq((userSupplyData_ >> 255) & 1, 0); // paused flag bit

        userBorrowData_ = resolver.getUserBorrow(address(DAI), address(USDC));
        assertEq((userBorrowData_ >> 255) & 1, 0); // paused flag bit
    }

    function test_GuardianUnpauseUser_LogUnpauseUser() public {
        // tokens to pause
        address[] memory tokens_ = new address[](1);
        tokens_[0] = address(USDC);

        // pause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).pauseUser(address(DAI), tokens_, tokens_);

        // set expected event
        vm.expectEmit(true, false, false, false);
        emit LogUnpauseUser(address(DAI), tokens_, tokens_);

        // unpause user as guardian
        vm.prank(alice);
        FluidLiquidityAdminModule(address(liquidity)).unpauseUser(address(DAI), tokens_, tokens_);
    }
}
