//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IRedstoneOracle } from "../../../../contracts/oracle/interfaces/external/IRedstoneOracle.sol";

contract MockRedstoneFeed is IRedstoneOracle {
    uint256 exchangeRate;

    function setExchangeRate(uint256 newExchangeRate_) external {
        exchangeRate = newExchangeRate_;
    }

    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        return exchangeRate;
    }

    function decimals() external view returns (uint8) {
        return 18;
    }
}
