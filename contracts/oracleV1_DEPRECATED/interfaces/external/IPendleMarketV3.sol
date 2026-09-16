// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IPendleMarketV3 {
    function decimals() external view returns (uint8);

    function expiry() external view returns (uint256);

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;
}
