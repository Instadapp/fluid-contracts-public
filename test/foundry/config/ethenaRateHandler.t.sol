//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityUserModuleBaseTest } from "../liquidity/userModule/liquidityUserModuleBaseTest.t.sol";
import { Structs as ResolverStructs } from "../../../contracts/periphery/resolvers/liquidity/structs.sol";
import { FluidEthenaRateConfigHandler } from "../../../contracts/config/ethenaRateHandler/main.sol";
import { Events } from "../../../contracts/config/ethenaRateHandler/events.sol";
import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { Error } from "../../../contracts/config/error.sol";
import { ErrorTypes } from "../../../contracts/config/errorTypes.sol";
import { FluidReserveContract } from "../../../contracts/reserve/main.sol";
import { FluidReserveContractProxy } from "../../../contracts/reserve/proxy.sol";
import { IFluidReserveContract } from "../../../contracts/reserve/interfaces/iReserveContract.sol";
import { IFluidLiquidity } from "../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "../../../contracts/liquidity/adminModule/structs.sol";
import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";
import { IStakedUSDe } from "../../../contracts/config/ethenaRateHandler/interfaces/iStakedUSDe.sol";
import { IFluidVaultT1 } from "../../../contracts/protocols/vault/interfaces/iVaultT1.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";
import { FluidVaultFactory } from "../../../contracts/protocols/vault/factory/main.sol";

import "forge-std/console2.sol";

contract FluidEthenaRateConfigHandlerTests is LiquidityUserModuleBaseTest, Events {
    FluidReserveContract reserveContractImpl;
    FluidReserveContract reserveContract; //proxy
    FluidEthenaRateConfigHandler configHandler;

    IStakedUSDe internal constant SUSDE_TOKEN = IStakedUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

    uint256 internal constant RATE_PERCENT_MARGIN = 1000; // 10%
    uint256 internal constant MAX_REWARDS_DELAY = 15 minutes;
    uint256 internal constant UTILIZATION_PENALTY_START = 9000; // 90%
    uint256 internal constant UTILIZATION100_PENALTY_PERCENT = 300; // 3%

    // use existing vault on fork for simplicity, doesn't matter which collateral token the vault has to check
    // for borrow rate magnifier being updated. e.g. ETH/USDC vault 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C
    address internal constant VAULT = 0xeAbBfca72F8a8bf14C4ac59e69ECB2eB69F0811C;

    address internal constant GOVERNANCE = 0x2386DC45AdDed673317eF068992F19421B481F4c;

    address internal constant VAULT_FACTORY = 0x324c5Dc1fC42c7a4D43d92df1eBA58a54d13Bf2d;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(19491337);

        super.setUp();

        // deploy reserve contract
        reserveContractImpl = new FluidReserveContract();
        reserveContract = FluidReserveContract(
            payable(new FluidReserveContractProxy(address(reserveContractImpl), new bytes(0)))
        );
        address[] memory authsRebalancers = new address[](1);
        authsRebalancers[0] = alice;
        reserveContract.initialize(authsRebalancers, authsRebalancers, admin);

        // deploy configHandler. constructor params:
        // constructor(
        //     IFluidReserveContract reserveContract_,
        //     IFluidLiquidity liquidity_,
        //     IFluidVaultT1 vault_,
        //     IStakedUSDe stakedUSDe_,
        //     address borrowToken_,
        //     uint256 ratePercentMargin_,
        //     uint256 maxRewardsDelay_,
        //     uint256 utilizationPenaltyStart_,
        //     uint256 utilization100PenaltyPercent_
        // )
        configHandler = new FluidEthenaRateConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidVaultT1(VAULT),
            IFluidVaultT1(address(0)),
            SUSDE_TOKEN,
            address(USDC),
            RATE_PERCENT_MARGIN,
            MAX_REWARDS_DELAY,
            UTILIZATION_PENALTY_START,
            UTILIZATION100_PENALTY_PERCENT
        );

        // make configHandler an auth at Vault
        vm.prank(GOVERNANCE);
        FluidVaultFactory(VAULT_FACTORY).setVaultAuth(VAULT, address(configHandler), true);
    }

    function test_currentMagnifier() public {
        assertEq(configHandler.currentMagnifier(), 1e4);
    }

    function test_getSUSDeYieldRate() public {
        // rate at given block should be
        // vestingAmount = 84310699350539958877622
        // totalAssets = 399083115635905571965778772
        // so 84310699350539958877622 / 399083115635905571965778772 = 0,00021126100315268389601938021 per 8 hours yield
        // so 0,00021126100315268389601938021 * 365 * 3 = 0,23133079845218886614122133035 yearly yield (23.13%)
        assertEq(SUSDE_TOKEN.vestingAmount(), 84310699350539958877622);
        assertEq(SUSDE_TOKEN.totalAssets(), 399083115635905571965778772);
        assertEq(configHandler.getSUSDeYieldRate(), 23133079845218885955);
    }

    function test_getSUSDeYieldRateWhenAboveMaxDelay() public {
        vm.warp(block.timestamp + 9 hours);

        assertEq(configHandler.getSUSDeYieldRate(), 0);
    }

    function test_rebalance() public {
        _simulateLiquidityUtilizationAndBorrowRate(5000, 1200);

        assertEq(configHandler.currentMagnifier(), 1e4);
        assertEq(configHandler.calculateMagnifier(), 17349);

        // check updates borrow rate magnifier as expected
        // check emits event
        vm.expectEmit(true, true, true, true);
        emit LogUpdateBorrowRateMagnifier(1e4, 17349);

        vm.prank(alice);
        configHandler.rebalance();

        assertEq(configHandler.currentMagnifier(), 17349);
    }

    function test_rebalance_RevertWhenNoUpdate() public {
        _simulateLiquidityUtilizationAndBorrowRate(5000, 1200);

        vm.prank(alice);
        configHandler.rebalance();

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.EthenaRateConfigHandler__NoUpdate)
        );
        vm.prank(alice);
        configHandler.rebalance();
    }

    function test_rebalance_RevertWhenUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidConfigError.selector, ErrorTypes.EthenaRateConfigHandler__Unauthorized)
        );
        vm.prank(bob);
        configHandler.rebalance();
    }

    function test_calculateMagnifier() public {
        // simulate sUSDe yield rate at 40%
        // _simulateSUSDeYieldRate(sUSDeYieldRate);

        // sUSDe yield rate is 23,133079845218885955%
        // uint256 sUSDeYieldRate = 23133079845218885955;

        uint256 borrowRate = 1200; // 12%

        // check at utilization 50%
        uint256 utilization = 5000;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        // expected borrow rate should be 23,133079845218885955% - 10% RATE_PERCENT_MARGIN
        // so 20,819771860696997359%. given current borrow rate is 12%, magnifier would have to be 1.7349809883914164466
        uint256 expectedMagnifier = 17349;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 90%
        utilization = 9000;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 17349;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 0%
        utilization = 0;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 17349;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 91%
        utilization = 9100;
        // penalty 10% of 3% so 0.3%
        // so expected borrow rate should be 23,133079845218885955% * 90.3% = 20.889171100232654017
        // given current borrow rate is 12%, magnifier would have to be 1.74076425835
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 17407;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 96%
        utilization = 9600;
        // penalty 60% of 3% so 1.8%
        // so expected borrow rate should be 23,133079845218885955% * 91.8% = 21.236167297910937307
        // given current borrow rate is 12%, magnifier would have to be 1.769680608159
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 17696;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 99%
        utilization = 9900;
        // penalty 90% of 3% so 2.7%
        // so expected borrow rate should be 23,133079845218885955% * 92.7% = 21.44436501651790728
        // given current borrow rate is 12%, magnifier would have to be 1.78703041804315894
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 17870;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 100%
        utilization = 10000;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        // expected borrow rate should be 23,133079845218885955% + penalty rate 3% (UTILIZATION100_PENALTY_PERCENT)
        // so 23,133079845218885955 * 93% -> 21.513764256053563938
        // given current borrow rate is 12%, magnifier would have to be 1.7928136880044636615
        expectedMagnifier = 17928;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check at utilization 110%
        utilization = 11000;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        // should be capped at same rate as for 100%
        expectedMagnifier = 17928;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check when borrow rate is 0%
        utilization = 5000;
        borrowRate = 0;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        expectedMagnifier = 1e4;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // check when liquidity borrow rate is above sUSDe yield target rate
        utilization = 5000;
        borrowRate = 4000;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        // magnifier should be 1, so even if sUSDe yield is below normal borrow rate the rate at Liquidity must always be paid
        expectedMagnifier = 1e4;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);

        // when magnifier would go above max value
        configHandler = new FluidEthenaRateConfigHandler(
            IFluidReserveContract(address(reserveContract)),
            IFluidLiquidity(address(liquidity)),
            IFluidVaultT1(address(mockProtocol)),
            IFluidVaultT1(address(0)),
            SUSDE_TOKEN,
            address(USDC),
            RATE_PERCENT_MARGIN,
            MAX_REWARDS_DELAY,
            UTILIZATION_PENALTY_START,
            80000 // set very high penalty of 800%
        );
        utilization = 9800;
        borrowRate = 1200;
        _simulateLiquidityUtilizationAndBorrowRate(utilization, borrowRate);
        // max magnifier ever set should be max possible value which is 65535
        expectedMagnifier = 65535;
        assertEq(configHandler.calculateMagnifier(), expectedMagnifier);
    }

    function _simulateLiquidityUtilizationAndBorrowRate(uint256 utilization, uint256 borrowRate) internal {
        uint256 exchangePricesAndConfig = resolver.getExchangePricesAndConfig(address(USDC));

        exchangePricesAndConfig =
            (exchangePricesAndConfig &
                // mask to update bits: 0-15 (borrow rate), 30-43 (utilization)
                0xfffffffffffffffffffffffffffffffffffffffffffffffffffff0003fff0000) |
            borrowRate | // borrow rate
            (utilization << LiquiditySlotsLink.BITS_EXCHANGE_PRICES_UTILIZATION);

        bytes32 slot = LiquiditySlotsLink.calculateMappingStorageSlot(
            LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT,
            address(USDC)
        );

        vm.store(address(liquidity), slot, bytes32(exchangePricesAndConfig));
    }
}
