//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { FluidCollectRevenueAuth, Events } from "../../../contracts/config/collectRevenueAuth/main.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";

contract FluidCollectRevenueAuthTest is Test, Events {
    IFluidLiquidity internal constant LIQUIDITY = IFluidLiquidity(0x52Aa899454998Be5b000Ad077a46Bbe360F4e497);
    IFluidReserveContract internal constant RESERVE_CONTRACT =
        IFluidReserveContract(0x264786EF916af64a1DB19F513F24a3681734ce92);

    address internal constant REBALANCER1 = 0x3BE5C671b20649DCA5D916b5698328D54BdAAf88;
    address internal constant REBALANCER2 = 0xb287f8A01a9538656c72Fa6aE1EE0117A187Be0C;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address bob = makeAddr("bob");

    FluidCollectRevenueAuth handler;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(20290539);

        _deployNewHandler();
    }

    function test_deployment() public {
        assertEq(address(handler.LIQUIDITY()), address(LIQUIDITY));
        assertEq(address(handler.RESERVE_CONTRACT()), address(RESERVE_CONTRACT));
    }

    function _deployNewHandler() internal {
        // constructor params
        // IFluidReserveContract reserveContract_,
        // IFluidLiquidity liquidity_,
        handler = new FluidCollectRevenueAuth(
            address(LIQUIDITY),
            address(RESERVE_CONTRACT)
        );

        // authorize handler at liquidity
        AdminModuleStructs.AddressBool[] memory updateAuthsParams = new AdminModuleStructs.AddressBool[](1);
        updateAuthsParams[0] = AdminModuleStructs.AddressBool(address(handler), true);

        vm.prank(GOVERNANCE);
        LIQUIDITY.updateAuths(updateAuthsParams);
    }

    function test_deploymentRevertWhenZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.CollectRevenueAuth__InvalidParams)
        );
        new FluidCollectRevenueAuth(address(0), address(RESERVE_CONTRACT));

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.CollectRevenueAuth__InvalidParams)
        );
        new FluidCollectRevenueAuth(address(LIQUIDITY), address(0));
    }

    function test_collectRevenue_revertWhenUnauthorized() public {
        address[] memory tokens = new address[](1);
        tokens[0] = ETH;

        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.CollectRevenueAuth__Unauthorized)
        );
        handler.collectRevenue(tokens);
    }


    function test_collectRevenue() public {
        address[] memory tokens = new address[](1);
        tokens[0] = ETH;

        vm.prank(REBALANCER1);
        handler.collectRevenue(tokens);

        vm.prank(REBALANCER2);
        handler.collectRevenue(tokens);

        tokens[0] = WSTETH;
        vm.prank(handler.TEAM_MULTISIG());
        handler.collectRevenue(tokens);
    }
}
