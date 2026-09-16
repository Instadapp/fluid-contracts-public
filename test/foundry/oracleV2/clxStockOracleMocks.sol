// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";

import { FluidUsEquityMarketHours } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/main.sol";
import { FluidUsEquityMarketHoursProxy } from "../../../contracts/oracleV2/stocks/usEquityMarketHours/proxy.sol";
import { FluidCLXStockOracle } from "../../../contracts/oracleV2/stocks/clxStockOracle/main.sol";
import { Structs as CLXStructs } from "../../../contracts/oracleV2/stocks/clxStockOracle/structs.sol";
import { ErrorTypes } from "../../../contracts/oracleV2/stocks/errorTypes.sol";
import { Error } from "../../../contracts/oracleV2/stocks/error.sol";
import { LiquidityGovernanceAuth, IFluidLiquidityGovernance } from "../../../contracts/libraries/access/liquidityGovernanceAuth.sol";
import { BasicUpgradeable } from "../../../contracts/libraries/access/basicUpgradeable.sol";
import { UsEquityMarketHoursCalendarLib as Cal } from "./UsEquityMarketHoursCalendarLib.sol";

contract MockChainlinkFeed {
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint80 public latestRoundId;
    mapping(uint80 => Round) internal _rounds;
    mapping(uint80 => bool) public revertRound;
    /// @dev When set, `getRoundData` returns success with answer=0 / updatedAt=0 (mainnet CL post-tip quirk).
    mapping(uint80 => bool) public phantomRound;
    uint8 public decimals_ = 8;
    bool public revertLatest;

    function pushRound(int256 answer_, uint256 updatedAt_) external {
        ++latestRoundId;
        _rounds[latestRoundId] = Round({ answer: answer_, updatedAt: updatedAt_ });
    }

    function setLatest(int256 answer_, uint256 updatedAt_) external {
        if (latestRoundId == 0) {
            latestRoundId = 1;
        }
        _rounds[latestRoundId] = Round({ answer: answer_, updatedAt: updatedAt_ });
    }

    function setRevertLatest(bool revert_) external {
        revertLatest = revert_;
    }

    function setRevertRound(uint80 roundId_, bool revert_) external {
        revertRound[roundId_] = revert_;
    }

    function setPhantomRound(uint80 roundId_, bool phantom_) external {
        phantomRound[roundId_] = phantom_;
    }

    /// @dev Mark `count_` ids after `latestRoundId` as successful empty rounds (no tip advance).
    function setPhantomRoundsAfterLatest(uint256 count_) external {
        for (uint256 i_ = 1; i_ <= count_; ++i_) {
            phantomRound[latestRoundId + uint80(i_)] = true;
        }
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (revertLatest) revert("latest revert");
        Round memory r_ = _rounds[latestRoundId];
        return (latestRoundId, r_.answer, 0, r_.updatedAt, latestRoundId);
    }

    function getRoundData(uint80 roundId_) external view returns (uint80, int256, uint256, uint256, uint80) {
        if (revertRound[roundId_]) revert("round revert");
        if (phantomRound[roundId_]) return (roundId_, 0, 0, 0, roundId_);
        Round memory r_ = _rounds[roundId_];
        require(r_.updatedAt != 0 || r_.answer != 0, "no round");
        return (roundId_, r_.answer, 0, r_.updatedAt, roundId_);
    }
}

contract MockBackedAutoFeeToken {
    uint256 public lastMultiplier = 1e18;
    uint256 public newMultiplier = 1e18;
    uint256 public newMultiplierActivationTime;

    function setMultiplier(uint256 multiplier_) external {
        lastMultiplier = multiplier_;
        newMultiplier = multiplier_;
        newMultiplierActivationTime = 0;
    }

    function getCurrentMultiplier() external view returns (uint256, uint256, uint256) {
        if (block.timestamp < newMultiplierActivationTime) return (lastMultiplier, 0, 0);
        return (newMultiplier, 0, 0);
    }
}

contract MockBackedWrapper {
    MockBackedAutoFeeToken public immutable token;

    constructor(MockBackedAutoFeeToken token_) {
        token = token_;
    }

    function convertToAssets(uint256 shares_) external view returns (uint256) {
        (uint256 multiplier_, , ) = token.getCurrentMultiplier();
        return (shares_ * multiplier_) / 1e18;
    }

    function asset() external view returns (address) {
        return address(token);
    }
}

abstract contract CLXStockOracleTestBase is Test {
    using Cal for *;

    FluidUsEquityMarketHours marketHours;
    MockChainlinkFeed feed;
    MockBackedAutoFeeToken token;
    MockBackedWrapper wrapper;
    FluidCLXStockOracle oracle;

    address constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
    bytes32 constant GOVERNANCE_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address constant GOVERNANCE = address(0xA11CE);
    address constant AUTH = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;
    address constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    /// @dev Market hours auth classes: `1` writes the schedule, `2` may also rewrite pinned sessions.
    uint256 internal constant AUTH_CLASS_SCHEDULE = 1;
    uint256 internal constant AUTH_CLASS_SCHEDULE_OVERRIDE = 2;

    uint256 internal constant RATE_MULTIPLIER = 1e19;
    uint256 internal constant MAX_EXTENDED_CAP_PERCENT = 10e4;

    uint8 constant sessionTypeUnknown = 0;
    uint8 constant sessionTypeRegular = 1;
    uint8 constant sessionTypeExtended = 2;
    uint8 constant sessionTypeHoliday = 3;

    function _mockGovernance(address gov_) internal {
        vm.mockCall(
            LIQUIDITY,
            abi.encodeWithSelector(IFluidLiquidityGovernance.readFromStorage.selector, GOVERNANCE_SLOT),
            abi.encode(uint256(uint160(gov_)))
        );
    }

    function _deployMarketHours() internal returns (FluidUsEquityMarketHours) {
        FluidUsEquityMarketHours impl_ = new FluidUsEquityMarketHours(LIQUIDITY);
        FluidUsEquityMarketHoursProxy proxy_ = new FluidUsEquityMarketHoursProxy(
            address(impl_),
            abi.encodeCall(BasicUpgradeable.initialize, ())
        );
        return FluidUsEquityMarketHours(address(proxy_));
    }

    function _deployOracleDefault() internal returns (FluidCLXStockOracle) {
        return
            new FluidCLXStockOracle(
                CLXStructs.CLXStockOracleConstructorParams({
                    infoName: "wSPYx / USD",
                    targetDecimals: 27,
                    liquidity: LIQUIDITY,
                    chainlinkFeed: address(feed),
                    backedWrapper: address(wrapper),
                    marketHours: address(marketHours),
                    rateMultiplier: RATE_MULTIPLIER,
                    maxMultiplierChangePercent: 100,
                    maxExtendedHoursCapPercent: MAX_EXTENDED_CAP_PERCENT,
                    maxPriceGapDownPercent: 9999, // non-binding: these suites exercise session/clamp mechanics
                    maxPriceGapUpPercent: 1e8
                })
            );
    }

    function _scaledPrice(uint256 clAnswer_, uint256 multiplier_) internal pure returns (uint256) {
        return (clAnswer_ * multiplier_ * RATE_MULTIPLIER) / 1e18;
    }

    function _clampUp(uint256 live_, uint256 anchor_, uint256 capPercent_) internal pure returns (uint256) {
        uint256 delta_ = (anchor_ * capPercent_) / 1e6;
        uint256 cap_ = anchor_ + delta_;
        return live_ > cap_ ? cap_ : live_;
    }

    function _clampDown(uint256 live_, uint256 anchor_, uint256 capPercent_) internal pure returns (uint256) {
        uint256 delta_ = (anchor_ * capPercent_) / 1e6;
        if (delta_ > anchor_) return live_;
        uint256 floor_ = anchor_ - delta_;
        return live_ < floor_ ? floor_ : live_;
    }

    function _expectNotFound() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__RegularHoursReferenceNotFound
            )
        );
    }

    function _expectMultiplierNeedsConfirmation() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                Error.FluidStockOracleError.selector,
                ErrorTypes.CLXStockOracle__MultiplierNeedsConfirmation
            )
        );
    }

    function _sessionEnd(uint32 open_) internal pure returns (uint32) {
        Cal.Date memory d_ = Cal.dateFromTimestamp(open_);
        if (Cal.isEarlyClose(d_.year, d_.month, d_.day)) {
            return open_ + uint32(Cal.EARLY_CLOSE_MINUTES) * 60;
        }
        return open_ + uint32(Cal.REGULAR_MINUTES) * 60;
    }

    function _windowEnd(uint32 regularEnd_) internal pure returns (uint256) {
        return uint256(regularEnd_) + 15 minutes;
    }

    /// @dev Mirror oracle in-window RTH discovery from the mock feed tip.
    function _findAnchorClAnswer(
        MockChainlinkFeed feed_,
        uint32 regStart_,
        uint32 regEnd_
    ) internal view returns (int256 answer_) {
        if (regStart_ == 0) return 0;
        uint256 windowEnd_ = _windowEnd(regEnd_);
        uint80 id_ = feed_.latestRoundId();
        for (uint256 steps_; steps_ < 301 && id_ > 0; ++steps_) {
            (, int256 ans_, , uint256 at_, ) = feed_.getRoundData(id_);
            if (ans_ > 0 && at_ >= regStart_ && at_ <= windowEnd_) {
                return ans_;
            }
            unchecked {
                --id_;
            }
        }
        return 0;
    }
}
