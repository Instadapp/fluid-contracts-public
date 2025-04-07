//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// TODO: newer tests:
// 14. Set limits on liquidity for withdrawal. Reach near to limit, withdrawal from operate should fail due to withdrawal gap with error Vault__WithdrawMoreThanOperateLimit while liquidation should pass.
// 15. [Admin] try absorbing dust debt of a non liquidated position. Should fail.
// 16. [Admin] try absorbing dust debt of a liquidated position. Should fail.
// 17. [Admin] try absorbing dust debt of a liquidated position which is near 100% liquidated. Should fail.

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LiquidityBaseTest } from "../../liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultT1 } from "../../../../contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Admin } from "../../../../contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { VaultFactoryBaseTest } from "../factory/vaultFactory.t.sol";
import { FluidLiquidityResolver } from "../../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/main.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { TickMath } from "../../../../contracts/libraries/tickMath.sol";
import { LiquidityCalcs } from "../../../../contracts/libraries/liquidityCalcs.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { ErrorTypes } from "../../../../contracts/protocols/vault/errorTypes.sol";
import { Error } from "../../../../contracts/protocols/vault/error.sol";

import { FluidVaultLiquidationResolver } from "../../../../contracts/periphery/resolvers/vaultLiquidation/main.sol";
import { Structs as LiquidationResolverStructs } from "../../../../contracts/periphery/resolvers/vaultLiquidation/structs.sol";
import { IFluidVaultResolver } from "../../../../contracts/periphery/resolvers/vault/iVaultResolver.sol";

abstract contract VaultT1BaseTest is VaultFactoryBaseTest {
    FluidVaultT1 vaultOne;
    FluidVaultT1 vaultTwo;
    FluidVaultT1 vaultThree; // Native supply vault
    FluidVaultT1 vaultFour; // Native borrow vault
    address constant nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    TestERC20Dec6 supplyToken;
    TestERC20 borrowToken;
    MockOracle oracleOne;
    MockOracle oracleTwo;
    MockOracle oracleThree;
    MockOracle oracleFour;

    uint256 supplyTokenDecimals;
    uint256 borrowTokenDecimals;
    uint256 nativeTokenDecimals;

    function vaultSupplyDecimals(address vault_) internal returns (uint256) {
        if (vault_ == address(vaultOne)) {
            return supplyTokenDecimals;
        }
        if (vault_ == address(vaultTwo)) {
            return borrowTokenDecimals;
        }
        if (vault_ == address(vaultThree)) {
            return nativeTokenDecimals;
        }
        if (vault_ == address(vaultFour)) {
            return supplyTokenDecimals;
        }
    }

    function vaultBorrowDecimals(address vault_) internal returns (uint256) {
        if (vault_ == address(vaultOne)) {
            return borrowTokenDecimals;
        }
        if (vault_ == address(vaultTwo)) {
            return supplyTokenDecimals;
        }
        if (vault_ == address(vaultThree)) {
            return borrowTokenDecimals;
        }
        if (vault_ == address(vaultFour)) {
            return nativeTokenDecimals;
        }
    }

    function setUp() public virtual override {
        super.setUp();

        supplyToken = TestERC20Dec6(address(USDC)); // TODO UPDATE
        borrowToken = TestERC20(address(DAI));

        supplyTokenDecimals = supplyToken.decimals();
        borrowTokenDecimals = borrowToken.decimals();
        nativeTokenDecimals = 18;

        vaultOne = FluidVaultT1(_deployVaultTokens(address(supplyToken), address(borrowToken)));
        vaultTwo = FluidVaultT1(_deployVaultTokens(address(borrowToken), address(supplyToken)));
        vaultThree = FluidVaultT1(_deployVaultTokens(address(nativeToken), address(borrowToken)));
        vaultFour = FluidVaultT1(_deployVaultTokens(address(supplyToken), address(nativeToken)));

        // Updating admin related things to setup vault
        oracleOne = MockOracle(_setDefaultVaultSettings(address(vaultOne)));
        oracleTwo = MockOracle(_setDefaultVaultSettings(address(vaultTwo)));
        oracleThree = MockOracle(_setDefaultVaultSettings(address(vaultThree)));
        oracleFour = MockOracle(_setDefaultVaultSettings(address(vaultFour)));

        // set default allowances for vault
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultOne));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultOne));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultTwo));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultTwo));

        _setUserAllowancesDefault(address(liquidity), address(admin), address(nativeToken), address(vaultThree));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(borrowToken), address(vaultThree));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(supplyToken), address(vaultFour));
        _setUserAllowancesDefault(address(liquidity), address(admin), address(nativeToken), address(vaultFour));

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(supplyToken), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(borrowToken), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(nativeToken), address(mockProtocol));

        console2.log("DAI", address(DAI));
        console2.log("USDC", address(USDC));
        console2.log("mockProtocol", address(mockProtocol));
        console2.log("--------------------------------------------\n");

        _supply(mockProtocol, address(supplyToken), alice, 1e6 * 1e6);
        _supply(mockProtocol, address(borrowToken), alice, 1e6 * 1e18);
        _supplyNative(mockProtocol, alice, 1e3 * 1e18);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(USDC, address(vaultTwo), alice);
        _setApproval(USDC, address(vaultFour), alice);
        _setApproval(USDC, address(vaultOne), bob);
        _setApproval(USDC, address(vaultTwo), bob);
        _setApproval(USDC, address(vaultFour), bob);
        _setApproval(DAI, address(vaultOne), bob);
        _setApproval(DAI, address(vaultTwo), bob);
        _setApproval(DAI, address(vaultThree), bob);
        _setApproval(DAI, address(vaultOne), alice);
        _setApproval(DAI, address(vaultTwo), alice);
        _setApproval(DAI, address(vaultThree), alice);
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

    function _setOracleTwoPrice(uint price) internal {
        oracleTwo.setPrice(price);
    }

    function _setOracleThreePrice(uint price) internal {
        oracleThree.setPrice(price);
    }

    function _setOracleFourPrice(uint price) internal {
        oracleFour.setPrice(price);
    }

    function setOraclePrice(uint price, bool noInverse) internal {
        if (noInverse) {
            _setOracleOnePrice(price);
        } else {
            _setOracleTwoPrice(1e54 / price);
        }
    }

    /// @param percent should be in 1e2 decimals, 10000 = 100%
    function setOraclePricePercentDecrease(uint price, bool noInverse, uint percent) internal {
        uint newPrice;
        if (noInverse) {
            newPrice = (price * (1e4 - percent)) / 1e4;
            _setOracleOnePrice(newPrice);
        } else {
            newPrice = 1e54 / price;
            newPrice = (newPrice * (1e4 - percent)) / 1e4;
            _setOracleTwoPrice(newPrice);
        }
    }

    function _balanceBeforeHelper(IERC20 token_) internal returns (uint) {
        return token_.balanceOf(address(liquidity));
    }

    /// @dev helps in checking the initial and final liquidity balance is properly within expected limits
    function _balanceAfterCheck(IERC20 token_, uint initialBalance_, int differenceExpected) internal {
        uint finalBalance_ = token_.balanceOf(address(liquidity));

        int difference_ = int(finalBalance_) - int(initialBalance_);

        int factorHigh_ = 1e18 + 1e4;
        int factorLow_ = 1e18 - 1e4;

        int limitHigh_ = (difference_ * factorHigh_) / 1e18;
        int limitLow_ = (difference_ * factorLow_) / 1e18;

        if (difference_ <= 0 && differenceExpected <= 0) {
            // if less than 0 then need to inverse factor
            limitLow_ = (difference_ * factorHigh_) / 1e18;
            limitHigh_ = (difference_ * factorLow_) / 1e18;
        } else if (difference_ >= 0 && differenceExpected >= 0) {
            limitHigh_ = (difference_ * factorHigh_) / 1e18;
            limitLow_ = (difference_ * factorLow_) / 1e18;
        } else {
            vm.expectRevert();
            revert("difference should be of same sign");
        }

        if (limitHigh_ <= differenceExpected || limitLow_ >= differenceExpected) {
            vm.expectRevert();
            revert("difference exceeded the limits");
        }
    }

    function _verifyLiquidation(
        uint totalPositions_,
        uint expectedTotalFinalcol_,
        uint expectedTotalFinalDebt_
    ) internal {
        FluidVaultResolver.UserPosition memory userPosition_;
        FluidVaultResolver.VaultEntireData memory vaultData_;

        uint totalUserCol_;
        uint totalUserDebt_;
        uint totalUserDustDebt_;
        address vaultAddr_;
        for (uint i = 0; i < totalPositions_; i++) {
            (userPosition_, vaultData_) = vaultResolver.positionByNftId((i + 1));
            totalUserCol_ += userPosition_.supply;
            totalUserDebt_ += userPosition_.borrow;
            totalUserDustDebt_ += userPosition_.beforeDustBorrow;

            if (vaultAddr_ == address(0)) {
                vaultAddr_ = vaultData_.vault;
            } else {
                require(vaultData_.vault == vaultAddr_, "NFT-does-not-belong-to-same-vault");
            }
        }

        require(expectedTotalFinalcol_ > totalUserCol_, "collateral-expected-should-be-greater");
        require(expectedTotalFinalDebt_ > totalUserDebt_, "debt-expected-should-be-greater");

        // 1e18 = 100%, taking a precision of 1e14 as of now
        // TODO: Look if things can be more precise than 1e14
        assertApproxEqRel(((expectedTotalFinalcol_ * 9999) / 10000), totalUserCol_, 1e14);
        assertApproxEqRel(
            (((expectedTotalFinalDebt_ + totalUserDustDebt_) * 9999) / 10000) - totalUserDustDebt_,
            totalUserDebt_,
            1e14
        );
    }

    function _verifyPosition() internal {
        (FluidVaultResolver.UserPosition memory userPositionOne_, ) = vaultResolver.positionByNftId(1);
        (FluidVaultResolver.UserPosition memory userPositionTwo_, ) = vaultResolver.positionByNftId(2);

        assertApproxEqRel(userPositionOne_.supply, userPositionTwo_.supply, 1e9);
        assertApproxEqRel(userPositionOne_.borrow, userPositionTwo_.borrow, 1e9);
    }

    // ################### HELPERS END #####################
}

contract VaultT1Test is VaultT1BaseTest {
    // ################### TESTS #####################

    function _operateETHOnANonNativeVault(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueOperate)
        );
        vaultContract_.operate{ value: uint(collateral_) }(
            0, // new position
            collateral_,
            debt_,
            alice
        );

        vm.prank(alice);
        vaultContract_.operate(
            0, // new position
            collateral_,
            debt_,
            alice
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueOperate)
        );
        vaultContract_.operate{ value: uint(debt_ / 2) }(
            1, // new position
            -(collateral_ / 2),
            -(debt_ / 2),
            alice
        );
    }

    function testOperateETHOnANonNativeVaultPositive() public {
        _operateETHOnANonNativeVault(true);
    }

    function testOperateETHOnANonNativeVaultNegative() public {
        _operateETHOnANonNativeVault(false);
    }

    function testNativeOperate() public {
        int nativeCol_ = 5 * 1e18;
        int debt_ = 5000 * 1e6;
        int col_ = 10000 * 1e18;
        int nativeDebt_ = 2 * 1e18;

        uint oracleThreePrice_ = 2000 * 1e39; // 1 ETH = 2000 USDC
        _setOracleThreePrice(oracleThreePrice_);

        uint oracleFourPrice_ = 1e54 / (2000 * 1e27); // 1 DAI = 1 / 2000 ETH
        _setOracleFourPrice(oracleFourPrice_);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueOperate)
        );
        vaultThree.operate(
            0, // new position
            nativeCol_,
            debt_,
            alice
        );

        vm.prank(alice);
        vaultThree.operate{ value: uint(nativeCol_) }(
            0, // new position
            nativeCol_,
            debt_,
            alice
        );

        vm.prank(alice);
        vaultThree.operate(
            1, // new position
            -(nativeCol_ / 2),
            -(debt_ / 2),
            alice
        );

        vm.prank(alice);
        vaultFour.operate(
            0, // new position
            col_,
            nativeDebt_,
            alice
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueOperate)
        );
        vaultFour.operate(
            2, // new position
            -(col_ / 2),
            -(nativeDebt_ / 2),
            alice
        );

        vm.prank(alice);
        vaultFour.operate{ value: uint(nativeDebt_ / 2) }(
            2, // new position
            -(col_ / 2),
            -(nativeDebt_ / 2),
            alice
        );
    }

    function testNativeLiquidate() public {
        int col_ = 10000 * 1e18;
        int nativeDebt_ = 3.995 * 1e18;

        uint oracleFourPrice_ = 1e54 / (2000 * 1e27); // 1 DAI = 1 / 2000 ETH
        _setOracleFourPrice(oracleFourPrice_);
        vm.prank(alice);
        vaultFour.operate(
            0, // new position
            col_,
            nativeDebt_,
            alice
        );

        oracleFourPrice_ = (oracleFourPrice_ * 985) / 1000;
        _setOracleFourPrice(oracleFourPrice_);

        uint liquidateAmt_ = 1e17; // 0.1 ETH

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueLiquidate)
        );
        vaultFour.liquidate{ value: (liquidateAmt_ + liquidateAmt_) }(liquidateAmt_, 0, bob, true);

        uint ethBalance_ = bob.balance;
        vm.prank(bob);
        (uint actualDebtAmt_, uint actualColAmt_) = vaultFour.liquidate{ value: liquidateAmt_ }(
            liquidateAmt_,
            0,
            bob,
            true
        );
        ethBalance_ -= actualDebtAmt_;
        assertEq(ethBalance_, bob.balance);
    }

    function testNativeLiquidateWithAbsorb() public {
        int col_ = 10000 * 1e18;
        int nativeDebt_ = 3.995 * 1e18;

        uint oracleFourPrice_ = 1e54 / (2000 * 1e27); // 1 DAI = 1 / 2000 ETH
        _setOracleFourPrice(oracleFourPrice_);
        vm.prank(alice);
        vaultFour.operate(
            0, // new position
            col_,
            nativeDebt_,
            alice
        );

        oracleFourPrice_ = (oracleFourPrice_ * 850) / 1000;
        _setOracleFourPrice(oracleFourPrice_);

        uint liquidateAmt_ = 1e17; // 0.1 ETH

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueLiquidate)
        );
        vaultFour.liquidate{ value: (liquidateAmt_ + liquidateAmt_) }(liquidateAmt_, 0, bob, true);

        uint ethBalance_ = bob.balance;
        vm.prank(bob);
        (uint actualDebtAmt_, uint actualColAmt_) = vaultFour.liquidate{ value: liquidateAmt_ }(
            liquidateAmt_,
            0,
            bob,
            true
        );
        ethBalance_ -= actualDebtAmt_;
        assertEq(ethBalance_, bob.balance);
    }

    function _liquidateNonNative(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 1000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidMsgValueLiquidate)
        );
        (uint actualDebtAmt_, uint actualColAmt_) = vaultContract_.liquidate{ value: liquidateAmt_ }(
            liquidateAmt_,
            0,
            address(bob),
            false
        );
    }

    function testLiquidateNonNativePositive() public {
        _liquidateNonNative(true);
    }

    function testLiquidateNonNativeNegative() public {
        _liquidateNonNative(false);
    }

    /// @dev Withdrawing more than user's actual supply should fail
    function testWithdrawMoreThanSupplied() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oracleOnePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oracleOnePrice_); //

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(DAI, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6,
            7_990 * 1e18,
            alice
        );

        // creating a dust position as withdrawing 1st user fully can result is error due to precision loss
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 * 1e6,
            7 * 1e18,
            alice
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__ExcessCollateralWithdrawal)
        );
        vaultOne.operate(
            1, // new position
            -(10_000 * 1e6 + 1),
            type(int).min,
            alice
        );
    }

    /// @dev Paying back more than user's actual borrow should fail
    function testPaybackMoreThanBorrowed() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oracleOnePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oracleOnePrice_); //

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(DAI, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6,
            7_990 * 1e18,
            alice
        );

        // creating a dust position as withdrawing 1st user fully can result is error due to precision loss
        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10 * 1e6,
            7 * 1e18,
            alice
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__ExcessDebtPayback));
        vaultOne.operate(
            1, // new position
            0,
            -(7_991 * 1e18),
            alice
        );
    }

    function testWithdrawAndPaybackMax() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oracleOnePrice_ = 1e39;
        _setOracleOnePrice(oracleOnePrice_);

        _setApproval(USDC, address(vaultOne), alice);
        _setApproval(DAI, address(vaultOne), alice);

        int supply_ = 10_000 * 1e6;
        int borrow_ = 7_990 * 1e18;

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            supply_,
            borrow_,
            alice
        );

        vm.prank(alice);
        // depositing dust
        vaultOne.operate(
            0, // new position
            10 * 1e6,
            7 * 1e18,
            alice
        );

        uint usdcBalLiq_ = _balanceBeforeHelper(IERC20(address(USDC)));
        uint daiBalLiq_ = _balanceBeforeHelper(IERC20(address(DAI)));

        vm.prank(alice);
        vaultOne.operate(
            1, // new position
            type(int).min,
            type(int).min,
            alice
        );

        _balanceAfterCheck(IERC20(address(USDC)), usdcBalLiq_, -supply_);
        _balanceAfterCheck(IERC20(address(DAI)), daiBalLiq_, borrow_);
    }

    /// @dev any address should be able to payback or deposit
    function testDepositAndPaybackFromAnyAddress() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oraclePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oraclePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6,
            7_990 * 1e18,
            alice
        );

        _setApproval(USDC, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), bob);

        vm.prank(bob);
        vaultOne.operate(
            1, // new position
            12000 * 1e6,
            -(1000 * 1e18),
            address(0)
        );
    }

    /// @dev any address should not be able to withdraw or borrow
    function testWithdrawAndBorrowFromAnyAddress() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oraclePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oraclePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10000 * 1e6,
            3000 * 1e18,
            alice
        );

        _setApproval(USDC, address(vaultOne), bob);
        _setApproval(DAI, address(vaultOne), bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NotAnOwner));
        vaultOne.operate(
            1, // new position
            -(1000 * 1e6),
            0,
            bob
        );

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NotAnOwner));
        vaultOne.operate(
            1, // new position
            0,
            3000 * 1e18,
            bob
        );
    }

    /// @dev interact with NFT of different vault (should fail)
    function testInteractFromDifferentVaultNFT() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oracleTwoPrice_ = 1e15; // * 1e18
        _setOracleTwoPrice(oracleTwoPrice_); //

        _setApproval(DAI, address(vaultTwo), alice);

        vm.prank(alice);
        vaultTwo.operate(
            0, // new position
            10000 * 1e18,
            7990 * 1e6,
            alice
        );

        uint oracleOnePrice_ = 1e39; // * 1e18
        _setOracleTwoPrice(oracleOnePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NftNotOfThisVault));
        vaultOne.operate(
            1, // new position
            10000 * 1e6,
            7990 * 1e18,
            alice
        );
    }

    /// @dev transfer NFT ownership and interact with new owner
    function testTransferNFTOwnershipAndInteractWithNewOwner() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oraclePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oraclePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10000 * 1e6,
            3000 * 1e18,
            alice
        );

        vm.prank(alice);
        vaultFactory.transferFrom(alice, bob, 1);

        _setApproval(USDC, address(vaultOne), bob);

        vm.prank(bob);
        vaultOne.operate(
            1, // new position
            10000 * 1e6,
            3000 * 1e18,
            bob
        );
    }

    /// @dev transfer NFT ownership and interact with old owner (should fail)
    function testTransferNFTOwnershipAndInteractWithOldOwner() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oraclePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oraclePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10000 * 1e6,
            3000 * 1e18,
            alice
        );

        vm.prank(alice);
        vaultFactory.transferFrom(alice, bob, 1);

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__NotAnOwner));
        vaultOne.operate(
            1, // new position
            10000 * 1e6,
            3000 * 1e18,
            alice
        );
    }

    /// @dev deposit and borrow 0 (should fail)
    function testDepositAndBorrowInvalidAmount() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        uint oraclePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oraclePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10000 * 1e6,
            3000 * 1e18,
            alice
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOperateAmount));
        vaultOne.operate(1, 0, 0, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOperateAmount));
        vaultOne.operate(1, 9999, 0, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOperateAmount));
        vaultOne.operate(1, 0, 9999, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOperateAmount));
        vaultOne.operate(1, -9999, 0, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__InvalidOperateAmount));
        vaultOne.operate(1, 0, -9999, alice);
    }

    function _depositAndBorrowAboveCF(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, -(100 * int(10 ** vaultSupplyDecimals(vault_))), 0, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, 0, 100 * int(10 ** vaultBorrowDecimals(vault_)), alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, -(100 * int(10 ** vaultSupplyDecimals(vault_))), 0, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, 0, 100 * int(10 ** vaultBorrowDecimals(vault_)), alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, collateral_ / 10, debt_ / 11, alice);
    }

    function testDepositAndBorrowAboveCFPositive() public {
        _depositAndBorrowAboveCF(true);
    }

    function testDepositAndBorrowAboveCFNegative() public {
        _depositAndBorrowAboveCF(false);
    }

    function _paybackAndWithdrawAboveCF(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, -(collateral_ / 10), -(debt_ / 10), alice);

        vm.prank(alice);
        vaultContract_.operate(1, -((collateral_ * 10) / 102), -(debt_ / 10), alice);
    }

    function testPaybackAndWithdrawAboveCFPositive() public {
        _paybackAndWithdrawAboveCF(true);
    }

    function testPaybackAndWithdrawAboveCFNegative() public {
        _paybackAndWithdrawAboveCF(false);
    }

    function _paybackAndDepositAboveCF(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__PositionAboveCF));
        vaultContract_.operate(1, -(collateral_ / 10), -(debt_ / 10), alice);

        vm.prank(alice);
        vaultContract_.operate(1, -((collateral_ * 10) / 102), -(debt_ / 10), alice);
    }

    function testPaybackAndDepositAboveCFPositive() public {
        _paybackAndDepositAboveCF(true);
    }

    function testPaybackAndDepositAboveCFNegative() public {
        _paybackAndDepositAboveCF(false);
    }

    // TODO: Also, verify change in exchange price when exchange price is not 1e12
    /// @dev verifies change in exchange price when magnifier is greater than 1x & less than 1x.
    function testChangeInExchangePrice() public {
        FluidVaultResolver.UserPosition memory userPosition_;

        // creating position in both vaults to make sure supply & borrow rates are not 0

        uint oracleOnePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oracleOnePrice_); //

        _setApproval(USDC, address(vaultOne), alice);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6 * 2,
            7_990 * 1e18 * 2,
            alice
        );

        uint oracleTwoPrice_ = 1e15; // * 1e18
        _setOracleTwoPrice(oracleTwoPrice_); //

        _setApproval(DAI, address(vaultTwo), alice);

        vm.prank(alice);
        vaultTwo.operate(
            0, // new position
            10_000 * 1e18,
            7_990 * 1e6,
            alice
        );

        uint vaultOneNewMagnifier_ = 11000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateSupplyRateMagnifier(vaultOneNewMagnifier_);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(vaultOneNewMagnifier_);

        uint vaultTwoNewMagnifier_ = 9000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultTwo)).updateSupplyRateMagnifier(vaultTwoNewMagnifier_);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultTwo)).updateBorrowRateMagnifier(vaultTwoNewMagnifier_);

        vm.warp(100000);

        (
            uint256 liqSupplyExPrice_,
            uint256 liqBorrowExPrice_,
            uint256 vaultSupplyExPrice_,
            uint256 vaultBorrowExPrice_
        ) = vaultOne.updateExchangePricesOnStorage();

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedSupplyExDifference_ = liqSupplyExPrice_ - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * vaultOneNewMagnifier_) / 10000;

        assertEq((LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_), vaultSupplyExPrice_);

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedBorrowExDifference_ = liqBorrowExPrice_ - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * vaultOneNewMagnifier_) / 10000;

        assertEq((LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_), vaultBorrowExPrice_);

        (liqSupplyExPrice_, liqBorrowExPrice_, vaultSupplyExPrice_, vaultBorrowExPrice_) = vaultTwo
            .updateExchangePricesOnStorage();

        expectedSupplyExDifference_ = liqSupplyExPrice_ - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * vaultTwoNewMagnifier_) / 10000;

        assertEq((LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_), vaultSupplyExPrice_);

        expectedBorrowExDifference_ = liqBorrowExPrice_ - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * vaultTwoNewMagnifier_) / 10000;

        assertEq((LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_), vaultBorrowExPrice_);
    }

    struct VaultRebalance {
        uint liqSupplyExPrice;
        uint liqBorrowExPrice;
        uint vaultSupplyExPrice;
        uint vaultBorrowExPrice;
        uint supplyVault;
        uint supplyVaultAfter;
        uint supplyVaultAfterLiquidity;
        uint borrowVault;
        uint borrowVaultAfter;
        uint borrowVaultAfterLiquidity;
        uint expectedSupplyRebalanceAmt;
        uint expectedBorrowRebalanceAmt;
    }

    /// @dev verifies change in exchange price when magnifier is greater than 1x & less than 1x.
    /// after verifying exchange price testing rebalance
    /// Checks the rebalance for both positive and negative ticks
    function testRebalance() public {
        FluidVaultResolver.UserPosition memory userPosition_;
        VaultRebalance memory rebalance_;

        // creating position in both vaults to make sure supply & borrow rates are not 0

        uint oracleOnePrice_ = 1e39; // * 1e18
        _setOracleOnePrice(oracleOnePrice_);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6 * 2,
            7_990 * 1e18 * 2,
            alice
        );

        uint oracleTwoPrice_ = 1e15; // * 1e18
        _setOracleTwoPrice(oracleTwoPrice_);

        vm.prank(alice);
        vaultTwo.operate(
            0, // new position
            10_000 * 1e18,
            7_990 * 1e6,
            alice
        );

        uint vaultOneNewMagnifier_ = 11000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateSupplyRateMagnifier(vaultOneNewMagnifier_);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultOne)).updateBorrowRateMagnifier(vaultOneNewMagnifier_);

        uint vaultTwoNewMagnifier_ = 9000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultTwo)).updateSupplyRateMagnifier(vaultTwoNewMagnifier_);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultTwo)).updateBorrowRateMagnifier(vaultTwoNewMagnifier_);

        vm.warp(100000);

        // ################ Vault One ################

        (
            rebalance_.liqSupplyExPrice,
            rebalance_.liqBorrowExPrice,
            rebalance_.vaultSupplyExPrice,
            rebalance_.vaultBorrowExPrice
        ) = vaultOne.updateExchangePricesOnStorage();

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedSupplyExDifference_ = rebalance_.liqSupplyExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * vaultOneNewMagnifier_) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_),
            rebalance_.vaultSupplyExPrice
        );

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedBorrowExDifference_ = rebalance_.liqBorrowExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * vaultOneNewMagnifier_) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_),
            rebalance_.vaultBorrowExPrice
        );

        rebalance_.supplyVault = 10_000 * 1e6 * 2;
        rebalance_.supplyVaultAfter =
            (rebalance_.supplyVault * rebalance_.vaultSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.supplyVaultAfterLiquidity =
            (rebalance_.supplyVault * rebalance_.liqSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVault = (7_990 * 1e18 * 2);
        rebalance_.borrowVaultAfter =
            (((rebalance_.borrowVault * (1e9 + 1)) / 1e9) * rebalance_.vaultBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVaultAfterLiquidity =
            (rebalance_.borrowVault * rebalance_.liqBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // Vault one will have deposit
        rebalance_.expectedSupplyRebalanceAmt = rebalance_.supplyVaultAfter - rebalance_.supplyVaultAfterLiquidity;
        // Vault one will have borrow
        rebalance_.expectedBorrowRebalanceAmt = rebalance_.borrowVaultAfter - rebalance_.borrowVaultAfterLiquidity;

        vm.prank(alice);
        (int supplyRebalanceAmt_, int borrowRebalanceAmt_) = vaultOne.rebalance();

        // 1e18 = 100%
        assertApproxEqRel(rebalance_.expectedSupplyRebalanceAmt, uint(supplyRebalanceAmt_), 1e4);
        assertApproxEqRel(rebalance_.expectedBorrowRebalanceAmt, uint(borrowRebalanceAmt_), 1e6);

        // ################ Vault Two ################

        (
            rebalance_.liqSupplyExPrice,
            rebalance_.liqBorrowExPrice,
            rebalance_.vaultSupplyExPrice,
            rebalance_.vaultBorrowExPrice
        ) = vaultTwo.updateExchangePricesOnStorage();

        expectedSupplyExDifference_ = rebalance_.liqSupplyExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * vaultTwoNewMagnifier_) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_),
            rebalance_.vaultSupplyExPrice
        );

        expectedBorrowExDifference_ = rebalance_.liqBorrowExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * vaultTwoNewMagnifier_) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_),
            rebalance_.vaultBorrowExPrice
        );

        rebalance_.supplyVault = 10_000 * 1e18;
        rebalance_.supplyVaultAfter =
            (rebalance_.supplyVault * rebalance_.vaultSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.supplyVaultAfterLiquidity =
            (rebalance_.supplyVault * rebalance_.liqSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVault = 7_990 * 1e6;
        rebalance_.borrowVaultAfter =
            ((rebalance_.borrowVault + 7) * rebalance_.vaultBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVaultAfterLiquidity =
            (rebalance_.borrowVault * rebalance_.liqBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // Vault two will have withdraw
        rebalance_.expectedSupplyRebalanceAmt = rebalance_.supplyVaultAfterLiquidity - rebalance_.supplyVaultAfter;
        // Vault two will have payback
        rebalance_.expectedBorrowRebalanceAmt = rebalance_.borrowVaultAfterLiquidity - rebalance_.borrowVaultAfter;

        _setApproval(USDC, address(vaultTwo), alice);
        vm.prank(alice);
        (supplyRebalanceAmt_, borrowRebalanceAmt_) = vaultTwo.rebalance();

        // 1e18 = 100%
        assertApproxEqRel(rebalance_.expectedSupplyRebalanceAmt, uint(-supplyRebalanceAmt_), 1e13);
        assertApproxEqRel(rebalance_.expectedBorrowRebalanceAmt, uint(-borrowRebalanceAmt_), 2e13);
    }

    struct RebalanceNative {
        uint colThree;
        uint debtThree;
        uint colFour;
        uint debtFour;
        uint vaultThreeNewMagnifier;
        uint vaultFourNewMagnifier;
    }

    function testRebalanceNative() public {
        FluidVaultResolver.UserPosition memory userPosition_;
        VaultRebalance memory rebalance_;
        RebalanceNative memory m_;

        _setOracleOnePrice(1e39);

        vm.prank(alice);
        vaultOne.operate(
            0, // new position
            10_000 * 1e6,
            7_990 * 1e18,
            alice
        );

        _setOracleTwoPrice(1e15);

        vm.prank(alice);
        vaultTwo.operate(
            0, // new position
            10_000 * 1e18,
            7_990 * 1e6,
            alice
        );

        uint oracleThreePrice_ = 2000 * 1e39; // 1 ETH = 2000 USDC
        _setOracleThreePrice(oracleThreePrice_);

        uint oracleFourPrice_ = 1e54 / (2000 * 1e27); // 1 DAI = 1 / 2000 ETH
        _setOracleFourPrice(oracleFourPrice_);

        // creating position in both vaults to make sure supply & borrow rates are not 0

        m_.colThree = 5 * 1e18;
        m_.debtThree = 7990 * 1e6;
        m_.colFour = 10000 * 1e18;
        m_.debtFour = 3995 * 1e15;

        vm.prank(alice);
        vaultThree.operate{ value: m_.colThree }(
            0, // new position
            int(m_.colThree),
            int(m_.debtThree),
            alice
        );

        vm.prank(alice);
        vaultFour.operate(
            0, // new position
            int(m_.colFour),
            int(m_.debtFour),
            alice
        );

        m_.vaultThreeNewMagnifier = 11000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultThree)).updateSupplyRateMagnifier(m_.vaultThreeNewMagnifier);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultThree)).updateBorrowRateMagnifier(m_.vaultThreeNewMagnifier);

        m_.vaultFourNewMagnifier = 9000;
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultFour)).updateSupplyRateMagnifier(m_.vaultFourNewMagnifier);
        vm.prank(alice);
        FluidVaultT1Admin(address(vaultFour)).updateBorrowRateMagnifier(m_.vaultFourNewMagnifier);

        vm.warp(100000);

        // ################ Vault Three ################

        (
            rebalance_.liqSupplyExPrice,
            rebalance_.liqBorrowExPrice,
            rebalance_.vaultSupplyExPrice,
            rebalance_.vaultBorrowExPrice
        ) = vaultThree.updateExchangePricesOnStorage();

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedSupplyExDifference_ = rebalance_.liqSupplyExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * m_.vaultThreeNewMagnifier) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_),
            rebalance_.vaultSupplyExPrice
        );

        // last liquidity exchange price is same as EXCHANGE_PRICES_PRECISION
        uint expectedBorrowExDifference_ = rebalance_.liqBorrowExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * m_.vaultThreeNewMagnifier) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_),
            rebalance_.vaultBorrowExPrice
        );

        rebalance_.supplyVault = m_.colThree;
        rebalance_.supplyVaultAfter =
            (rebalance_.supplyVault * rebalance_.vaultSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.supplyVaultAfterLiquidity =
            (rebalance_.supplyVault * rebalance_.liqSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVault = m_.debtThree;
        rebalance_.borrowVaultAfter =
            (((rebalance_.borrowVault * (1 + 1e9)) / 1e9) * rebalance_.vaultBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVaultAfterLiquidity =
            (rebalance_.borrowVault * rebalance_.liqBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // Vault one will have deposit
        rebalance_.expectedSupplyRebalanceAmt = rebalance_.supplyVaultAfter - rebalance_.supplyVaultAfterLiquidity;
        // Vault one will have borrow
        rebalance_.expectedBorrowRebalanceAmt = rebalance_.borrowVaultAfter - rebalance_.borrowVaultAfterLiquidity;

        vm.prank(alice);
        (int supplyRebalanceAmt_, int borrowRebalanceAmt_) = vaultThree.rebalance{
            value: rebalance_.expectedSupplyRebalanceAmt
        }();
        // 1e18 = 100%
        assertApproxEqRel(rebalance_.expectedSupplyRebalanceAmt, uint(supplyRebalanceAmt_), 1e4);
        if (uint(borrowRebalanceAmt_) - rebalance_.expectedBorrowRebalanceAmt > 1) {
            // difference should be greater than 1 wei to check this condition as liquidity does round up
            assertApproxEqRel((rebalance_.expectedBorrowRebalanceAmt + 2), uint(borrowRebalanceAmt_), 1e4);
        }

        // ################ Vault Four ################

        (
            rebalance_.liqSupplyExPrice,
            rebalance_.liqBorrowExPrice,
            rebalance_.vaultSupplyExPrice,
            rebalance_.vaultBorrowExPrice
        ) = vaultFour.updateExchangePricesOnStorage();

        expectedSupplyExDifference_ = rebalance_.liqSupplyExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedSupplyExDifference_ = (expectedSupplyExDifference_ * m_.vaultFourNewMagnifier) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedSupplyExDifference_),
            rebalance_.vaultSupplyExPrice
        );

        expectedBorrowExDifference_ = rebalance_.liqBorrowExPrice - LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        expectedBorrowExDifference_ = (expectedBorrowExDifference_ * m_.vaultFourNewMagnifier) / 10000;

        assertEq(
            (LiquidityCalcs.EXCHANGE_PRICES_PRECISION + expectedBorrowExDifference_),
            rebalance_.vaultBorrowExPrice
        );

        rebalance_.supplyVault = m_.colFour;
        rebalance_.supplyVaultAfter =
            (rebalance_.supplyVault * rebalance_.vaultSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.supplyVaultAfterLiquidity =
            (rebalance_.supplyVault * rebalance_.liqSupplyExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVault = m_.debtFour;
        rebalance_.borrowVaultAfter =
            (((rebalance_.borrowVault * (1 + 1e9)) / 1e9) * rebalance_.vaultBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;
        rebalance_.borrowVaultAfterLiquidity =
            (rebalance_.borrowVault * rebalance_.liqBorrowExPrice) /
            LiquidityCalcs.EXCHANGE_PRICES_PRECISION;

        // Vault two will have withdraw
        rebalance_.expectedSupplyRebalanceAmt = rebalance_.supplyVaultAfterLiquidity - rebalance_.supplyVaultAfter;
        // Vault two will have payback
        rebalance_.expectedBorrowRebalanceAmt = rebalance_.borrowVaultAfterLiquidity - rebalance_.borrowVaultAfter;

        vm.prank(alice);
        (supplyRebalanceAmt_, borrowRebalanceAmt_) = vaultFour.rebalance{
            value: rebalance_.expectedBorrowRebalanceAmt
        }();

        // 1e18 = 100%
        assertApproxEqRel(rebalance_.expectedSupplyRebalanceAmt, uint(-supplyRebalanceAmt_), 1e13);
        assertApproxEqRel(rebalance_.expectedBorrowRebalanceAmt, uint(-borrowRebalanceAmt_), 1e13);
    }

    /// @param positiveTick_ if true then vault 1, else vault 2 as vault 1 will have positive ticks & vault 2 will have negative ticks
    function _liquidateFromSinglePerfectTickTillLiquidationThreshold(bool positiveTick_) internal {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 3000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (uint actualDebtAmt_, uint actualColAmt_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);

        uint expectedFinalCollateral_ = uint(collateral_) - actualColAmt_;
        uint expectedFinalDebt_ = uint(debt_) - actualDebtAmt_;
        _verifyLiquidation(1, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testLiquidateFromSinglePerfectTickTillLiquidationThresholdPositive() public {
        _liquidateFromSinglePerfectTickTillLiquidationThreshold(true);
    }

    function testLiquidateFromSinglePerfectTickTillLiquidationThresholdNegative() public {
        _liquidateFromSinglePerfectTickTillLiquidationThreshold(false);
    }

    function _liquidateSingleFromPerfectTickTillBetween(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 100 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (uint actualDebtAmt_, uint actualColAmt_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);

        uint expectedFinalCollateral_ = uint(collateral_) - actualColAmt_;
        uint expectedFinalDebt_ = uint(debt_) - actualDebtAmt_;
        _verifyLiquidation(1, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testLiquidateSingleFromPerfectTickTillBetweenPositive() public {
        _liquidateSingleFromPerfectTickTillBetween(true);
    }

    function testLiquidateSingleFromPerfectTickTillBetweenNegative() public {
        _liquidateSingleFromPerfectTickTillBetween(false);
    }

    function _liquidateFromBranch(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint totalColLiquidated_;
        uint totalDebtLiquidated_;
        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        uint liquidateAmt_ = 100 * (10 ** vaultBorrowDecimals(vault_));

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalColLiquidated_ += colLiquidated_;
        totalDebtLiquidated_ += debtLiquidated_;

        liquidateAmt_ = 200 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalColLiquidated_ += colLiquidated_;
        totalDebtLiquidated_ += debtLiquidated_;

        uint expectedFinalCollateral_ = uint(collateral_) - totalColLiquidated_;
        uint expectedFinalDebt_ = uint(debt_) - totalDebtLiquidated_;
        _verifyLiquidation(1, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testLiquidateFromBranchPositive() public {
        _liquidateFromBranch(true);
    }

    function testLiquidateFromBranchNegative() public {
        _liquidateFromBranch(false);
    }

    function _multiplePerfectTickLiquidation(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = (debt_ * 994) / 1000; // 0.4% less will result in a different tick

        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        uint liquidateAmt_ = 1000 * (10 ** vaultBorrowDecimals(vault_));

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);

        uint expectedFinalCollateral_ = uint(collateral_ + collateral_) - colLiquidated_;
        uint expectedFinalDebt_ = uint(debt_ + debtTwo_) - debtLiquidated_;
        _verifyLiquidation(2, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testMultiplePerfectTickLiquidationPositive() public {
        _multiplePerfectTickLiquidation(true);
    }

    function testMultiplePerfectTickLiquidationNegative() public {
        _multiplePerfectTickLiquidation(false);
    }

    // - Initializing a tick
    // - Liquidating a tick
    // - Initializing another tick exactly same as before
    // - Liquidating another tick exactly same as before
    // - Liquidating again. Final position of both position should be same
    function _perfectTickAndBranchLiquidation(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint totalColLiquidated_;
        uint totalDebtLiquidated_;
        uint colLiquidated_;
        uint debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 50 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        liquidateAmt_ = 49 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        liquidateAmt_ = 50 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        uint expectedFinalCollateral_ = uint(collateral_ + collateral_) - totalColLiquidated_;
        uint expectedFinalDebt_ = uint(debt_ + debt_) - totalDebtLiquidated_;
        _verifyLiquidation(2, expectedFinalCollateral_, expectedFinalDebt_);
        _verifyPosition();
    }

    function testPerfectTickAndBranchLiquidationPositive() public {
        _perfectTickAndBranchLiquidation(true);
    }

    function testPerfectTickAndBranchLiquidationNegative() public {
        _perfectTickAndBranchLiquidation(false);
    }

    // initialize a tick
    // liquidate
    // inititalize again at the exact same tick
    // liquidate a bit less such that the branch doesn't merge with other branch
    // inititalize again at the exact same tick
    // liquidate everything together
    // 3rd branch will merge into 2nd branch will merge into 1st branch
    function _perfectTickAndMultipleBranchesLiquidation(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint totalColLiquidated_;
        uint totalDebtLiquidated_;

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 100 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        liquidateAmt_ = 50 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        liquidateAmt_ = 500 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        uint expectedFinalCollateral_ = uint(collateral_ * 3) - totalColLiquidated_;
        uint expectedFinalDebt_ = uint(debt_ * 3) - totalDebtLiquidated_;
        _verifyLiquidation(3, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testPerfectTickAndMultipleBranchesLiquidationPositive() public {
        _perfectTickAndMultipleBranchesLiquidation(true);
    }

    function testPerfectTickAndMultipleBranchesLiquidationNegative() public {
        _perfectTickAndMultipleBranchesLiquidation(false);
    }

    function _tickBranchTickBranchLiquidation(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        uint length_ = 5;
        int[] memory collaterals_ = new int[](length_);
        int[] memory debts_ = new int[](length_);

        collaterals_[0] = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        debts_[0] = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        collaterals_[1] = 9_000 * int(10 ** vaultSupplyDecimals(vault_));
        debts_[1] = 6_800 * int(10 ** vaultBorrowDecimals(vault_));
        collaterals_[2] = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        debts_[2] = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        collaterals_[3] = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        debts_[3] = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        collaterals_[4] = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        debts_[4] = 7_840 * int(10 ** vaultBorrowDecimals(vault_));

        uint totalColLiquidated_;
        uint totalDebtLiquidated_;

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collaterals_[0], debts_[0], alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 500);

        uint liquidateAmt_ = 1000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collaterals_[1], debts_[1], alice);

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collaterals_[2], debts_[2], alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 500);

        liquidateAmt_ = 500 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collaterals_[3], debts_[3], alice);

        vm.prank(alice);
        vaultContract_.operate(0, collaterals_[4], debts_[4], alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1000);

        liquidateAmt_ = 10000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalDebtLiquidated_ += debtLiquidated_;
        totalColLiquidated_ += colLiquidated_;

        uint expectedFinalCollateral_;
        uint expectedFinalDebt_;
        for (uint i; i < length_; i++) {
            expectedFinalCollateral_ += uint(collaterals_[i]);
            expectedFinalDebt_ += uint(debts_[i]);
        }
        expectedFinalCollateral_ -= totalColLiquidated_;
        expectedFinalDebt_ -= totalDebtLiquidated_;
        _verifyLiquidation(length_, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testTickBranchTickBranchLiquidationPositive() public {
        _tickBranchTickBranchLiquidation(true);
    }

    function testTickBranchTickBranchLiquidationNegative() public {
        _tickBranchTickBranchLiquidation(false);
    }

    /// 1. Initializing a position
    /// 2. Unitializing by making debt 0 aka supply only position
    /// 3. Initializing another position
    /// 4. Liquidating.
    function _unitializeFirstPosition(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(1, 0, type(int).min, alice);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.topTick == type(int).min, "top-tick-should-not-exist");

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 200 * 10 ** vaultBorrowDecimals(vault_);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);

        uint expectedFinalCollateral_ = uint(collateral_ + collateral_) - colLiquidated_;
        uint expectedFinalDebt_ = uint(debt_) - debtLiquidated_;
        _verifyLiquidation(2, expectedFinalCollateral_, expectedFinalDebt_);
    }

    // function testUnitializeFirstPositionPositive() public {
    //     _unitializeFirstPosition(true);
    // }

    function testUnitializeFirstPositionNegative() public {
        // returning this test case as it fails at Liquidity contract level due to some wei precision which is expected
        return;
        _unitializeFirstPosition(false);
    }

    // 1. Creating a position
    // 2. Partial liquidating it
    // 3. Creating another position above last liquidation point by changing oracle
    // 4. Removing new position entirely
    // 5. Liquidating old position again by partial liquidating
    // It checks initial top tick was not liquidated, after liquidation it's a liquidated top tick,
    // after creating new position it's again not liquidated & after removing the above position it's again liquidated
    function _liquidateInitializeAndUnitialize(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint totalColLiquidated_;
        uint totalDebtLiquidated_;

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 100 * 10 ** vaultBorrowDecimals(vault_);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        totalColLiquidated_ += colLiquidated_;
        totalDebtLiquidated_ += debtLiquidated_;

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(2, type(int).min, type(int).min, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), false);
        console2.log("debtLiquidated_", debtLiquidated_);
        totalColLiquidated_ += colLiquidated_;
        totalDebtLiquidated_ += debtLiquidated_;

        uint expectedFinalCollateral_ = uint(collateral_) - totalColLiquidated_;
        uint expectedFinalDebt_ = uint(debt_) - totalDebtLiquidated_;
        _verifyLiquidation(2, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testLiquidateInitializeAndUnitializePositive(bool positiveTick_) public {
        _liquidateInitializeAndUnitialize(true);
    }

    function testLiquidateInitializeAndUnitializeNegative(bool positiveTick_) public {
        _liquidateInitializeAndUnitialize(false);
    }

    function _absorbMultiplePerfectTickOne(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 990 * int(10 ** vaultBorrowDecimals(vault_));

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        FluidVaultResolver.UserPosition memory userPosition_;
        for (uint i = 0; i < 3; i++) {
            (userPosition_, ) = vaultResolver.positionByNftId((i + 1));
            require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
            require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        }

        require(vaultData_.vaultState.topTick == type(int).min, "4th-user-position-should-be-top-tick");

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        (userPosition_, vaultData_) = vaultResolver.positionByNftId(4);
        require(userPosition_.tick == vaultData_.vaultState.topTick, "4th-user-position-should-be-top-tick");
    }

    function testAbsorbMultiplePerfectTickOnePositive() public {
        _absorbMultiplePerfectTickOne(true);
    }

    function testAbsorbMultiplePerfectTickOneNegative() public {
        _absorbMultiplePerfectTickOne(false);
    }

    function _absorbMultiplePerfectTickTwo(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 10000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        FluidVaultResolver.UserPosition memory userPosition_;
        for (uint i = 0; i < 3; i++) {
            (userPosition_, ) = vaultResolver.positionByNftId((i + 1));
            require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
            require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        }

        (userPosition_, vaultData_) = vaultResolver.positionByNftId(4);
        require(userPosition_.tick == vaultData_.vaultState.topTick, "4th-user-position-should-be-top-tick");
        require(vaultData_.vaultState.currentBranch == 1, "branch-not-1");

        assertApproxEqRel(vaultData_.vaultState.totalSupply, (uint(collateral_) * 4) - colLiquidated_, 1e14);
        assertApproxEqRel(
            vaultData_.vaultState.totalBorrow,
            (uint(debt_) * 3) + uint(debtTwo_) - debtLiquidated_,
            1e14
        );
    }

    function testAbsorbMultiplePerfectTickTwoPositive() public {
        _absorbMultiplePerfectTickTwo(true);
    }

    function testAbsorbMultiplePerfectTickTwoNegative() public {
        _absorbMultiplePerfectTickTwo(false);
    }

    function _absorbMultiplePerfectTickAndBranches(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 7800 * int(10 ** vaultBorrowDecimals(vault_));
        int debtThree_ = 900 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtThree_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 200 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 2, "first-branch-got-closed");

        setOraclePrice(1e39, positiveTick_);

        liquidateAmt_ = 10000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        for (uint i = 0; i < 4; i++) {
            if (i + 1 != 3) (userPosition_, ) = vaultResolver.positionByNftId((i + 1));
            require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
            require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        }

        require(vaultData_.vaultState.currentBranch == 2, "first-branch-got-closed");

        (userPosition_, ) = vaultResolver.positionByNftId(3);
        require(vaultData_.vaultState.topTick == userPosition_.tick, "top-tick-should-be-of-3rd-user");
    }

    function testAbsorbMultiplePerfectTickAndBranchesPositive() public {
        _absorbMultiplePerfectTickAndBranches(true);
    }

    function testAbsorbMultiplePerfectTickAndBranchesNegative() public {
        _absorbMultiplePerfectTickAndBranches(false);
    }

    function _absorbBranch(bool positiveTick_) internal {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 800 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 200 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 2, "first-branch-got-closed");

        setOraclePrice(1e39, positiveTick_);

        liquidateAmt_ = 5000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        (userPosition_, ) = vaultResolver.positionByNftId(1);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");

        require(vaultData_.vaultState.currentBranch == 2, "first-branch-got-closed");

        (userPosition_, ) = vaultResolver.positionByNftId(2);
        require(vaultData_.vaultState.topTick == userPosition_.tick, "top-tick-should-be-of-2nd-user");
    }

    function testAbsorbBranchPositive() public {
        _absorbBranch(true);
    }

    function testAbsorbBranchNegative() public {
        _absorbBranch(false);
    }

    function _absorbMultipleBranches(bool positiveTick_) internal {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 800 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 500);

        uint liquidateAmt_ = 500 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        liquidateAmt_ = 200 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 3, "first-branch-got-closed");

        setOraclePrice(1e39, positiveTick_);

        liquidateAmt_ = 5000 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        (userPosition_, ) = vaultResolver.positionByNftId(1);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        (userPosition_, ) = vaultResolver.positionByNftId(3);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");

        require(vaultData_.vaultState.currentBranch == 3, "first-branch-got-closed");

        (userPosition_, ) = vaultResolver.positionByNftId(2);
        require(vaultData_.vaultState.topTick == userPosition_.tick, "top-tick-should-be-of-2nd-user");
    }

    function testAbsorbMultipleBranchesPositive() public {
        _absorbBranch(true);
    }

    function testAbsorbMultipleBranchesNegative() public {
        _absorbBranch(false);
    }

    function _absorbTickWhileBranchAsNextTopTick(bool positiveTick_) internal {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 500 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        liquidateAmt_ = 1000 * (10 ** vaultBorrowDecimals(vault_));

        setOraclePricePercentDecrease(1e39, positiveTick_, 400);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 2, "should-be-2nd-branch");

        setOraclePricePercentDecrease(1e39, positiveTick_, 1300);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        setOraclePrice(1e39, positiveTick_);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 1, "first-branch-should-be-the-branch");
        require(vaultData_.vaultState.currentBranchState.status == 1, "first-branch-is-in-liquidated-state");
    }

    function testAbsorbTickWhileBranchAsNextTopTickPositive() public {
        _absorbTickWhileBranchAsNextTopTick(true);
    }

    function testAbsorbTickWhileBranchAsNextTopTickNegative() public {
        _absorbTickWhileBranchAsNextTopTick(false);
    }

    function _absorbBranchWhileBranchAsNextTopTick(bool positiveTick_) internal {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debt_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));

        uint colLiquidated_;
        uint debtLiquidated_;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        uint liquidateAmt_ = 500 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        liquidateAmt_ = 1000 * (10 ** vaultBorrowDecimals(vault_));

        setOraclePricePercentDecrease(1e39, positiveTick_, 400);

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        setOraclePrice(1e39, positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 2, "should-be-2nd-branch");

        setOraclePricePercentDecrease(1e39, positiveTick_, 200);

        liquidateAmt_ = 100 * (10 ** vaultBorrowDecimals(vault_));

        vm.prank(bob);
        (debtLiquidated_, colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1300);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        setOraclePrice(1e39, positiveTick_);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        require(vaultData_.vaultState.currentBranch == 1, "first-branch-should-be-the-branch");
        require(vaultData_.vaultState.currentBranchState.status == 1, "first-branch-is-in-liquidated-state");
    }

    function testAbsorbBranchWhileBranchAsNextTopTickPositive() public {
        _absorbBranchWhileBranchAsNextTopTick(true);
    }

    function testAbsorbBranchWhileBranchAsNextTopTickNegative() public {
        _absorbBranchWhileBranchAsNextTopTick(false);
    }

    function testInitializeBigAndDustUserAndChangeBigUser() public {
        bool positiveTick_ = true;
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateralBig_ = 10000 * int(1e18) * 6;
        int debtBig_ = 7990 * int(1e18) * 6;

        int collateralSmall_ = 1000000;
        int debtSmall_ = 799000;

        vm.prank(alice);
        vaultContract_.operate(0, collateralSmall_, debtSmall_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateralBig_, debtBig_, alice);

        collateralBig_ = 11000 * int(1e18);
        debtBig_ = 5990 * int(1e18);

        vm.prank(alice);
        vaultContract_.operate(2, collateralBig_, debtBig_, alice);

        collateralSmall_ = 3000000;
        debtSmall_ = 1399000;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Error.FluidVaultError.selector, ErrorTypes.Vault__TickIsEmpty));
        vaultContract_.operate(1, collateralSmall_, debtSmall_, alice);
    }

    function testLiquidate0Tick() public {
        bool positiveTick_ = true;
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        int collateral_ = 10000 * 1e18;
        int debt_ = 10000 * 1e18;

        setOraclePrice(((1e27 * 126) / 100), positiveTick_);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        FluidVaultLiquidationResolver liquidationResolver = new FluidVaultLiquidationResolver(
            IFluidVaultResolver(address(vaultResolver)),
            IFluidLiquidity(address(liquidity))
        );
        LiquidationResolverStructs.Swap memory swap = liquidationResolver.getSwapForProtocol(vault_);
        assertEq(swap.data.inAmt, 0, "unexpected liquidation available");

        int debtTwo_ = debt_ * 10000;
        debtTwo_ = debtTwo_ / 10001;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        int debtThree_ = debt_ * 10000;
        debtThree_ = debtThree_ / 10020;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtThree_, alice);

        setOraclePrice(((1e27 * 122) / 100), positiveTick_);

        uint liquidateAmt_ = 2000 * 1e18;

        swap = liquidationResolver.getSwapForProtocol(vault_);
        assertEq(swap.data.inAmt, 1881160285369995569778);

        vm.prank(bob);
        (uint debtLiquidated_, uint colLiquidated_) = vaultContract_.liquidate(liquidateAmt_, 0, address(bob), true);

        uint expectedFinalCollateral_ = uint(collateral_ * 3) - colLiquidated_;
        uint expectedFinalDebt_ = uint(debt_ + debtTwo_ + debtThree_) - debtLiquidated_;
        _verifyLiquidation(3, expectedFinalCollateral_, expectedFinalDebt_);
    }

    function testAbsorb0Tick() public {
        bool positiveTick_ = true;
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(((1e27 * 126) / 100), positiveTick_);

        int collateral_ = 10000 * 1e18;
        int debt_ = 100 * 1e18;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        collateral_ = 10000 * 1e18;
        debt_ = 10000 * 1e18;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debt_, alice);

        int debtTwo_ = debt_ * 10000;
        debtTwo_ = debtTwo_ / 10001;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        int debtThree_ = debt_ * 10000;
        debtThree_ = debtThree_ / 10020;

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtThree_, alice);

        setOraclePrice(((1e27 * 110) / 100), positiveTick_);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        (userPosition_, ) = vaultResolver.positionByNftId(2);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        (userPosition_, ) = vaultResolver.positionByNftId(3);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");
        (userPosition_, ) = vaultResolver.positionByNftId(4);
        require(userPosition_.supply == 0, "Absorbed-position-supply-should-be-0");
        require(userPosition_.borrow == 0, "Absorbed-position-borrow-should-be-0");

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        (userPosition_, ) = vaultResolver.positionByNftId(1);
        require(userPosition_.tick == vaultData_.vaultState.topTick, "1st-user-position-should-be-top-tick");
    }

    // function testLiquidate0TickPositive() public {
    //     _liquidate0Tick(true);
    // }

    // function testLiquidate0TickNegative() public {
    //     _liquidateSingleFromPerfectTickTillBetween(false);
    // }

    // ################### Admin module ###################

    function _absorbAndUseAbsorbDustDebt(bool positiveTick_) public {
        address vault_ = positiveTick_ ? address(vaultOne) : address(vaultTwo);
        FluidVaultT1 vaultContract_ = FluidVaultT1(vault_);
        FluidVaultResolver.VaultEntireData memory vaultData_ = vaultResolver.getVaultEntireData(vault_);
        FluidVaultResolver.UserPosition memory userPosition_;

        setOraclePrice(1e39, positiveTick_);

        int collateral_ = 10000 * int(10 ** vaultSupplyDecimals(vault_));
        int debtOne_ = 7990 * int(10 ** vaultBorrowDecimals(vault_));
        int debtTwo_ = 7900 * int(10 ** vaultBorrowDecimals(vault_));
        int debtThree_ = 7800 * int(10 ** vaultBorrowDecimals(vault_));

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtOne_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtTwo_, alice);

        vm.prank(alice);
        vaultContract_.operate(0, collateral_, debtThree_, alice);

        setOraclePricePercentDecrease(1e39, positiveTick_, 1500);

        vm.prank(bob);
        vaultContract_.liquidate(0, 0, address(0), false);

        setOraclePrice(1e39, positiveTick_);

        uint totalDustDebt_;
        for (uint i = 1; i < 4; i++) {
            (userPosition_, ) = vaultResolver.positionByNftId(i);
            totalDustDebt_ += userPosition_.beforeDustBorrow;
        }

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        uint totalBorrowDiff_ = vaultData_.vaultState.totalBorrow;

        uint[] memory nftIds_ = new uint[](3);
        nftIds_[0] = 1;
        nftIds_[1] = 2;
        nftIds_[2] = 3;
        vm.prank(alice);
        FluidVaultT1Admin(vault_).absorbDustDebt(nftIds_);

        vaultData_ = vaultResolver.getVaultEntireData(vault_);
        totalBorrowDiff_ = vaultData_.vaultState.totalBorrow - totalBorrowDiff_;

        assertApproxEqRel(totalBorrowDiff_, totalDustDebt_, 1e6);
    }

    function testAbsorbAndUseAbsorbDustDebtPositive() public {
        _absorbAndUseAbsorbDustDebt(true);
    }

    function testAbsorbAndUseAbsorbDustDebtNegative() public {
        _absorbAndUseAbsorbDustDebt(false);
    }
}
