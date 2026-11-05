//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// todo: transfer to resolver tests -> or integrate with Liquidity tests directly?

// import { LiquidityBaseTest } from "./liquidityBaseTest.t.sol";
// import { AuthModule, GuardianModule } from "../../../contracts/liquidity/adminModule/main.sol";
// import { FluidLiquidityUserModule } from "../../../contracts/liquidity/userModule/main.sol";
// import { ReadModule } from "../../../contracts/liquidity/readModule/main.sol";

// contract LiquidityReadModuleBaseTest is LiquidityBaseTest {
//     function setUp() public virtual override {
//         super.setUp();

//         _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
//         _setDefaultRateDataV1(address(liquidity), admin, address(DAI));

//         _setDefaultTokenFee(address(liquidity), admin, address(USDC));
//         _setDefaultTokenFee(address(liquidity), admin, address(DAI));

//         _setUserAllowancesDefault(address(liquidity), admin, address(USDC), alice);
//         _setUserAllowancesDefault(address(liquidity), admin, address(DAI), alice);
//         _setUserAllowancesDefault(address(liquidity), admin, address(USDC), bob);
//         _setUserAllowancesDefault(address(liquidity), admin, address(DAI), bob);
//     }
// }

// contract LiquidityReadModuleConfigsTest is LiquidityReadModuleBaseTest {
//     function testReadGovernanceAddress() public {
//         assertEq(ReadModule(address(liquidity)).governance(), admin);
//     }

//     /// @dev all other view Methods regarding adminModule are indirectly tested through the other tests for adminModule
//     /// that update the respective value and then check via the view method if it was set (i.e. and read) correctly!
//     /// specifically the following methods are covered in liquidityAdminModule tests:
//     /// - ReadModule.allowancesOf.selector, (tested in liquidityUserModule tests)
//     /// - ReadModule.tokenFee.selector,
//     /// - ReadModule.riskyYieldPremium.selector,
//     /// - ReadModule.isAuth.selector,
//     /// - ReadModule.isGuardian.selector,
//     /// - ReadModule.isPaused.selector,
//     /// - ReadModule.rateDataV1.selector,
//     /// - ReadModule.rateDataV2.selector,
//     /// - ReadModule.rateDataVersion.selector
//     /// - ReadModule.revenue.selector
// }

// contract LiquidityReadModuleBalancesOfTest is LiquidityReadModuleBaseTest {
//     function testReadBalancesOf() public {
//         // 1. supply safe as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(USDC), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 2. borrow as bob
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), DEFAULT_BORROW_AMOUNT, bob);

//         // 3. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 4. supply risky as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplyRisky
//         FluidLiquidityUserModule(address(liquidity)).supplyRisky(address(USDC), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 5. check balances of for alice, who supplied safe and risky but did not borrow
//         // for calculation of exchange prices explanation see test "testUserExchangePricesEventsWithBorrowers"
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 201712328; // 0,000201712328767123287671232876732 in 12 decimals

//         (uint256 suppliedSafe_, uint256 suppliedRisky_, uint256 borrowed_) = ReadModule(address(liquidity)).balancesOf(
//             address(USDC),
//             alice
//         );
//         // suppliedSafe_ = supply amount * current exchange price.
//         assertEq(suppliedSafe_, (DEFAULT_SUPPLY_AMOUNT * newSupplySafeExchangePrice) / EXCHANGE_PRICES_PRECISION);
//         // supply risky has just now been supplied, didn't receive any interest yet
//         assertEq(suppliedRisky_, 1e18);
//         // alice has no borrowings
//         assertEq(borrowed_, 0); //

//         // 6. check balances of for bob, who only borrowed
//         (suppliedSafe_, suppliedRisky_, borrowed_) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);

//         // bob has no supplies
//         assertEq(suppliedSafe_, 0);
//         assertEq(suppliedRisky_, 0);
//         // borrowed_ = borrow amount * current exchange price.
//         assertEq(borrowed_, (DEFAULT_BORROW_AMOUNT * newBorrowExchangePrice) / EXCHANGE_PRICES_PRECISION);

//         // 7. simulate passing time again (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 8. check balances of for alice, who supplied safe and risky but did not borrow
//         // calculation of new exchange prices based on see test "testUserExchangePricesEventsWithBorrowers"
//         // utilization = 25008 (raw borrow / raw supply)
//         // borrow rate annual = 4% + 1.8756% (25.008 / 8 * 0.6%) = 5.8756%
//         // passed time in percent = 172800 / 31536000 = 0,00547945205479452054794520548, rounded up in 1e12: 0,00547945206
//         // so rate increase = 5.8756% * 0,00547945206 = 0,032195068523736 %
//         // total new borrowings = previous borrow amount raw * rate increase.
//         // = 0,500212328767120000 * 0,032195068493150684931506849 % = 0,000161043701857758
//         // lenders get this minus token fee (5%) = 0,000152991516764870
//         // supplies are supply risky = 1 ether. supply safe = 1 ether * previous exchange price (1,000201712328767122)
//         // total supply = 2,000201712328767122, percentages: safe 50,0050422996721734420995826015%
//         // so safe gets 0,000152991516764870 * 50,005[] % = 0,000076503472673183, adding this to previous safe supply
//         // = 1,00020171232876 + 0,000076503472673183 = 1,000278215801433183
//         // risky gets the rest, 0,000076488044091687, adding to previous supply is simply this plus 1e18

//         newBorrowExchangePrice = (newBorrowExchangePrice * 1000321950686) / EXCHANGE_PRICES_PRECISION; //  0,032195068523736 % in 12 decimals, rounded up
//         newSupplySafeExchangePrice += 201712328; // 0,000201712328767123287671232876732 in 12 decimals
//         (suppliedSafe_, suppliedRisky_, borrowed_) = ReadModule(address(liquidity)).balancesOf(address(USDC), alice);

//         assertEq(suppliedSafe_, 1000278215800000000); // 1,000278215801433183 in EXCHANGE_PRICES_PRECISION
//         assertEq(suppliedRisky_, 1000076488044000000);
//         // alice has no borrowings
//         assertEq(borrowed_, 0);

//         // 8. check balances of for bob, who only borrowed
//         (suppliedSafe_, suppliedRisky_, borrowed_) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);

//         // bob has no supplies
//         assertEq(suppliedSafe_, 0);
//         assertEq(suppliedRisky_, 0);
//         // borrowed_ = borrow amount * new exchange price.
//         assertEq(borrowed_, (DEFAULT_BORROW_AMOUNT * newBorrowExchangePrice) / EXCHANGE_PRICES_PRECISION);
//     }
// }

// contract LiquidityReadModuleRatesTest is LiquidityReadModuleBaseTest {
//     function setUp() public override {
//         super.setUp();

//         // set default risky yield premium
//         _setDefaultRiskyYieldPremium(address(liquidity), admin, address(USDC));
//     }

//     // ---------------- UTILIZATION --------------------------------

//     function testReadUtilizationNoBorrowers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).utilization(address(USDC)), 0);
//     }

//     function testReadUtilizationSomeBorrowers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(50 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(
//             ReadModule(address(liquidity)).utilization(address(USDC)),
//             (DEFAULT_BORROW_AMOUNT * 1e6) / DEFAULT_SUPPLY_AMOUNT
//         );
//     }

//     function testReadUtilizationMaxBorrowers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).utilization(address(USDC)), 1e6);
//     }

//     // ---------------- BORROW APR --------------------------------

//     function testReadBorrowAPRNoBorrowers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).borrowAPR(address(USDC)), DEFAULT_RATE_AT_ZERO / 1e2);
//     }

//     function testReadBorrowAPRBelowKink() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(40 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results (7% in 1e6 because constant + half way to kink which is 10% at 80%)
//         assertEq(ReadModule(address(liquidity)).borrowAPR(address(USDC)), 7_000_000 / 1e2);
//     }

//     function testReadBorrowAPRAtKink() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(80 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).borrowAPR(address(USDC)), DEFAULT_RATE_AT_KINK / 1e2);
//     }

//     function testReadBorrowAPRAboveKink() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(90 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results (80% in 1e6 because kink + half way to max which is 150% at 100%)
//         assertEq(ReadModule(address(liquidity)).borrowAPR(address(USDC)), 80_000_000 / 1e2);
//     }

//     function testReadBorrowAPRAtMax() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results (80% in 1e6 because kink + half way to max which is 150% at 100%)
//         assertEq(ReadModule(address(liquidity)).borrowAPR(address(USDC)), DEFAULT_RATE_AT_MAX / 1e2);
//     }

//     // ---------------- SUPPLY SAFE APR --------------------------------

//     function testReadSupplySafeAPRNoBorrowers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 0);
//     }

//     function testReadSupplySafeAPRBelowKinkNoRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(40 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // borrow APR = 7%, minus token fee 5% of it is 6.65%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 6_650_000 / 1e2);
//     }

//     function testReadSupplySafeAPRBelowKinkWithRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(40 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // borrow APR = 7%, minus token fee 5% of it is 6.65%
//         // 20% of that goes from safe to risky, 6.65% * 80% = 5,32%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 5_320_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAtKinkNoRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(80 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // default rate at kink = 10%, minus the 5% token fee is 9.5%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 9_500_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAtKinkWithRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(80 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // default rate at kink = 10%, minus the 5% token fee is 9.5%
//         // 20% of that goes from safe to risky, 9.5% * 80% = 7,6%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 7_600_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAboveKinkNoRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(90 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // borrow rate = 80% in 1e6 because kink + half way to max which is 150% at 100%
//         // minus the 5% token fee is 76%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 76_000_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAboveKinkWithRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(90 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // 76% but 20% of that goes to risky suppliers -> 60,8%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 60_800_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAtMaxNoRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // Default rate at max = 150%, minus the 5% token fee is 142.5%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 142_500_000 / 1e2);
//     }

//     function testReadSupplySafeAPRAtMaxkWithRiskySuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // 142.5% but 20% of that goes to risky suppliers -> 114%
//         assertEq(ReadModule(address(liquidity)).supplySafeAPR(address(USDC)), 114_000_000 / 1e2);
//     }

//     // ---------------- SUPPLY RISKY APR --------------------------------

//     function testReadSupplyRiskyAPRNoBorrowers() public {
//         // 1. set utilization
//         _setSupplyRiskyUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 0);
//     }

//     function testReadSupplyRiskyAPRBelowKinkNoSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplyRiskyUtilization(40 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // 65_500_000_000
//         // borrow APR = 7%, minus token fee 5% of it is 6.65%
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 6_650_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRBelowKinkWithSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(40 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // borrow APR = 7%, minus token fee 5% of it is 6.65%
//         // safeEarnings = Default supply * 6.65% = 1_000_000_000_000_000_000 * 6.65% = 66_500_000_000_000_000
//         // 20% of that goes from safe to risky, 66_500_000_000_000_000 * 20% = 13_300_000_000_000_000
//         // risky earnings = 66_500_000_000_000_000 + 13_300_000_000_000_000 = 79_800_000_000_000_000
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 7_980_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAtKinkNoSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplyRiskyUtilization(80 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // default rate at kink = 10%, minus the 5% token fee is 9.5%
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 9_500_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAtKinkWithSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(80 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // default rate at kink = 10%, minus the 5% token fee is 9.5%
//         // safeEarnings = Default supply * 9.5% = 1_000_000_000_000_000_000 * 9.5% = 95_000_000_000_000_000
//         // 20% of that goes from safe to risky, 95_000_000_000_000_000 * 20% = 19_000_000_000_000_000
//         // risky earnings = 95_000_000_000_000_000 + 19_000_000_000_000_000 = 114_000_000_000_000_000
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 11_400_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAboveKinkNoSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplyRiskyUtilization(90 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // borrow rate = 80% in 1e6 because kink + half way to max which is 150% at 100%, so: 10% + 70%
//         // minus the 5% token fee is 76%
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 76_000_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAboveKinkWithSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(90 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // safeEarnings = Default supply * 76% = 1_000_000_000_000_000_000 * 76% = 760_000_000_000_000_000
//         // 20% of that goes from safe to risky, 760_000_000_000_000_000 * 20% = 152_000_000_000_000_000
//         // risky earnings = 760_000_000_000_000_000 + 152_000_000_000_000_000 = 912_000_000_000_000_000
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 91_200_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAtMaxNoSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplyRiskyUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // Default rate at max = 150%, minus the 5% token fee is 142.5%
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 142_500_000 / 1e2);
//     }

//     function testReadSupplyRiskyAPRAtMaxkWithSafeSuppliers() public {
//         // 1. set utilization
//         _setSupplySafeAndRiskyUtilization(100 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 2. assert expected results
//         // safeEarnings = Default supply * 142.5% = 1_000_000_000_000_000_000 * 142.5% = 14_250_000_000_000_000_000
//         // 20% of that goes from safe to risky, 14_250_000_000_000_000_000 * 20% = 2_850_000_000_000_000_000
//         // risky earnings = 14_250_000_000_000_000_000 + 2_850_000_000_000_000_000 = 17_100_000_000_000_000_000
//         assertEq(ReadModule(address(liquidity)).supplyRiskyAPR(address(USDC)), 171_000_000 / 1e2);
//     }
// }

// contract LiquidityReadModuleTotalAmountsTest is LiquidityReadModuleBaseTest {
//     function testReadTotalSupplySafe() public {
//         // 1. assert initial values
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), 0);

//         // 2. set utilization (will execute supply)
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 3. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), DEFAULT_SUPPLY_AMOUNT);

//         // 4. set utilization (will execute supply again)
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 5. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);

//         // 6. withdraw some amount
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).withdrawSafe(address(USDC), DEFAULT_WITHDRAW_AMOUNT, alice);

//         // 7. assert expected results
//         assertEq(
//             ReadModule(address(liquidity)).totalSupplySafe(address(USDC)),
//             DEFAULT_SUPPLY_AMOUNT * 2 - DEFAULT_WITHDRAW_AMOUNT
//         );
//     }

//     function testReadTotalSupplyRisky() public {
//         // 1. assert initial values
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), 0);

//         // 2. set utilization (will execute supply)
//         _setSupplyRiskyUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 3. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), DEFAULT_SUPPLY_AMOUNT);

//         // 4. set utilization (will execute supply again)
//         _setSupplyRiskyUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 5. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);

//         // 6. withdraw some amount
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).withdrawRisky(address(USDC), DEFAULT_WITHDRAW_AMOUNT, alice);

//         // 7. assert expected results
//         assertEq(
//             ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)),
//             DEFAULT_SUPPLY_AMOUNT * 2 - DEFAULT_WITHDRAW_AMOUNT
//         );
//     }

//     function testReadTotalSupply() public {
//         // 1. assert initial values
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), 0);
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), 0);
//         assertEq(ReadModule(address(liquidity)).totalSupply(address(USDC)), 0);

//         // 2. set utilization (will execute supply risky)
//         _setSupplyRiskyUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 3. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), 0);
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), DEFAULT_SUPPLY_AMOUNT);
//         assertEq(ReadModule(address(liquidity)).totalSupply(address(USDC)), DEFAULT_SUPPLY_AMOUNT);

//         // 4. set utilization (will execute supply safe)
//         _setSupplySafeUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 5. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), DEFAULT_SUPPLY_AMOUNT);
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), DEFAULT_SUPPLY_AMOUNT);
//         assertEq(ReadModule(address(liquidity)).totalSupply(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);

//         // 6. set utilization (will execute supply safe & supply risky)
//         _setSupplySafeAndRiskyUtilization(0 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 7. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);
//         assertEq(ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);
//         assertEq(ReadModule(address(liquidity)).totalSupply(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 4);

//         // 8. withdraw some amount
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).withdrawRisky(address(USDC), DEFAULT_WITHDRAW_AMOUNT, alice);

//         // 9. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupplySafe(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);
//         assertEq(
//             ReadModule(address(liquidity)).totalSupplyRisky(address(USDC)),
//             DEFAULT_SUPPLY_AMOUNT * 2 - DEFAULT_WITHDRAW_AMOUNT
//         );
//         assertEq(
//             ReadModule(address(liquidity)).totalSupply(address(USDC)),
//             DEFAULT_SUPPLY_AMOUNT * 4 - DEFAULT_WITHDRAW_AMOUNT
//         );
//     }

//     function testReadTotalBorrow() public {
//         // 1. assert initial values
//         assertEq(ReadModule(address(liquidity)).totalBorrow(address(USDC)), 0);

//         // 2. set utilization (will execute supply safe & supply risky & borrow)
//         _setSupplySafeAndRiskyUtilization(50 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 3. assert expected results
//         assertEq(ReadModule(address(liquidity)).totalSupply(address(USDC)), DEFAULT_SUPPLY_AMOUNT * 2);
//         // total borrow should be 50% of total supply
//         assertEq(ReadModule(address(liquidity)).totalBorrow(address(USDC)), DEFAULT_SUPPLY_AMOUNT);

//         // 4. borrow more
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), DEFAULT_BORROW_AMOUNT, bob);

//         // 5. assert expected results
//         assertEq(
//             ReadModule(address(liquidity)).totalBorrow(address(USDC)),
//             DEFAULT_SUPPLY_AMOUNT + DEFAULT_BORROW_AMOUNT
//         );
//     }
// }

// /// @dev The following tests are almost identical with LiquidityUserModuleUpdateExchangePricesTest
// contract LiquidityReadModuleExchangePricesTest is LiquidityReadModuleBaseTest {
//     function testReadExchangePricesDefault() public {
//         // read
//         address[] memory tokens_ = new address[](2);
//         tokens_[0] = address(USDC);
//         tokens_[1] = address(DAI);
//         (
//             uint256[] memory supplySafeExchangePrices,
//             uint256[] memory supplyRiskyExchangePrices,
//             uint256[] memory borrowExchangePrices
//         ) = ReadModule(address(liquidity)).exchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//     }

//     function testReadExchangePricesSupplySafe() public {
//         // 1. supply safe as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(USDC), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 2. borrow as bob
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), DEFAULT_BORROW_AMOUNT, bob);

//         // 3. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 4. check exchange prices
//         // for calculation of exchange prices explanation see test "testUserExchangePricesEventsWithBorrowers"
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 201712328; // 0,000201712328767123287671232876732 in 12 decimals

//         // read
//         address[] memory tokens_ = new address[](2);
//         tokens_[0] = address(USDC);
//         tokens_[1] = address(DAI);
//         (
//             uint256[] memory supplySafeExchangePrices,
//             uint256[] memory supplyRiskyExchangePrices,
//             uint256[] memory borrowExchangePrices
//         ) = ReadModule(address(liquidity)).exchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePrice);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//     }

//     function testReadExchangePrices() public {
//         // set risky yield premium
//         _setDefaultRiskyYieldPremium(address(liquidity), admin, address(USDC));

//         // 1. supply safe as alice
//         // USDC
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, alice);
//         // DAI
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(DAI), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 2. supply risky as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplyRisky(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, alice);

//         // 3. borrow as bob
//         // USDC
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), DEFAULT_BORROW_AMOUNT, bob);
//         // DAI
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(DAI), DEFAULT_BORROW_AMOUNT, bob);

//         // 4. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 5. check exchange prices
//         // calculation for borrow exchange price same as in test without the risky yield premium
//         // so rate increase = 7.75% * 0,00547945205479452054794520548 = 0,04246575342465753424657534247 %
//         uint256 newBorrowExchangePriceUSDC = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         // borrowers pay amountBorrowed (0.5 * 1e18) * rate increase =
//         // 500000000000000000 * 0,04246575342465753424657534247% = 0,00021232876712328767123287671235 * 1e18
//         // for suppliers, they get the amount borrowers pay minus the fee. default fee is set to 5%.
//         // 0,00021232876712328767123287671235 * 1e18 * 0.95 = 0,000201712328767123287671232876732
//         // supply amounts for safe and risky are 50% each, so safe gets 50% of this but 20% of that amount goes to risky
//         // 1/2 * 1/5 = 1/10 of total goes to risky instead of safe. so safe gets 40%, risky gets 60%.
//         // safeEarnings = 0,00008068493150684931506849315; riskyEarnings = 0,00012102739726027397260273973
//         // because supply is only half, amounts must be adjusted. price = supply + earnings / supply
//         // for safe = 500080684931506849÷500000000000000000 = 1,000161369863013698
//         // for risky = 500121027397260273÷500000000000000000 = 1,000242054794520546
//         uint256 newSupplySafeExchangePriceUSDC = EXCHANGE_PRICES_PRECISION + 161369863; // 1,000161369863013698 in 12 decimals
//         uint256 newSupplyRiskyExchangePriceUSDC = EXCHANGE_PRICES_PRECISION + 242054794; // 1,000242054794520546 in 12 decimals

//         // for calculation of exchange prices explanation see test "testUserExchangePricesEventsWithBorrowers"
//         uint256 newBorrowExchangePriceDAI = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         uint256 newSupplySafeExchangePriceDAI = EXCHANGE_PRICES_PRECISION + 201712328; // 0,000201712328767123287671232876732 in 12 decimals

//         // read
//         address[] memory tokens_ = new address[](2);
//         tokens_[0] = address(USDC);
//         tokens_[1] = address(DAI);
//         (
//             uint256[] memory supplySafeExchangePrices,
//             uint256[] memory supplyRiskyExchangePrices,
//             uint256[] memory borrowExchangePrices
//         ) = ReadModule(address(liquidity)).exchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePriceUSDC);
//         assertEq(supplyRiskyExchangePrices[0], newSupplyRiskyExchangePriceUSDC);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePriceUSDC);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], newSupplySafeExchangePriceDAI);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], newBorrowExchangePriceDAI);
//     }

//     function testReadExchangePricesAboveKink() public {
//         // set risky yield premium
//         _setDefaultRiskyYieldPremium(address(liquidity), admin, address(USDC));

//         // 1. supply safe as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(USDC), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 2. supply risky as alice
//         // prank msg.sender to be alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplyRisky(address(USDC), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 3. borrow as bob
//         uint256 borrowAmount = ((DEFAULT_SUPPLY_AMOUNT * 2 * 90) / 100);
//         // prank msg.sender to be bob
//         vm.prank(bob);
//         // execute borrow, borrow 90% of supplied amount
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowAmount, bob);

//         // 4. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 5. check exchange prices
//         // for new borrow exchange price:
//         // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 90%:
//         // at 80% it is 10%, at 100% it's 150%, 90% is exactly in between so 80%.
//         // seconds per year = 31536000
//         // passed seconds = 2 days = 172800
//         // so in 31536000 seconds borrowers pay 80%. how much do they pay in 172800 seconds?
//         // passed time in percent = 172800 / 31536000 = 0,00547945205479452054794520548
//         // so rate increase = 80% * 0,00547945205479452054794520548 = 0,438356164383561643835616438 %
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 4383561644; // 0,438356164383561643835616438% in 12 decimals, rounding up
//         // borrowers pay amountBorrowed * rate increase =
//         // 1800000000000000000 * 0,438356164383561643835616438% = 0,00078904109589041095890410958912
//         // for suppliers, they get the amount borrowers pay minus the fee. default fee is set to 5%.
//         // 0,00078904109589041095890410958912 * 1e18 * 0.95 = 0,000749589041095890410958904109664
//         // supply amounts for safe and risky are 50% each, so safe gets 50% of this but 20% of that amount goes to risky
//         // 1/2 * 1/5 = 1/10 of total goes to risky instead of safe. so safe gets 40%, risky gets 60%.
//         // riskyEarnings = 0,000449753424657534246575342465798; safeEarnings = 0,000299835616438356164383561643866
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 2998356164; // 0,000299835616438356164383561643866 in 12 decimals
//         uint256 newSupplyRiskyExchangePrice = EXCHANGE_PRICES_PRECISION + 4497534246; // 0,000449753424657534246575342465798 in 12 decimals

//         // read
//         address[] memory tokens_ = new address[](1);
//         tokens_[0] = address(USDC);
//         (
//             uint256[] memory supplySafeExchangePrices,
//             uint256[] memory supplyRiskyExchangePrices,
//             uint256[] memory borrowExchangePrices
//         ) = ReadModule(address(liquidity)).exchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrices[0], newSupplyRiskyExchangePrice);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePrice);

//         assertEq(supplySafeExchangePrices.length, 1);
//         assertEq(supplyRiskyExchangePrices.length, 1);
//         assertEq(borrowExchangePrices.length, 1);

//         // read single exchangePrice()
//         (uint256 supplySafeExchangePrice, uint256 supplyRiskyExchangePrice, uint256 borrowExchangePrice) = ReadModule(
//             address(liquidity)
//         ).exchangePrice(address(USDC));

//         // assert for USDC
//         assertEq(supplySafeExchangePrice, newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrice, newSupplyRiskyExchangePrice);
//         assertEq(borrowExchangePrice, newBorrowExchangePrice);
//     }
// }

// contract LiquidityReadModuleRateDatasTest is LiquidityReadModuleBaseTest {
//     function testReadRateDataV2sForRateDataV1Revert() public {
//         // set rate data v1
//         _setDefaultRateDataV1(address(liquidity), admin, address(USDC));
//         assertEq(ReadModule(address(liquidity)).rateDataVersion(address(USDC)), 1);

//         // set expected revert
//         vm.expectRevert(ReadModule.ReadModuleRateDataVersionMismatch.selector);

//         // execute read rate data v2
//         ReadModule(address(liquidity)).rateDataV2(address(USDC));
//     }

//     function testReadRateDataV1sForRateDataV2Revert() public {
//         // set rate data v2
//         _setDefaultRateDataV2(address(liquidity), admin, address(USDC));
//         assertEq(ReadModule(address(liquidity)).rateDataVersion(address(USDC)), 2);

//         // set expected revert
//         vm.expectRevert(ReadModule.ReadModuleRateDataVersionMismatch.selector);

//         // execute read rata data v1
//         ReadModule(address(liquidity)).rateDataV1(address(USDC));
//     }
// }
