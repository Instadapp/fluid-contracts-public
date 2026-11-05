// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { Structs as CLXStructs } from "../../../contracts/oracleV2/stocks/clxStockOracle/structs.sol";
import { Structs } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/structs.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

/// @dev Minimal AggregatorV3 for fork reads.
interface IAggregatorV3Minimal {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @dev ERC-4626-style Backed wrapper surface used by CLX.
interface IBackedWrapperMinimal {
    function convertToAssets(uint256 shares) external view returns (uint256);

    function asset() external view returns (address);

    function symbol() external view returns (string memory);
}

/**
 * @title FluidCLXStockOracleForkTest
 * @notice Layer B — mainnet fork against real Chainlink AggregatorV3 + Backed wrapper.
 *
 * Defaults (SPY / wSPYx on Ethereum mainnet):
 * - Chainlink `SPY-USD (24/5)` AggregatorV3 proxy: `0x25efbA0d9b115D233cfA849F16BA743E8FFba2a1`
 * - Backed `wSPYx` wrapper V2 (`convertToAssets`): `0xe7e553cd128f0011777323a0b44a7b96ea1cb540`
 *   (underlying SPYx `asset()` = `0x90A2a4c76b5D8c0bc892A69EA28Aa775a8f2dD48`; the v1 legacy wrapper
 *   `0xc88F…4c02` is not a multiplier passthrough and is rejected by the constructor)
 *
 * Env (optional overrides):
 * - `MAINNET_RPC_URL` or `MAINNET_RPC` (falls back to publicnode)
 * - `CLX_CHAINLINK_FEED`, `CLX_BACKED_WRAPPER`
 * - `CLX_FORK_BLOCK` to pin the fork
 */
contract FluidCLXStockOracleForkTest is Test {
    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @dev https://data.chain.link/feeds/ethereum/mainnet/spy-usd-kalman-24-5
    address constant DEFAULT_SPY_FEED = 0x25efbA0d9b115D233cfA849F16BA743E8FFba2a1;
    /// @dev Current Wrapped SP500 xStock (wSPYx) V2 on Ethereum.
    address constant DEFAULT_WSPYX_WRAPPER = 0xE7E553Cd128F0011777323A0b44a7b96EA1CB540;
    address constant SPYX_UNDERLYING = 0x90A2a4c76b5D8c0bc892A69EA28Aa775a8f2dD48;

    FluidUsEquityMarketHours marketHours;
    FluidCLXStockOracle oracle;
    address feed;
    address wrapper;

    function setUp() public {
        string memory rpc_ = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc_).length == 0) {
            rpc_ = vm.envOr("MAINNET_RPC", string(""));
        }
        if (bytes(rpc_).length == 0) {
            rpc_ = "https://ethereum-rpc.publicnode.com";
        }

        if (vm.envExists("CLX_FORK_BLOCK")) {
            vm.createSelectFork(rpc_, vm.envUint("CLX_FORK_BLOCK"));
        } else {
            vm.createSelectFork(rpc_);
        }

        feed = vm.envOr("CLX_CHAINLINK_FEED", DEFAULT_SPY_FEED);
        wrapper = vm.envOr("CLX_BACKED_WRAPPER", DEFAULT_WSPYX_WRAPPER);

        // Smoke: AggregatorV3 + convertToAssets must work.
        require(IAggregatorV3Minimal(feed).decimals() == 8, "unexpected feed decimals");
        (, int256 answer_, , uint256 updatedAt_, ) = IAggregatorV3Minimal(feed).latestRoundData();
        require(answer_ > 0 && updatedAt_ > 0, "bad feed latest");
        require(IBackedWrapperMinimal(wrapper).convertToAssets(1e18) > 0, "bad wrapper");
        require(IBackedWrapperMinimal(wrapper).asset() == SPYX_UNDERLYING, "wrapper asset != SPYx");

        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(GOVERNANCE)))
        );

        FluidUsEquityMarketHours impl_ = new FluidUsEquityMarketHours(LIQUIDITY);
        FluidUsEquityMarketHoursProxy proxy_ = new FluidUsEquityMarketHoursProxy(
            address(impl_),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        marketHours = FluidUsEquityMarketHours(address(proxy_));
        vm.prank(GOVERNANCE);
        marketHours.updateAuth(AUTH, 2); // harness writes unrelated weeks out of order

        // Schedule covering fork tip (calendar lib span 2025–2026).
        uint32 tip_ = uint32(block.timestamp);
        Cal.Date memory d_ = Cal.dateFromTimestamp(tip_);
        if (d_.year < 2025 || d_.year > 2026) {
            vm.skip(true);
        }

        // Writing needs an instant the schedule covers; the tip is restored right after.
        (Structs.Session[] memory sessions_, uint32 writeAt_) = Cal.scheduleForTip(tip_);
        vm.warp(writeAt_);
        vm.prank(AUTH);
        marketHours.updateWeekSessions(sessions_);
        vm.warp(tip_);

        uint8 decimals_ = IAggregatorV3Minimal(feed).decimals();
        uint256 rateMultiplier_ = 10 ** (27 - uint256(decimals_));

        oracle = new FluidCLXStockOracle(
            CLXStructs.CLXStockOracleConstructorParams({
                infoName: "wSPYx / USD fork",
                targetDecimals: 27,
                liquidity: LIQUIDITY,
                chainlinkFeed: feed,
                backedWrapper: wrapper,
                marketHours: address(marketHours),
                rateMultiplier: rateMultiplier_,
                maxMultiplierChangePercent: 100,
                maxExtendedHoursCapPercent: 10e4,
                maxPriceGapDownPercent: 4200,
                maxPriceGapUpPercent: 6800
            })
        );
    }

    function test_Fork_SpyFeedAndWrapperIdentity() public view {
        assertEq(IAggregatorV3Minimal(feed).description(), "SPY-USD (24/5)");
        assertEq(IBackedWrapperMinimal(wrapper).symbol(), "wSPYx");
        assertEq(IBackedWrapperMinimal(wrapper).asset(), SPYX_UNDERLYING);
    }

    function test_Fork_LatestRoundReadableAndPositive() public view {
        (uint80 roundId_, int256 answer_, , uint256 updatedAt_, ) = IAggregatorV3Minimal(feed).latestRoundData();
        assertGt(roundId_, 0);
        assertGt(answer_, 0);
        assertGt(updatedAt_, 0);
        assertGt(IBackedWrapperMinimal(wrapper).convertToAssets(1e18), 0);
    }

    function test_Fork_OperateAndLiquidateReturnPositive() public {
        try oracle.updateRegularHoursAnchor(0) {} catch {}

        uint256 op_ = oracle.getExchangeRateOperate();
        uint256 liq_ = oracle.getExchangeRateLiquidate();
        assertGt(op_, 0);
        assertGt(liq_, 0);
        assertGt(oracle.getExchangeRateOperateDebt(), 0);
        assertGt(oracle.getExchangeRateLiquidateDebt(), 0);
    }

    function test_Fork_WalkBackHistoryDoesNotRevertBlindly() public {
        (uint80 latest_, , , , ) = IAggregatorV3Minimal(feed).latestRoundData();
        uint80 cursor_ = latest_;
        uint256 okCount_;
        for (uint256 i_; i_ < 20 && cursor_ > 0; ++i_) {
            try IAggregatorV3Minimal(feed).getRoundData(cursor_) returns (
                uint80,
                int256 answer_,
                uint256,
                uint256 updatedAt_,
                uint80
            ) {
                if (answer_ > 0 && updatedAt_ > 0) ++okCount_;
            } catch {}
            unchecked {
                --cursor_;
            }
        }
        assertGt(okCount_, 0, "expected at least one readable historical round");
    }

    function test_Fork_RawMatchesLiveScaleWhenRegular() public {
        (uint256 sessionType_, , ) = marketHours.getCurrentSession();
        if (sessionType_ != 1) return;

        (, int256 answer_, , , ) = IAggregatorV3Minimal(feed).latestRoundData();
        uint256 mult_ = IBackedWrapperMinimal(wrapper).convertToAssets(1e18);
        uint8 decimals_ = IAggregatorV3Minimal(feed).decimals();
        uint256 rateMultiplier_ = 10 ** (27 - uint256(decimals_));
        uint256 expected_ = (uint256(answer_) * mult_ * rateMultiplier_) / 1e18;
        assertEq(oracle.getExchangeRateOperate(), expected_);
        assertEq(oracle.getExchangeRateOperateRaw(), expected_);
    }
}
