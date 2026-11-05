// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { FluidDexReservesResolver } from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";
import { PriceDiffCheckExposed } from "../../dex/poolT1/priceDiffCheck.t.sol";

import "../../testERC20.sol";

/// @dev Exposes the resolver's internal price-band gate so tests can drive it with exact ratios.
contract ExposedDexReservesResolver is FluidDexReservesResolver {
    constructor() FluidDexReservesResolver(address(1), address(2), address(3)) {}

    function exposed_priceMoveExceedsLimit(
        address dex_,
        uint256 oldPrice_,
        uint256 newPrice_
    ) external view returns (bool) {
        return _priceMoveExceedsLimit(dex_, oldPrice_, newPrice_);
    }

    function exposed_oracleLimit() external pure returns (uint256) {
        return ORACLE_LIMIT;
    }
}

contract VersionedDexMock {
    string public constant VERSION = "1.1.0";
}

/// @dev Like a deployed pool: no `VERSION`, so calling it reverts.
contract UnversionedDexMock {

}

contract DexReservesResolverPriceBandTest is Test {
    ExposedDexReservesResolver internal resolver;
    PriceDiffCheckExposed internal poolCheck;
    address internal versionedDex;
    address internal unversionedDex;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant LIMIT = 5e16; // 5%
    uint256 internal constant OLD_PRICE = 1e18;

    function setUp() public {
        resolver = new ExposedDexReservesResolver();
        assertEq(resolver.exposed_oracleLimit(), LIMIT, "ORACLE_LIMIT drifted from the value this suite assumes");

        poolCheck = new PriceDiffCheckExposed(
            address(new TestERC20("TokenA", "TKA")),
            address(new TestERC20("TokenB", "TKB"))
        );
        versionedDex = address(new VersionedDexMock());
        unversionedDex = address(new UnversionedDexMock());
    }

    function _rejects(address dex_, uint256 newPricePerMille_) internal view returns (bool) {
        return resolver.exposed_priceMoveExceedsLimit(dex_, OLD_PRICE, (OLD_PRICE * newPricePerMille_) / 1000);
    }

    // ------------------------------------------------------------------
    // Pools with VERSION: [0.95, 1.05] x oldPrice.
    // ------------------------------------------------------------------

    function test_priceMoveExceedsLimit_VersionedPool_AcceptsDrop4Point9Percent() public {
        // 0.951 < 1/1.05 (~0.952381): only an unversioned pool rejects this.
        assertFalse(_rejects(versionedDex, 951));
    }

    function test_priceMoveExceedsLimit_VersionedPool_RejectsDrop5Point1Percent() public {
        assertTrue(_rejects(versionedDex, 949));
    }

    function test_priceMoveExceedsLimit_VersionedPool_AcceptsRise4Point9Percent() public {
        assertFalse(_rejects(versionedDex, 1049));
    }

    function test_priceMoveExceedsLimit_VersionedPool_RejectsRise5Point1Percent() public {
        assertTrue(_rejects(versionedDex, 1051));
    }

    function test_priceMoveExceedsLimit_VersionedPool_Boundaries() public {
        uint256 upper_ = (OLD_PRICE * (PRECISION + LIMIT)) / PRECISION;
        uint256 lower_ = (OLD_PRICE * (PRECISION - LIMIT)) / PRECISION;

        assertFalse(resolver.exposed_priceMoveExceedsLimit(versionedDex, OLD_PRICE, upper_));
        assertTrue(resolver.exposed_priceMoveExceedsLimit(versionedDex, OLD_PRICE, upper_ + 1));
        assertFalse(resolver.exposed_priceMoveExceedsLimit(versionedDex, OLD_PRICE, lower_));
        assertTrue(resolver.exposed_priceMoveExceedsLimit(versionedDex, OLD_PRICE, lower_ - 1));
    }

    // ------------------------------------------------------------------
    // Pools without VERSION: old / new in [0.95, 1.05], i.e. newPrice in [1/1.05, 1/0.95] x oldPrice.
    // ------------------------------------------------------------------

    function test_priceMoveExceedsLimit_UnversionedPool_AcceptsDrop4Point7Percent() public {
        assertFalse(_rejects(unversionedDex, 953));
    }

    function test_priceMoveExceedsLimit_UnversionedPool_RejectsDrop4Point9Percent() public {
        assertTrue(_rejects(unversionedDex, 951));
    }

    function test_priceMoveExceedsLimit_UnversionedPool_AcceptsRise5Point2Percent() public {
        // 1.052 < 1/0.95 (~1.052632): only a versioned pool rejects this.
        assertFalse(_rejects(unversionedDex, 1052));
    }

    function test_priceMoveExceedsLimit_UnversionedPool_RejectsRise5Point3Percent() public {
        assertTrue(_rejects(unversionedDex, 1053));
    }

    function test_priceMoveExceedsLimit_UnversionedPool_RejectsZeroNewPrice() public {
        assertTrue(resolver.exposed_priceMoveExceedsLimit(unversionedDex, OLD_PRICE, 0));
    }

    function test_priceMoveExceedsLimit_AcceptsNoMove() public {
        assertFalse(resolver.exposed_priceMoveExceedsLimit(versionedDex, OLD_PRICE, OLD_PRICE));
        assertFalse(resolver.exposed_priceMoveExceedsLimit(unversionedDex, OLD_PRICE, OLD_PRICE));
    }

    // ------------------------------------------------------------------
    // Exact agreement with each pool's own check.
    // ------------------------------------------------------------------

    function _boundPrices(
        uint256 oldPriceRaw_,
        uint256 newPriceRaw_
    ) internal pure returns (uint256 oldPrice_, uint256 newPrice_) {
        oldPrice_ = bound(oldPriceRaw_, 1, 1e36);
        // around both bands' edges
        newPrice_ = bound(newPriceRaw_, (oldPrice_ * 94) / 100, (oldPrice_ * 106) / 100);
    }

    function test_fuzz_priceMoveExceedsLimit_MatchesVersionedPoolCheck(
        uint256 oldPriceRaw_,
        uint256 newPriceRaw_
    ) public {
        (uint256 oldPrice_, uint256 newPrice_) = _boundPrices(oldPriceRaw_, newPriceRaw_);

        bool poolRejects_;
        try poolCheck.priceDiffCheck(oldPrice_, newPrice_) {} catch {
            poolRejects_ = true;
        }

        assertEq(resolver.exposed_priceMoveExceedsLimit(versionedDex, oldPrice_, newPrice_), poolRejects_);
    }

    /// @dev Copy of the deployed pools' check, whose code is no longer in this repo.
    function _unversionedPoolRejects(uint256 oldPrice_, uint256 newPrice_) internal pure returns (bool) {
        if (newPrice_ == 0) {
            return true;
        }
        unchecked {
            int256 priceDiff_ = int256(PRECISION) - int256((oldPrice_ * PRECISION) / newPrice_);
            return priceDiff_ > int256(LIMIT) || priceDiff_ < -int256(LIMIT);
        }
    }

    function test_fuzz_priceMoveExceedsLimit_MatchesUnversionedPoolCheck(
        uint256 oldPriceRaw_,
        uint256 newPriceRaw_
    ) public {
        (uint256 oldPrice_, uint256 newPrice_) = _boundPrices(oldPriceRaw_, newPriceRaw_);

        assertEq(
            resolver.exposed_priceMoveExceedsLimit(unversionedDex, oldPrice_, newPrice_),
            _unversionedPoolRejects(oldPrice_, newPrice_)
        );
    }
}
