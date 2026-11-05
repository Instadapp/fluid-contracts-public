//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { IFluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/iLiquidityResolver.sol";
import { FluidLiquidityResolver } from "../../../contracts/periphery/resolvers/liquidity/main.sol";
import { FluidLiquidityTokenAuth, Events, Constants } from "../../../contracts/config/liquidityTokenAuth/main.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { TestERC20 } from "../testERC20.sol";

contract LiquidityTokenAuthTest is Test, Events {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    IFluidLiquidityResolver liquidityResolver;

    address internal constant REBALANCER = 0x3BE5C671b20649DCA5D916b5698328D54BdAAf88;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    uint256 internal constant X14 = 0x3fff;

    address bob = makeAddr("bob");

    FluidLiquidityTokenAuth handler;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(20286605);

        liquidityResolver = IFluidLiquidityResolver(address(new FluidLiquidityResolver(LIQUIDITY)));

        _deployNewHandler();
    }

    function test_deployment() public {
        assertEq(address(handler.LIQUIDITY()), address(LIQUIDITY));
    }

    function _deployNewHandler() internal {
        handler = new FluidLiquidityTokenAuth(address(LIQUIDITY), RESERVE_CONTRACT);

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
    }
}

contract FluidLiquidityTokenAuthTestsListToken is LiquidityTokenAuthTest {
    function test_listToken_revertWhenUnauthorized() public {
        TestERC20 token = new TestERC20("TestERC20", "TST");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LiquidityTokenAuth__Unauthorized)
        );
        handler.listToken(address(token));
    }

    function test_listToken_revertIfAlreadyInitialized() public {
        TestERC20 token = new TestERC20("TestERC20", "TST");

        vm.startPrank(handler.TEAM_MULTISIG());
        handler.listToken(address(token));

        // verifying rateDataV2 struct values are set
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(address(token));
        assertEq(currentRateData.version, 2);
        assertEq(currentRateData.rateDataV2.kink1, 5000);
        assertEq(currentRateData.rateDataV2.kink2, 8000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationZero, 0);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 2000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 4000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationMax, 10000);

        // verifying token config values are set
        uint256 exchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(address(token));
        uint256 fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        uint256 threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        uint256 configs2_ = liquidityResolver.getConfigs2(address(token));
        uint256 maxUtilization_ = configs2_ & X14;
        assertEq(1000, fee_);
        assertEq(30, threshold_);
        assertEq(0, maxUtilization_);

        // trying to initialize again
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LiquidityTokenAuth_AlreadyInitialized)
        );
        handler.listToken(address(token));
    }

    function test_listToken() public {
        TestERC20 token = new TestERC20("TestERC20", "TST");

        vm.prank(REBALANCER);
        handler.listToken(address(token));

        // verifying rateDataV2 struct values are set
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(address(token));
        assertEq(currentRateData.version, 2);
        assertEq(currentRateData.rateDataV2.kink1, 5000);
        assertEq(currentRateData.rateDataV2.kink2, 8000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationZero, 0);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 2000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 4000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationMax, 10000);

        // verifying token config values are set
        uint256 exchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(address(token));
        uint256 fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        uint256 threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        uint256 configs2_ = liquidityResolver.getConfigs2(address(token));
        uint256 maxUtilization_ = configs2_ & X14;
        assertEq(1000, fee_);
        assertEq(30, threshold_);
        assertEq(0, maxUtilization_);
    }

    function test_updateReserveFactor() public {
        TestERC20 token = new TestERC20("TestERC20", "TST");

        vm.prank(REBALANCER);
        handler.listToken(address(token));

        // verifying rateDataV2 struct values are set
        ResolverStructs.RateData memory currentRateData = liquidityResolver.getTokenRateData(address(token));
        assertEq(currentRateData.version, 2);
        assertEq(currentRateData.rateDataV2.kink1, 5000);
        assertEq(currentRateData.rateDataV2.kink2, 8000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationZero, 0);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink1, 2000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationKink2, 4000);
        assertEq(currentRateData.rateDataV2.rateAtUtilizationMax, 10000);

        // verifying token config values are set
        uint256 exchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(address(token));
        uint256 fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        uint256 threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        uint256 configs2_ = liquidityResolver.getConfigs2(address(token));
        uint256 maxUtilization_ = configs2_ & X14;
        assertEq(1000, fee_);
        assertEq(30, threshold_);
        assertEq(0, maxUtilization_);

        vm.prank(handler.TEAM_MULTISIG());
        handler.updateReserveFactor(address(token), 3500);

        // verifying token config values are set
        exchangePricesAndConfig_ = liquidityResolver.getExchangePricesAndConfig(address(token));
        fee_ = (exchangePricesAndConfig_ >> 16) & X14;
        threshold_ = (exchangePricesAndConfig_ >> 44) & X14;
        configs2_ = liquidityResolver.getConfigs2(address(token));
        maxUtilization_ = configs2_ & X14;
        assertEq(3500, fee_);
        assertEq(30, threshold_);
        assertEq(0, maxUtilization_);
    }

    function test_updateReserveFactor_revertWhenUnauthorized() public {
        TestERC20 token = new TestERC20("TestERC20", "TST");

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.LiquidityTokenAuth__Unauthorized)
        );
        handler.updateReserveFactor(address(token), 3500);
    }
}
