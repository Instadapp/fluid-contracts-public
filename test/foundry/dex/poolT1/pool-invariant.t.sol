import "forge-std/Test.sol";
import { FluidDexReservesResolver } from "../../../../contracts/periphery/resolvers/dexReserves/main.sol";

contract PoolInvariantTest is Test {
    address private constant POOL_ADDRESS = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;
    FluidDexReservesResolver private constant DEX_RESERVES_RESOLVER =
        FluidDexReservesResolver(0xF38082d58bF0f1e07C04684FF718d69a70f21e62);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21579159);
    }

    function test_dexPool_invariantReservesIncrease() public {
        FluidDexReservesResolver.PoolWithReserves memory poolReserves;

        console.log("When rolling 1 blocks");
        // Roll 1 block for 10 times -> imaginary reserves can be slightly less
        for (uint256 i = 0; i < 10; i++) {
            vm.rollFork(block.number + 1);
            poolReserves = _updateAndAssertReserves(poolReserves, false);
        }

        console.log("When rolling 100 blocks");
        // Roll 100 blocks
        vm.rollFork(block.number + 100);
        poolReserves = _updateAndAssertReserves(poolReserves, true);

        console.log("When rolling 3 blocks");
        // Roll 3 blocks for 10 times -> imaginary should also always increase
        for (uint256 i = 0; i < 10; i++) {
            vm.rollFork(block.number + 3);
            poolReserves = _updateAndAssertReserves(poolReserves, true);
        }
    }

    function _updateAndAssertReserves(
        FluidDexReservesResolver.PoolWithReserves memory poolReserves,
        bool assertTmmaginaryIncrease
    ) internal returns (FluidDexReservesResolver.PoolWithReserves memory) {
        FluidDexReservesResolver.PoolWithReserves memory newPoolReserves = DEX_RESERVES_RESOLVER.getPoolReserves(
            POOL_ADDRESS
        );
        _compareAndAssertReserves(poolReserves, newPoolReserves, assertTmmaginaryIncrease);
        return newPoolReserves;
    }

    function _compareAndAssertReserves(
        FluidDexReservesResolver.PoolWithReserves memory oldReserves,
        FluidDexReservesResolver.PoolWithReserves memory newReserves,
        bool assertTmmaginaryIncrease
    ) internal {
        bool testFails;

        if (oldReserves.collateralReserves.token0RealReserves > newReserves.collateralReserves.token0RealReserves) {
            console.log(block.number);
            console.log(oldReserves.collateralReserves.token0RealReserves);
            console.log(newReserves.collateralReserves.token0RealReserves);
            console.log("collateralReserves.token0RealReserves new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (oldReserves.collateralReserves.token1RealReserves > newReserves.collateralReserves.token1RealReserves) {
            console.log(block.number);
            console.log(oldReserves.collateralReserves.token1RealReserves);
            console.log(newReserves.collateralReserves.token1RealReserves);
            console.log("collateralReserves.token1RealReserves new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (oldReserves.debtReserves.token0Debt > newReserves.debtReserves.token0Debt) {
            console.log(block.number);
            console.log(oldReserves.debtReserves.token0Debt);
            console.log(newReserves.debtReserves.token0Debt);
            console.log("debtReserves.token0Debt new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (oldReserves.debtReserves.token1Debt > newReserves.debtReserves.token1Debt) {
            console.log(block.number);
            console.log(oldReserves.debtReserves.token1Debt);
            console.log(newReserves.debtReserves.token1Debt);
            console.log("debtReserves.token1Debt new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (oldReserves.debtReserves.token0RealReserves > newReserves.debtReserves.token0RealReserves) {
            console.log(block.number);
            console.log(oldReserves.debtReserves.token0RealReserves);
            console.log(newReserves.debtReserves.token0RealReserves);
            console.log("debtReserves.token0RealReserves new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (oldReserves.debtReserves.token1RealReserves > newReserves.debtReserves.token1RealReserves) {
            console.log(block.number);
            console.log(oldReserves.debtReserves.token1RealReserves);
            console.log(newReserves.debtReserves.token1RealReserves);
            console.log("debtReserves.token1RealReserves new value is unexpectedly smaller than old value");
            testFails = true;
        }

        if (assertTmmaginaryIncrease) {
            if (
                oldReserves.collateralReserves.token0ImaginaryReserves >
                newReserves.collateralReserves.token0ImaginaryReserves
            ) {
                console.log(block.number);
                console.log(oldReserves.collateralReserves.token0ImaginaryReserves);
                console.log(newReserves.collateralReserves.token0ImaginaryReserves);
                console.log(
                    "collateralReserves.token0ImaginaryReserves new value is unexpectedly smaller than old value"
                );
                testFails = true;
            }

            if (
                oldReserves.collateralReserves.token1ImaginaryReserves >
                newReserves.collateralReserves.token1ImaginaryReserves
            ) {
                console.log(block.number);
                console.log(oldReserves.collateralReserves.token1ImaginaryReserves);
                console.log(newReserves.collateralReserves.token1ImaginaryReserves);
                console.log(
                    "collateralReserves.token1ImaginaryReserves new value is unexpectedly smaller than old value"
                );
                testFails = true;
            }

            if (oldReserves.debtReserves.token0ImaginaryReserves > newReserves.debtReserves.token0ImaginaryReserves) {
                console.log("##################################################");
                console.log(block.number);
                console.log(oldReserves.debtReserves.token0Debt);
                console.log(newReserves.debtReserves.token0Debt);
                console.log(oldReserves.debtReserves.token0RealReserves);
                console.log(newReserves.debtReserves.token0RealReserves);
                console.log(oldReserves.debtReserves.token0ImaginaryReserves);
                console.log(newReserves.debtReserves.token0ImaginaryReserves);
                console.log("debtReserves.token0ImaginaryReserves new value is unexpectedly smaller than old value");
                testFails = true;
            }

            if (oldReserves.debtReserves.token1ImaginaryReserves > newReserves.debtReserves.token1ImaginaryReserves) {
                console.log("##################################################");
                console.log(block.number);
                console.log(oldReserves.debtReserves.token1Debt);
                console.log(newReserves.debtReserves.token1Debt);
                console.log(oldReserves.debtReserves.token1RealReserves);
                console.log(newReserves.debtReserves.token1RealReserves);
                console.log(oldReserves.debtReserves.token1ImaginaryReserves);
                console.log(newReserves.debtReserves.token1ImaginaryReserves);
                console.log("debtReserves.token1ImaginaryReserves new value is unexpectedly smaller than old value");
                testFails = true;
            }
        } else {
            // must be > 99.99% of old value
            if (
                (oldReserves.collateralReserves.token0ImaginaryReserves * 9999) / 10000 >
                newReserves.collateralReserves.token0ImaginaryReserves
            ) {
                console.log(block.number);
                console.log(oldReserves.collateralReserves.token0ImaginaryReserves);
                console.log(newReserves.collateralReserves.token0ImaginaryReserves);
                console.log(
                    "collateralReserves.token0ImaginaryReserves new value is unexpectedly smaller than 99.99% of old value"
                );
                testFails = true;
            }

            if (
                (oldReserves.collateralReserves.token1ImaginaryReserves * 9999) / 10000 >
                newReserves.collateralReserves.token1ImaginaryReserves
            ) {
                console.log(block.number);
                console.log(oldReserves.collateralReserves.token1ImaginaryReserves);
                console.log(newReserves.collateralReserves.token1ImaginaryReserves);
                console.log(
                    "collateralReserves.token1ImaginaryReserves new value is unexpectedly smaller than 99.99% of old value"
                );
                testFails = true;
            }

            if (
                (oldReserves.debtReserves.token0ImaginaryReserves * 9999) / 10000 >
                newReserves.debtReserves.token0ImaginaryReserves
            ) {
                console.log("##################################################");
                console.log(block.number);
                console.log(oldReserves.debtReserves.token0Debt);
                console.log(newReserves.debtReserves.token0Debt);
                console.log(oldReserves.debtReserves.token0RealReserves);
                console.log(newReserves.debtReserves.token0RealReserves);
                console.log(oldReserves.debtReserves.token0ImaginaryReserves);
                console.log(newReserves.debtReserves.token0ImaginaryReserves);
                console.log(
                    "debtReserves.token0ImaginaryReserves new value is unexpectedly smaller than 99.99% of old value"
                );
                testFails = true;
            }

            if (
                (oldReserves.debtReserves.token1ImaginaryReserves * 9999) / 10000 >
                newReserves.debtReserves.token1ImaginaryReserves
            ) {
                console.log("##################################################");
                console.log(block.number);
                console.log(oldReserves.debtReserves.token1Debt);
                console.log(newReserves.debtReserves.token1Debt);
                console.log(oldReserves.debtReserves.token1RealReserves);
                console.log(newReserves.debtReserves.token1RealReserves);
                console.log(oldReserves.debtReserves.token1ImaginaryReserves);
                console.log(newReserves.debtReserves.token1ImaginaryReserves);
                console.log(
                    "debtReserves.token1ImaginaryReserves new value is unexpectedly smaller than 99.99% of old value"
                );
                testFails = true;
            }
        }

        assertFalse(testFails);
    }
}
