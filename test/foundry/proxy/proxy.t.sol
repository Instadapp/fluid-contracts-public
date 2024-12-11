//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityBaseTest } from "../liquidity/liquidityBaseTest.t.sol";
import { Proxy } from "../../../contracts/infiniteProxy/proxy.sol";
import { FluidLiquidityAdminModule } from "../../../contracts/liquidity/adminModule/main.sol";

contract InfiniteProxyTest is LiquidityBaseTest {
    uint256 internal constant TEST_VALUE = 579847653843275623785367832687563287563287;

    function setUp() public virtual override {
        super.setUp();

        // set revenue collector alice (at slot 0)
        vm.prank(admin);
        FluidLiquidityAdminModule(address(liquidity)).updateRevenueCollector(alice);

        // also set slot 1 (_status)
        vm.store(
            address(liquidity),
            0x0000000000000000000000000000000000000000000000000000000000000001,
            bytes32(TEST_VALUE)
        );
    }

    function testProxyReadFromStorage() public {
        // slot 0 should be revenue collector, which is set to alice
        assertEq(
            address(
                uint160(
                    Proxy(payable(liquidity)).readFromStorage(
                        0x0000000000000000000000000000000000000000000000000000000000000000
                    )
                )
            ),
            alice
        );

        // slot 1 was set to TEST_VALUE
        assertEq(
            Proxy(payable(liquidity)).readFromStorage(
                0x0000000000000000000000000000000000000000000000000000000000000001
            ),
            TEST_VALUE
        );

        // slot 2 should be empty
        assertEq(
            Proxy(payable(liquidity)).readFromStorage(
                0x0000000000000000000000000000000000000000000000000000000000000002
            ),
            0
        );
    }
}
