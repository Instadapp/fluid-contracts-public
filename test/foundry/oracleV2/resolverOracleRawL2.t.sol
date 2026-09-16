// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { IFluidOracle } from "../../../contracts/oracleV2/interfaces/iFluidOracle.sol";
import { FluidUsdOracle } from "../../../contracts/oracleV2/usdOracle/main.sol";
import { VaultT1Oracle } from "../../../contracts/oracleV2/vaultOracle/vaultTypes/vaultT1Oracle.sol";
import { Error } from "../../../contracts/oracleV2/usdOracle/error.sol";
import { ErrorTypes as UsdOracleErrorTypes } from "../../../contracts/oracleV2/usdOracle/errorTypes.sol";
import { UsdOracleForkTestBase } from "./usdOracleForkTestBase.sol";
import { IChainlinkAggregatorV3, MockChainlinkFeed, MockReadFromStorage } from "./usdOracleForkTestBase.sol";
import { MockSequencerUptimeFeed, FluidUsdOracleL2Harness } from "./usdOracleL2.t.sol";

/// @dev Mirrors `ResolverHelpers._fetchOraclePrices` for oracleV2 contracts in this test module.
library ResolverOraclePriceFetch {
    function fetch(address oracle_) internal view returns (uint256 operate_, uint256 liquidate_) {
        if (oracle_ == address(0)) {
            return (0, 0);
        }

        try IFluidOracle(oracle_).getExchangeRateOperate() returns (uint256 exchangeRate_) {
            operate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidate() returns (uint256 liquidateRate_) {
                liquidate_ = liquidateRate_;
            } catch {
                liquidate_ = exchangeRate_;
            }
            return (operate_, liquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRateOperateRaw() returns (uint256 exchangeRate_) {
            operate_ = exchangeRate_;
            try IFluidOracle(oracle_).getExchangeRateLiquidateRaw() returns (uint256 liquidateRate_) {
                liquidate_ = liquidateRate_;
            } catch {
                liquidate_ = exchangeRate_;
            }
            return (operate_, liquidate_);
        } catch {}

        try IFluidOracle(oracle_).getExchangeRate() returns (uint256 exchangeRate_) {
            return (exchangeRate_, exchangeRate_);
        } catch {}

        return (0, 0);
    }
}

/// @dev Vault T1 oracle + USD oracle L2 + capped-rate L2: guarded paths revert, raw + resolver fetch succeed.
contract ResolverOracleRawL2Test is UsdOracleForkTestBase {
    FluidUsdOracleL2Harness internal usdOracleL2;
    MockSequencerUptimeFeed internal sequencerFeed;
    VaultT1Oracle internal vaultOracle;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IChainlinkAggregatorV3 internal constant CHAINLINK_ETH_USD =
        IChainlinkAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.rollFork(21148750);

        admin = makeAddr("admin");
        liquidityMock = new MockReadFromStorage();
        liquidityMock.setStorage(
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103,
            uint256(uint160(admin))
        );

        sequencerFeed = new MockSequencerUptimeFeed();
        sequencerFeed.setRound(1, 0, block.timestamp - 2 hours);

        usdOracleL2 = new FluidUsdOracleL2Harness(address(liquidityMock), address(sequencerFeed));
        usdOracle = FluidUsdOracle(address(usdOracleL2));

        clOracle = new MockChainlinkFeed(IChainlinkAggregatorV3(address(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4)));

        vm.startPrank(admin);
        usdOracle.setTokenType(USDC, 2);
        usdOracle.setTokenType(WETH, 3);
        vm.stopPrank();

        _setupUsdcAndWethConfigs();

        vaultOracle = new VaultT1Oracle(address(usdOracleL2), WETH, USDC, 0, 0);
    }

    function _setupUsdcAndWethConfigs() internal {
        SourceConfig memory usdcSource_ = SourceConfig({ sourceType: 2, source: address(clOracle), capOperand: 0 });
        _registerAndSetConfig(admin, USDC, 0, 1, 1, usdcSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 1, 0, usdcSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 1, usdcSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, USDC, 0, 0, 0, usdcSource_, _emptyCfg(), _emptyCfg());

        MockChainlinkFeed wethCl_ = new MockChainlinkFeed(CHAINLINK_ETH_USD);
        SourceConfig memory wethSource_ = SourceConfig({ sourceType: 2, source: address(wethCl_), capOperand: 0 });
        _registerAndSetConfig(admin, WETH, 0, 1, 1, wethSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, WETH, 0, 1, 0, wethSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, WETH, 0, 0, 1, wethSource_, _emptyCfg(), _emptyCfg());
        _registerAndSetConfig(admin, WETH, 0, 0, 0, wethSource_, _emptyCfg(), _emptyCfg());
    }

    function _setupGracePeriodScenario() internal {
        sequencerFeed.setRound(1, 0, block.timestamp - 1 hours);
        sequencerFeed.setRound(2, 1, block.timestamp - 10 minutes);
        sequencerFeed.setRound(3, 0, block.timestamp - 1 minutes);
    }

    function test_vaultT1Oracle_guardedReverts_rawSucceeds_withinGracePeriod() public {
        _setupGracePeriodScenario();

        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidUsdOracleError.selector,
                UsdOracleErrorTypes.UsdOracle__SequencerGracePeriod
            )
        );
        vaultOracle.getExchangeRateOperate();

        uint256 rawOperate_ = vaultOracle.getExchangeRateOperateRaw();
        uint256 rawLiquidate_ = vaultOracle.getExchangeRateLiquidateRaw();
        assertGt(rawOperate_, 0);
        assertGt(rawLiquidate_, 0);
    }

    function test_vaultT1Oracle_guardedReverts_rawSucceeds_whileSequencerDown() public {
        sequencerFeed.setRound(2, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(Error.FluidUsdOracleError.selector, UsdOracleErrorTypes.UsdOracle__SequencerDown)
        );
        vaultOracle.getExchangeRateOperate();

        uint256 rawOperate_ = vaultOracle.getExchangeRateOperateRaw();
        assertGt(rawOperate_, 0);
    }

    function test_resolverFetch_vaultOracle_doesNotRevert_duringGracePeriod() public {
        _setupGracePeriodScenario();

        (uint256 operate_, uint256 liquidate_) = ResolverOraclePriceFetch.fetch(address(vaultOracle));
        assertGt(operate_, 0, "resolver fetch must return operate price during L2 grace");
        assertGt(liquidate_, 0, "resolver fetch must return liquidate price during L2 grace");
    }

    function test_resolverFetch_vaultOracle_doesNotRevert_whileSequencerDown() public {
        sequencerFeed.setRound(2, 1, block.timestamp);

        (uint256 operate_, uint256 liquidate_) = ResolverOraclePriceFetch.fetch(address(vaultOracle));
        assertGt(operate_, 0);
        assertGt(liquidate_, 0);
    }
}
