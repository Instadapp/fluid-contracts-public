//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidityBaseTest } from "../liquidityBaseTest.t.sol";
import { Events } from "../../../../contracts/liquidity/userModule/events.sol";
import { MockProtocol } from "../../../../contracts/mocks/mockProtocol.sol";

contract LiquidityUserModuleBaseTest is LiquidityBaseTest, Events {
    // erc20 Transfer event for testing
    event Transfer(address indexed from, address indexed to, uint256 amount);

    MockProtocol mockProtocolUnauthorized;

    function setUp() public virtual override {
        super.setUp();

        mockProtocolUnauthorized = new MockProtocol(address(liquidity));

        // set default allowances for mockProtocol
        _setUserAllowancesDefault(address(liquidity), admin, address(USDC), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, address(DAI), address(mockProtocol));
        _setUserAllowancesDefault(address(liquidity), admin, NATIVE_TOKEN_ADDRESS, address(mockProtocol));
    }
}
