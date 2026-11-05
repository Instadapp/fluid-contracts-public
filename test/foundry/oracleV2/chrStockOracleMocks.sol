// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Chronicle router stub. `setRevert` models a caller without a toll.
contract MockChronicle {
    bool public ok;
    uint256 public value;
    uint256 public age;
    bool public revertMode;

    function set(bool ok_, uint256 value_, uint256 age_) external {
        ok = ok_;
        value = value_;
        age = age_;
    }

    function setRevert(bool revert_) external {
        revertMode = revert_;
    }

    function tryReadWithAge() external view returns (bool, uint256, uint256) {
        if (revertMode) revert("chronicle: not tolled");
        return (ok, value, age);
    }
}

/// @notice Reality rtoken stub (ERC-8056 surface used by the oracle).
contract MockRealityToken {
    uint256 internal _uiMultiplier = 1e18;
    bool internal _paused;
    bool internal _isDelisted;
    bool internal _revertAll;
    bool internal _shortReturn;

    function setUIMultiplier(uint256 value_) external {
        _uiMultiplier = value_;
    }

    function setPaused(bool value_) external {
        _paused = value_;
    }

    function setDelisted(bool value_) external {
        _isDelisted = value_;
    }

    /// @dev Every getter reverts.
    function setRevertAll(bool value_) external {
        _revertAll = value_;
    }

    /// @dev Every getter returns empty returndata.
    function setShortReturn(bool value_) external {
        _shortReturn = value_;
    }

    modifier getter() {
        if (_revertAll) revert("rtoken: revert");
        if (_shortReturn) {
            assembly {
                return(0, 0)
            }
        }
        _;
    }

    function uiMultiplier() external view getter returns (uint256) {
        return _uiMultiplier;
    }

    function paused() external view getter returns (bool) {
        return _paused;
    }

    function isDelisted() external view getter returns (bool) {
        return _isDelisted;
    }
}

/// @notice Reality primary-market trade stub: `tradePaused` per rtoken.
contract MockRealityTokenTrade {
    mapping(address => bool) internal _tradePaused;
    bool internal _revertMode;

    function setTradePaused(address token_, bool value_) external {
        _tradePaused[token_] = value_;
    }

    function setRevert(bool revert_) external {
        _revertMode = revert_;
    }

    function tradePaused(address token_) external view returns (bool) {
        if (_revertMode) revert("trade: revert");
        return _tradePaused[token_];
    }
}

/// @notice AuthGate stub. Level 1 = MID, level 2 = HIGH (passes MID too). Anything else reverts.
contract MockAuthGate {
    error Access__Unauthorized();

    address internal _liquidity = address(0xBEEF1);
    mapping(address => uint8) internal _level;

    function setLiquidity(address value_) external {
        _liquidity = value_;
    }

    function setLevel(address who_, uint8 level_) external {
        _level[who_] = level_;
    }

    function LIQUIDITY() external view returns (address) {
        return _liquidity;
    }

    function requireAuthLevelMid(address addr_) external view {
        if (_level[addr_] < 1) revert Access__Unauthorized();
    }

    function requireAuthLevelHigh(address addr_) external view {
        if (_level[addr_] < 2) revert Access__Unauthorized();
    }
}

contract SequencerUptimeFeedMock {
    struct RoundData {
        int256 answer;
        uint256 startedAt;
    }

    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRoundId;

    function setRound(uint80 roundId_, int256 answer_, uint256 startedAt_) external {
        rounds[roundId_] = RoundData(answer_, startedAt_);
        if (roundId_ > latestRoundId) {
            latestRoundId = roundId_;
        }
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[latestRoundId];
        return (latestRoundId, r.answer, r.startedAt, block.timestamp, latestRoundId);
    }

    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory r = rounds[roundId_];
        return (roundId_, r.answer, r.startedAt, r.startedAt, roundId_);
    }
}
