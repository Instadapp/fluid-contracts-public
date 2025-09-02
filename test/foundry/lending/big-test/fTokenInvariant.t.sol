//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "forge-std/console2.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { fToken } from "../../../../contracts/protocols/lending/fToken/main.sol";
import { ErrorTypes } from "../../../../contracts/protocols/lending/errorTypes.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { IFluidLendingFactory } from "../../../../contracts/protocols/lending/interfaces/iLendingFactory.sol";
import { Structs as AdminModuleStructs } from "../../../../contracts/liquidity/adminModule/structs.sol";
import { Structs as ResolverStructs } from "../../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFToken } from "../../../../contracts/protocols/lending/interfaces/iFToken.sol";

import { fTokenBaseSetUp } from "../fToken.t.sol";
import { TestERC20 } from "../../testERC20.sol";
import { ERC4626fTokenHelperTest } from "../erc4626/erc4626.t.sol";
import { FTokenHandler } from "./fTokenHandler.sol";

import { Error } from "../../../../contracts/liquidity/error.sol";

contract FTokenHandlerInvariantsHandlerTest is ERC4626fTokenHelperTest {
    FTokenHandler handler;
    address john = address(0xABFF);

    address[] users = new address[](3);
    uint256 lastTokenExchangePrice;

    function setUp() public virtual override(ERC4626fTokenHelperTest) {
        ERC4626fTokenHelperTest.setUp();
        (rateModel, endTime_, startTime_) = activateRewardRateModel();
        _setUserAllowancesDefault(address(liquidity), admin, address(asset), address(mockProtocol));
        users[0] = address(alice);
        users[1] = address(bob);
        users[2] = address(john);
        handler = new FTokenHandler(
            IFToken(address(token)),
            address(asset),
            users,
            admin,
            address(liquidity),
            mockProtocol
        );

        vm.prank(alice);
        asset.approve(address(token), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(token), type(uint256).max);

        vm.prank(john);
        asset.approve(address(token), type(uint256).max);

        vm.prank(alice);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(john);
        asset.approve(address(handler), type(uint256).max);

        vm.prank(alice);
        token.approve(address(handler), type(uint256).max);

        vm.prank(bob);
        token.approve(address(handler), type(uint256).max);

        vm.prank(john);
        token.approve(address(handler), type(uint256).max);

        targetContract(address(handler));

        // address[] memory senders = [alice, bob];
        targetSender(alice);
        targetSender(bob);

        vm.prank(admin);
        factory.setAuth(alice, true);
        vm.prank(admin);
        factory.setAuth(bob, true);
        vm.prank(admin);
        factory.setAuth(john, true);

        (, , , , , , , , lastTokenExchangePrice) = IFToken(address(token)).getData();

        initialDeposit(15e18);
    }

    function invariant_TokenExchangePriceShouldOnlyGoUp() public {
        // warp to last update timestamp 40 bits in slot 8 starting at bit 128
        uint256 lastUpdateTimestamp = uint256(vm.load(address(token), bytes32(uint256(8))));
        lastUpdateTimestamp = lastUpdateTimestamp >> 128 & 0xFFFFFFFFFF;
        vm.warp(lastUpdateTimestamp);

        (, , , , , , , , uint256 currentTokenExchangePrice) = IFToken(address(token)).getData();
        assertGe(currentTokenExchangePrice, lastTokenExchangePrice, "Token exchange price should not decrease");
    }

    function invariant_UndelyingBalanceOfFTokenShouldNeverBeGreaterThanZero() public {
        // with normal interactions (supply, withdraw) ERC20 underlying balanceOf fToken should never be > 0.
        assertEq(asset.balanceOf(address(token)), 0, "UndelyingBalanceOfFTokenShouldNeverBeGreaterThanZero");
    }

    function invariant_SharesShouldAlwaysBeSumOfAllDepositorsShares() public {
        // warp to last update timestamp 40 bits in slot 8 starting at bit 128
        uint256 lastUpdateTimestamp = uint256(vm.load(address(token), bytes32(uint256(8))));
        lastUpdateTimestamp = lastUpdateTimestamp >> 128 & 0xFFFFFFFFFF;
        vm.warp(lastUpdateTimestamp);

        uint256 sum;
        for (uint256 i = 0; i > users.length; i++) {
            sum += IFToken(address(token)).balanceOf(users[i]);
        }
        assertGe(IFToken(address(token)).totalAssets(), sum, "SharesShouldAlwaysBeSumOfAllDepositorsShares");
    }

    function invariant_totalSupplyAlwaysSumOfUserShares() public {
        uint256 adminBalance = IFToken(address(token)).balanceOf(admin);
        uint256 aliceBalance = IFToken(address(token)).balanceOf(alice);
        uint256 bobBalance = IFToken(address(token)).balanceOf(bob);
        uint256 johnBalance = IFToken(address(token)).balanceOf(john);
        uint256 allBalance = adminBalance + aliceBalance + bobBalance + johnBalance;
        uint256 totalSupply = IERC4626(address(token)).totalSupply();
        assertEq(allBalance, totalSupply);
        uint256 ghost_sumBalanceOf = FTokenHandler(handler).ghost_sumBalanceOf();
        assertEq(uint256(ghost_sumBalanceOf + sharesAmountFrominitialDeposit), uint256(totalSupply));
    }

    function invariant_Metadata() public {
        assertEq(token.name(), string.concat("Fluid ", asset.symbol()));
        assertEq(token.symbol(), string.concat("f", asset.symbol()));
        assertEq(token.decimals(), token.decimals());
    }
}
