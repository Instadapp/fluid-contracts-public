//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestERC20 } from "../testERC20.sol";
import { TestERC20Dec6 } from "../testERC20Dec6.sol";
import { TestHelpers } from "./liquidityTestHelpers.sol";

import { FluidLiquidityUserModule } from "../../../contracts/liquidity/userModule/main.sol";
import { FluidLiquidityAdminModule, AuthModule, GuardianModule, GovernanceModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { FluidLiquidityProxy } from "../../../contracts/liquidity/proxy.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { MockProtocol } from "../../../contracts/mocks/mockProtocol.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

interface IVariables {
    function revenueCollector() external view returns (address);
}

abstract contract LiquidityBaseTest is Test, TestHelpers {
    FluidLiquidityProxy liquidity;
    FluidLiquidityAdminModule adminModule;
    bytes4[] adminSigs;
    FluidLiquidityUserModule userModule;
    bytes4[] userSigs;
    FluidLiquidityResolver resolver;
    MockProtocol mockProtocol; // can have switching mode according to test
    MockProtocol mockProtocolInterestFree; // always as interest free mode
    MockProtocol mockProtocolWithInterest; // always as with interest mode

    IERC20 DAI;
    TestERC20Dec6 USDC;

    TestERC20Dec6 USDT;
    IERC20 SUSDE;

    address payable internal admin = payable(makeAddr("admin"));
    address payable internal alice;
    uint256 internal alicePrivateKey;
    address payable internal bob = payable(makeAddr("bob"));

    bytes32 internal constant SKIP_TRANSFERS = keccak256(bytes("SKIP_TRANSFERS"));

    function setUp() public virtual {
        address aliceAddr;
        (aliceAddr, alicePrivateKey) = makeAddrAndKey("alice");
        alice = payable(aliceAddr);

        liquidity = new FluidLiquidityProxy(admin, address(0));
        resolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        userModule = new FluidLiquidityUserModule();
        adminModule = new FluidLiquidityAdminModule(1e10 * 1e18); // set native token max hard cap very high so it can be ignored for noramal tests
        mockProtocol = new MockProtocol(address(liquidity));
        mockProtocolInterestFree = new MockProtocol(address(liquidity));
        mockProtocolWithInterest = new MockProtocol(address(liquidity));

        adminSigs = [
            AuthModule.updateRateDataV1s.selector,
            AuthModule.updateRateDataV2s.selector,
            GovernanceModule.updateAuths.selector,
            GovernanceModule.updateRevenueCollector.selector,
            GovernanceModule.updateGuardians.selector,
            IVariables.revenueCollector.selector,
            AuthModule.collectRevenue.selector,
            AuthModule.updateTokenConfigs.selector,
            AuthModule.updateUserWithdrawalLimit.selector,
            AuthModule.updateUserSupplyConfigs.selector,
            AuthModule.updateUserBorrowConfigs.selector,
            AuthModule.updateUserClasses.selector,
            AuthModule.changeStatus.selector,
            GuardianModule.pauseUser.selector,
            GuardianModule.unpauseUser.selector,
            FluidLiquidityAdminModule.updateExchangePrices.selector
        ];

        userSigs = [FluidLiquidityUserModule.operate.selector];

        // add admin module functions
        vm.prank(admin);
        liquidity.addImplementation(address(adminModule), adminSigs);

        // add user module functions
        vm.prank(admin);
        liquidity.addImplementation(address(userModule), userSigs);

        USDC = new TestERC20Dec6("USDC", "USDC");
        DAI = new TestERC20("DAI", "DAI");
        SUSDE = new TestERC20("SUSDE", "SUSDE");
        USDT = new TestERC20Dec6("USDT", "USDT");

        TestERC20Dec6(address(USDC)).mint(alice, 1e50 ether);
        TestERC20(address(DAI)).mint(alice, 1e50 ether);
        TestERC20Dec6(address(USDT)).mint(alice, 1e50 ether);
        TestERC20(address(SUSDE)).mint(alice, 1e50 ether);
        TestERC20Dec6(address(USDC)).mint(bob, 1e50 ether);
        TestERC20(address(DAI)).mint(bob, 1e50 ether);
        TestERC20Dec6(address(USDT)).mint(bob, 1e50 ether);
        TestERC20(address(SUSDE)).mint(bob, 1e50 ether);
        vm.deal(alice, 1e50 ether);
        vm.deal(bob, 1e50 ether);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDT), "USDT");
        vm.label(address(SUSDE), "SUSDE");

        // give approvals to MockProtocol. operations have to go through a protocol because of liquidityCallback
        _setApproval(USDC, address(mockProtocol), alice);
        _setApproval(USDC, address(mockProtocol), bob);
        _setApproval(DAI, address(mockProtocol), alice);
        _setApproval(DAI, address(mockProtocol), bob);
        _setApproval(USDT, address(mockProtocol), alice);
        _setApproval(USDT, address(mockProtocol), bob);
        _setApproval(SUSDE, address(mockProtocol), alice);
        _setApproval(SUSDE, address(mockProtocol), bob);

        _setApproval(USDC, address(mockProtocolInterestFree), alice);
        _setApproval(USDC, address(mockProtocolInterestFree), bob);
        _setApproval(DAI, address(mockProtocolInterestFree), alice);
        _setApproval(DAI, address(mockProtocolInterestFree), bob);
        _setApproval(USDT, address(mockProtocolInterestFree), alice);
        _setApproval(USDT, address(mockProtocolInterestFree), bob);
        _setApproval(SUSDE, address(mockProtocolInterestFree), alice);
        _setApproval(SUSDE, address(mockProtocolInterestFree), bob);

        _setApproval(USDC, address(mockProtocolWithInterest), alice);
        _setApproval(USDC, address(mockProtocolWithInterest), bob);
        _setApproval(DAI, address(mockProtocolWithInterest), alice);
        _setApproval(DAI, address(mockProtocolWithInterest), bob);
        _setApproval(USDT, address(mockProtocolWithInterest), alice);
        _setApproval(USDT, address(mockProtocolWithInterest), bob);
        _setApproval(SUSDE, address(mockProtocolWithInterest), alice);
        _setApproval(SUSDE, address(mockProtocolWithInterest), bob);

        // 1. Setup rate data for USDC and DAI, must happen before token configs
        _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
        _setDefaultRateDataV1(address(liquidity), admin, address(USDT));
        _setDefaultRateDataV1(address(liquidity), admin, address(DAI));
        _setDefaultRateDataV1(address(liquidity), admin, address(SUSDE));
        _setDefaultRateDataV1(address(liquidity), admin, NATIVE_TOKEN_ADDRESS);

        // 2. Add a token configuration for USDC and DAI
        AdminModuleStructs.TokenConfig[] memory tokenConfigs_ = new AdminModuleStructs.TokenConfig[](5);
        tokenConfigs_[0] = AdminModuleStructs.TokenConfig({
            token: address(USDC),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[1] = AdminModuleStructs.TokenConfig({
            token: address(DAI),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[2] = AdminModuleStructs.TokenConfig({
            token: NATIVE_TOKEN_ADDRESS,
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[3] = AdminModuleStructs.TokenConfig({
            token: address(USDT),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });
        tokenConfigs_[4] = AdminModuleStructs.TokenConfig({
            token: address(SUSDE),
            // set threshold and fee to 0 so it doesn't affect tests that don't specifically target testing this
            fee: 0,
            threshold: 0,
            maxUtilization: 1e4 // 100%
        });

        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateTokenConfigs(tokenConfigs_);

        _setUserAllowancesDefaultInterestFree(
            address(liquidity),
            admin,
            address(USDC),
            address(mockProtocolInterestFree)
        );
        _setUserAllowancesDefaultInterestFree(
            address(liquidity),
            admin,
            address(DAI),
            address(mockProtocolInterestFree)
        );
        _setUserAllowancesDefaultInterestFree(
            address(liquidity),
            admin,
            NATIVE_TOKEN_ADDRESS,
            address(mockProtocolInterestFree)
        );
        _setUserAllowancesDefaultInterestFree(
            address(liquidity),
            admin,
            address(USDT),
            address(mockProtocolInterestFree)
        );
        _setUserAllowancesDefaultInterestFree(
            address(liquidity),
            admin,
            address(SUSDE),
            address(mockProtocolInterestFree)
        );

        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocolWithInterest));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocolWithInterest));
        _setUserAllowancesDefault(address(liquidity), admin, address(USDT), address(mockProtocolWithInterest));
        _setUserAllowancesDefault(address(liquidity), admin, address(SUSDE), address(mockProtocolWithInterest));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocolWithInterest));
    }
}
