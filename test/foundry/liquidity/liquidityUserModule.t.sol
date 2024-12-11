//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// contract LiquidityUserModuleExchangePricesFromEventsTest is LiquidityUserModuleBaseTest {
//     function testUserExchangePricesEventsNoBorrowers() public {
//         int256 balanceBefore = int256(USDC.balanceOf(alice));

//         // set expected event
//         vm.expectEmit(true, true, true, true);
//         emit LogOperate(
//             alice,
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             0,
//             0,
//             0,
//             0,
//             EXCHANGE_PRICES_PRECISION,
//             EXCHANGE_PRICES_PRECISION
//         );

//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // simulate passing time
//         vm.warp(2 days);

//         // set expected event, still precision everywhere because nobody is borrowing, totalSupply should be 2x amount
//         vm.expectEmit(true, true, true, true);
//         emit LogOperate(
//             alice,
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             0,
//             0,
//             0,
//             0,
//             EXCHANGE_PRICES_PRECISION,
//             EXCHANGE_PRICES_PRECISION
//         );

//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         int256 balanceAfter = int256(USDC.balanceOf(alice));
//         assertEq(balanceAfter, balanceBefore - DEFAULT_SUPPLY_AMOUNT * 2);
//     }

//     function testUserExchangePricesEventsWithBorrowers() public {
//         // 1. supply as alice
//         // set expected event
//         vm.expectEmit(true, true, true, true);
//         emit LogOperate(
//             alice,
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             0,
//             0,
//             0,
//             0,
//             EXCHANGE_PRICES_PRECISION,
//             EXCHANGE_PRICES_PRECISION
//         );

//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 2. borrow as bob
//         // set expected event
//         vm.expectEmit(true, true, true, true);
//         emit LogOperate(
//             bob,
//             address(USDC),
//             0,
//             DEFAULT_BORROW_AMOUNT,
//             address(0),
//             address(0),
//             0,
//             0,
//             0,
//             0,
//             EXCHANGE_PRICES_PRECISION,
//             EXCHANGE_PRICES_PRECISION
//         );

//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

//         // 3. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 4. supply as alice again and expect calc interest to be collected correctly: set expected event
//         // for new borrow exchange price:
//         // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 50%:
//         // for every 8% in utilization incrase, rate grows 0.6%.
//         // at utilization 40% it would be 7% (4% + 3% from half of defaultRateAtKink increase)
//         // at utilization 50% it's 4% + 3.75% (50 / 8 * 0.6%) = 7.75%
//         // seconds per year = 31536000
//         // passed seconds = 2 days = 172800
//         // so in 31536000 seconds borrowers pay 7.75%. how much do they pay in 172800 seconds?
//         // passed time in percent = 172800 / 31536000 = 0,00547945205479452054794520548
//         // so rate increase = 7.75% * 0,00547945205479452054794520548 = 0,04246575342465753424657534247 %
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         // borrowers pay amountBorrowed (0.5 * 1e18) * rate increase =
//         // 500000000000000000 * 0,04246575342465753424657534247% = 0,00021232876712328767123287671235 * 1e18
//         // for suppliers, they get the amount borrowers pay minus the fee. default fee is set to 5%.
//         // 0,00021232876712328767123287671235 * 1e18 * 0.95 = 0,000201712328767123287671232876732
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 201712328; // 0,000201712328767123287671232876732 in 12 decimals

//         // vm.expectEmit(true, true, true, true);
//         emit LogOperate(
//             alice,
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             0,
//             0,
//             0,
//             0,
//             newSupplySafeExchangePrice,
//             newBorrowExchangePrice
//         );

//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );
//     }

//     function testUserExchangePricesEventsUtilizationAboveKink() public {
//         // 1. supply safe as alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 2. supply risky as alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT / 2,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 3. borrow as bob
//         int256 borrowAmount = ((DEFAULT_SUPPLY_AMOUNT * 2 * 90) / 100);
//         vm.prank(bob);
//         // execute borrow, borrow 90% of supplied amount
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, borrowAmount, address(0), bob, new bytes(0));

//         // 4. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 5. supply as alice again and expect calc interest to be collected correctly: set expected event
//         // for new borrow exchange price:
//         // annual borrow rate for default test data with default values see {TestHelpers}, at utilization 90%:
//         // at 80% it is 10%, at 100% it's 150%, 90% is exactly in between so 80%.
//         // seconds per year = 31536000
//         // passed seconds = 2 days = 172800
//         // so in 31536000 seconds borrowers pay 80%. how much do they pay in 172800 seconds?
//         // passed time in percent = 172800 / 31536000 = 0,00547945205479452054794520548
//         // so rate increase = 80% * 0,00547945205479452054794520548 = 0,438356164383561643835616438 %
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 4383561644; // 0,438356164383561643835616438% in 12 decimals, rounded up
//         // borrowers pay amountBorrowed * rate increase =
//         // 1800000000000000000 * 0,438356164383561643835616438% = 0,00078904109589041095890410958912
//         // for suppliers, they get the amount borrowers pay minus the fee. default fee is set to 5%.
//         // 0,00078904109589041095890410958912 * 1e18 * 0.95 = 0,000749589041095890410958904109664
//         // supply amounts for safe and risky are 50% each, so safe gets 50% of this but 20% of that amount goes to risky
//         // 1/2 * 1/5 = 1/10 of total goes to risky instead of safe. so safe gets 40%, risky gets 60%.
//         // riskyEarnings = 0,000449753424657534246575342465798; safeEarnings = 0,000299835616438356164383561643866
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 2998356164; // 0,000299835616438356164383561643866 in 12 decimals
//         uint256 newSupplyRiskyExchangePrice = EXCHANGE_PRICES_PRECISION + 4497534246; // 0,000449753424657534246575342465798 in 12 decimals

//         // vm.expectEmit(true, true, true, true);
//         // emit LogSupply(
//         //     alice,
//         //     address(USDC),
//         //     DEFAULT_SUPPLY_AMOUNT,
//         //     alice,
//         //     newSupplySafeExchangePrice,
//         //     newSupplyRiskyExchangePrice,
//         //     newBorrowExchangePrice,
//         //     // totalSupply should be half of default supply amount * new exchange price for safe and risky each + 1x supplyAmount
//         //     ((DEFAULT_SUPPLY_AMOUNT * newSupplySafeExchangePrice) / EXCHANGE_PRICES_PRECISION) +
//         //         ((DEFAULT_SUPPLY_AMOUNT * newSupplyRiskyExchangePrice) / EXCHANGE_PRICES_PRECISION) +
//         //         DEFAULT_SUPPLY_AMOUNT -
//         //         1, // minor rounding error -1
//         //     (borrowAmount * newBorrowExchangePrice) / EXCHANGE_PRICES_PRECISION,
//         //     0 // supply type = 0
//         // );

//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );
//     }
// }

// contract LiquidityUserModuleExchangePricesFromActionReturnValuesTest is LiquidityUserModuleBaseTest {
//     //     // 5. expected prices see testUserExchangePricesEventsWithBorrowersAndRiskyYieldPremium
//     uint256 constant newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//     uint256 constant newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 161369863; // 1,000161369863013698 in 12 decimals
//     uint256 constant newSupplyRiskyExchangePrice = EXCHANGE_PRICES_PRECISION + 242054794; // 1,000242054794520546 in 12 decimals

//     function setUp() public override {
//         super.setUp();

//         // 1. supply safe as alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT / 2,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 2. supply risky as alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT / 2,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 3. borrow as bob
//         vm.prank(bob);
//         // execute borrow
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

//         // 4. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);
//     }

//     function testUserExchangePricesSupplySafeReturnValues() public {
//         // test return values of supplySafe
//         vm.prank(alice);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }

//     function testUserExchangePricesSupplyRiskyReturnValues() public {
//         // test return values of supplyRisky
//         vm.prank(alice);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }

//     function testUserExchangePricesWithdrawSafeReturnValues() public {
//         // test return values of withdrawSafe
//         vm.prank(alice);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), DEFAULT_WITHDRAW_AMOUNT, 0, alice, address(0), new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }

//     function testUserExchangePricesWithdrawRiskyReturnValues() public {
//         // test return values of withdrawRisky
//         vm.prank(alice);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), DEFAULT_WITHDRAW_AMOUNT, 0, alice, address(0), new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }

//     function testUserExchangePricesBorrowReturnValues() public {
//         // test return values of borrow
//         vm.prank(alice);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }

//     function testUserExchangePricesRepayReturnValues() public {
//         // test return values of repay
//         vm.prank(bob);
//         (uint256 checkSupplySafeExchangePrice_, uint256 checkBorrowExchangePrice_) = FluidLiquidityUserModule(address(liquidity))
//             .operate(address(USDC), 0, DEFAULT_PAYBACK_AMOUNT, address(0), address(0), new bytes(0));
//         assertEq(checkSupplySafeExchangePrice_, newSupplySafeExchangePrice);
//         assertEq(checkBorrowExchangePrice_, newBorrowExchangePrice);
//     }
// }

// contract LiquidityUserModuleCalcInterestTest is LiquidityUserModuleBaseTest {
// @dev direct tests are not needed because _calcExchangePrices is indirectly tested through the ExchangePrices tests
// which check exchange prices but also total supply and borrow through the checks on events
// }

// todo: add back pause tests
// contract LiquidityUserModulePauseTest is LiquidityUserModuleBaseTest {
//     function testUserPauseActions() public {
//         // 1. assert initial values
//         // assertEq(ReadModule(address(liquidity)).isPaused(), false);

//         // 2. set up supply and borrowed
//         // supplies both safe and risky DEFAULT amount, borrows as bob to 50% utilization so Default supply amount
//         _setSupplySafeAndRiskyUtilization(50 * 1e4, address(liquidity), address(USDC), alice, bob);

//         // 3. execute pause
//         vm.prank(admin);
//         FluidLiquidityAdminModule(address(liquidity)).changeStatus(1);
//         // assert expected changes
//         // assertEq(ReadModule(address(liquidity)).isPaused(), true);

//         // 4. assert expected actions are halted while others still work

//         // expect withdraw and repay to still work
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_PAYBACK_AMOUNT, address(0), bob, new bytes(0));
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_WITHDRAW_AMOUNT, 0, alice, address(0), new bytes(0));
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_WITHDRAW_AMOUNT, 0, alice, address(0), new bytes(0));

//         // expect deposits, borrow and batch to revert because of paused
//         vm.expectRevert(UserModuleHelpers.UserModulePaused.selector);
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));
//         vm.expectRevert(UserModuleHelpers.UserModulePaused.selector);
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));
//         vm.expectRevert(UserModuleHelpers.UserModulePaused.selector);
//         vm.prank(bob);
//          FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));
//         // batch
//         // UserModuleStructs.BatchAction[] memory actions = new UserModuleStructs.BatchAction[](1);
//         // actions[0] = UserModuleStructs.BatchAction(
//         //     1, // supplySafe
//         //     address(USDC), // token
//         //     DEFAULT_SUPPLY_AMOUNT, // amount
//         //     alice // from
//         // );
//         // vm.expectRevert(UserModuleHelpers.UserModulePaused.selector);
//         // vm.prank(alice);
//         // FluidLiquidityUserModule(address(liquidity)).batch(actions);

//         // 5. execute unpause
//         vm.prank(admin);
//         FluidLiquidityAdminModule(address(liquidity)).changeStatus(0);

//         // assert expected changes now all actions should work again
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));
//         vm.prank(bob);
//          FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));
//         vm.prank(alice);
//         // FluidLiquidityUserModule(address(liquidity)).batch(actions);
//     }
// }

// NOTE: Update Exchange Prices looks like it was moved to an internal method. Commenting out for now.
/// @dev The following tests are almost identical with LiquidityReadModuleExchangePricesTest
// contract LiquidityUserModuleUpdateExchangePricesTest is LiquidityUserModuleBaseTest {
//     function testUserUpdateExchangePricesDefault() public {
//         // read
//         address[] memory tokens_ = new address[](2);
//         tokens_[0] = address(USDC);
//         tokens_[1] = address(DAI);
//         (
//             uint256[] memory supplySafeExchangePrices,
//             uint256[] memory supplyRiskyExchangePrices,
//             uint256[] memory borrowExchangePrices
//         ) = FluidLiquidityUserModule(address(liquidity)).updateExchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//     }

//     function testUserUpdateExchangePricesSupplySafe() public {
//         // 1. supply safe as alice
//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));

//         // 2. borrow as bob
//         vm.prank(bob);
//         // execute borrow
//          FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

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
//         ) = FluidLiquidityUserModule(address(liquidity)).updateExchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePrice);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//     }

//     function testUserUpdateExchangePricesSupplySafeRateDataV2() public {
//         // set rate data v2
//         _setDefaultRateDataV2(address(liquidity), admin, address(USDC));
//         // assertEq(ReadModule(address(liquidity)).rateDataVersion(address(USDC)), 2);

//         // 1. supply safe as alice
//         vm.prank(alice);
//         // execute supplySafe
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));

//         // 2. borrow as bob
//         vm.prank(bob);
//         // execute borrow
//          FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

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
//         ) = FluidLiquidityUserModule(address(liquidity)).updateExchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePrice);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//     }

//     function testUserUpdateExchangePrices() public {
//         // set risky yield premium
//         _setDefaultRiskyYieldPremium(address(liquidity), admin, address(USDC));

//         // 1. supply safe as alice
//         // USDC
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));
//         // DAI
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(DAI), DEFAULT_SUPPLY_AMOUNT, alice);

//         // 2. supply risky as alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));

//         // 3. borrow as bob
//         // USDC
//         vm.prank(bob);
//         // execute borrow
//          FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));
//         // DAI
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
//         ) = FluidLiquidityUserModule(address(liquidity)).updateExchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePriceUSDC);
//         assertEq(supplyRiskyExchangePrices[0], newSupplyRiskyExchangePriceUSDC);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePriceUSDC);
//         // assert for DAI
//         assertEq(supplySafeExchangePrices[1], newSupplySafeExchangePriceDAI);
//         assertEq(supplyRiskyExchangePrices[1], EXCHANGE_PRICES_PRECISION);
//         assertEq(borrowExchangePrices[1], newBorrowExchangePriceDAI);
//     }

//     function testUserUpdateExchangePricesAboveKink() public {
//         // set risky yield premium
//         _setDefaultRiskyYieldPremium(address(liquidity), admin, address(USDC));

//         // 1. supply safe as alice
//         vm.prank(alice);
//         // execute supplySafe, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));

//         // 2. supply risky as alice
//         vm.prank(alice);
//         // execute supplyRisky, only half amount to have same utilization as in other test
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT / 2, 0, address(0), address(0), new bytes(0));

//         // 3. borrow as bob
//         int256 borrowAmount = ((DEFAULT_SUPPLY_AMOUNT * 2 * 90) / 100);
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
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 4383561644; // 0,438356164383561643835616438% in 12 decimals, rounded up
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
//         ) = FluidLiquidityUserModule(address(liquidity)).updateExchangePrices(tokens_);

//         // assert for USDC
//         assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         assertEq(supplyRiskyExchangePrices[0], newSupplyRiskyExchangePrice);
//         assertEq(borrowExchangePrices[0], newBorrowExchangePrice);

//         assertEq(supplySafeExchangePrices.length, 1);
//         assertEq(supplyRiskyExchangePrices.length, 1);
//         assertEq(borrowExchangePrices.length, 1);
//     }
// }

// contract LiquidityUserModuleDebtCeilingsTest is LiquidityUserModuleBaseTest {
//     address[] usdcTokenArray = new address[](1);

//     uint256 debtCeilingBaseDefault;
//     uint256 debtCeilingMaxDefault;

//     function setUp() public override {
//         super.setUp();

//         usdcTokenArray[0] = address(USDC);

//         // read actual base & max debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (debtCeilingBaseDefault, debtCeilingMaxDefault, , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(
//             address(USDC),
//             alice
//         );

//         // create sufficient supply as alice
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).supplySafe(address(USDC), DEFAULT_MAX_DEBT_CEILING * 10, alice);
//     }

//     function testUserDebtCeilingDefaultFallbackToBase() public {
//         // expect to be able to borrow at least base debt ceiling without prior action

//         // expect allowancesOf bob to be equal base debt ceiling
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertEq(borrowLimit, debtCeilingBaseDefault);

//         // borrow as bob exactly base debt ceiling
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);
//     }

//     function testUserDebtCeilingBorrowAboveLimitRevert() public {
//         // expect borrowing to revert if trying to borrow more than user debt ceiling

//         // borrow as bob base debt ceiling +1 -> should fail
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault + 1, bob);
//     }

//     function testUserDebtCeilingExpand() public {
//         // expect user debt ceiling to expand when borrowing more than range of target - expandPercentage

//         // borrow as bob exactly 4.90 ether just below base debt ceiling to avoid dealing with precision loss influence
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), 4.9 ether, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 5.39 ether (4.9 ether + half of 20% more = 4.9 + 0.49 (+ 10%))
//         // assert allowancesOf bob
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // + expected add amount (10%)
//         uint256 expectedAmount = currentBorrow + currentBorrow / 10;
//         assertEq(borrowLimit, expectedAmount);
//         // double check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 5.39 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 5.88 ether (4.9 ether + 20%)
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // + expected add amount (20%)
//         expectedAmount = currentBorrow + currentBorrow / 5;
//         assertEq(borrowLimit, expectedAmount);
//         // double check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 5.88 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob to current debt ceiling
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);

//         // double check again simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);
//         // assert allowancesOf bob, should now be 7.056 ether (5.88 ether + 20%)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // + expected add amount (20%)
//         expectedAmount = currentBorrow + currentBorrow / 5;
//         assertEq(borrowLimit, expectedAmount);
//         // double check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 7.056 ether, 1e16);
//     }

//     function testUserDebtCeilingBorrowDuringExpand() public {
//         // expect user debt ceiling to expand accordingly when borrowing during ongoing expand process

//         // borrow as bob exactly 4.90 ether just below base debt ceiling to avoid dealing with precision loss influence
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), 4.9 ether, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 5.39 ether (4.9 ether + half of 20% more = 4.9 + 0.49 (+ 10%))
//         // assert allowancesOf bob
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // + expected add amount (10%)
//         uint256 expectedAmount = currentBorrow + currentBorrow / 10;
//         assertEq(borrowLimit, expectedAmount);
//         // double check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 5.39 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // borrow again to trigger another expand
//         // borrow as bob to 5.3 ether. Borrow limit should expand from 5.39 (previous) to 6.36 (new, 5.3 + 20%)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), 5.3 ether - currentBorrow, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 5.875 ether (5.39 ether + half of to 6.36 ether)
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 5.875 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 6.36 ether (5.3 ether + 20%)
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // + expected add amount (10%)
//         expectedAmount = currentBorrow + currentBorrow / 5;
//         assertEq(borrowLimit, expectedAmount);
//         // double check is within expected amount without caring about exchange price and BigMath precision loss
//         assertApproxEqAbs(borrowLimit, 6.36 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob to current debt ceiling
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingNotExpandAboveMax() public {
//         // expect user debt ceiling not to grow above maximum debt ceiling

//         // set user debt ceiling for test
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 5.5 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // read actual base & max debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (uint256 baseDebtCeiling, uint256 maxDebtCeiling, , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(
//             address(USDC),
//             bob
//         );

//         // borrow as bob to base debt ceiling.
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), baseDebtCeiling, bob);

//         // simulate passing time (2 days) -> should be fully expanded but only to (max) and not to ~6 ether
//         vm.warp(block.timestamp + 2 days);

//         // expect allowancesOf bob to be equal max debt ceiling
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertEq(borrowLimit, maxDebtCeiling);
//         // should be around 5.5 ether
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), maxDebtCeiling - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), maxDebtCeiling - currentBorrow, bob);
//     }

//     function testUserDebtCeilingShrink() public {
//         // expect user debt ceiling to shrink to a lower level on repay

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // set base debt ceiling of bob down to 1 ether (to set shrink down to amount)
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimitBeforeRepay) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, 6 ether, 1e16);

//         // repay as bob down to 2 ether to trigger shrinking
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 2 ether, bob);

//         // allowance right after repay should still be the same
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, borrowLimit, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be shrunk by half from ~6 ether down to 2 ether + 20% -> 2.4 ether = 4.2 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.2 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be 2 ether + 20% -> 2.4 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2.4 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingNotShrinkBelowBase() public {
//         // expect to be able to borrow at least base debt ceiling after shrinking

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimitBeforeRepay) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, 6 ether, 1e16);

//         // set base debt ceiling of bob to 5.2 ether
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5.2 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // allowance should still be ~6 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, borrowLimitBeforeRepay, 1e16);

//         // repay as bob down to 4 ether -> limit should shrink from 6 ether to ~5.2 ether base instead of 4.8 of user
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 4 ether, bob);

//         // allowance right after repay should still be the same
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, borrowLimitBeforeRepay, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);

//         // repay again as bob down to 4 ether -> limit should shrink from 6 ether to ~5.2 ether base instead of 4.8 of user
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 4 ether, bob);

//         // simulate passing time for shrink to happen half
//         vm.warp(block.timestamp + 1 days);

//         // assert allowancesOf bob -> should be half down from 6 to 4.8 -> = 5.4
//         // shrink happens in the normal speed down to user target, but base debt ceiling would act like a lowest stop
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.4 ether, 1e16);

//         // simulate more passing time for shrink to happen fully
//         vm.warp(block.timestamp + 2 days);

//         // limit should now be base debt ceiling because base > current user target
//         // read actual base & max debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (uint256 baseDebtCeiling, , , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(address(USDC), bob);
//         assertApproxEqAbs(baseDebtCeiling, 5.2 ether, 1e16);
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, baseDebtCeiling, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingRepayDuringExpand() public {
//         // expect user debt ceiling to switch to shrink instead of expand on repay

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // set base debt ceiling of bob down to 1 ether to neutralize effect of base debt ceiling for this test
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e16);

//         // borrow with bob to current limit
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be expanded to ~6.6 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6.6 ether, 1e16);

//         // repay as bob down to 4 ether to trigger shrinking
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 4 ether, bob);

//         // allowance right after repay should still be the same
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6.6 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be shrunk to ~5.7 ether (half of 6.6 to 4.8)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.7 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be fully shrunk to ~4.8 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.8 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingBorrowDuringShrink() public {
//         // expect user debt ceiling to switch to expand instead of shrink on borrow

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e16);

//         // set base debt ceiling of bob down to 1 ether (to set shrink down to amount)
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // repay as bob down to 2 ether to trigger shrinking
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 2 ether, bob);

//         // borrow limit right after should still be 6 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be shrunk to 6- (6 - 2.4) / 2 = ~4.2 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.2 ether, 1e16);

//         // borrow with bob to current limit of ~4.2 ether
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);

//         // allowance right after borrow should still be the same
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.2 ether, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be expanded to ~4.62 ether (4.2 + 10%)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.62 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be fully expanded to ~5.04 ether (4.2 + 20%)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.04 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingRepayDuringShrink() public {
//         // expect user debt ceiling to shrink to a lower level on repay

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // set base debt ceiling of bob down to 1 ether (to set shrink down to amount)
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimitBeforeRepay) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, 6 ether, 1e16);

//         // repay as bob down to 4 ether to trigger shrinking
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 4 ether, bob);

//         // allowance right after repay should still be the same
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, borrowLimit, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be shrunk by half from ~6 ether down to 4 ether + 20% (-> 4.8 ether) = 5.4 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.4 ether, 1e16);

//         // repay as bob again now down to 2 ether to trigger shrinking again
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 2 ether, bob);

//         // allowance right after repay should still be the same
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.4 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be shrunk by half from ~5.4 ether down to 2 ether + 20% (-> 2.4 ether) = 5.4 - (5.4 - 2.4) / 2 = 3.9
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 3.9 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be shrunk fully to 2.4 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2.4 ether, 1e16);

//         // simulate passing time (10 days)
//         vm.warp(block.timestamp + 10 days);

//         // limit should still be 2.4 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2.4 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigExpandDuration() public {
//         // expect user debt ceiling to change accordingly if config values for expand duration change

//         // borrow with bob to current base (default) to trigger expand
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be expanded to ~5.5 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // set expand debt ceiling duration to 10 days instead of 2 days
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
//             expandDebtCeilingDuration: 10 days,
//             shrinkDebtCeilingDuration: DEFAULT_SHRINK_DEBT_CEILING_DURATION
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // borrow limit should now only be ~5.1 ether (reference point stayed the same but duration got longer)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.1 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (4 days)
//         vm.warp(block.timestamp + 4 days);

//         // borrow limit should now only be ~5.5 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (5 days)
//         vm.warp(block.timestamp + 5 days);

//         // borrow limit should now be fully expanded to ~6 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigExpandPercentage() public {
//         // expect user debt ceiling to change accordingly if config values for expand percentage change

//         // borrow with bob to current base (default) to trigger expand
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be expanded to ~5.5 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // set expand debt ceiling percentage to 50 instead of 20
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 50 * 1e4, // 50%
//             expandDebtCeilingDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
//             shrinkDebtCeilingDuration: DEFAULT_SHRINK_DEBT_CEILING_DURATION
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // borrow limit should now be 5 + 50% of 50% = ~6.25 ether (reference point stayed the same but percentage got bigger)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6.25 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // borrow limit should now be fully expanded to ~7.5 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 7.5 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigShrinkDuration() public {
//         // expect user debt ceiling to change accordingly if config values for shrink duration change

//         // borrow with bob to current base (default)
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // set base debt ceiling of bob down to 1 ether (to set shrink down to amount)
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
//             expandDebtCeilingDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
//             shrinkDebtCeilingDuration: DEFAULT_SHRINK_DEBT_CEILING_DURATION
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should now be expanded to ~6 ether
//         (, , uint256 borrowLimitBeforeRepay) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, 6 ether, 1e16);

//         // repay as bob down to 2 ether to trigger shrinking
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 2 ether, bob);

//         // allowance right after repay should still be the same
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimitBeforeRepay, borrowLimit, 1e16);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // limit should now be shrunk by half from ~6 ether down to 2 ether + 20% (-> 2.4 ether) = 4.2 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.2 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // set shrink debt ceiling duration to 0 instead of 2 days
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
//             expandDebtCeilingDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
//             shrinkDebtCeilingDuration: 0
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // borrow limit should now be instantly shrunk fully down to 2 ether + 20% (-> 2.4 ether)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2.4 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // set shrink debt ceiling duration to 10 days instead of 2 days
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
//             expandDebtCeilingDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
//             shrinkDebtCeilingDuration: 10 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // limit should now be shrunk by 10% from ~6 ether down to 2 ether + 20% (-> 2.4 ether) = 5.6 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.6 ether, 1e17);

//         // simulate passing time (4 days)
//         vm.warp(block.timestamp + 4 days);

//         // limit should now be shrunk by half from ~6 ether down to 2 ether + 20% (-> 2.4 ether) = 4.2 ether
//         // assert allowancesOf bob
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 4.2 ether, 1e17);

//         // simulate passing time (5 days)
//         vm.warp(block.timestamp + 5 days);

//         // borrow limit should now be shrunk fully down to 2 ether + 20% (-> 2.4 ether)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2.4 ether, 1e17);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigMaxIncrease() public {
//         // expect user debt ceiling to change accordingly if config values for maximum ceiling change
//         // e.g. if max is increased then expanding should automatically happen for all users previously limited
//         // by the max limit. even for users that have borrowed a long time ago

//         // set user debt ceiling for test
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 5.4 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // read actual base & max debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (uint256 baseDebtCeiling, uint256 maxDebtCeiling, , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(
//             address(USDC),
//             bob
//         );

//         // borrow as bob to base debt ceiling.
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), baseDebtCeiling, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // expect allowancesOf bob to be equal max debt ceiling
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertEq(borrowLimit, maxDebtCeiling);
//         // should be around 5.4 ether
//         assertApproxEqAbs(borrowLimit, 5.4 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // increase max debt ceiling to 5.7 ether
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 5.7 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // limit should now be 5.5 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e17);

//         // simulate passing time (10 days) -> should be fully expanded to max debt ceiling ether
//         vm.warp(block.timestamp + 10 days);

//         // limit should now be 5.7 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.7 ether, 1e17);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);

//         // increase max debt ceiling to 10 ether
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 10 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // limit should be fully expanded to 6 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e17);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigMaxDecrease() public {
//         // expect user debt ceiling to change accordingly if config values for maximum ceiling change
//         // e.g. user had debt ceiling of 70, currently growing to 84, limited by max of 80.
//         // now max is reduced to 75 before user borrows again. user debt ceiling should have only grown to
//         // 75, and not to previous max of 80.

//         // set user debt ceiling for test
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 10 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // read actual base debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (uint256 baseDebtCeiling, , , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(address(USDC), bob);

//         // borrow as bob to base debt ceiling.
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), baseDebtCeiling, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // expect allowancesOf bob to be expanded normally to 5.5 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // should be around 5.5 ether
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // decrease max debt ceiling to 5.3 ether
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 5.3 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // limit should now be instantly 5.3 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.3 ether, 1e17);

//         // simulate passing time (10 days) -> limit should still only be 5.3 ether
//         vm.warp(block.timestamp + 10 days);

//         // limit should be 5.3 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 5.3 ether, 1e17);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingChangeConfigBaseDecrease() public {
//         // expect user debt ceiling to change accordingly if config values for base ceiling change
//         // e.g. expand should still happen if user borrowed below base but then base is decreased

//         // borrow with bob to current base (default) -1
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault - 1, bob);

//         // set base debt ceiling of bob down to 1 ether
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 1 ether,
//             maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // expect allowancesOf bob to be equal borrow amount
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, debtCeilingBaseDefault - 1, 1e16);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // expect allowancesOf bob to be equal borrow amount (~5 ether) + 20% expanded (~6 ether)
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 6 ether, 1e16);
//     }

//     function testUserDebtCeilingChangeConfigBaseIncrease() public {
//         // expect user debt ceiling to change accordingly if config values for base ceiling change
//         // e.g. if base increased above current user borrow target then it should be active for that user right away

//         // set user debt ceiling for test
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 5 ether,
//             maxDebtCeiling: 10 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // read actual base debt ceiling after precision loss because of storing in BigMath 10 | 8
//         (uint256 baseDebtCeiling, , , , ) = ReadModule(address(liquidity)).debtCeilingConfigOf(address(USDC), bob);

//         // borrow as bob to base debt ceiling.
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), baseDebtCeiling, bob);

//         // simulate passing time (1 days)
//         vm.warp(block.timestamp + 1 days);

//         // expect allowancesOf bob to be expanded normally to 5.5 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         // should be around 5.5 ether
//         assertApproxEqAbs(borrowLimit, 5.5 ether, 1e16);

//         // increase base debt ceiling to 7 ether
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 7 ether,
//             maxDebtCeiling: 10 ether,
//             expandDebtCeilingPercentage: 20 * 1e4,
//             expandDebtCeilingDuration: 2 days,
//             shrinkDebtCeilingDuration: 2 days
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // limit should now be instantly 7 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 7 ether, 1e17);

//         // simulate passing time (10 days) -> limit should still be 7 ether
//         vm.warp(block.timestamp + 10 days);

//         // limit should be 7 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 7 ether, 1e17);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }

//     function testUserDebtCeilingRepayDuringAboveLimit() public {
//         // expect repay to not revert if trying to repay while borrowing more than user debt ceiling
//         // (e.g. because max config value has been modified)

//         // borrow with bob to current base (default) = 5 ether
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), debtCeilingBaseDefault, bob);

//         // set max debt ceiling of bob down to 2 ether, base to 0.1
//         AdminModuleStructs.TokenAllowancesConfig[] memory tokenConfigs = new AdminModuleStructs.TokenAllowancesConfig[](
//             1
//         );
//         tokenConfigs[0] = AdminModuleStructs.TokenAllowancesConfig({
//             token: address(USDC),
//             supplySafe: true,
//             supplyRisky: true,
//             baseDebtCeiling: 0.1 ether,
//             maxDebtCeiling: 2 ether,
//             expandDebtCeilingPercentage: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
//             expandDebtCeilingDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
//             shrinkDebtCeilingDuration: DEFAULT_SHRINK_DEBT_CEILING_DURATION
//         });
//         // set user allowances for bob
//         vm.prank(admin);
//         AuthModule(address(liquidity)).setUserAllowances(bob, tokenConfigs);

//         // bob is now borrowing 5 ether at a max debt ceiling of 2 ether
//         (, , uint256 borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2 ether, 1e16);
//         (, , uint256 currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         assertApproxEqAbs(currentBorrow, 5 ether, 1e16);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // bob is still borrowing 5 ether at a max debt ceiling of 2 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2 ether, 1e16);
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         assertApproxEqAbs(currentBorrow, 5 ether, 1e16);

//         // repay as bob down to 3 ether
//         // we must use current borrow amount which is adjusted for exchange price
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 3 ether, bob);

//         // bob is now borrowing 3 ether at a max debt ceiling of 2 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2 ether, 1e16);
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         assertApproxEqAbs(currentBorrow, 3 ether, 1e16);

//         // repay as bob down to 1 ether
//         // we must use current borrow amount which is adjusted for exchange price
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).repay(address(USDC), currentBorrow - 1 ether, bob);

//         // bob is now borrowing 1 ether at a max debt ceiling of 2 ether, and borrow limit of 2 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 2 ether, 1e16);
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         assertApproxEqAbs(currentBorrow, 1 ether, 1e16);

//         // simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // borrow limit should have shrunk down to 1.2 ether
//         (, , borrowLimit) = ReadModule(address(liquidity)).allowancesOf(address(USDC), bob);
//         assertApproxEqAbs(borrowLimit, 1.2 ether, 1e16);

//         // assert borrow too much reverts, ensuring logic between ReadModule and UserModule matches
//         // we must use current borrow amount which is adjusted for exchange price
//         (, , currentBorrow) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         vm.expectRevert(CoreInternals.UserModuleAboveBorrowLimit.selector);
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow + 1, bob);
//         // borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).borrow(address(USDC), borrowLimit - currentBorrow, bob);
//     }
// }

// contract LiquidityUserModuleTest is LiquidityUserModuleBaseTest {
//     function testUserActivityFullResetAndActivityAgain() public {
//         // -> supply, borrow, then repay to 0 and withdraw to 0. then supply and borrow again.
//         //    must exchange prices reset to 1:1? double check everything works as expected in this case

//         // 1. supply safe as alice
//         vm.prank(alice);
//         FluidLiquidityUserModule(address(liquidity)).operate(
//             address(USDC),
//             DEFAULT_SUPPLY_AMOUNT,
//             0,
//             address(0),
//             address(0),
//             new bytes(0)
//         );

//         // 2. borrow as bob
//         vm.prank(bob);
//         FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

//         // 3. simulate passing time (2 days)
//         vm.warp(block.timestamp + 2 days);

//         // 4. assert exchange prices
//         // for calculation of exchange prices explanation see test "testUserExchangePricesEventsWithBorrowers"
//         uint256 newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 424657535; // 0,04246575342465753424657534247% in 12 decimals, rounded up
//         uint256 newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 201712328; // 0,000201712328767123287671232876732 in 12 decimals

//         // read
//         // address[] memory tokens_ = new address[](1);
//         // tokens_[0] = address(USDC);
//         // (
//         //     uint256[] memory supplySafeExchangePrices,
//         //     uint256[] memory supplyRiskyExchangePrices,
//         //     uint256[] memory borrowExchangePrices
//         // ) = ReadModule(address(liquidity)).exchangePrices(tokens_);

//         // // assert
//         // assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         // assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         // assertEq(borrowExchangePrices[0], newBorrowExchangePrice);

//         // // 5. repay as bob to 0
//         // vm.prank(bob);
//         // FluidLiquidityUserModule(address(liquidity)).repay(
//         //     address(USDC),
//         //     (DEFAULT_BORROW_AMOUNT * newBorrowExchangePrice) / EXCHANGE_PRICES_PRECISION,
//         //     bob
//         // );
//         // (, , uint256 borrowed) = ReadModule(address(liquidity)).balancesOf(address(USDC), bob);
//         // assertEq(borrowed, 0);

//         // // 6. withdraw safe as alice to 0
//         // vm.prank(alice);
//         // FluidLiquidityUserModule(address(liquidity)).withdrawSafe(
//         //     address(USDC),
//         //     (DEFAULT_SUPPLY_AMOUNT * newSupplySafeExchangePrice) / EXCHANGE_PRICES_PRECISION,
//         //     alice
//         // );
//         // (uint256 supplySafe, , ) = ReadModule(address(liquidity)).balancesOf(address(USDC), alice);
//         // assertEq(supplySafe, 0);

//         // // 7. simulate passing time
//         // vm.warp(block.timestamp + 10 days);

//         // // 8. assert exchange prices, should still be the same
//         // (supplySafeExchangePrices, supplyRiskyExchangePrices, borrowExchangePrices) = ReadModule(address(liquidity))
//         //     .exchangePrices(tokens_);
//         // // assert
//         // assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         // assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         // assertEq(borrowExchangePrices[0], newBorrowExchangePrice);

//         // // 9. supply safe as alice, borrow as bob again
//         // vm.prank(alice);
//         // FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), DEFAULT_SUPPLY_AMOUNT, 0, address(0), address(0), new bytes(0));

//         // vm.prank(bob);
//         //  FluidLiquidityUserModule(address(liquidity)).operate(address(USDC), 0, DEFAULT_BORROW_AMOUNT, address(0), bob, new bytes(0));

//         // // 10. simulate passing time (2 days)
//         // vm.warp(block.timestamp + 2 days);

//         // // 11. assert new exchange prices
//         // newBorrowExchangePrice = EXCHANGE_PRICES_PRECISION + 849495404; // +0,04246575342465753424657534247% of previous newBorrowExchangePrice
//         // newSupplySafeExchangePrice = EXCHANGE_PRICES_PRECISION + 403465344; // +0,0201712328767123287671232876732 % of previous newSupplySafeExchangePrice

//         // (supplySafeExchangePrices, supplyRiskyExchangePrices, borrowExchangePrices) = ReadModule(address(liquidity))
//         //     .exchangePrices(tokens_);
//         // // assert
//         // assertEq(supplySafeExchangePrices[0], newSupplySafeExchangePrice);
//         // assertEq(supplyRiskyExchangePrices[0], EXCHANGE_PRICES_PRECISION);
//         // assertEq(borrowExchangePrices[0], newBorrowExchangePrice);
//     }
// }
